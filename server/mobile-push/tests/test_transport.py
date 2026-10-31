import base64
import datetime
import json
import socket
import ssl
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import http_ece
import pytest
from conftest import PREFIX
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature
from cryptography.x509.oid import NameOID

from mobile_push import transport
from mobile_push.config import Rejected
from mobile_push.transport import PinnedHTTPS, Sender, Target, validate_endpoint


@pytest.mark.parametrize(
    "endpoint",
    [
        "http://push.example.test/push",
        "file:///etc/passwd",
        "https://user:pw@push.example.test/push",
        "https://push.example.test/push#fragment",
        "https://push.example.test/push#",
        "https://127.0.0.1/push",
        "https://169.254.169.254/latest/meta-data",
        "https://[::1]/push",
        "https://10.0.0.1/push",
        "https://push.example.test./push",
        "https://push.example.test/\r\nInjected:yes",
        "https://push.example.test\\@127.0.0.1/push",
        "https://push.example.test:bad/push",
        "https://%31%32%37.0.0.1/push",
    ],
)
def test_malicious_endpoints_rejected(env, endpoint):
    with pytest.raises(Rejected):
        validate_endpoint(endpoint, env.profile.policy())


@pytest.mark.parametrize(
    "address",
    [
        "127.0.0.1",
        "10.0.0.1",
        "100.64.0.1",
        "169.254.169.254",
        "::1",
        "fc00::1",
        "::ffff:127.0.0.1",
        "2002:7f00:1::",
    ],
)
def test_changed_dns_mixed_answers_rejected(env, monkeypatch, address):
    monkeypatch.setattr(transport, "resolve_addresses", lambda *a, **kw: ("93.184.216.34", address))
    with pytest.raises(Rejected):
        validate_endpoint(env.body["endpoint"], env.profile.policy())


def test_real_resolver_queries_are_bounded_and_literal_ips_do_not_resolve(monkeypatch):
    queries = []

    class Resolver:
        def resolve(self, host, record_type, search, lifetime):
            queries.append((host, record_type, search, lifetime))
            if record_type == "AAAA":
                raise transport.dns.resolver.NoAnswer()
            return ["93.184.216.34"]

    monkeypatch.setattr(transport.dns.resolver, "Resolver", Resolver)
    assert transport.resolve_addresses("public.example.test", 443) == ("93.184.216.34",)
    assert queries == [
        ("public.example.test", "A", False, 2),
        ("public.example.test", "AAAA", False, 2),
    ]
    assert transport.resolve_addresses("127.0.0.1", 443) == ("127.0.0.1",)
    assert len(queries) == 2


@pytest.mark.parametrize(
    "address", ["224.0.0.1", "ff02::1", "64:ff9b::7f00:1", "fec0::1", "0.0.0.0"]
)
def test_non_unicast_and_embedded_private_ipv6_are_refused(env, monkeypatch, address):
    monkeypatch.setattr(transport, "resolve_addresses", lambda *args: (address,))
    with pytest.raises(Rejected):
        validate_endpoint(env.body["endpoint"], env.profile.policy())


def test_zero_port_is_not_silently_changed_to_443(env):
    with pytest.raises(Rejected):
        validate_endpoint("https://push.example.test:0/push", env.profile.policy())


def test_pinned_connect_does_not_resolve_twice_and_keeps_sni(monkeypatch):
    connected = []

    class Socket:
        def settimeout(self, timeout):
            pass

        def connect(self, address):
            connected.append(address)

        def close(self):
            pass

    class TLS:
        check_hostname = True
        # Python 3.11 HTTPSConnection validates this SSLContext attribute.
        verify_mode = ssl.CERT_REQUIRED

        def wrap_socket(self, sock, server_hostname):
            assert server_hostname == "push.example.test"
            return sock

    monkeypatch.setattr(socket, "socket", lambda *a, **kw: Socket())
    monkeypatch.setattr(socket, "getaddrinfo", lambda *a, **kw: pytest.fail("DNS rebound"))
    connection = PinnedHTTPS(Target("push.example.test", 443, "/push", ("93.184.216.34",)), TLS())
    connection.connect()
    assert connected == [("93.184.216.34", 443)]
    connection.close()


@pytest.fixture
def receiver(tmp_path, env, monkeypatch):
    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "receiver.example.test")])
    now = datetime.datetime.now(datetime.UTC)
    certificate = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=1))
        .not_valid_after(now + datetime.timedelta(days=1))
        .add_extension(
            x509.SubjectAlternativeName([x509.DNSName("receiver.example.test")]), critical=False
        )
        .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
        .sign(key, hashes.SHA256())
    )
    cert_path, key_path = tmp_path / "cert.pem", tmp_path / "tls.pem"
    cert_path.write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
    key_path.write_bytes(
        key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    )
    received = []
    status = [201]

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            received.append(
                (
                    self.path,
                    dict(self.headers),
                    self.rfile.read(int(self.headers["Content-Length"])),
                )
            )
            self.send_response(status[0])
            self.send_header("Location", "https://127.0.0.1/forbidden-redirect")
            self.send_header("Content-Length", "0")
            self.end_headers()

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    server_context.load_cert_chain(cert_path, key_path)
    server.socket = server_context.wrap_socket(server.socket, server_side=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env.config["private_endpoints"] = [{"host": "receiver.example.test", "ips": ["127.0.0.1"]}]
    env.save()
    previous = transport.resolve_addresses

    def resolve(host, port, *args, **kwargs):
        if host == "receiver.example.test":
            return ("127.0.0.1",)
        return previous(host, port, *args, **kwargs)

    monkeypatch.setattr(transport, "resolve_addresses", resolve)
    context = ssl.create_default_context(cafile=str(cert_path))
    env.runtime.sender = Sender(context)
    endpoint = f"https://receiver.example.test:{server.server_port}/subscription/private-token"
    yield endpoint, received, status
    server.shutdown()
    server.server_close()
    thread.join()


def decrypt(env, received):
    path, headers, ciphertext = received
    headers = {key.lower(): value for key, value in headers.items()}
    assert headers["content-encoding"] == "aes128gcm"
    assert headers["content-type"] == "application/octet-stream"
    assert headers["host"].startswith("receiver.example.test:")
    assert "cookie" not in headers and "x-hermes-token" not in headers
    assert b"registration_nonce" not in ciphertext and b"challenge" not in ciphertext
    plaintext = http_ece.decrypt(
        ciphertext, private_key=env.subscriber_key, auth_secret=b"a" * 16, version="aes128gcm"
    )
    hint = json.loads(plaintext)
    # Independently verify VAPID's JWT signature and audience, not only its existence.
    authorization = headers["authorization"]
    token = authorization.split("t=", 1)[1].split(",", 1)[0]
    head, payload, signature = token.split(".")

    def decode(value):
        return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))

    signature = decode(signature)
    der = encode_dss_signature(
        int.from_bytes(signature[:32], "big"), int.from_bytes(signature[32:], "big")
    )
    env.private_key.public_key().verify(
        der, (head + "." + payload).encode(), ec.ECDSA(hashes.SHA256())
    )
    claims = json.loads(decode(payload))
    assert claims["aud"] == "https://" + headers["host"]
    assert claims["sub"] == "mailto:operator@example.test"
    assert claims["exp"] > env.runtime.store.now()
    return hint


def test_real_encrypted_challenge_confirm_turn_and_resolution_roundtrip(env, receiver):
    endpoint, received, _ = receiver
    response = env.client.put(
        PREFIX + "/registrations/phone", json={**env.body, "endpoint": endpoint}
    )
    assert response.status_code == 200, response.text
    assert env.runtime.deliver_one()
    assert len(received) == 1
    challenge = decrypt(env, received[0])
    assert challenge["kind"] == "challenge"
    assert set(challenge) == {
        "schema",
        "event_id",
        "kind",
        "generation",
        "registration_nonce",
        "expires_at",
        "challenge",
    }
    assert (
        env.client.post(
            PREFIX + "/registrations/phone/confirm",
            json={"generation": 1, "challenge": challenge["challenge"]},
        ).status_code
        == 200
    )
    env.runtime.human_input(
        kind="approval", session_id="session-a", request_id="request-id", command="secret command"
    )
    assert env.runtime.deliver_one()
    assert decrypt(env, received[-1])["kind"] == "input"
    env.runtime.human_resolved(
        kind="approval", session_id="session-a", request_id="request-id", outcome="deny"
    )
    assert env.runtime.deliver_one()
    assert decrypt(env, received[-1])["kind"] == "input_resolved"
    env.runtime.session_end(
        session_id="session-a",
        turn_id="turn-1",
        completed=True,
        failed=False,
        interrupted=False,
        turn_exit_reason="stop",
    )
    assert env.runtime.deliver_one()
    hint = decrypt(env, received[-1])
    event = next(
        event
        for event in env.client.get(PREFIX + "/events").json()["events"]
        if event["event_id"] == hint["event_id"]
    )
    assert event["session_id"] == "session-a" and event["turn_id"] == "turn-1"
    assert not env.runtime.deliver_one()


def test_real_sender_never_follows_redirect_or_reuses_changed_dns(env, receiver, monkeypatch):
    endpoint, received, status = receiver
    status[0] = 307
    assert (
        env.client.put(
            PREFIX + "/registrations/phone", json={**env.body, "endpoint": endpoint}
        ).status_code
        == 200
    )
    assert env.runtime.deliver_one()
    assert len(received) == 1  # no second POST to Location
    status[0] = 201
    monkeypatch.setattr(transport, "resolve_addresses", lambda *a, **kw: ("169.254.169.254",))
    with env.runtime.store.transaction() as db:
        db.execute("UPDATE outbox SET next_at=0,lease_until=0")
    assert env.runtime.deliver_one()
    assert len(received) == 1
