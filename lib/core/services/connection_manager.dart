import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/connection.dart';
import '../models/session.dart';

// Re-export for convenience
export '../models/connection.dart';
export '../models/session.dart';

/// Manages saved remote connections using SharedPreferences.
class ConnectionManager {
  static const String _key = 'saved_connections';
  static const Uuid _uuid = Uuid();
  final SharedPreferences prefs;

  ConnectionManager(this.prefs);

  List<SavedConnection> getConnections() {
    final jsonList = prefs.getStringList(_key) ?? [];
    return jsonList.map((j) {
      final map = jsonDecode(j) as Map<String, dynamic>;
      return SavedConnection.fromMap(map);
    }).toList();
  }

  void saveConnection(String label, String host, int port) {
    final conn = SavedConnection(
      id: _uuid.v4(),
      label: label,
      host: host,
      port: port,
    );
    final current = getConnections();
    current.insert(0, conn);
    _saveAll(current);
  }

  void deleteConnection(String id) {
    final current = getConnections();
    current.removeWhere((c) => c.id == id);
    _saveAll(current);
  }

  void _saveAll(List<SavedConnection> list) {
    prefs.setStringList(
      _key,
      list.map((c) => jsonEncode(c.toMap())).toList(),
    );
  }
}

/// HTTP client for the Hermes dashboard REST API.
///
/// Automatically discovers the ephemeral session token by fetching the
/// dashboard SPA page (GET /) and extracting the embedded
/// `window.__HERMES_SESSION_TOKEN__` value.
class ApiClient {
  final http.Client _http;
  // Per-connection token cache: baseUrl -> token
  final Map<String, String> _tokenCache = {};

  ApiClient() : _http = http.Client();

  /// Auto-discover the session token by fetching the SPA page.
  Future<String> _getSessionToken(String baseUrl) async {
    final cached = _tokenCache[baseUrl];
    if (cached != null) return cached;

    final url = '$baseUrl/';
    final res = await _http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode} on /: ${res.body}');
    }

    // Extract window.__HERMES_SESSION_TOKEN__="..." from the <script> tag
    final body = res.body;
    final match = RegExp(r'window\.__HERMES_SESSION_TOKEN__="([^"]+)";').firstMatch(body);
    if (match == null) {
      throw Exception('Session token not found in SPA page');
    }

    final token = match.group(1)!;
    _tokenCache[baseUrl] = token;
    return token;
  }

  /// Public access to the session token for WebSocket auth.
  Future<String> getToken(String baseUrl) => _getSessionToken(baseUrl);

  Future<Map<String, dynamic>> apiGet(String baseUrl, String endpoint) async {
    final token = await _getSessionToken(baseUrl);
    final url = '$baseUrl/api/$endpoint';
    final res = await _http.get(Uri.parse(url), headers: {
      'X-Hermes-Session-Token': token,
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      // If we get a 401, invalidate the cached token and retry once
      if (res.statusCode == 401) {
        _tokenCache.remove(baseUrl);
        final newToken = await _getSessionToken(baseUrl);
        final retryRes = await _http.get(Uri.parse(url), headers: {
          'X-Hermes-Session-Token': newToken,
        });
        if (retryRes.statusCode < 200 || retryRes.statusCode >= 300) {
          throw Exception('HTTP ${retryRes.statusCode}: ${retryRes.body}');
        }
        return jsonDecode(retryRes.body) as Map<String, dynamic>;
      }
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Session>> getSessions(String baseUrl) async {
    final data = await apiGet(baseUrl, 'sessions');
    final list = data['sessions'] as List? ?? [];
    return list.map((s) => Session.fromJson(s as Map<String, dynamic>)).toList();
  }

  Future<List<Map<String, dynamic>>> getMessages(String baseUrl, String sessionId) async {
    final data = await apiGet(baseUrl, 'sessions/$sessionId/messages');
    final list = data['messages'] as List? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getModelInfo(String baseUrl) async {
    return await apiGet(baseUrl, 'model/info');
  }

  Future<Map<String, dynamic>> getModelOptions(String baseUrl) async {
    return await apiGet(baseUrl, 'model/options');
  }

  Future<Map<String, dynamic>> setModel(String baseUrl, String provider, String model,
      {String scope = 'main', String task = ''}) async {
    return await apiPost(baseUrl, 'model/set', {
      'scope': scope,
      'provider': provider,
      'model': model,
      'task': task,
    });
  }

  Future<Map<String, dynamic>> getConfig(String baseUrl) async {
    return await apiGet(baseUrl, 'config');
  }

  Future<List<dynamic>> getSkills(String baseUrl) async {
    final token = await _getSessionToken(baseUrl);
    final url = '$baseUrl/api/skills';
    final res = await _http.get(Uri.parse(url), headers: {
      'X-Hermes-Session-Token': token,
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> searchSessions(String baseUrl, String query) async {
    final token = await _getSessionToken(baseUrl);
    final encoded = Uri.encodeQueryComponent(query);
    final url = '$baseUrl/api/sessions/search?q=$encoded';
    final res = await _http.get(Uri.parse(url), headers: {
      'X-Hermes-Session-Token': token,
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (res.statusCode == 401) {
        _tokenCache.remove(baseUrl);
        final newToken = await _getSessionToken(baseUrl);
        final retryRes = await _http.get(
          Uri.parse('$baseUrl/api/sessions/search?q=$encoded'),
          headers: {'X-Hermes-Session-Token': newToken},
        );
        if (retryRes.statusCode < 200 || retryRes.statusCode >= 300) {
          throw Exception('HTTP ${retryRes.statusCode}: ${retryRes.body}');
        }
        return jsonDecode(retryRes.body) as Map<String, dynamic>;
      }
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> deleteSession(String baseUrl, String sessionId) async {
    final token = await _getSessionToken(baseUrl);
    final url = '$baseUrl/api/sessions/$sessionId';
    final res = await _http.delete(Uri.parse(url), headers: {
      'X-Hermes-Session-Token': token,
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<Map<String, dynamic>> apiPost(String baseUrl, String endpoint, Map<String, dynamic> body) async {
    final token = await _getSessionToken(baseUrl);
    final url = '$baseUrl/api/$endpoint';
    final res = await _http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'X-Hermes-Session-Token': token,
      },
      body: jsonEncode(body),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (res.statusCode == 401) {
        _tokenCache.remove(baseUrl);
        final newToken = await _getSessionToken(baseUrl);
        final retryRes = await _http.post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'X-Hermes-Session-Token': newToken,
          },
          body: jsonEncode(body),
        );
        if (retryRes.statusCode < 200 || retryRes.statusCode >= 300) {
          throw Exception('HTTP ${retryRes.statusCode}: ${retryRes.body}');
        }
        return jsonDecode(retryRes.body) as Map<String, dynamic>;
      }
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  void close() => _http.close();

  /// GET that returns a JSON array (for endpoints like /api/cron/jobs).
  Future<List<dynamic>> apiGetList(String baseUrl, String endpoint) async {
    final token = await _getSessionToken(baseUrl);
    final url = '$baseUrl/api/$endpoint';
    final res = await _http.get(Uri.parse(url), headers: {
      'X-Hermes-Session-Token': token,
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (res.statusCode == 401) {
        _tokenCache.remove(baseUrl);
        final newToken = await _getSessionToken(baseUrl);
        final retryRes = await _http.get(Uri.parse(url), headers: {
          'X-Hermes-Session-Token': newToken,
        });
        if (retryRes.statusCode < 200 || retryRes.statusCode >= 300) {
          throw Exception('HTTP ${retryRes.statusCode}: ${retryRes.body}');
        }
        return jsonDecode(retryRes.body) as List<dynamic>;
      }
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  /// DELETE request.
  Future<void> apiDelete(String baseUrl, String endpoint) async {
    final token = await _getSessionToken(baseUrl);
    final url = '$baseUrl/api/$endpoint';
    final res = await _http.delete(Uri.parse(url), headers: {
      'X-Hermes-Session-Token': token,
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (res.statusCode == 401) {
        _tokenCache.remove(baseUrl);
        final newToken = await _getSessionToken(baseUrl);
        final retryRes = await _http.delete(Uri.parse(url), headers: {
          'X-Hermes-Session-Token': newToken,
        });
        if (retryRes.statusCode < 200 || retryRes.statusCode >= 300) {
          throw Exception('HTTP ${retryRes.statusCode}: ${retryRes.body}');
        }
        return;
      }
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }
}
