// Background keep-alive contract: the Dart side must drive the native
// foreground service exactly once per background/foreground cycle, must
// treat a refused or missing native start as a silent no-op (the
// transport's reconnect-on-resume loop is the fallback), and must never
// lose a stop that races an in-flight start (a stuck foreground service
// means a permanent notification while the app is in the foreground).
import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_keepalive_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void mockChannel(Future<Object?> Function(MethodCall call)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ConnectionKeepAliveService.channel, handler);
  }

  tearDown(() => mockChannel(null));

  test(
    'start/stop drive the native service once each and are idempotent',
    () async {
      final calls = <String>[];
      mockChannel((call) async {
        calls.add(call.method);
        return true;
      });

      final service = ConnectionKeepAliveService();
      await service.start();
      await service.start();
      expect(service.isActive, isTrue);
      await service.stop();
      await service.stop();
      expect(service.isActive, isFalse);
      // Second start is deduped; stops always reach the native side (an
      // extra no-op stop is the price of guaranteed recovery), so the
      // native state — not the IPC count — is the idempotency contract.
      expect(calls, ['start', 'stop', 'stop']);
    },
  );

  test('a refused native start leaves the service inactive', () async {
    final calls = <String>[];
    mockChannel((call) async {
      calls.add(call.method);
      return false;
    });

    final service = ConnectionKeepAliveService();
    await service.start();
    expect(service.isActive, isFalse);
    // stop() must still reach the native side even when Dart believes
    // nothing is running: state can diverge (hot restart, engine
    // reattach), and an unconditional stop is the only recovery path.
    // Native stopService on a stopped service is a cheap no-op.
    await service.stop();
    expect(calls, ['start', 'stop']);
  });

  test('missing native plugin (non-Android host) is a silent no-op', () async {
    // No mock handler: invokeMethod throws MissingPluginException.
    final service = ConnectionKeepAliveService();
    await service.start();
    expect(service.isActive, isFalse);
    await service.stop();
  });

  test('a stop racing an in-flight start still stops the service', () async {
    // Minimize-then-immediately-return: the native start is still pending
    // when the resume arrives. If stop() only looks at the settled state
    // it no-ops, the start then succeeds, and the foreground service (and
    // its notification) stays up for the whole foreground session.
    final startResult = Completer<bool>();
    final calls = <String>[];
    mockChannel((call) async {
      calls.add(call.method);
      if (call.method == 'start') return startResult.future;
      return true;
    });

    final service = ConnectionKeepAliveService();
    final starting = service.start();
    await pumpEventQueue();
    await service.stop();
    startResult.complete(true);
    await starting;
    await pumpEventQueue();

    expect(calls, containsAllInOrder(['start', 'stop']));
    expect(service.isActive, isFalse);
  });

  test(
    'a background request landing during an in-flight start is retained',
    () async {
      // Rapid cycle: minimize → resume → minimize while the first native
      // start is still pending. The second start() is refused by the
      // in-flight guard and the first start then sees a stale cycle and
      // stops — leaving the app backgrounded with keep-alive inactive,
      // precisely when it is needed. The latest requested state must win.
      final firstStart = Completer<bool>();
      var first = true;
      final calls = <String>[];
      mockChannel((call) async {
        calls.add(call.method);
        if (call.method == 'start' && first) {
          first = false;
          return firstStart.future;
        }
        return true;
      });

      final service = ConnectionKeepAliveService();

      // Background: start #1 goes in flight.
      service.onAppLifecycleState(
        AppLifecycleState.inactive,
        hasActiveTurn: true,
      );
      await pumpEventQueue();

      // Resume: stop races the pending start.
      service.onAppLifecycleState(
        AppLifecycleState.resumed,
        hasActiveTurn: true,
      );
      await pumpEventQueue();

      // Background again: start #2 is refused while start #1 is in flight.
      service.onAppLifecycleState(
        AppLifecycleState.inactive,
        hasActiveTurn: true,
      );
      await pumpEventQueue();

      // The first native start finally lands (stale). The retained
      // background request must still leave the service active.
      firstStart.complete(true);
      await pumpEventQueue();
      await pumpEventQueue();

      expect(service.isActive, isTrue);
      expect(calls, containsAllInOrder(['start', 'stop', 'start']));

      // A later resume must still stop it: the retained retry is not a
      // permanently unstoppable service.
      service.onAppLifecycleState(
        AppLifecycleState.resumed,
        hasActiveTurn: true,
      );
      await pumpEventQueue();
      expect(service.isActive, isFalse);
      expect(calls.last, 'stop');
    },
  );

  test(
    'a retained background retry runs even when the stale first start was refused',
    () async {
      // Same rapid cycle as above, but the in-flight start is refused
      // (Android 12+ background-start limits). The retained request must
      // still get its own fresh attempt once the refusal lands.
      final firstStart = Completer<bool>();
      var first = true;
      final calls = <String>[];
      mockChannel((call) async {
        calls.add(call.method);
        if (call.method == 'start' && first) {
          first = false;
          return firstStart.future;
        }
        return true;
      });

      final service = ConnectionKeepAliveService();
      service.onAppLifecycleState(
        AppLifecycleState.inactive,
        hasActiveTurn: true,
      );
      await pumpEventQueue();
      service.onAppLifecycleState(
        AppLifecycleState.resumed,
        hasActiveTurn: true,
      );
      await pumpEventQueue();
      service.onAppLifecycleState(
        AppLifecycleState.inactive,
        hasActiveTurn: true,
      );
      await pumpEventQueue();

      firstStart.complete(false); // refused start lands, stale
      await pumpEventQueue();
      await pumpEventQueue();

      expect(service.isActive, isTrue);
      expect(calls, containsAllInOrder(['start', 'stop', 'start']));
    },
  );

  test('a malformed native reply does not wedge the service forever', () async {
    // The typed invoke casts the reply to bool?; a malformed native
    // response raises TypeError. If that escapes without resetting
    // _starting, every later start only records _pendingStart and the
    // keep-alive is permanently dead while backgrounded.
    var malformed = true;
    mockChannel((call) async {
      if (call.method == 'start' && malformed) return 42;
      return true;
    });

    final service = ConnectionKeepAliveService();
    await expectLater(service.start(), throwsA(isA<TypeError>()));

    // Once the native side behaves, a fresh background must work again.
    malformed = false;
    await service.start();
    expect(service.isActive, isTrue);
  });

  test('a stop after a retained request cancels it', () async {
    // background → resume → background → resume, all while the first
    // native start is pending. The second (final) stop must cancel the
    // retained background request — a retry after resume would leave a
    // foreground service running in the foreground.
    final firstStart = Completer<bool>();
    var first = true;
    final calls = <String>[];
    mockChannel((call) async {
      calls.add(call.method);
      if (call.method == 'start' && first) {
        first = false;
        return firstStart.future;
      }
      return true;
    });

    final service = ConnectionKeepAliveService();
    unawaited(service.start());
    await pumpEventQueue();
    await service.stop();
    unawaited(service.start()); // records the retained request
    await pumpEventQueue();
    await service.stop(); // cancels it

    firstStart.complete(true);
    await pumpEventQueue();
    await pumpEventQueue();

    expect(service.isActive, isFalse);
    // No retry: only the first start ever reached the native side.
    expect(calls.where((c) => c == 'start'), hasLength(1));
    expect(calls.last, 'stop');
  });

  test('a stop racing the retained retry still stops the service', () async {
    // The compensating-stop contract must hold for the retry start too,
    // not just the first-generation start.
    final firstStart = Completer<bool>();
    final retryStart = Completer<bool>();
    var first = true;
    final calls = <String>[];
    mockChannel((call) async {
      calls.add(call.method);
      if (call.method == 'start') {
        if (first) {
          first = false;
          return firstStart.future;
        }
        return retryStart.future;
      }
      return true;
    });

    final service = ConnectionKeepAliveService();
    unawaited(service.start());
    await pumpEventQueue();
    await service.stop();
    unawaited(service.start()); // retained
    await pumpEventQueue();

    firstStart.complete(true); // stale → retry fires, now in flight
    await pumpEventQueue();
    await service.stop(); // races the retry
    retryStart.complete(true);
    await pumpEventQueue();
    await pumpEventQueue();

    expect(service.isActive, isFalse);
    expect(calls, containsAllInOrder(['start', 'stop', 'start', 'stop']));
    expect(calls.last, 'stop');
  });

  test(
    'a refused retry leaves the service inactive with nothing leaked',
    () async {
      // The retained retry's own start may be refused too (OEM limits).
      // That is a silent no-op — no active flag, no orphaned service.
      final firstStart = Completer<bool>();
      var first = true;
      final calls = <String>[];
      mockChannel((call) async {
        calls.add(call.method);
        if (call.method == 'start') {
          if (first) {
            first = false;
            return firstStart.future;
          }
          return false; // the retry is refused
        }
        return true;
      });

      final service = ConnectionKeepAliveService();
      unawaited(service.start());
      await pumpEventQueue();
      await service.stop();
      unawaited(service.start());
      await pumpEventQueue();
      firstStart.complete(true);
      await pumpEventQueue();
      await pumpEventQueue();

      expect(service.isActive, isFalse);
      expect(calls, containsAllInOrder(['start', 'stop', 'start']));
    },
  );

  test(
    'burst double-start leaves no stale retained request past a stop',
    () async {
      // inactive → paused fires start() twice with no stop between: the
      // second records a retained request that never gets consumed (the
      // first start lands non-stale). stop() must clear it so a later
      // stop-raced start cannot resurrect the service after resume.
      final slowStart = Completer<bool>();
      var slow = false;
      final calls = <String>[];
      mockChannel((call) async {
        calls.add(call.method);
        if (call.method == 'start' && slow) return slowStart.future;
        return true;
      });

      final service = ConnectionKeepAliveService();
      unawaited(service.start());
      unawaited(service.start()); // records a stale retained request
      await pumpEventQueue();
      expect(service.isActive, isTrue);

      await service.stop(); // must clear the stale retained request
      expect(service.isActive, isFalse);

      // A stop racing the next start must still stop it (no retry).
      slow = true;
      unawaited(service.start());
      await pumpEventQueue();
      await service.stop();
      slowStart.complete(true);
      await pumpEventQueue();
      await pumpEventQueue();

      expect(service.isActive, isFalse);
      // The burst's second start was only recorded, never dispatched.
      expect(calls.where((c) => c == 'start'), hasLength(2));
      expect(calls.last, 'stop');
    },
  );

  test(
    'lifecycle policy: background-with-active-turn starts; resume and detach stop',
    () async {
      final calls = <String>[];
      mockChannel((call) async {
        calls.add(call.method);
        return true;
      });

      final service = ConnectionKeepAliveService();

      // Backgrounding with no unresolved turn must not start the service:
      // an idle (or reconnecting) socket alone is not user-perceptible work,
      // and a persistent notification for it fails Play's FGS criteria.
      service.onAppLifecycleState(
        AppLifecycleState.inactive,
        hasActiveTurn: false,
      );
      await pumpEventQueue();
      expect(calls, isEmpty);

      // Backgrounding with a turn in flight starts it.
      service.onAppLifecycleState(
        AppLifecycleState.inactive,
        hasActiveTurn: true,
      );
      await pumpEventQueue();
      expect(calls, ['start']);

      // Exiting the app via Back must stop it: after `detached` there is no
      // Dart isolate left to ever stop it, and the FGS would pin the
      // process with a permanent notification protecting a dead socket.
      service.onAppLifecycleState(
        AppLifecycleState.detached,
        hasActiveTurn: true,
      );
      await pumpEventQueue();
      expect(calls, containsAllInOrder(['start', 'stop']));
      expect(service.isActive, isFalse);

      // Resume stops too (a foregrounded app never needs the service).
      service.onAppLifecycleState(
        AppLifecycleState.inactive,
        hasActiveTurn: true,
      );
      await pumpEventQueue();
      service.onAppLifecycleState(
        AppLifecycleState.resumed,
        hasActiveTurn: true,
      );
      await pumpEventQueue();
      expect(calls, containsAllInOrder(['start', 'stop', 'start', 'stop']));
    },
  );

  test('a turn settling while backgrounded stops the service', () async {
    // The bounded-lifetime stop condition: the service exists only while
    // a user-visible turn is unresolved. A turn that completes minutes
    // after backgrounding must end the notification then, not at resume.
    final calls = <String>[];
    mockChannel((call) async {
      calls.add(call.method);
      return true;
    });

    final service = ConnectionKeepAliveService();
    service.onAppLifecycleState(
      AppLifecycleState.inactive,
      hasActiveTurn: true,
    );
    await pumpEventQueue();
    expect(calls, ['start']);

    service.onTurnActivityChanged(false);
    await pumpEventQueue();
    expect(calls, containsAllInOrder(['start', 'stop']));
    expect(service.isActive, isFalse);

    // A second settle event (multiple turns settling) stays a no-op.
    service.onTurnActivityChanged(false);
    await pumpEventQueue();
    expect(calls.last, 'stop');
  });

  test('a turn starting while backgrounded starts the service', () async {
    // Backgrounded with no turn (service not started), then a detached or
    // recovered turn becomes active: the app must gain protection then.
    final calls = <String>[];
    mockChannel((call) async {
      calls.add(call.method);
      return true;
    });

    final service = ConnectionKeepAliveService();
    service.onAppLifecycleState(
      AppLifecycleState.inactive,
      hasActiveTurn: false,
    );
    await pumpEventQueue();
    expect(calls, isEmpty);

    service.onTurnActivityChanged(true);
    await pumpEventQueue();
    expect(calls, ['start']);
    expect(service.isActive, isTrue);
  });

  test(
    'a new turn starting during an in-flight stop re-earns the service',
    () async {
      // Stop racing a fresh start: the settle dispatches a native stop that
      // is still in flight when a new turn becomes active. The later
      // request (start) must win and the service must end up live, with the
      // native side seeing stop-before-start (platform messages are FIFO).
      final calls = <String>[];
      final stopGate = Completer<void>();
      mockChannel((call) async {
        calls.add(call.method);
        if (call.method == 'stop') await stopGate.future;
        return true;
      });

      final service = ConnectionKeepAliveService();
      service.onAppLifecycleState(
        AppLifecycleState.inactive,
        hasActiveTurn: true,
      );
      await pumpEventQueue();
      expect(calls, ['start']);

      service.onTurnActivityChanged(false);
      await pumpEventQueue();
      expect(calls.last, 'stop'); // native stop still gated

      service.onTurnActivityChanged(true);
      await pumpEventQueue();
      stopGate.complete();
      await pumpEventQueue();

      expect(calls, containsAllInOrder(['start', 'stop', 'start']));
      expect(service.isActive, isTrue);
    },
  );

  test('turn activity in the foreground never touches the service', () async {
    // A foregrounded app never needs the service; a turn starting or
    // settling while resumed must not start (or spuriously stop) it.
    final calls = <String>[];
    mockChannel((call) async {
      calls.add(call.method);
      return true;
    });

    final service = ConnectionKeepAliveService();
    service.onTurnActivityChanged(true);
    service.onTurnActivityChanged(false);
    await pumpEventQueue();
    expect(calls, isEmpty);
  });

  test('turn activity after detach does not restart the service', () async {
    // After `detached` no isolate survives to stop the service, so the
    // backgrounded flag must be cleared: a late activity event (e.g. a
    // settle landing during teardown) must not start it again.
    final calls = <String>[];
    mockChannel((call) async {
      calls.add(call.method);
      return true;
    });

    final service = ConnectionKeepAliveService();
    service.onAppLifecycleState(
      AppLifecycleState.inactive,
      hasActiveTurn: true,
    );
    await pumpEventQueue();
    service.onAppLifecycleState(
      AppLifecycleState.detached,
      hasActiveTurn: true,
    );
    await pumpEventQueue();
    expect(calls, containsAllInOrder(['start', 'stop']));

    service.onTurnActivityChanged(true);
    await pumpEventQueue();
    expect(calls.last, 'stop');
    expect(service.isActive, isFalse);
  });
}
