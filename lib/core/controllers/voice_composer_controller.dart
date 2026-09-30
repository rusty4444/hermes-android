import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/voice_composer_adapter.dart';

/// Owns a single dictation session and edits only its controlled replacement
/// range. Recognition callbacks never have access to chat submission.
class VoiceComposerController extends ChangeNotifier {
  final TextEditingController textController;
  final VoiceComposerAdapter adapter;

  Timer? _elapsedTimer;
  TextEditingValue? _startValue;
  int? _replacementStart;
  int? _replacementEnd;
  bool _needsLeadingSeparator = false;
  bool _needsTrailingSeparator = false;
  bool _available = false;
  bool _listening = false;
  bool _acceptResults = false;
  bool _stopping = false;
  bool _disposed = false;
  Duration _elapsed = Duration.zero;
  String? _status;

  VoiceComposerController({
    required this.textController,
    required this.adapter,
  });

  bool get available => _available;
  bool get listening => _listening;
  Duration get elapsed => _elapsed;
  String? get status => _status;

  /// Fired when a final dictation result has been staged into the text field.
  /// The chat screen uses this to remember that the next send originated from
  /// voice, so the reply is read aloud (spoken replies).
  VoidCallback? onDictationStaged;

  Future<bool> initialize({bool requestPermission = false}) async {
    try {
      if (!requestPermission && !await adapter.hasPermission) {
        _available = false;
        _status = null;
        _notify();
        return false;
      }
      _available = await adapter.initialize(
        onStatus: _handleStatus,
        onError: _handleError,
      );
      _status = _available ? null : 'Speech recognition is unavailable';
    } catch (error) {
      _available = false;
      _status = 'Voice setup failed: $error';
    }
    _notify();
    return _available;
  }

  Future<bool> start({String? localeId}) async {
    if (_disposed || _listening) return false;
    if (!_available && !await initialize(requestPermission: true)) return false;

    _startValue = textController.value;
    final insertion = _validSelectionOrEnd(_startValue!);
    _configureReplacement(_startValue!, insertion);
    _acceptResults = true;
    _listening = true;
    _status = 'Listening';
    _startElapsedTimer();
    _notify();

    try {
      await adapter.listen(onResult: _handleResult, localeId: localeId);
      return true;
    } catch (error) {
      _handleError(error.toString());
      return false;
    }
  }

  Future<void> stop() async {
    if (_disposed || !_listening) return;
    _stopping = true;
    Object? stopError;
    try {
      await adapter.stop();
    } catch (error) {
      stopError = error;
    } finally {
      if (!_disposed) {
        _stopping = false;
        _acceptResults = false;
        _finishListening(status: stopError?.toString());
        _clearSession();
      }
    }
  }

  Future<void> cancel() async {
    if (_disposed || (_startValue == null && !_listening)) return;
    _acceptResults = false;
    _stopping = false;
    final snapshot = _startValue;
    _finishListening(status: null);
    if (snapshot != null) textController.value = snapshot;
    _clearSession();
    try {
      await adapter.cancel();
    } catch (error) {
      if (!_disposed) {
        _status = error.toString();
        _notify();
      }
    }
  }

  void _handleResult({required String transcript, required bool isFinal}) {
    if (_disposed || !_acceptResults) return;
    final recognized = transcript.trim();
    if (recognized.isEmpty) return;

    final value = textController.value;
    var start = _replacementStart;
    var end = _replacementEnd;
    if (start == null ||
        end == null ||
        start < 0 ||
        end < start ||
        end > value.text.length) {
      final fallback = _validSelectionOrEnd(value);
      start = fallback.start;
      end = fallback.end;
      _configureReplacement(value, fallback);
    }

    final leading =
        _needsLeadingSeparator && !_isClosingPunctuation(recognized[0])
        ? ' '
        : '';
    final trailing =
        _needsTrailingSeparator &&
            !_isOpeningPunctuation(recognized[recognized.length - 1])
        ? ' '
        : '';
    final replacement = '$leading$recognized$trailing';
    final updated = value.text.replaceRange(start, end, replacement);
    final caret = start + leading.length + recognized.length;
    textController.value = value.copyWith(
      text: updated,
      selection: TextSelection.collapsed(offset: caret),
      composing: TextRange.empty,
    );
    _replacementStart = start;
    _replacementEnd = start + replacement.length;
    if (isFinal) {
      if (_stopping) {
        _status = 'Dictation ready to edit';
        _notify();
        onDictationStaged?.call();
        return;
      }
      _acceptResults = false;
      _finishListening(status: 'Dictation ready to edit');
      _clearSession();
      onDictationStaged?.call();
      unawaited(_stopAdapterAfterFinal());
    } else {
      _status = 'Listening';
      _notify();
    }
  }

  Future<void> _stopAdapterAfterFinal() async {
    try {
      await adapter.stop();
    } catch (error) {
      if (!_disposed) {
        _status = error.toString();
        _notify();
      }
    }
  }

  void _handleStatus(String status) {
    if (_disposed) return;
    final normalized = status.toLowerCase();
    if (normalized == 'listening') {
      if (!_acceptResults) return;
      _listening = true;
      _status = 'Listening';
      _notify();
      return;
    }
    if (normalized == 'done' || normalized == 'notlistening') {
      if (_stopping || !_listening) return;
      _acceptResults = false;
      _finishListening(status: null);
      _clearSession();
    }
  }

  void _handleError(String message) {
    if (_disposed) return;
    _acceptResults = false;
    _stopping = false;
    _finishListening(status: message);
    _clearSession();
  }

  TextSelection _validSelectionOrEnd(TextEditingValue value) {
    final selection = value.selection;
    if (selection.isValid &&
        selection.start >= 0 &&
        selection.end >= selection.start &&
        selection.end <= value.text.length) {
      return selection;
    }
    return TextSelection.collapsed(offset: value.text.length);
  }

  void _configureReplacement(TextEditingValue value, TextSelection selection) {
    _replacementStart = selection.start;
    _replacementEnd = selection.end;
    _needsLeadingSeparator =
        selection.start > 0 &&
        value.text
            .substring(selection.start - 1, selection.start)
            .trim()
            .isNotEmpty;
    _needsTrailingSeparator =
        selection.end < value.text.length &&
        value.text
            .substring(selection.end, selection.end + 1)
            .trim()
            .isNotEmpty;
  }

  bool _isClosingPunctuation(String character) =>
      '.,!?;:)]}'.contains(character);

  bool _isOpeningPunctuation(String character) => '([{'.contains(character);

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsed = Duration.zero;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || !_listening) return;
      _elapsed += const Duration(seconds: 1);
      _notify();
    });
  }

  void _finishListening({required String? status}) {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _elapsed = Duration.zero;
    _listening = false;
    _status = status;
    _notify();
  }

  void _clearSession() {
    _startValue = null;
    _replacementStart = null;
    _replacementEnd = null;
    _needsLeadingSeparator = false;
    _needsTrailingSeparator = false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _acceptResults = false;
    _stopping = false;
    _listening = false;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _elapsed = Duration.zero;
    adapter.dispose();
    super.dispose();
  }
}
