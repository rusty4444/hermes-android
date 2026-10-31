import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/hands_free_voice_platform.dart';

enum HandsFreeState {
  idle,
  listening,
  recording,
  waiting,
  speaking,
  followup,
  error,
}

enum HandsFreeStopReason {
  user,
  background,
  routeChanged,
  connectionChanged,
  sessionChanged,
  accountMutation,
  permissionRevoked,
  manualDictation,
  manualReadAloud,
  composerEdited,
  attachmentAction,
  manualSend,
  voiceReplyDisabled,
  disposed,
  nativeDetached,
}

enum HandsFreeTurnStatus { completed, failed, interrupted, unknown, needsInput }

enum HandsFreeSpeechOutcome {
  completed,
  canceled,
  unavailable,
  failed,
  deadline,
}

/// Immutable consent, not credentials. Every continuation intersects this with
/// the screen's current route/account/session/foreground authority.
class HandsFreeAuthority {
  const HandsFreeAuthority({
    required this.routeToken,
    required this.connectionId,
    required this.connectionMutationEpoch,
    required this.sessionId,
    required this.foregroundEpoch,
    required this.controllerGeneration,
  });
  final Object routeToken;
  final String connectionId;
  final Object? connectionMutationEpoch;
  final String sessionId;
  final int foregroundEpoch;
  final int controllerGeneration;
  HandsFreeAuthority forGeneration(int generation) => HandsFreeAuthority(
    routeToken: routeToken,
    connectionId: connectionId,
    connectionMutationEpoch: connectionMutationEpoch,
    sessionId: sessionId,
    foregroundEpoch: foregroundEpoch,
    controllerGeneration: generation,
  );
}

class HandsFreePrompt {
  const HandsFreePrompt({
    required this.requestId,
    required this.transcript,
    required this.authority,
  });
  final String requestId;
  final String transcript;
  final HandsFreeAuthority authority;
}

class HandsFreeSubmittedTurn {
  const HandsFreeSubmittedTurn({
    required this.clientTurnId,
    required this.settled,
  });
  final String clientTurnId;
  final Future<HandsFreeTurnOutcome> settled;
}

class HandsFreeTurnOutcome {
  const HandsFreeTurnOutcome({
    required this.clientTurnId,
    required this.status,
    required this.publicFinalText,
  });
  final String clientTurnId;
  final HandsFreeTurnStatus status;
  final String? publicFinalText;
}

class HandsFreeReply {
  const HandsFreeReply({
    required this.clientTurnId,
    required this.text,
    required this.authority,
  });
  final String clientTurnId;
  final String text;
  final HandsFreeAuthority authority;
}

typedef VoiceTimerFactory =
    Timer Function(Duration duration, void Function() fire);

/// Foreground-only flow. Native events carry release barriers; timers can stop
/// recognition but can never promote a partial into a sendable final.
class HandsFreeConversationController extends ChangeNotifier {
  HandsFreeConversationController({
    required this.platform,
    required this.ownerId,
    required this.isAuthorityCurrent,
    required this.canStart,
    required this.prepareAudio,
    required this.submitHandsFreePrompt,
    required this.speakHandsFreeReply,
    required this.cancelSpeech,
    required this.localeId,
    VoiceTimerFactory? timerFactory,
  }) : _timerFactory =
           timerFactory ?? ((duration, fire) => Timer(duration, fire));

  void _listenEvents() {
    _subscription ??= platform.events.listen(
      _event,
      onError: (Object _) {
        if (_authority != null) _fail('engineLoadFailed');
      },
      onDone: () {
        if (_authority != null) _fail('engineLoadFailed');
      },
    );
  }

  final HandsFreeVoicePlatform platform;
  final String ownerId;
  final bool Function(HandsFreeAuthority) isAuthorityCurrent;
  final bool Function(HandsFreeAuthority) canStart;
  final Future<bool> Function() prepareAudio;
  final Future<HandsFreeSubmittedTurn?> Function(HandsFreePrompt)
  submitHandsFreePrompt;
  final Future<HandsFreeSpeechOutcome> Function(HandsFreeReply)
  speakHandsFreeReply;
  final Future<void> Function() cancelSpeech;
  final String? Function() localeId;
  final VoiceTimerFactory _timerFactory;
  StreamSubscription<VoicePlatformEvent>? _subscription;
  HandsFreeState _state = HandsFreeState.idle;
  HandsFreeState get state => _state;
  HandsFreeAuthority? _authority;
  HandsFreeAuthority? get authority => _authority;
  int _generation = 0;
  int get generation => _generation;
  int _operation = 0;
  int _seq = 0;
  bool _disposed = false;
  bool _starting = false;
  bool get starting => _starting;
  bool _permissionSetupComplete = false;
  bool get permissionSetupComplete => _permissionSetupComplete;
  bool _ready = false;
  bool get ready => _ready;
  String _preview = '';
  String get preview => _preview;
  String? _errorCode;
  String? get errorCode => _errorCode;
  bool get active => _authority != null;
  Duration _followupTimeout = const Duration(seconds: 10);
  String? _armId;
  String? _requestId;
  VoiceRecognitionPurpose? _purpose;
  String? _nativeFinal;
  bool _speechStarted = false;
  bool _finishing = false;
  Timer? _deadline;
  Timer? _echo;
  Completer<bool>? _echoDone;
  final Set<String> _consumed = {};
  Future<bool>? _startFlight;
  final Set<Future<void>> _nativeFlights = {};
  Future<void>? _speechFlight;
  Future<void>? _cleanup;
  bool _cleanupFailed = false;

  bool isCurrent(HandsFreeAuthority authority) =>
      !_disposed &&
      identical(authority, _authority) &&
      authority.controllerGeneration == _generation &&
      isAuthorityCurrent(authority);
  bool _current(int generation) {
    final authority = _authority;
    if (authority == null || generation != _generation || _disposed) {
      return false;
    }
    if (!isAuthorityCurrent(authority)) {
      revoke(HandsFreeStopReason.nativeDetached);
      return false;
    }
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _stateTo(HandsFreeState state) {
    _state = state;
    _notify();
  }

  Future<bool> start({
    required HandsFreeAuthority authority,
    required Duration followupTimeout,
  }) {
    if (followupTimeout < Duration.zero ||
        followupTimeout > const Duration(seconds: 30)) {
      return Future.error(
        ArgumentError.value(followupTimeout, 'followupTimeout'),
      );
    }
    if (_disposed ||
        active ||
        _starting ||
        _cleanupFailed ||
        !canStart(authority) ||
        !isAuthorityCurrent(authority)) {
      return Future.value(false);
    }
    _listenEvents();
    final generation = ++_generation;
    _authority = authority.forGeneration(generation);
    _followupTimeout = followupTimeout;
    _starting = true;
    _permissionSetupComplete = false;
    _ready = false;
    _errorCode = null;
    _seq = 0;
    _consumed.clear();
    _stateTo(HandsFreeState.listening);
    final previousCleanup = _cleanup;
    final flight = _start(generation, previousCleanup);
    _startFlight = flight;
    return flight;
  }

  Future<bool> _start(int generation, Future<void>? previousCleanup) async {
    try {
      await previousCleanup;
      if (!_current(generation) || _cleanupFailed) return false;
      if (!await prepareAudio()) {
        if (_current(generation)) _fail('audioBusy');
        return false;
      }
      if (!_current(generation)) return false;
      var capabilities = await platform.capabilities();
      if (!_current(generation)) return false;
      if (!capabilities.recordPermissionGranted) {
        final granted = await platform.requestRecordPermission();
        // A permission dialog may revoke foreground consent; grant is setup,
        // not a second implicit Start, even when the app has resumed meanwhile.
        if (!_current(generation)) {
          if (granted && !_disposed) {
            _permissionSetupComplete = true;
            _notify();
          }
          return false;
        }
        if (!granted) {
          _fail('permissionDenied');
          return false;
        }
        capabilities = await platform.capabilities();
        if (!_current(generation)) return false;
      }
      if (!canStart(_authority!)) {
        _fail('submissionRejected');
        return false;
      }
      final failure = !capabilities.recordPermissionGranted
          ? 'permissionDenied'
          : !capabilities.sttAvailable
          ? 'recognizerUnavailable'
          : !capabilities.wakeAssetsPresent
          ? 'assetMissing'
          : !capabilities.wakeSupportedAbi
          ? 'unsupportedAbi'
          : null;
      if (failure != null) {
        _fail(failure);
        return false;
      }
      await _arm(generation);
      return _current(generation);
    } catch (_) {
      if (_current(generation)) _fail('engineLoadFailed');
      return false;
    } finally {
      _starting = false;
      _notify();
    }
  }

  Future<void> _native(Future<void> flight) async {
    _nativeFlights.add(flight);
    try {
      await flight;
    } finally {
      _nativeFlights.remove(flight);
    }
  }

  void _timer(Duration duration, int generation, void Function() fire) {
    _deadline?.cancel();
    _deadline = _timerFactory(duration, () {
      if (!_current(generation)) return;
      fire();
    });
  }

  Future<void> _arm(int generation) async {
    if (!_current(generation)) return;
    _requestId = null;
    _purpose = null;
    _nativeFinal = null;
    _preview = '';
    _ready = false;
    final arm = _armId = 'arm-${++_operation}';
    _stateTo(HandsFreeState.listening);
    _timer(
      const Duration(seconds: 5),
      generation,
      () => _fail('recognizerDeadline'),
    );
    await _native(
      platform.armWake(ownerId: ownerId, generation: generation, armId: arm),
    );
  }

  Future<void> _recognize(
    int generation,
    VoiceRecognitionPurpose purpose,
  ) async {
    if (!_current(generation)) return;
    _armId = null;
    _purpose = purpose;
    final request = _requestId = 'speech-${++_operation}';
    _nativeFinal = null;
    _speechStarted = false;
    _finishing = false;
    _ready = false;
    _preview = '';
    _stateTo(
      purpose == VoiceRecognitionPurpose.handsFreeFollowup
          ? HandsFreeState.followup
          : HandsFreeState.recording,
    );
    _timer(
      const Duration(seconds: 5),
      generation,
      () => _fail('recognizerDeadline'),
    );
    await _native(
      platform.recognizeOnce(
        ownerId: ownerId,
        generation: generation,
        requestId: request,
        purpose: purpose,
        localeId: localeId(),
        listenForMs: 30000,
        pauseForMs: 3000,
        noSpeechTimeoutMs: purpose == VoiceRecognitionPurpose.handsFreeFollowup
            ? _followupTimeout.inMilliseconds
            : null,
      ),
    );
  }

  void _run(Future<void> flight, int generation) {
    unawaited(
      flight.catchError((Object _) {
        if (_current(generation)) _fail('engineLoadFailed');
      }),
    );
  }

  void _event(VoicePlatformEvent event) {
    final generation = _generation;
    if (!_current(generation) ||
        event.ownerId != ownerId ||
        event.generation != generation ||
        event.seq <= _seq) {
      return;
    }
    _seq = event.seq;
    if (event.type == VoicePlatformEventType.error &&
        (event.operationId == 'session' ||
            event.operationId == _armId ||
            event.operationId == _requestId)) {
      _fail(event.code ?? 'engineLoadFailed');
      return;
    }
    if (event.type == VoicePlatformEventType.stopped &&
        event.operationId == 'session') {
      revoke(HandsFreeStopReason.nativeDetached);
      return;
    }
    if (event.operationId == _armId && _state == HandsFreeState.listening) {
      if (event.type == VoicePlatformEventType.wakeArmed) {
        _deadline?.cancel();
        _ready = true;
        _notify();
      } else if (event.type == VoicePlatformEventType.wakeDetected) {
        _deadline?.cancel();
        _armId =
            null; // Consume before starting another asynchronous operation.
        _run(
          _recognize(generation, VoiceRecognitionPurpose.handsFreeInitial),
          generation,
        );
      }
      return;
    }
    if (event.operationId != _requestId || _requestId == null) return;
    switch (event.type) {
      case VoicePlatformEventType.recognitionReady:
        if (_ready) return;
        if (event.purpose != _purpose) {
          _fail('engineLoadFailed');
          return;
        }
        _ready = true;
        if (_purpose == VoiceRecognitionPurpose.handsFreeFollowup &&
            !_speechStarted) {
          _timer(
            _followupTimeout,
            generation,
            () => _run(_noSpeech(generation), generation),
          );
        } else {
          _timer(
            const Duration(seconds: 30),
            generation,
            () => _run(_finish(generation), generation),
          );
        }
        _notify();
      case VoicePlatformEventType.speechStarted:
        if (_speechStarted || _finishing) return;
        _speechStarted = true;
        _stateTo(HandsFreeState.recording);
        _timer(
          const Duration(seconds: 30),
          generation,
          () => _run(_finish(generation), generation),
        );
      case VoicePlatformEventType.speechResult:
        if (event.isFinal == true) {
          _nativeFinal ??= event.transcript?.trim();
        }
        _preview = event.transcript ?? '';
        _notify();
      case VoicePlatformEventType.recognitionEnded:
        _deadline?.cancel();
        final request = _requestId!;
        final text = _nativeFinal;
        _requestId = null;
        _ready = false;
        if (event.hadNativeFinal == true &&
            event.reason == 'final' &&
            text != null &&
            text.isNotEmpty &&
            _consumed.add(request)) {
          _stateTo(HandsFreeState.waiting);
          _run(_submit(request, text, _authority!), generation);
        } else if (const {
          'final',
          'empty',
          'noSpeech',
          'deadline',
        }.contains(event.reason)) {
          _run(_arm(generation), generation);
        } else {
          _fail('recognizerAudio');
        }
      default:
        break;
    }
  }

  Future<void> _noSpeech(int generation) async {
    final request = _requestId;
    if (request == null) return;
    _requestId =
        null; // Deadline cancels eligibility before native cancellation.
    await _native(
      platform.cancelRecognition(
        ownerId: ownerId,
        generation: generation,
        requestId: request,
      ),
    );
    if (_current(generation)) await _arm(generation);
  }

  Future<void> _finish(int generation) async {
    final request = _requestId;
    if (request == null || _finishing) return;
    _finishing = true;
    _timer(
      const Duration(seconds: 2),
      generation,
      () => _fail('recognizerDeadline'),
    );
    await _native(
      platform.finishRecognition(
        ownerId: ownerId,
        generation: generation,
        requestId: request,
      ),
    );
    if (_current(generation) && _requestId == request) {
      _fail('recognizerDeadline');
    }
  }

  Future<void> _submit(
    String request,
    String text,
    HandsFreeAuthority authority,
  ) async {
    if (!isCurrent(authority)) return;
    final turn = await submitHandsFreePrompt(
      HandsFreePrompt(
        requestId: request,
        transcript: text,
        authority: authority,
      ),
    );
    if (!isCurrent(authority)) return;
    if (turn == null) {
      _fail('submissionRejected');
      return;
    }
    final outcome = await turn.settled;
    if (!isCurrent(authority)) return;
    if (outcome.clientTurnId != turn.clientTurnId ||
        outcome.status != HandsFreeTurnStatus.completed ||
        outcome.publicFinalText?.trim().isNotEmpty != true) {
      _fail(switch (outcome.status) {
        HandsFreeTurnStatus.needsInput => 'turnNeedsInput',
        HandsFreeTurnStatus.unknown => 'turnUnknown',
        _ => 'turnFailed',
      });
      return;
    }
    // recognitionEnded already established native owner=none. No history reads
    // or arbitrary assistant rows enter this exact turn's one-shot TTS path.
    _preview = '';
    _stateTo(HandsFreeState.speaking);
    final speech = speakHandsFreeReply(
      HandsFreeReply(
        clientTurnId: turn.clientTurnId,
        text: outcome.publicFinalText!,
        authority: authority,
      ),
    );
    final joined = speech.then<void>((_) {}, onError: (Object _) {});
    _speechFlight = joined;
    final spoken = await speech;
    if (identical(_speechFlight, joined)) _speechFlight = null;
    if (!isCurrent(authority)) return;
    if (spoken != HandsFreeSpeechOutcome.completed) {
      _fail(switch (spoken) {
        HandsFreeSpeechOutcome.canceled => 'ttsCanceled',
        HandsFreeSpeechOutcome.unavailable => 'ttsUnavailable',
        HandsFreeSpeechOutcome.deadline => 'ttsDeadline',
        _ => 'ttsError',
      });
      return;
    }
    if (!await _echoGuard() || !isCurrent(authority)) return;
    if (_followupTimeout == Duration.zero) {
      await _arm(authority.controllerGeneration);
    } else {
      await _recognize(
        authority.controllerGeneration,
        VoiceRecognitionPurpose.handsFreeFollowup,
      );
    }
  }

  Future<bool> _echoGuard() {
    final done = _echoDone = Completer<bool>();
    _echo = _timerFactory(const Duration(milliseconds: 300), () {
      if (!done.isCompleted) done.complete(true);
    });
    return done.future;
  }

  void _fail(String code) {
    if (!active) return;
    revoke(HandsFreeStopReason.nativeDetached);
    _errorCode = code;
    _stateTo(HandsFreeState.error);
  }

  /// Invalidates consent synchronously. Cleanup immediately tells native about
  /// the *canceled* generation, then joins every accepted start and playback.
  void revoke(HandsFreeStopReason reason) {
    final canceled = _authority?.controllerGeneration;
    if (canceled == null) return;
    ++_generation;
    _authority = null;
    _armId = _requestId = null;
    _purpose = null;
    _nativeFinal = null;
    _preview = '';
    _ready = false;
    _deadline?.cancel();
    _echo?.cancel();
    final echoDone = _echoDone;
    if (echoDone != null && !echoDone.isCompleted) echoDone.complete(false);
    _echoDone = null;
    final starts = _startFlight;
    final native = List<Future<void>>.of(_nativeFlights);
    final speech = _speechFlight;
    final prior = _cleanup;
    // Invoke stop before waiting for anything which may itself be held in native.
    final stop = Future<void>.sync(
      () => platform.stop(
        ownerId: ownerId,
        generation: canceled,
        reason: reason.name,
      ),
    );
    final silence = Future<void>.sync(cancelSpeech);
    _cleanup = _join(prior, starts, native, speech, stop, silence);
    _stateTo(HandsFreeState.idle);
  }

  Future<void> _join(
    Future<void>? prior,
    Future<bool>? start,
    List<Future<void>> native,
    Future<void>? speech,
    Future<void> stop,
    Future<void> silence,
  ) async {
    // A failed start is already sanitized by its owning path; a failed release
    // is different and must fence future capture instead of claiming settlement.
    Future<void> absorb(Future<dynamic> value) async {
      try {
        await value;
      } catch (_) {}
    }

    await Future.wait([
      if (prior != null) absorb(prior),
      if (start != null) absorb(start),
      for (final flight in native) absorb(flight),
      if (speech != null) absorb(speech),
      () async {
        try {
          await Future.wait([stop, silence]);
        } catch (_) {
          _cleanupFailed = true;
        }
      }(),
    ]);
  }

  Future<void> stop({required HandsFreeStopReason reason}) {
    revoke(reason);
    if (_state == HandsFreeState.error) _stateTo(HandsFreeState.idle);
    return settle();
  }

  Future<void> settle() async {
    await _cleanup;
    if (_cleanupFailed) {
      throw StateError('Voice release could not be confirmed');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    revoke(HandsFreeStopReason.disposed);
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
