import 'dart:convert';
import 'dart:io';

import 'connection_manager.dart';

/// Uses the configured Hermes server's existing authenticated STT route.
/// No provider credentials, third-party URL or client-side recognizer is used.
Future<String> transcribeVoiceRecording(
  DashboardClient dashboard,
  String path,
) async {
  final file = File(path);
  final size = await file.length();
  if (size == 0 || size > 6 * 1024 * 1024) {
    throw const VoiceTranscriptionException();
  }
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty || bytes.length > 6 * 1024 * 1024) {
    throw const VoiceTranscriptionException();
  }
  try {
    final result = await dashboard.transcribeAudioRecording(
      'data:audio/mp4;base64,${base64Encode(bytes)}',
    );
    final transcript = result['transcript'];
    if (result['ok'] != true ||
        transcript is! String ||
        transcript.trim().isEmpty) {
      throw const VoiceTranscriptionException();
    }
    return transcript.trim();
  } catch (_) {
    // Never surface response bodies: provider errors can contain private data.
    // In particular, do not fall back to an external STT service or auto-retry.
    throw const VoiceTranscriptionException();
  }
}

class VoiceTranscriptionException implements Exception {
  const VoiceTranscriptionException();
}
