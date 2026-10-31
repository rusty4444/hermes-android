"""RFC8291/8292 Web Push with DNS checked on every attempt and IP-pinned TLS."""

from __future__ import annotations

import http.client
import ipaddress
import re
import socket
import ssl
import time
from dataclasses import dataclass
from urllib.parse import urlsplit

import dns.exception
import dns.resolver
from py_vapid import Vapid
from pywebpush import WebPushException, webpush
from requests import Response

from .config import Policy, Rejected, private_file


@dataclass(frozen=True)
class Target:
    host: str
    port: int
    path: str
    addresses: tuple[str, ...]


def resolve_addresses(host, port):
    try:
        return (str(ipaddress.ip_address(host)),)
    except ValueError:
        pass
    resolver = dns.resolver.Resolver()
    addresses = []
    for record_type in ("A", "AAAA"):
        try:
            answer = resolver.resolve(host, record_type, search=False, lifetime=2)
            addresses.extend(str(item) for item in answer)
        except (dns.resolver.NoAnswer, dns.resolver.NXDOMAIN):
            continue
        except dns.exception.DNSException:
            raise OSError("Push DNS unavailable") from None
    return tuple(dict.fromkeys(addresses))


def validate_endpoint(endpoint: str, policy: Policy) -> Target:
    try:
        parts = urlsplit(endpoint)
        if (
            len(endpoint) > 2048
            or any(ord(c) < 33 or ord(c) > 126 for c in endpoint)
            or "\\" in endpoint
            or parts.scheme != "https"
            or not parts.hostname
            or parts.username is not None
            or parts.password is not None
            or parts.fragment
            or "#" in endpoint
        ):
            raise ValueError
        host = parts.hostname
        # DNS names are ASCII/IDNA, not arbitrary URI escapes or ambiguous numeric hosts.
        if "%" in host or host.endswith("."):
            raise ValueError
        port = parts.port if parts.port is not None else 443
        if not 1 <= port <= 65535:
            raise ValueError
        addresses = resolve_addresses(host, port)
        if not addresses:
            raise ValueError
        exceptions = dict(policy.allowed_private).get(host, frozenset())
        for address in addresses:
            ip = ipaddress.ip_address(address)
            # Reject mapped/translation forms as well as every non-global network.
            if isinstance(ip, ipaddress.IPv6Address) and (
                ip.ipv4_mapped or ip.sixtofour or ip.teredo
            ):
                raise ValueError
            if ip.is_multicast or ip.is_unspecified:
                raise ValueError
            global_unicast = ip.is_global and not ip.is_reserved
            if isinstance(ip, ipaddress.IPv6Address):
                global_unicast = global_unicast and ip in ipaddress.ip_network("2000::/3")
            if not global_unicast and address not in exceptions:
                raise ValueError
        path = parts.path or "/"
        if parts.query:
            path += "?" + parts.query
        return Target(host, port, path, addresses)
    except ValueError:
        raise Rejected(422, "Endpoint is not an allowed HTTPS push service") from None


class PinnedHTTPS(http.client.HTTPSConnection):
    def __init__(self, target, context=None, timeout=5):
        super().__init__(
            target.host,
            target.port,
            timeout=timeout,
            context=context or ssl.create_default_context(),
        )
        self.target = target
        self.deadline = time.monotonic() + timeout

    def remaining(self):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("Push deadline exceeded")
        return remaining

    def connect(self):
        # Never pass a hostname to socket.create_connection: it would resolve it again.
        address = self.target.addresses[0]
        family = socket.AF_INET6 if ":" in address else socket.AF_INET
        sock = socket.socket(family, socket.SOCK_STREAM)
        sock.settimeout(self.remaining())
        try:
            sock.connect((address, self.target.port))
            sock.settimeout(self.remaining())
            self.sock = self._context.wrap_socket(sock, server_hostname=self.target.host)
        except BaseException:
            sock.close()
            raise


class PinnedSession:
    def __init__(self, policy, context=None):
        self.policy = policy
        self.context = context

    def post(self, endpoint, data, headers, timeout):
        target = validate_endpoint(endpoint, self.policy)
        connection = PinnedHTTPS(target, self.context, timeout=min(timeout, 5))
        try:
            # No proxies, cookies, client certs, Hermes credentials, redirects or second DNS lookup.
            connection.request("POST", target.path, body=data, headers=dict(headers))
            # Bound the entire status/header read, including slow-drip peers. Never read a body.
            reply = bytearray()
            while b"\r\n\r\n" not in reply:
                connection.sock.settimeout(connection.remaining())
                chunk = connection.sock.recv(1024)
                if not chunk or len(reply) + len(chunk) > 8192:
                    raise OSError("Invalid push response")
                reply.extend(chunk)
            match = re.fullmatch(
                rb"HTTP/1\.[01] ([1-5][0-9]{2})(?: [^\r\n]*)?", bytes(reply).split(b"\r\n", 1)[0]
            )
            if not match:
                raise OSError("Invalid push response")
            response = Response()
            response.status_code = int(match[1])
            response.reason = ""
            response._content = b""  # Never retain or log arbitrary push-service response contents.
            return response
        finally:
            connection.close()


class Sender:
    def __init__(self, context=None):
        self.context = context

    def send(self, registration, hint_json, policy):
        import json

        # Validate the private key file at use time, not just on startup.
        key = Vapid.from_pem(private_file(policy.vapid_key))
        try:
            response = webpush(
                subscription_info={
                    "endpoint": registration["endpoint"],
                    "keys": json.loads(registration["keys_json"]),
                },
                data=hint_json,
                vapid_private_key=key,
                vapid_claims={"sub": policy.vapid_subject},
                content_encoding="aes128gcm",
                requests_session=PinnedSession(policy, self.context),
                timeout=5,
                ttl=max(0, json.loads(hint_json)["expires_at"] - int(time.time())),
                headers={"Content-Type": "application/octet-stream", "Urgency": "normal"},
                verbose=False,
            )
            return response.status_code
        except WebPushException as error:
            if error.response is not None:
                return error.response.status_code
            raise
