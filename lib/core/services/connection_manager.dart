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
class ApiClient {
  final http.Client _http;

  ApiClient() : _http = http.Client();

  Future<Map<String, dynamic>> _get(String baseUrl, String endpoint) async {
    final url = '$baseUrl/api/$endpoint';
    final res = await _http.get(Uri.parse(url));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Session>> getSessions(String baseUrl) async {
    final data = await _get(baseUrl, 'sessions');
    final list = data['sessions'] as List? ?? [];
    return list.map((s) => Session.fromJson(s as Map<String, dynamic>)).toList();
  }

  Future<List<Map<String, dynamic>>> getMessages(String baseUrl, String sessionId) async {
    final data = await _get(baseUrl, 'sessions/$sessionId/messages');
    final list = data['messages'] as List? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getStatus(String baseUrl) async {
    return _get(baseUrl, 'status');
  }

  void close() => _http.close();
}
