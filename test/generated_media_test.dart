import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/utils/generated_media.dart';

Map<String, dynamic> _image(String path) => {'success': true, 'image': path};

void main() {
  group('audited image_generate result contract', () {
    test('parsed and stored JSON prefer host_image, never sandbox image', () {
      const host = '/Users/sam/.hermes/image_cache/a space 雪#%.png';
      final result = {
        'success': true,
        'image': '/old/fallback.png',
        'host_image': host,
        'agent_visible_image': '/sandbox/.hermes/image_cache/a.png',
        'prompt': 'not a delivery: MEDIA:/out/prompt.pdf',
      };
      for (final payload in [result, jsonEncode(result)]) {
        final parsed = generatedMediaFromToolResult('image_generate', payload);
        expect(parsed.deliveredFiles.single.path, host);
        expect(parsed.isFailure, isFalse);
        expect(() => parsed.deliveredFiles.clear(), throwsUnsupportedError);
      }
      expect(
        generatedMediaFromToolResult('image_generate', {
          'success': true,
          'agent_visible_image': '/sandbox/a.png',
        }).deliveredFiles,
        isEmpty,
      );
    });

    test('image fallback and literal Windows/home paths are lossless', () {
      for (final path in [
        '/out/雪 #%?.PNG',
        '~/image_cache/a.png',
        r'C:\new\renders\a space.png',
        'C:/renders/a.png',
      ]) {
        expect(
          generatedMediaFromToolResult('image_generate', {
            ..._image(path),
            'host_image': 42,
          }).deliveredFiles.single.path,
          path,
        );
      }
    });

    test('HTTPS URL-only results retain URL and gain safe image semantics', () {
      for (final url in [
        'https://cdn.example/image.png?sig=exact%2Ftoken#fragment',
        'https://cdn.example/generated/opaque-id?format=png',
      ]) {
        final ref = generatedMediaFromToolResult(
          'image_generate',
          _image(url),
        ).deliveredFiles.single;
        expect(ref.path, url);
        expect(ref.extension, 'png');
      }
      expect(
        generatedMediaFromToolResult(
          'image_generate',
          _image('https://cdn.example/opaque-id'),
        ).deliveredFiles.single.suggestedFilename,
        'generated-image.png',
      );
    });

    test('does not guess producer names or scan arbitrary tool output', () {
      for (final name in [
        'terminal',
        'read_file',
        'image',
        'Image_generate',
        'functions.image_generate',
        'image_generate ',
        'text_to_speech',
      ]) {
        expect(
          generatedMediaFromToolResult(
            name,
            _image('/out/a.png'),
          ).deliveredFiles,
          isEmpty,
          reason: name,
        );
      }
      for (final result in [
        null,
        '',
        'MEDIA:/out/a.png',
        '{broken json',
        [],
        jsonEncode(jsonEncode(_image('/out/a.png'))),
        {'image': '/out/a.png'},
        {'success': 'true', 'image': '/out/a.png'},
        {
          'success': true,
          'attachments': ['/out/a.png'],
        },
        {'success': true, 'result': _image('/out/a.png')},
        {
          'success': true,
          'image': ['/out/a.png'],
        },
      ]) {
        expect(
          generatedMediaFromToolResult('image_generate', result).deliveredFiles,
          isEmpty,
        );
      }
    });

    test('rejects failures and unsafe/unrecognised reference shapes', () {
      for (final result in [
        {'success': false, 'image': '/out/a.png'},
        {'success': true, 'error': 'failed', 'image': '/out/a.png'},
      ]) {
        final parsed = generatedMediaFromToolResult('image_generate', result);
        expect(parsed.deliveredFiles, isEmpty);
        expect(parsed.isFailure, isTrue);
      }
      for (final path in [
        'relative.png',
        '/out/not-an-image.pdf',
        '//cdn.example/a.png',
        'http://cdn.example/a.png',
        'https://name:secret@cdn.example/a.png',
        'data:image/png;base64,AAAA',
        'file:///out/a.png',
        '/out/a.png\nMEDIA:/out/b.png',
        ' /out/a.png',
        '/out/a.png ',
      ]) {
        expect(
          generatedMediaFromToolResult(
            'image_generate',
            _image(path),
          ).deliveredFiles,
          isEmpty,
          reason: path,
        );
      }
    });

    test('bounds raw JSON parsing instead of scanning a large output', () {
      final oversized = jsonEncode({
        ..._image('/out/a.png'),
        'padding': 'x' * maxGeneratedMediaResultCodeUnits,
      });
      expect(
        generatedMediaFromToolResult(
          'image_generate',
          oversized,
        ).deliveredFiles,
        isEmpty,
      );
    });
  });

  group('GatewayToolActivity deliveredFiles', () {
    test('only tool.complete consumes result, not args or summary', () {
      final activity = GatewayToolActivity.fromGatewayEvent('tool.complete', {
        'tool_id': 'call-image',
        'name': 'image_generate',
        'args': {'output': '/out/args.png'},
        'summary': 'MEDIA:/out/summary.png',
        'result': _image('/out/real.png'),
      })!;
      expect(activity.deliveredFiles.single.path, '/out/real.png');
      expect(activity.detail, 'MEDIA:/out/summary.png');
      for (final event in ['tool.start', 'tool.progress', 'tool.generating']) {
        expect(
          GatewayToolActivity.fromGatewayEvent(event, {
            'name': 'image_generate',
            'result': _image('/out/not-complete.png'),
          })!.deliveredFiles,
          isEmpty,
        );
      }
      expect(
        GatewayToolActivity.fromGatewayEvent('tool.complete', {
          'label': 'image_generate',
          'result': _image('/out/label.png'),
        })!.deliveredFiles,
        isEmpty,
      );
    });

    test('compact resume without result preserves known files on merge', () {
      final known = GatewayToolActivity.fromGatewayEvent('tool.complete', {
        'tool_id': 'image-1',
        'name': 'image_generate',
        'result': jsonEncode(_image('/out/a.png')),
      })!;
      final compact = GatewayToolActivity.fromGatewayEvent('tool.complete', {
        'tool_id': 'image-1',
        'name': 'image_generate',
        'duration_s': 2,
      })!;
      expect(compact.deliveredFiles, isEmpty);
      final merged = known.merge(compact);
      expect(merged.deliveredFiles.single.path, '/out/a.png');
      expect(merged.identity, known.identity);
      expect(merged.durationSeconds, 2);
      expect(
        GatewayToolActivity.fromStoredResult(
          name: 'image_generate',
          timestamp: 10,
          result: jsonEncode(_image('/out/stored.png')),
        ).deliveredFiles.single.path,
        '/out/stored.png',
      );
    });

    test('failures remove earlier files and cannot be revived by replay', () {
      final success = GatewayToolActivity.fromGatewayEvent('tool.complete', {
        'tool_id': 'same-call',
        'name': 'image_generate',
        'result': _image('/out/old.png'),
      })!;
      for (final fields in [
        {'error': 'failed'},
        {'status': 'failed'},
        {
          'result': {'success': false, 'image': '/out/failed.png'},
        },
      ]) {
        final failure = GatewayToolActivity.fromGatewayEvent('tool.complete', {
          'tool_id': 'same-call',
          'name': 'image_generate',
          ...fields,
        })!;
        final merged = success.merge(failure);
        expect(merged.deliveredFiles, isEmpty);
        expect(merged.hasFailedDelivery, isTrue);
        expect(merged.merge(success).deliveredFiles, isEmpty);
      }
      expect(success.deliveredFiles.single.path, '/out/old.png');
    });
  });
}
