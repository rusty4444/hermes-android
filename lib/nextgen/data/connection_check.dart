// Checks a gateway stage by stage, so a failure names its stage: the server
// answering `/api/status`, the stored sign-in (`/api/auth/me`), and the live
// chat connection (a WS ticket, the `/api/ws` upgrade and `gateway.ready`).
import 'dart:async';
import 'dart:convert';

import '../../core/services/connection_manager.dart';
import '../../core/services/dashboard_api_client.dart';
import '../../core/services/desktop_gateway_client.dart';
import '../../core/services/hermes_sign_in.dart';
import '../../core/services/ws_client.dart';

enum CheckStage { server, signIn, live }

extension CheckStageLabel on CheckStage {
  String get label => switch (this) {
    CheckStage.server => 'Server access',
    CheckStage.signIn => 'Sign-in',
    CheckStage.live => 'Live connection',
  };
}

enum CheckOutcome { checking, passed, failed, skipped }

class StageResult {
  final CheckOutcome outcome;
  final String detail;
  final String? fix;
  const StageResult(this.outcome, this.detail, [this.fix]);
}

class ConnectionReport {
  final Map<CheckStage, StageResult> results;
  const ConnectionReport(this.results);

  CheckStage? get failedStage => CheckStage.values
      .where((s) => results[s]?.outcome == CheckOutcome.failed)
      .firstOrNull;

  bool get allPassed => CheckStage.values.every(
    (s) => results[s]?.outcome == CheckOutcome.passed,
  );
}

String _fixFor(GatewayUrl url) {
  if (url.host.endsWith('.ts.net') || url.host.startsWith('100.')) {
    return 'Check that Tailscale is on, on this phone and on the server.';
  }
  if (url.isHttps) {
    return 'Check the address and that the proxy forwards to the dashboard.';
  }
  if (isPrivateHost(url.host)) {
    return 'Use the same network as the server, and start the dashboard with '
        '--host 0.0.0.0 so other devices can reach it.';
  }
  return 'Check the address, VPN or Tailscale connection.';
}

/// Runs every stage in order; [onProgress] gets the report so far.
Future<ConnectionReport> runConnectionCheck(
  SavedConnection connection, {
  void Function(ConnectionReport)? onProgress,
}) async {
  final results = <CheckStage, StageResult>{
    for (final s in CheckStage.values)
      s: const StageResult(CheckOutcome.skipped, 'Not checked yet.'),
  };
  void record(CheckStage stage, StageResult result) {
    results[stage] = result;
    onProgress?.call(ConnectionReport(Map.of(results)));
  }

  final url = GatewayUrl.parse(
    connection.singleLoginUrl ??
        DesktopGatewayClient.normalizedGatewayBaseUrl(connection),
  );

  record(
    CheckStage.server,
    const StageResult(CheckOutcome.checking, 'Checking…'),
  );
  final probe = await GatewayProbe().probe(
    url,
    certificate: connection.clientCertificate,
  );
  switch (probe) {
    case ProbeReachable(:final status):
      record(
        CheckStage.server,
        StageResult(
          CheckOutcome.passed,
          'Hermes ${status.version} answers at ${url.display}.',
        ),
      );
    case ProbeUnreachable(:final reason):
      record(
        CheckStage.server,
        StageResult(CheckOutcome.failed, reason, _fixFor(url)),
      );
    case ProbeNotHermes(:final httpStatus):
      record(
        CheckStage.server,
        StageResult(
          CheckOutcome.failed,
          httpStatus == null
              ? 'Something answered, but not a Hermes dashboard.'
              : 'Something answered (HTTP $httpStatus), but not a Hermes dashboard.',
          'Use the dashboard\'s address and port (9119 by default), not the '
          'API server\'s.',
        ),
      );
    case ProbeAccessBlocked(:final tokenSent):
      record(
        CheckStage.server,
        StageResult(
          CheckOutcome.failed,
          tokenSent
              ? 'Cloudflare Access turned the service token down.'
              : 'Cloudflare Access is in front of this address.',
          tokenSent
              ? 'Check the service token and its Service Auth policy.'
              : 'Add a Cloudflare Access service token for this address.',
        ),
      );
    case ProbeClientCertRequired():
      record(
        CheckStage.server,
        const StageResult(
          CheckOutcome.failed,
          'The server asks for a client certificate.',
          'Pick the client certificate for this gateway, then test again.',
        ),
      );
  }
  if (results[CheckStage.server]!.outcome != CheckOutcome.passed) {
    record(
      CheckStage.signIn,
      const StageResult(CheckOutcome.skipped, 'Needs server access first.'),
    );
    record(
      CheckStage.live,
      const StageResult(CheckOutcome.skipped, 'Needs a sign-in first.'),
    );
    return ConnectionReport(results);
  }

  final dashboard = DashboardClient.fromConnection(connection);
  try {
    record(
      CheckStage.signIn,
      const StageResult(CheckOutcome.checking, 'Checking…'),
    );
    final status = (probe as ProbeReachable).status;
    try {
      final res = await dashboard.apiRequest('GET', 'auth/me');
      if (res.statusCode == 200) {
        final me = jsonDecode(res.body);
        final who = me is Map<String, dynamic>
            ? AuthUser.fromJson(me).label
            : 'you';
        record(
          CheckStage.signIn,
          StageResult(CheckOutcome.passed, 'Signed in as $who.'),
        );
      } else if (!status.authRequired &&
          (res.statusCode == 404 || res.statusCode == 401)) {
        record(
          CheckStage.signIn,
          const StageResult(
            CheckOutcome.passed,
            'This dashboard doesn\'t need a sign-in.',
          ),
        );
      } else if (res.statusCode == 401) {
        record(
          CheckStage.signIn,
          const StageResult(
            CheckOutcome.failed,
            'The saved sign-in has expired.',
            'Sign in again.',
          ),
        );
      } else if (res.statusCode == 429) {
        record(
          CheckStage.signIn,
          const StageResult(
            CheckOutcome.failed,
            'Too many sign-in attempts.',
            'Wait a minute, then check again.',
          ),
        );
      } else {
        record(
          CheckStage.signIn,
          StageResult(
            CheckOutcome.failed,
            'The gateway answered: ${dashboardErrorMessage(res)}.',
            'Sign in again, or update Hermes.',
          ),
        );
      }
    } catch (e) {
      record(
        CheckStage.signIn,
        StageResult(
          CheckOutcome.failed,
          e is DashboardHttpException && e.statusCode == 401
              ? 'The saved sign-in has expired.'
              : 'Couldn\'t check the sign-in: $e',
          'Sign in again.',
        ),
      );
    }
    if (results[CheckStage.signIn]!.outcome != CheckOutcome.passed) {
      record(
        CheckStage.live,
        const StageResult(CheckOutcome.skipped, 'Needs a sign-in first.'),
      );
      return ConnectionReport(results);
    }

    record(
      CheckStage.live,
      const StageResult(CheckOutcome.checking, 'Checking…'),
    );
    WsClient? client;
    try {
      final ticketRes = await dashboard.apiRequest('POST', 'auth/ws-ticket');
      if (ticketRes.statusCode != 200) {
        record(
          CheckStage.live,
          StageResult(
            CheckOutcome.failed,
            'The gateway wouldn\'t issue a chat ticket '
                '(${dashboardErrorMessage(ticketRes)}).',
            'Sign in again, or update Hermes.',
          ),
        );
        return ConnectionReport(results);
      }
      final ticket = (jsonDecode(ticketRes.body) as Map)['ticket'] as String;
      client = WsClient(
        dashboard.baseUrl,
        ticket: ticket,
        profile: connection.gatewayProfile,
        clientCertificate: connection.clientCertificate,
        ticketInSubprotocol: true,
      );
      await client.connect();
      await client.waitForGatewayReady();
      record(
        CheckStage.live,
        const StageResult(
          CheckOutcome.passed,
          'The chat connection opened and the gateway said it\'s ready.',
        ),
      );
    } on TimeoutException {
      record(
        CheckStage.live,
        const StageResult(
          CheckOutcome.failed,
          'The gateway never said it was ready.',
          'Check that the agent is running on the server.',
        ),
      );
    } catch (e) {
      final text = e.toString();
      record(
        CheckStage.live,
        StageResult(
          CheckOutcome.failed,
          text.contains('403')
              ? 'The gateway refused the chat connection (HTTP 403).'
              : text.contains('404')
              ? 'This dashboard has no chat endpoint (/api/ws).'
              : 'The chat connection failed: $text',
          text.contains('403')
              ? 'Use the exact address the dashboard is configured for.'
              : text.contains('404')
              ? 'Update Hermes.'
              : 'Make sure the proxy allows WebSocket upgrades on /api/ws.',
        ),
      );
    } finally {
      client?.close();
    }
  } finally {
    dashboard.close();
  }
  return ConnectionReport(results);
}
