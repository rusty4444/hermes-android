import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'connection_manager.dart';
import 'desktop_gateway_client.dart';

/// Shared streaming budget for user-opened chat deliveries and Assets.
const maxAttachmentDownloadBytes = 25 * 1024 * 1024;

class RemoteDirectory {
  final String path;
  final String? branch;

  const RemoteDirectory({required this.path, this.branch});
}

class RemoteFileEntry {
  final String name;
  final String path;
  final bool isDirectory;

  const RemoteFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
  });

  factory RemoteFileEntry.fromJson(Map<String, dynamic> json) =>
      RemoteFileEntry(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        isDirectory: json['isDirectory'] == true,
      );
}

class RemoteTextPreview {
  final String path;
  final String text;
  final String language;
  final String mimeType;
  final int byteSize;
  final bool binary;
  final bool truncated;

  const RemoteTextPreview({
    required this.path,
    required this.text,
    required this.language,
    required this.mimeType,
    required this.byteSize,
    required this.binary,
    required this.truncated,
  });

  factory RemoteTextPreview.fromJson(Map<String, dynamic> json) =>
      RemoteTextPreview(
        path: json['path'] as String? ?? '',
        text: json['text'] as String? ?? '',
        language: json['language'] as String? ?? 'text',
        mimeType: json['mimeType'] as String? ?? 'text/plain',
        byteSize: (json['byteSize'] as num?)?.toInt() ?? 0,
        binary: json['binary'] == true,
        truncated: json['truncated'] == true,
      );
}

class RemoteFileDownload {
  final String filename;
  final Uint8List bytes;

  RemoteFileDownload({required this.filename, required List<int> bytes})
    : bytes = Uint8List.fromList(bytes);
}

abstract class RemoteFilesDataSource {
  Future<RemoteDirectory> defaultDirectory();
  Future<List<RemoteFileEntry>> listDirectory(String path);
  Future<RemoteTextPreview> readText(String path);
  Future<RemoteFileDownload> download(String path);
}

class RemoteFilesClient implements RemoteFilesDataSource {
  final DashboardClient dashboard;
  final String? profile;
  final String? sessionId;
  final int? maxDownloadBytes;
  http.Client? _urlHttpClient;
  bool _closed = false;

  RemoteFilesClient({
    required this.dashboard,
    this.profile,
    this.sessionId,
    this.maxDownloadBytes,
    this._urlHttpClient,
  });

  factory RemoteFilesClient.fromConnection(
    SavedConnection connection, {
    String? sessionId,
    http.Client? httpClient,
    http.Client? urlHttpClient,
    int? maxDownloadBytes,
  }) {
    final baseUri = Uri.parse(
      DesktopGatewayClient.normalizedGatewayBaseUrl(connection),
    );
    return RemoteFilesClient(
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
      sessionId: sessionId,
      maxDownloadBytes: maxDownloadBytes,
      urlHttpClient: urlHttpClient,
    );
  }

  Map<String, String> _scopedQuery(
    Map<String, String> parameters, {
    bool includeSession = false,
  }) => {
    ...parameters,
    if (profile?.isNotEmpty == true) 'profile': profile!,
    if (includeSession && sessionId?.isNotEmpty == true)
      'session_id': sessionId!,
  };

  @override
  Future<RemoteDirectory> defaultDirectory() async {
    final data = await dashboard.apiGet(
      'fs/default-cwd',
      queryParameters: _scopedQuery(const {}),
    );
    return RemoteDirectory(
      path: data['cwd'] as String? ?? '/',
      branch: data['branch'] as String?,
    );
  }

  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) async {
    final data = await dashboard.apiGet(
      'fs/list',
      queryParameters: _scopedQuery({'path': path}),
    );
    final error = data['error'] as String?;
    if (error != null && error.isNotEmpty) {
      throw Exception('Could not read directory: $error');
    }
    final entries = (data['entries'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RemoteFileEntry.fromJson)
        .toList();
    entries.sort(
      (left, right) => left.isDirectory == right.isDirectory
          ? left.name.toLowerCase().compareTo(right.name.toLowerCase())
          : left.isDirectory
          ? -1
          : 1,
    );
    return entries;
  }

  @override
  Future<RemoteTextPreview> readText(String path) async {
    final data = await dashboard.apiGet(
      'fs/read-text',
      queryParameters: _scopedQuery({'path': path}),
    );
    return RemoteTextPreview.fromJson(data);
  }

  @override
  Future<RemoteFileDownload> download(String path) async {
    if (_closed) throw StateError('Remote files client is closed');
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(path)) {
      return _downloadUrl(Uri.parse(path));
    }
    final response = await dashboard.apiGetBytes(
      'fs/download',
      queryParameters: _scopedQuery({'path': path}, includeSession: true),
      maxBytes: maxDownloadBytes,
    );
    final disposition = response.headers['content-disposition'] ?? '';
    final match = RegExp(
      r'''filename\*?=(?:UTF-8''|["'])?([^"';]+)''',
      caseSensitive: false,
    ).firstMatch(disposition);
    return RemoteFileDownload(
      filename: match?.group(1)?.trim() ?? path.split('/').last,
      bytes: response.bodyBytes,
    );
  }

  /// URL-only image-generation results are not filesystem paths. Fetch them
  /// only after an explicit tap, on a separate client with no dashboard auth,
  /// cookies or client certificate. Validate every redirect before sending it.
  Future<RemoteFileDownload> _downloadUrl(Uri initial) async {
    final limit = maxDownloadBytes ?? maxAttachmentDownloadBytes;
    if (limit <= 0) throw ArgumentError.value(limit, 'maxDownloadBytes');
    final client = _urlHttpClient ??= http.Client();
    var uri = initial;
    for (var redirects = 0; redirects <= 3; redirects++) {
      if (_closed) throw StateError('Remote files client is closed');
      if (uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException(
          'Attachment URLs must use HTTPS without credentials',
        );
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await client
          .send(request)
          .timeout(ApiClient.requestTimeout);
      if (_closed) {
        await response.stream.listen((_) {}).cancel();
        throw StateError('Remote files client is closed');
      }
      if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
        await response.stream.listen((_) {}).cancel();
        final location = response.headers['location'];
        if (location == null || redirects == 3) {
          throw const FormatException(
            'Attachment redirect limit exceeded or missing destination',
          );
        }
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        throw http.ClientException(
          'Attachment download failed: HTTP ${response.statusCode}',
        );
      }
      if ((response.contentLength ?? 0) > limit) {
        await response.stream.listen((_) {}).cancel();
        throw const DownloadSizeLimitException();
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        ApiClient.requestTimeout,
      )) {
        if (_closed) throw StateError('Remote files client is closed');
        if (bytes.length + chunk.length > limit) {
          throw const DownloadSizeLimitException();
        }
        bytes.add(chunk);
      }
      return RemoteFileDownload(
        filename:
            initial.pathSegments
                .where((segment) => segment.isNotEmpty)
                .lastOrNull ??
            'attachment',
        bytes: bytes.takeBytes(),
      );
    }
    throw const FormatException('Attachment redirect limit exceeded');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _urlHttpClient?.close();
    dashboard.close();
  }
}
