package com.eyedeadevelopment.fluttertts;

import android.os.*;
import android.speech.tts.*;
import io.flutter.plugin.common.*;
import java.lang.reflect.Field;
import java.util.*;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.*;
import static org.junit.Assert.*;

/** Executes the shipping plugin through its real MethodCall and listener paths. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35, manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
public class FlutterTtsCorrelationTest {
    FlutterTtsPlugin plugin;
    Engine engine;
    UtteranceProgressListener listener;
    static class Reply implements MethodChannel.Result {
        final List<Object> values = new ArrayList<>();
        public void success(Object value) { values.add(value); }
        public void error(String c, String m, Object d) { throw new AssertionError(c); }
        public void notImplemented() { throw new AssertionError("notImplemented"); }
    }
    public static class Engine extends TextToSpeech {
        String lastId;
        final List<String> starts = new ArrayList<>();
        Engine() { super(RuntimeEnvironment.getApplication(), s -> {}); }
        @Override public int speak(CharSequence text, int mode, Bundle params, String id) {
            lastId = id; starts.add(text.toString()); return SUCCESS;
        }
        @Override public int stop() { return SUCCESS; }
    }
    static void set(Object o, String name, Object value) throws Exception {
        Field f = o.getClass().getDeclaredField(name); f.setAccessible(true); f.set(o, value);
    }
    static Object get(Object o, String name) throws Exception {
        Field f = o.getClass().getDeclaredField(name); f.setAccessible(true); return f.get(o);
    }
    void drain() { Shadows.shadowOf(Looper.getMainLooper()).idle(); }
    Reply call(String method, Object args) {
        Reply r = new Reply(); plugin.onMethodCall(new MethodCall(method, args), r); return r;
    }
    Reply speak(String text) { return call("speak", Map.of("text", text, "focus", false)); }
    @Before public void setup() throws Exception {
        plugin = new FlutterTtsPlugin(); engine = new Engine();
        set(plugin, "handler", new Handler(Looper.getMainLooper()));
        set(plugin, "tts", engine); set(plugin, "ttsStatus", 0);
        set(plugin, "context", RuntimeEnvironment.getApplication());
        set(plugin, "bundle", new Bundle());
        listener = (UtteranceProgressListener) get(plugin, "utteranceProgressListener");
        call("awaitSpeakCompletion", true); call("setQueueMode", 0);
    }
    @Test public void lateDoneAfterStopCannotCompleteB() {
        Reply a = speak("A"); String old = engine.lastId;
        Reply stop = call("stop", null); Reply b = speak("B"); String current = engine.lastId;
        listener.onDone(old); drain();
        assertEquals(List.of(0), a.values); assertEquals(List.of(1), stop.values);
        assertTrue("B must await its own native terminal", b.values.isEmpty());
        listener.onDone(current); drain(); assertEquals(List.of(1), b.values);
    }
    @Test public void queuedDoneBeforeStopCannotBorrowNewResult() {
        Reply a = speak("A"); listener.onDone(engine.lastId);
        call("stop", null); Reply b = speak("B"); String current = engine.lastId;
        drain(); assertEquals(List.of(0), a.values); assertTrue(b.values.isEmpty());
        listener.onDone(current); drain(); assertEquals(List.of(1), b.values);
    }
    @Test public void noOldCallbackControlAndDuplicateTerminal() {
        Reply a = speak("A"); call("stop", null); Reply b = speak("B");
        drain(); assertTrue(b.values.isEmpty());
        listener.onDone(engine.lastId); listener.onDone(engine.lastId); drain();
        assertEquals(List.of(0), a.values); assertEquals(List.of(1), b.values);
    }
    @Test public void oldErrorsStopStartAndProgressCannotMutateB() throws Exception {
        speak("A"); String old = engine.lastId; call("stop", null); Reply b = speak("B");
        listener.onError(old); listener.onError(old, 1); listener.onStop(old, true);
        listener.onStart(old); listener.onRangeStart(old, 0, 1, 0); drain();
        assertTrue(b.values.isEmpty()); assertEquals(true, get(plugin, "speaking"));
        listener.onDone(engine.lastId); drain(); assertEquals(List.of(1), b.values);
    }
    @Test public void pendingInitializationStopRejectsAAllowsExplicitB() throws Exception {
        set(plugin, "ttsStatus", null); Reply a = speak("A"); Reply stop = call("stop", null);
        Reply b = speak("B");
        assertEquals(List.of(1), stop.values); assertEquals(List.of(0), a.values);
        ((TextToSpeech.OnInitListener)get(plugin, "onInitListenerWithoutCallback")).onInit(0);
        drain(); assertEquals(List.of("B"), engine.starts); assertTrue(b.values.isEmpty());
        listener.onDone(engine.lastId); drain(); assertEquals(List.of(1), b.values);
    }
    @Test public void pauseRevokesOldAndResumeKeepsExactResult() {
        Reply a = speak("A"); String old = engine.lastId; call("pause", null);
        Reply b = speak("A"); String current = engine.lastId;
        listener.onDone(old); listener.onStop(old, true); drain();
        assertEquals(List.of(0), a.values); assertTrue(b.values.isEmpty());
        listener.onDone(current); drain(); assertEquals(List.of(1), b.values);
    }
    @Test public void oldTerminalCannotReleaseNewAudioFocus() throws Exception {
        call("speak", Map.of("text", "A", "focus", true)); String old = engine.lastId;
        call("stop", null); Reply b = call("speak", Map.of("text", "B", "focus", true));
        Object focus = get(plugin, "audioFocusRequest"); assertNotNull(focus);
        listener.onDone(old); listener.onStop(old, true); listener.onError(old, 1); drain();
        assertSame(focus, get(plugin, "audioFocusRequest")); assertTrue(b.values.isEmpty());
        listener.onDone(engine.lastId); drain(); assertNull(get(plugin, "audioFocusRequest"));
    }
    @Test public void retryInitializationCannotResurrectStoppedA() throws Exception {
        TextToSpeech disconnected = new TextToSpeech(RuntimeEnvironment.getApplication(), s -> {});
        set(plugin, "tts", disconnected); set(disconnected, "mServiceConnection", null);
        Reply a = speak("A");
        TextToSpeech initializing = (TextToSpeech)get(plugin, "tts");
        TextToSpeech.OnInitListener init = Shadows.shadowOf(initializing).getOnInitListener();
        call("stop", null); Reply b = speak("B"); set(plugin, "tts", engine);
        init.onInit(0); drain();
        assertEquals(List.of(0), a.values); assertEquals(List.of("B"), engine.starts);
        assertTrue(b.values.isEmpty()); listener.onDone(engine.lastId); drain();
        assertEquals(List.of(1), b.values);
    }
    @Test public void synthPrefixAndSilenceCannotCompleteSpeech() {
        Reply b = speak("B"); String current = engine.lastId;
        listener.onDone("STF_" + current); listener.onError("STF_" + current, 1);
        listener.onDone("SIL_" + current); listener.onStart("SIL_" + current); drain();
        assertTrue(b.values.isEmpty()); listener.onDone(current); drain();
        assertEquals(List.of(1), b.values);
    }
    @Test public void genuineErrorAndStopSettleOnlyOwnResultOnce() {
        Reply a = speak("A"); listener.onError(engine.lastId, 1); drain();
        assertEquals(List.of(0), a.values);
        Reply b = speak("B"); listener.onStop(engine.lastId, true); drain();
        assertEquals(List.of(0), b.values); call("stop", null);
        assertEquals(List.of(0), b.values);
    }
}
