import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/attachment_controller.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:hermes_android/core/utils/media_tags.dart';
import 'package:hermes_android/nextgen/data/chat_controller.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

/// Refuses the in-memory read (as the 25 MiB preview cap would) and streams
/// [content] to disk instead, or fails with [streamError].
class _Streaming implements RemoteFilesDataSource, RemoteFileStreamingSource {
  _Streaming(this.content, {this.streamError});
  final List<int> content;
  final Object? streamError;
  var streams = 0;

  @override
  Future<RemoteFileDownload> download(String path) async =>
      throw const DownloadSizeLimitException();

  @override
  Future<String?> downloadToFile(
    String path,
    File target, {
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    streams++;
    if (streamError case final error?) throw error;
    await target.writeAsBytes(content, flush: true);
    onProgress?.call(content.length, content.length);
    return path.split('/').last;
  }

  @override
  Future<RemoteDirectory> defaultDirectory() => throw UnimplementedError();
  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) =>
      throw UnimplementedError();
  @override
  Future<RemoteTextPreview> readText(String path) => throw UnimplementedError();
}

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('large-attachment-test-');
    PathProviderPlatform.instance = _Paths(temp.path);
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('download budget for Save and Share is 1 GiB', () {
    expect(maxLargeAttachmentBytes, 1024 * 1024 * 1024);
    expect(maxAttachmentDownloadBytes, lessThan(maxLargeAttachmentBytes));
  });

  test('a delivery over the preview cap streams to disk for Save', () async {
    final files = _Streaming(utf8.encode('big file body'));
    File? saved;
    String? savedContent;
    final controller = AttachmentController(
      ref: const MediaTagRef(path: '/out/video.mp4'),
      filesClient: () => files,
      fileSaveHandler: ({required file, required ref}) async {
        saved = file;
        savedContent = await file.readAsString();
        return 'content://saved/video.mp4';
      },
    );
    await controller.save(dialogTitle: 'Save');
    expect(files.streams, 1);
    expect(savedContent, 'big file body');
    expect(controller.feedback, AttachmentFeedback.saved);
    expect(saved!.path, startsWith(temp.path));
    controller.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await saved!.exists(), isFalse);
  });

  test('a streamed delivery is shared by file and reused', () async {
    final files = _Streaming(Uint8List(64));
    final shared = <String>[];
    final controller = AttachmentController(
      ref: const MediaTagRef(path: '/out/archive.zip'),
      filesClient: () => files,
      fileShareHandler:
          ({required file, required ref, required isCurrent}) async {
            shared.add(file.path);
          },
    );
    await controller.share();
    await controller.share();
    expect(shared, hasLength(2));
    expect(shared.first, shared.last);
    expect(files.streams, 1);
    controller.dispose();
  });

  test('a delivery over 1 GiB says only the dashboard can fetch it', () async {
    final files = _Streaming(
      const [],
      streamError: const DownloadSizeLimitException(),
    );
    var saves = 0;
    final controller = AttachmentController(
      ref: const MediaTagRef(path: '/out/huge.iso'),
      filesClient: () => files,
      fileSaveHandler: ({required file, required ref}) async {
        saves++;
        return 'x';
      },
    );
    await controller.save(dialogTitle: 'Save');
    expect(saves, 0);
    expect(controller.feedback, AttachmentFeedback.overPhoneLimit);
    controller.dispose();
  });

  group('dashboard streaming', () {
    late HttpServer server;
    late DashboardClient client;
    final uploads = <Map<String, Object?>>[];
    setUp(() async {
      uploads.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.uri.path == '/api/fs/download') {
          if (request.uri.queryParameters['path'] == '/big') {
            request.response.contentLength = 2048;
            request.response.add(Uint8List(2048));
          } else {
            request.response.add(utf8.encode('hello world'));
          }
          await request.response.close();
          return;
        }
        if (request.uri.path == '/api/files/upload-stream') {
          final type = request.headers.contentType!;
          final body = await request.fold<List<int>>(
            [],
            (all, chunk) => all..addAll(chunk),
          );
          final text = latin1.decode(body);
          final boundary = type.parameters['boundary']!;
          String field(String name) => RegExp(
            'name="$name"\r\n\r\n(.*?)\r\n--$boundary',
            dotAll: true,
          ).firstMatch(text)!.group(1)!;
          uploads.add({
            'type': type.mimeType,
            'length': request.headers.contentLength,
            'received': body.length,
            'path': field('path'),
            'overwrite': field('overwrite'),
            'file': RegExp(
              'filename="([^"]*)"\r\nContent-Type: ([^\r]*)\r\n\r\n(.*)\r\n--$boundary--',
              dotAll: true,
            ).firstMatch(text)!.groups([1, 2, 3]),
          });
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'path': field('path')}));
          await request.response.close();
          return;
        }
        request.response.statusCode = 404;
        await request.response.close();
      });
      client = DashboardClient(
        host: '127.0.0.1',
        port: server.port,
        proxied: true,
      );
    });
    tearDown(() async {
      client.close();
      await server.close(force: true);
    });

    test('a download streams into a file', () async {
      final target = File('${temp.path}/out.txt');
      final progress = <int>[];
      await client.apiDownloadToFile(
        'fs/download',
        target,
        queryParameters: {'path': '/small'},
        maxBytes: 1024,
        onProgress: (received, _) => progress.add(received),
      );
      expect(await target.readAsString(), 'hello world');
      expect(progress.last, 11);
    });

    test('a download over its budget leaves no partial file', () async {
      final target = File('${temp.path}/big.bin');
      await expectLater(
        client.apiDownloadToFile(
          'fs/download',
          target,
          queryParameters: {'path': '/big'},
          maxBytes: 1024,
        ),
        throwsA(isA<DownloadSizeLimitException>()),
      );
      expect(await target.exists(), isFalse);
    });

    test('an upload goes as one streamed multipart form', () async {
      final source = File('${temp.path}/report.pdf');
      await source.writeAsString('PDF body');
      final sent = <int>[];
      final res = await client.apiUploadStream(
        source,
        targetPath: '/home/me/.ares-uploads/abc/report.pdf',
        filename: 'report.pdf',
        mimeType: 'application/pdf',
        onProgress: (bytes, total) => sent.add(bytes),
      );
      expect(res.statusCode, 200);
      final upload = uploads.single;
      expect(upload['type'], 'multipart/form-data');
      expect(upload['length'], upload['received']);
      expect(upload['path'], '/home/me/.ares-uploads/abc/report.pdf');
      expect(upload['overwrite'], 'false');
      expect(upload['file'], ['report.pdf', 'application/pdf', 'PDF body']);
      expect(sent.last, 8);
    });
  });

  test('upload names stay one safe path segment', () {
    expect(ngSafeUploadName('../../etc/passwd'), 'passwd');
    expect(ngSafeUploadName(r'C:\Users\me\$HOME%x.txt'), 'HOMEx.txt');
    expect(ngSafeUploadName('  .hidden. '), 'hidden');
    expect(ngSafeUploadName('NUL.txt'), '_NUL.txt');
    expect(ngSafeUploadName('com1'), '_com1');
    expect(ngSafeUploadName(''), 'attachment');
    expect(ngSafeUploadName('a' * 300).length, 200);
  });
}
