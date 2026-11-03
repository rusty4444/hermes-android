import 'package:http/http.dart' as http;

import '../models/session.dart';
import 'connection_manager.dart' show DashboardClient, SavedConnection;
import 'desktop_gateway_client.dart';

export '../models/chat_asset.dart';

class ChatAssetsSessionPage {
  final List<Session> sessions;
  final int nextOffset;
  final bool hasMore;

  /// The server reported a storage/read problem, or an unusable row was
  /// omitted. Even a non-partial page is not a complete file inventory.
  final bool partial;

  const ChatAssetsSessionPage({
    required this.sessions,
    required this.nextOffset,
    required this.hasMore,
    this.partial = false,
  });
}

class ChatAssetsMessagePage {
  final List<Map<String, dynamic>> messages;
  final int nextOffset;
  final bool hasMore;

  const ChatAssetsMessagePage({
    required this.messages,
    required this.nextOffset,
    required this.hasMore,
  });
}

abstract class ChatAssetsDataSource {
  Future<ChatAssetsSessionPage> listSessions({int offset = 0, int limit = 10});

  Future<ChatAssetsMessagePage> getMessages(
    Session session, {
    int offset = 0,
    int limit = 100,
  });
}

/// Read-only discovery of chat-delivered files on one dashboard/profile.
///
/// Only lists sessions and reads durable messages. It does not resume/create a
/// session, invoke an agent, enumerate profiles, scan directories, or index the
/// host's disk. OFFSET pages are mutable views, not an exhaustive snapshot.
class ChatAssetsClient implements ChatAssetsDataSource {
  final DashboardClient dashboard;
  final String? profile;
  bool _closed = false;
  String? _inferredProfile;

  ChatAssetsClient({required this.dashboard, this.profile});

  factory ChatAssetsClient.fromConnection(
    SavedConnection connection, {
    http.Client? httpClient,
  }) {
    final baseUri = Uri.parse(
      DesktopGatewayClient.normalizedGatewayBaseUrl(connection),
    );
    return ChatAssetsClient(
      dashboard: DashboardClient(
        host: baseUri.host,
        port: baseUri.port,
        useHttps: baseUri.scheme == 'https',
        pathPrefix: baseUri.path == '/' ? '' : baseUri.path,
        proxied: connection.dashboardProxied,
        username: connection.dashboardUsername,
        password: connection.dashboardPassword,
        gatewayProfile: connection.gatewayProfile,
        clientCertificate: connection.clientCertificate,
        httpClient: httpClient,
      ),
      profile: connection.gatewayProfile,
    );
  }

  Map<String, String> _query(int offset, int limit) => {
    'limit': '$limit',
    'offset': '$offset',
    if (profile?.isNotEmpty == true) 'profile': profile!,
  };

  void _checkOpen() {
    if (_closed) throw StateError('Chat assets client is closed');
    if (profile?.isNotEmpty == true) _canonicalProfile(profile!);
  }

  @override
  Future<ChatAssetsSessionPage> listSessions({
    int offset = 0,
    int limit = 10,
  }) async {
    _checkOpen();
    _validateRequest(offset, limit, maximumLimit: 100);
    // Unlike profiles/sessions, this endpoint defaults to the serving profile,
    // not all profiles. Omit profile only when the connection also omits it.
    final data = await dashboard.apiGet(
      'sessions',
      queryParameters: {
        ..._query(offset, limit),
        'archived': 'include',
        'order': 'recent',
      },
    );
    _checkOpen();
    _validatePagination(data, offset: offset, limit: limit);
    final total = _optionalCount(data, 'total');
    final rows = _rows(data, 'sessions');
    final owner = _validateProfiles([data, ...rows]);
    final sessions = <String, Session>{};
    var partial = _hasIssues(data);
    for (final row in rows) {
      final id = row['id'];
      if (id is! String || id.trim().isEmpty) {
        partial = true;
        continue;
      }
      for (final key in const ['title', 'model', 'source', 'preview']) {
        if (row[key] != null && row[key] is! String) {
          throw FormatException('Invalid session $key');
        }
      }
      // A server may back-fill every pin, including rows already in this
      // window. Keep one row per id, but never advance by this deduped count.
      sessions.putIfAbsent(id, () => Session.fromJson(row));
    }
    final nextOffset = offset + limit;
    _inferredProfile = owner;
    return ChatAssetsSessionPage(
      sessions: sessions.values.toList(),
      nextOffset: nextOffset,
      hasMore: total != null ? nextOffset < total : rows.isNotEmpty,
      partial: partial,
    );
  }

  @override
  Future<ChatAssetsMessagePage> getMessages(
    Session session, {
    int offset = 0,
    int limit = 100,
  }) async {
    _checkOpen();
    _validateRequest(offset, limit, maximumLimit: 500);
    if (session.id.trim().isEmpty) {
      throw ArgumentError.value(session.id, 'session.id', 'Must not be empty');
    }
    final data = await dashboard.apiGet(
      'sessions/${Uri.encodeComponent(session.id)}/messages',
      queryParameters: {
        ..._query(offset, limit),
        'order': 'latest',
        'include_compacted': 'true',
        'inline_images': 'false',
      },
    );
    _checkOpen();

    if (_hasIssues(data)) {
      throw const FormatException('Chat assets message history is unavailable');
    }
    final messages = _rows(data, 'messages');
    if (messages.length > limit) {
      throw const FormatException('Message page exceeds the requested limit');
    }
    // The list provides the current tip. A compression race must be retried
    // from a fresh list, not silently filed under the old chat's identity.
    // Accepting a different canonical id would require independent lineage
    // proof, which this deliberately scoped, read-only client does not obtain.
    if (data['session_id'] != session.id) {
      throw const FormatException(
        'Chat assets response has a different session id',
      );
    }
    final pagination = data['pagination'];
    int? returned;
    if (data.containsKey('pagination')) {
      if (pagination is! Map<String, dynamic>) {
        throw const FormatException('Invalid message pagination');
      }
      _validatePagination(
        pagination,
        offset: offset,
        limit: limit,
        order: 'latest',
      );
      returned = _optionalCount(pagination, 'returned');
      if (returned != null && returned != messages.length) {
        throw const FormatException('Message returned count does not match');
      }
    }
    final owner = _validateProfiles([data, ...messages]);
    _inferredProfile = owner;
    return ChatAssetsMessagePage(
      messages: messages,
      nextOffset: offset + limit,
      // Without explicit returned metadata, a short projected page need not
      // mean a short raw-row window. Keep paging nonempty legacy responses.
      hasMore: returned != null ? returned >= limit : messages.isNotEmpty,
    );
  }

  String? _validateProfiles(Iterable<Map<String, dynamic>> records) {
    // The backend accepts title-cased profile aliases and emits canonical IDs.
    // Keep the original query token unchanged; canonicalise only for identity.
    var owner = profile?.isNotEmpty == true
        ? _canonicalProfile(profile!)
        : _inferredProfile;
    for (final record in records) {
      if (!record.containsKey('profile')) continue;
      final stamp = record['profile'];
      if (stamp is! String) {
        throw const FormatException('Invalid chat assets profile');
      }
      final canonical = _canonicalProfile(stamp);
      if (owner != null && owner != canonical) {
        throw const FormatException(
          'Chat assets response has a different profile',
        );
      }
      owner = canonical;
    }
    // Commit inference only after the caller validates the entire response.
    return owner;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    dashboard.close();
  }
}

String _canonicalProfile(String name) {
  final canonical = name.trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(canonical)) {
    throw const FormatException('Invalid chat assets profile');
  }
  return canonical;
}

void _validateRequest(int offset, int limit, {required int maximumLimit}) {
  RangeError.checkNotNegative(offset, 'offset');
  RangeError.checkValueInInterval(limit, 1, maximumLimit, 'limit');
}

List<Map<String, dynamic>> _rows(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! List || value.any((row) => row is! Map<String, dynamic>)) {
    throw FormatException('Expected a $key list of objects');
  }
  return value.cast<Map<String, dynamic>>();
}

int? _optionalCount(Map<String, dynamic> data, String key) {
  if (!data.containsKey(key)) return null;
  final value = data[key];
  if (value is! int || value < 0) {
    throw FormatException('Invalid chat assets $key');
  }
  return value;
}

void _validatePagination(
  Map<String, dynamic> pagination, {
  required int offset,
  required int limit,
  String? order,
}) {
  final returnedOffset = _optionalCount(pagination, 'offset');
  final returnedLimit = _optionalCount(pagination, 'limit');
  if ((returnedOffset != null && returnedOffset != offset) ||
      (returnedLimit != null && returnedLimit != limit) ||
      (order != null &&
          pagination.containsKey('order') &&
          pagination['order'] != order)) {
    throw const FormatException(
      'Chat assets pagination does not match request',
    );
  }
}

bool _hasIssues(Map<String, dynamic> data) =>
    _hasValue(data['error']) ||
    _hasValue(data['errors']) ||
    _hasValue(data['storage']) ||
    _hasValue(data['storage_unavailable']) ||
    _hasValue(data['partial']) ||
    data['ok'] == false;

bool _hasValue(Object? value) => switch (value) {
  null || false => false,
  String value => value.isNotEmpty,
  Map value => value.isNotEmpty,
  Iterable value => value.isNotEmpty,
  _ => true,
};
