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
import '../nextgen_l10n.dart';

enum CheckStage { server, signIn, live }

extension CheckStageLabel on CheckStage {
  String get label => switch (this) {
    CheckStage.server => ngL.ng_server_access,
    CheckStage.signIn => ngL.ng_sign_in,
    CheckStage.live => ngL.ng_live_connection,
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
    return ngL.ng_check_that_tailscale_is_on_on;
  }
  if (url.isHttps) {
    return ngL.ng_check_the_address_and_that_the;
  }
  if (isPrivateHost(url.host)) {
    return ngL.ng_use_the_same_network_as_the;
  }
  return ngL.ng_check_the_address_vpn_or_tailscale;
}

/// Runs every stage in order; [onProgress] gets the report so far.
Future<ConnectionReport> runConnectionCheck(
  SavedConnection connection, {
  void Function(ConnectionReport)? onProgress,
}) async {
  final results = <CheckStage, StageResult>{
    for (final s in CheckStage.values)
      s: StageResult(CheckOutcome.skipped, ngL.ng_not_checked_yet),
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
    StageResult(CheckOutcome.checking, ngL.ng_checking),
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
          ngL.ng_hermes_answers_at(status.version ?? '', url.display),
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
              ? ngL.ng_something_answered_but_not_a_hermes
              : ngL.ng_something_answered_http_but_not_a(httpStatus),
          ngL.ng_use_the_dashboard_s_address_and,
        ),
      );
    case ProbeAccessBlocked(:final tokenSent):
      record(
        CheckStage.server,
        StageResult(
          CheckOutcome.failed,
          tokenSent
              ? ngL.ng_cloudflare_access_turned_the_service_token
              : ngL.ng_cloudflare_access_is_in_front_of,
          tokenSent
              ? ngL.ng_check_the_service_token_and_its
              : ngL.ng_add_a_cloudflare_access_service_token,
        ),
      );
    case ProbeClientCertRequired():
      record(
        CheckStage.server,
        StageResult(
          CheckOutcome.failed,
          ngL.ng_the_server_asks_for_a_client,
          ngL.ng_pick_the_client_certificate_for_this,
        ),
      );
  }
  if (results[CheckStage.server]!.outcome != CheckOutcome.passed) {
    record(
      CheckStage.signIn,
      StageResult(CheckOutcome.skipped, ngL.ng_needs_server_access_first),
    );
    record(
      CheckStage.live,
      StageResult(CheckOutcome.skipped, ngL.ng_needs_a_sign_in_first),
    );
    return ConnectionReport(results);
  }

  final dashboard = DashboardClient.fromConnection(connection);
  try {
    record(
      CheckStage.signIn,
      StageResult(CheckOutcome.checking, ngL.ng_checking),
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
          StageResult(CheckOutcome.passed, ngL.ng_signed_in_as(who)),
        );
      } else if (!status.authRequired &&
          (res.statusCode == 404 || res.statusCode == 401)) {
        record(
          CheckStage.signIn,
          StageResult(
            CheckOutcome.passed,
            ngL.ng_this_dashboard_doesn_t_need_a,
          ),
        );
      } else if (res.statusCode == 401) {
        record(
          CheckStage.signIn,
          StageResult(
            CheckOutcome.failed,
            ngL.ng_the_saved_sign_in_has_expired,
            ngL.ng_sign_in_again,
          ),
        );
      } else if (res.statusCode == 429) {
        record(
          CheckStage.signIn,
          StageResult(
            CheckOutcome.failed,
            ngL.ng_too_many_sign_in_attempts,
            ngL.ng_wait_a_minute_then_check_again,
          ),
        );
      } else {
        record(
          CheckStage.signIn,
          StageResult(
            CheckOutcome.failed,
            ngL.ng_the_gateway_answered(dashboardErrorMessage(res)),
            ngL.ng_sign_in_again_or_update_hermes,
          ),
        );
      }
    } catch (e) {
      record(
        CheckStage.signIn,
        StageResult(
          CheckOutcome.failed,
          e is DashboardHttpException && e.statusCode == 401
              ? ngL.ng_the_saved_sign_in_has_expired
              : ngL.ng_couldn_t_check_the_sign_in(e),
          ngL.ng_sign_in_again,
        ),
      );
    }
    if (results[CheckStage.signIn]!.outcome != CheckOutcome.passed) {
      record(
        CheckStage.live,
        StageResult(CheckOutcome.skipped, ngL.ng_needs_a_sign_in_first),
      );
      return ConnectionReport(results);
    }

    record(
      CheckStage.live,
      StageResult(CheckOutcome.checking, ngL.ng_checking),
    );
    WsClient? client;
    try {
      final ticketRes = await dashboard.apiRequest('POST', 'auth/ws-ticket');
      if (ticketRes.statusCode != 200) {
        record(
          CheckStage.live,
          StageResult(
            CheckOutcome.failed,
            ngL.ng_the_gateway_wouldn_t_issue_a(
              dashboardErrorMessage(ticketRes),
            ),
            ngL.ng_sign_in_again_or_update_hermes,
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
        StageResult(
          CheckOutcome.passed,
          ngL.ng_the_chat_connection_opened_and_the,
        ),
      );
    } on TimeoutException {
      record(
        CheckStage.live,
        StageResult(
          CheckOutcome.failed,
          ngL.ng_the_gateway_never_said_it_was,
          ngL.ng_check_that_the_agent_is_running,
        ),
      );
    } catch (e) {
      final text = e.toString();
      record(
        CheckStage.live,
        StageResult(
          CheckOutcome.failed,
          text.contains('403')
              ? ngL.ng_the_gateway_refused_the_chat_connection
              : text.contains('404')
              ? ngL.ng_this_dashboard_has_no_chat_endpoint
              : ngL.ng_the_chat_connection_failed(text),
          text.contains('403')
              ? ngL.ng_use_the_exact_address_the_dashboard
              : text.contains('404')
              ? ngL.ng_update_hermes
              : ngL.ng_make_sure_the_proxy_allows_websocket,
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
