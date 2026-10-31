package com.eyedeadevelopment.fluttertts

import android.content.ContentValues
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.flutter.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.lang.reflect.Field
import java.util.Locale
import java.util.MissingResourceException
import java.util.UUID


/** FlutterTtsPlugin  */
class FlutterTtsPlugin : MethodCallHandler, FlutterPlugin {
    private var handler: Handler? = null
    private var methodChannel: MethodChannel? = null
    // All mutable ownership is confined to the main Handler. Provider callbacks
    // carry an immutable utterance ID; no posted closure reads a global Result.
    private data class Playback(val id: String, val epoch: Long, val result: Result?, val file: Boolean)
    private data class Pending(val call: MethodCall, val result: Result, val epoch: Long)
    private var epoch = 0L
    private var engineEpoch = 0L
    private val playbacks = HashMap<String, Playback>()
    private var speechOwner: Playback? = null
    private var fileOwner: Playback? = null
    private var awaitSpeakCompletion = false
    private var speaking = false
    private var awaitSynthCompletion = false
    private var synth = false
    private var context: Context? = null
    private var tts: TextToSpeech? = null
    private val tag = "TTS"
    private val pendingMethodCalls = ArrayList<Pending>()
    private val utterances = HashMap<String, String>()
    private var bundle: Bundle? = null
    private var silencems = 0
    private var lastProgress = 0
    private var currentText: String? = null
    private var pauseText: String? = null
    private var isPaused: Boolean = false
    private var queueMode: Int = TextToSpeech.QUEUE_FLUSH
    private var ttsStatus: Int? = null
    private var selectedEngine: String? = null
    private var engineResult: Result? = null
    private var parcelFileDescriptor: ParcelFileDescriptor? = null
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null

    companion object {
        private const val SILENCE_PREFIX = "SIL_"
        private const val SYNTHESIZE_TO_FILE_PREFIX = "STF_"
    }

    private fun initInstance(messenger: BinaryMessenger, context: Context) {
        this.context = context
        methodChannel = MethodChannel(messenger, "flutter_tts")
        methodChannel!!.setMethodCallHandler(this)
        handler = Handler(Looper.getMainLooper())
        bundle = Bundle()
        initialize()
    }

    /** Android Plugin APIs  */
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        initInstance(binding.binaryMessenger, binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stop()
        ++engineEpoch
        engineResult?.success(0)
        engineResult = null
        tts!!.shutdown()
        context = null
        methodChannel!!.setMethodCallHandler(null)
        methodChannel = null
    }

    // Look up only on the main looper, after the queued delivery boundary.
    // UUID + epoch + owner identity prevents an old terminal borrowing B's result.
    private fun callback(id: String, action: (Playback) -> Unit) {
        handler!!.post {
            val owned = playbacks[id]
            if (owned != null && owned.epoch == epoch &&
                (if (owned.file) fileOwner === owned else speechOwner === owned)) action(owned)
        }
    }

    private fun terminal(owned: Playback, success: Int, event: String, argument: Any = true) {
        if (playbacks.remove(owned.id) !== owned) return
        utterances.remove(owned.id)
        if (owned.file) {
            fileOwner = null
            synth = false
            closeParcelFileDescriptor(success == 0)
        } else {
            speechOwner = null
            speaking = false
            lastProgress = 0
            pauseText = null
            releaseAudioFocus()
        }
        owned.result?.success(success)
        // Already on main: do not enqueue a second uncorrelated channel event.
        methodChannel?.invokeMethod(event, argument)
    }

    private fun progress(owned: Playback, start: Int, end: Int) {
        if (owned.file) return
        val text = utterances[owned.id] ?: return
        if (start < 0 || end < start || end > text.length) return
        lastProgress = start
        methodChannel?.invokeMethod("speak.onProgress", hashMapOf(
            "text" to text, "start" to start.toString(), "end" to end.toString(),
            "word" to text.substring(start, end)))
    }

    private val utteranceProgressListener: UtteranceProgressListener =
        object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String) = callback(utteranceId) { owned ->
                val event = if (owned.file) "synth.onStart" else if (isPaused) "speak.onContinue" else "speak.onStart"
                if (!owned.file) isPaused = false
                methodChannel?.invokeMethod(event, true)
                if (Build.VERSION.SDK_INT < 26) progress(owned, 0, utterances[utteranceId]?.length ?: 0)
            }
            override fun onDone(utteranceId: String) = callback(utteranceId) { owned ->
                terminal(owned, 1, if (owned.file) "synth.onComplete" else "speak.onComplete")
            }
            override fun onStop(utteranceId: String, interrupted: Boolean) = callback(utteranceId) { owned ->
                terminal(owned, 0, if (owned.file) "synth.onError" else "speak.onCancel")
            }
            override fun onRangeStart(utteranceId: String, startAt: Int, endAt: Int, frame: Int) =
                callback(utteranceId) { owned -> progress(owned, startAt, endAt) }
            @Deprecated("")
            override fun onError(utteranceId: String) = onError(utteranceId, TextToSpeech.ERROR)
            override fun onError(utteranceId: String, errorCode: Int) = callback(utteranceId) { owned ->
                terminal(owned, 0, if (owned.file) "synth.onError" else "speak.onError", "Error from TextToSpeech")
            }
        }

    private fun queue(call: MethodCall, result: Result) {
        pendingMethodCalls.add(Pending(call, result, epoch))
    }

    private fun drainPending() {
        val pending = pendingMethodCalls.toList()
        pendingMethodCalls.clear()
        for (entry in pending) {
            if (entry.epoch != epoch && entry.call.method in listOf("speak", "synthesizeToFile")) {
                entry.result.success(0)
            } else onMethodCall(entry.call, entry.result)
        }
    }

    // Register before any platform call, which may callback synchronously.
    private fun register(id: String, result: Result?, file: Boolean): Playback {
        val owned = Playback(id, epoch, result, file)
        playbacks[id] = owned
        if (file) fileOwner = owned else speechOwner = owned
        return owned
    }

    private fun initialize(engine: String? = null, result: Result? = null) {
        val generation = ++engineEpoch
        engineResult?.success(0)
        engineResult = result
        var delivered = false
        ttsStatus = null
        tts = TextToSpeech(context, { status ->
            handler!!.post {
                if (generation == engineEpoch && !delivered) {
                    delivered = true
                    // Keep the exact engine-result identity across initialization.
                    engineResult = result
                    if (result == null) onInitListenerWithoutCallback.onInit(status)
                    else onInitListenerWithCallback.onInit(status)
                    engineResult = null
                }
            }
        }, engine)
    }

    private val onInitListenerWithCallback: TextToSpeech.OnInitListener =
        TextToSpeech.OnInitListener { status ->
            // Handle pending method calls (sent while TTS was initializing)
            synchronized(this@FlutterTtsPlugin) {
                ttsStatus = status

            }

            if (status == TextToSpeech.SUCCESS) {
                tts!!.setOnUtteranceProgressListener(utteranceProgressListener)
                try {
                    val locale: Locale = tts!!.defaultVoice.locale
                    if (isLanguageAvailable(locale)) {
                        tts!!.language = locale
                    }
                } catch (e: NullPointerException) {
                    Log.e(tag, "getDefaultLocale: " + e.message)
                } catch (e: IllegalArgumentException) {
                    Log.e(tag, "getDefaultLocale: " + e.message)
                }

                engineResult!!.success(1)
            } else {
                engineResult!!.error("TtsError","Failed to initialize TextToSpeech with status: $status", null)
            }
            drainPending()
        }

    private val onInitListenerWithoutCallback: TextToSpeech.OnInitListener =
        TextToSpeech.OnInitListener { status ->
            // Handle pending method calls (sent while TTS was initializing)
            synchronized(this@FlutterTtsPlugin) {
                ttsStatus = status

            }

            if (status == TextToSpeech.SUCCESS) {
                tts!!.setOnUtteranceProgressListener(utteranceProgressListener)
                try {
                    val locale: Locale = tts!!.defaultVoice.locale
                    if (isLanguageAvailable(locale)) {
                        tts!!.language = locale
                    }
                } catch (e: NullPointerException) {
                    Log.e(tag, "getDefaultLocale: " + e.message)
                } catch (e: IllegalArgumentException) {
                    Log.e(tag, "getDefaultLocale: " + e.message)
                }
            } else {
                Log.e(tag, "Failed to initialize TextToSpeech with status: $status")
            }
            drainPending()
        }

    override fun onMethodCall(call: MethodCall, result: Result) {
        // Stop/pause revoke pending initialization/retry starts before any await.
        if (call.method == "stop" || call.method == "pause") {
            isPaused = call.method == "pause"
            if (isPaused) pauseText = pauseText?.substring(lastProgress)
            else { pauseText = null; lastProgress = 0 }
            stop()
            result.success(1)
            methodChannel?.invokeMethod(if (isPaused) "speak.onPause" else "speak.onCancel", true)
            return
        }
        // If TTS is still loading
        synchronized(this@FlutterTtsPlugin) {
            if (ttsStatus == null) {
                // Suspend method call until the TTS engine is ready
                queue(call, result)
                return
            }
        }
        if (ttsStatus != TextToSpeech.SUCCESS && call.method in listOf("speak", "synthesizeToFile")) {
            result.success(0)
            return
        }
        when (call.method) {
            "speak" -> {
                var text: String = call.argument("text")!!
                val focus: Boolean = call.argument("focus")!!
                if (pauseText == null) {
                    pauseText = text
                    currentText = pauseText!!
                }
                if (isPaused) {
                    // Ensure the text hasn't changed
                    if (currentText == text) {
                        text = pauseText!!
                    } else {
                        pauseText = text
                        currentText = pauseText!!
                        lastProgress = 0
                    }
                }
                if (speaking) {
                    // If TTS is set to queue mode, allow the utterance to be queued up rather than discarded
                    if (queueMode == TextToSpeech.QUEUE_FLUSH) {
                        result.success(0)
                        return
                    }
                }
                val uuid = UUID.randomUUID().toString()
                val awaited = awaitSpeakCompletion && queueMode == TextToSpeech.QUEUE_FLUSH
                val owned = register(uuid, if (awaited) result else null, false)
                speaking = awaited
                val b = speak(text, focus, uuid)
                if (!b) {
                    if (ttsStatus != null) {
                        terminal(owned, 0, "speak.onError", "Error from TextToSpeech")
                        return
                    }
                    playbacks.remove(uuid)
                    if (speechOwner === owned) speechOwner = null
                    utterances.remove(uuid)
                    speaking = false
                    synchronized(this@FlutterTtsPlugin) {
                        queue(call, result)
                    }
                    return
                }
                // Only use await speak completion if queueMode is set to QUEUE_FLUSH
                if (!awaited) {
                    result.success(1)
                }
            }

            "awaitSpeakCompletion" -> {
                awaitSpeakCompletion = java.lang.Boolean.parseBoolean(call.arguments.toString())
                result.success(1)
            }

            "awaitSynthCompletion" -> {
                awaitSynthCompletion = java.lang.Boolean.parseBoolean(call.arguments.toString())
                result.success(1)
            }

            "getMaxSpeechInputLength" -> {
                val res = maxSpeechInputLength
                result.success(res)
            }

            "synthesizeToFile" -> {
                val text: String? = call.argument("text")
                if (fileOwner != null) {
                    result.success(0)
                    return
                }
                val fileName: String? = call.argument("fileName")
                val isFullPath: Boolean? = call.argument("isFullPath")
                val uuid = SYNTHESIZE_TO_FILE_PREFIX + UUID.randomUUID().toString()
                register(uuid, if (awaitSynthCompletion) result else null, true)
                synth = awaitSynthCompletion
                synthesizeToFile(text!!, fileName!!, isFullPath!!, uuid)
                if (!awaitSynthCompletion) {
                    result.success(1)
                }
            }

            "setEngine" -> {
                val engine: String = call.arguments.toString()
                setEngine(engine, result)
            }

            "setSpeechRate" -> {
                val rate: String = call.arguments.toString()
                // To make the FlutterTts API consistent across platforms,
                // Android 1.0 is mapped to flutter 0.5.
                setSpeechRate(rate.toFloat() * 2.0f)
                result.success(1)
            }

            "setVolume" -> {
                val volume: String = call.arguments.toString()
                setVolume(volume.toFloat(), result)
            }

            "setPitch" -> {
                val pitch: String = call.arguments.toString()
                setPitch(pitch.toFloat(), result)
            }

            "setLanguage" -> {
                val language: String = call.arguments.toString()
                setLanguage(language, result)
            }

            "getLanguages" -> getLanguages(result)
            "getVoices" -> getVoices(result)
            "getSpeechRateValidRange" -> getSpeechRateValidRange(result)
            "getEngines" -> getEngines(result)
            "getDefaultEngine" -> getDefaultEngine(result)
            "getDefaultVoice" -> getDefaultVoice(result)
            "setVoice" -> {
                val voice: HashMap<String?, String>? = call.arguments()
                setVoice(voice!!, result)
            }

            "clearVoice" -> clearVoice(result)

            "isLanguageAvailable" -> {
                val language: String = call.arguments.toString()
                val locale: Locale = Locale.forLanguageTag(language)
                result.success(isLanguageAvailable(locale))
            }

            "setSilence" -> {
                val silencems: String = call.arguments.toString()
                this.silencems = silencems.toInt()
            }

            "setSharedInstance" -> result.success(1)
            "isLanguageInstalled" -> {
                val language: String = call.arguments.toString()
                result.success(isLanguageInstalled(language))
            }

            "areLanguagesInstalled" -> {
                val languages: List<String?>? = call.arguments()
                result.success(areLanguagesInstalled(languages!!))
            }

            "setQueueMode" -> {
                val queueMode: String = call.arguments.toString()
                this.queueMode = queueMode.toInt()
                result.success(1)
            }

            "setAudioAttributesForNavigation" -> {
                setAudioAttributesForNavigation()
                result.success(1)
            }

            else -> result.notImplemented()
        }
    }

    private fun setSpeechRate(rate: Float) {
        tts!!.setSpeechRate(rate)
    }

    private fun isLanguageAvailable(locale: Locale?): Boolean {
        return tts!!.isLanguageAvailable(locale) >= TextToSpeech.LANG_AVAILABLE
    }

    private fun areLanguagesInstalled(languages: List<String?>): Map<String?, Boolean> {
        val result: MutableMap<String?, Boolean> = HashMap()
        for (language in languages) {
            result[language] = isLanguageInstalled(language)
        }
        return result
    }

    private fun isLanguageInstalled(language: String?): Boolean {
        val locale: Locale = Locale.forLanguageTag(language!!)
        if (isLanguageAvailable(locale)) {
            var voiceToCheck: Voice? = null
            for (v in tts!!.voices) {
                if (v.locale == locale && !v.isNetworkConnectionRequired) {
                    voiceToCheck = v
                    break
                }
            }
            if (voiceToCheck != null) {
                val features: Set<String> = voiceToCheck.features
                return (!features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED))
            }
        }
        return false
    }

    private fun setEngine(engine: String?, result: Result) {
        stop()
        tts?.shutdown()
        selectedEngine = engine
        initialize(engine, result)
    }

    private fun setLanguage(language: String?, result: Result) {
        val locale: Locale = Locale.forLanguageTag(language!!)
        if (isLanguageAvailable(locale)) {
            tts!!.language = locale
            result.success(1)
        } else {
            result.success(0)
        }
    }

    private fun setVoice(voice: HashMap<String?, String>, result: Result) {
        for (ttsVoice in tts!!.voices) {
            if (ttsVoice.name == voice["name"] && ttsVoice.locale
                    .toLanguageTag() == voice["locale"]
            ) {
                tts!!.voice = ttsVoice
                result.success(1)
                return
            }
        }
        Log.d(tag, "Voice name not found: $voice")
        result.success(0)
    }

    private fun clearVoice(result: Result) {
        tts!!.voice = tts!!.defaultVoice
        result.success(1)
    }

    private fun setVolume(volume: Float, result: Result) {
        if (volume in (0.0f..1.0f)) {
            bundle!!.putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
            result.success(1)
        } else {
            Log.d(tag, "Invalid volume $volume value - Range is from 0.0 to 1.0")
            result.success(0)
        }
    }

    private fun setPitch(pitch: Float, result: Result) {
        if (pitch in (0.5f..2.0f)) {
            tts!!.setPitch(pitch)
            result.success(1)
        } else {
            Log.d(tag, "Invalid pitch $pitch value - Range is from 0.5 to 2.0")
            result.success(0)
        }
    }

    private fun getVoices(result: Result) {
        val voices = ArrayList<HashMap<String, String>>()
        try {
            for (voice in tts!!.voices) {
                val voiceMap = HashMap<String, String>()
                readVoiceProperties(voiceMap, voice)
                voices.add(voiceMap)
            }
            result.success(voices)
        } catch (e: NullPointerException) {
            Log.d(tag, "getVoices: " + e.message)
            result.success(null)
        }
    }

    private fun getLanguages(result: Result) {
        val locales = ArrayList<String>()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                // While this method was introduced in API level 21, it seems that it
                // has not been implemented in the speech service side until API Level 23.
                for (locale in tts!!.availableLanguages) {
                    locales.add(locale.toLanguageTag())
                }
            } else {
                for (locale in Locale.getAvailableLocales()) {
                    if (locale.variant.isEmpty() && isLanguageAvailable(locale)) {
                        locales.add(locale.toLanguageTag())
                    }
                }
            }
        } catch (e: MissingResourceException) {
            Log.d(tag, "getLanguages: " + e.message)
        } catch (e: NullPointerException) {
            Log.d(tag, "getLanguages: " + e.message)
        }
        result.success(locales)
    }

    private fun getEngines(result: Result) {
        val engines = ArrayList<String>()
        try {
            for (engineInfo in tts!!.engines) {
                engines.add(engineInfo.name)
            }
        } catch (e: Exception) {
            Log.d(tag, "getEngines: " + e.message)
        }
        result.success(engines)
    }

    private fun getDefaultEngine(result: Result) {
        val defaultEngine: String? = tts!!.defaultEngine
        result.success(defaultEngine)
    }

    private fun getDefaultVoice(result: Result) {
        val defaultVoice: Voice? = tts!!.defaultVoice
        val voice = HashMap<String, String>()
        if (defaultVoice != null) {
            readVoiceProperties(voice, defaultVoice)
        }
        result.success(voice)
    }
    // Add voice properties into the voice map
    fun readVoiceProperties(map: MutableMap<String, String>, voice: Voice) {
        map["name"] = voice.name
        map["locale"] = voice.locale.toLanguageTag()
        map["quality"] = qualityToString(voice.quality)
        map["latency"] = latencyToString(voice.latency)
        map["network_required"] = if (voice.isNetworkConnectionRequired) "1" else "0"
        map["features"] = voice.features.joinToString(separator = "\t")
        
    }

    // Function to map quality integer to the constant name
    fun qualityToString(quality: Int): String {
        return when (quality) {
            Voice.QUALITY_VERY_HIGH -> "very high"
            Voice.QUALITY_HIGH -> "high"
            Voice.QUALITY_NORMAL -> "normal"
            Voice.QUALITY_LOW -> "low"
            Voice.QUALITY_VERY_LOW -> "very low"
            else -> "unknown"
        }
    }
    // Function to map latency integer to the constant name
    fun latencyToString(quality: Int): String {
        return when (quality) {
            Voice.LATENCY_VERY_HIGH -> "very high"
            Voice.LATENCY_HIGH -> "high"
            Voice.LATENCY_NORMAL -> "normal"
            Voice.LATENCY_LOW -> "low"
            Voice.LATENCY_VERY_LOW -> "very low"
            else -> "unknown"
        }
    }

    private fun getSpeechRateValidRange(result: Result) {
        // Valid values available in the android documentation.
        // https://developer.android.com/reference/android/speech/tts/TextToSpeech#setSpeechRate(float)
        // To make the FlutterTts API consistent across platforms,
        // we map Android 1.0 to flutter 0.5 and so on.
        val data = HashMap<String, String>()
        data["min"] = "0"
        data["normal"] = "0.5"
        data["max"] = "1.5"
        data["platform"] = "android"
        result.success(data)
    }

    private fun speak(text: String, focus: Boolean, uuid: String): Boolean {
        utterances[uuid] = text
        return if (ismServiceConnectionUsable(tts)) {
            if(focus){
                requestAudioFocus()
            }

            if (silencems > 0) {
                tts!!.playSilentUtterance(
                    silencems.toLong(),
                    TextToSpeech.QUEUE_FLUSH,
                    SILENCE_PREFIX + uuid
                )
                tts!!.speak(text, TextToSpeech.QUEUE_ADD, bundle, uuid) == 0
            } else {
                tts!!.speak(text, queueMode, bundle, uuid) == 0
            }
        } else {
            initialize(selectedEngine)
            false
        }
    }

    private fun stop() {
        ++epoch
        val canceled = playbacks.values.toList()
        playbacks.clear()
        speechOwner = null
        fileOwner = null
        speaking = false
        synth = false
        utterances.clear()
        val queued = pendingMethodCalls.filter { it.call.method in listOf("speak", "synthesizeToFile") }
        pendingMethodCalls.removeAll(queued.toSet())
        // Revoke every owner before platform stop can synchronously callback.
        tts?.stop()
        releaseAudioFocus()
        closeParcelFileDescriptor(true)
        canceled.forEach { it.result?.success(0) }
        queued.forEach { it.result.success(0) }
    }

    private val maxSpeechInputLength: Int
        get() = TextToSpeech.getMaxSpeechInputLength()

    private fun closeParcelFileDescriptor(isError: Boolean)  {
        if (this.parcelFileDescriptor != null)  {
            if (isError) {
                this.parcelFileDescriptor!!.closeWithError("Error synthesizing TTS to file")
            } else {
                this.parcelFileDescriptor!!.close()
            }
            this.parcelFileDescriptor = null
        }
    }

    private fun synthesizeToFile(text: String, fileName: String, isFullPath: Boolean, uuid: String) {
        val fullPath: String
        bundle!!.putString(
            TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID,
            uuid
        )

        val result: Int =
            if(isFullPath){
                val file = File(fileName)
                fullPath = file.path

                tts!!.synthesizeToFile(text, bundle!!, file!!, uuid)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val resolver = this.context?.contentResolver
                val contentValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, "audio/wav")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_MUSIC)
                }
                val uri = resolver?.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, contentValues)
                this.parcelFileDescriptor = resolver?.openFileDescriptor(uri!!, "rw")
                fullPath = uri?.path + File.separatorChar + fileName

                tts!!.synthesizeToFile(text, bundle!!, parcelFileDescriptor!!, uuid)
            } else {
                val musicDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
                val file = File(musicDir, fileName)
                fullPath = file.path

                tts!!.synthesizeToFile(text, bundle!!, file!!, uuid)
            }

        if (result == TextToSpeech.SUCCESS) {
            Log.d(tag, "Successfully created file : $fullPath")
        } else {
            fileOwner?.let { terminal(it, 0, "synth.onError", "Error from TextToSpeech") }
            Log.d(tag, "Failed creating file : $fullPath")
        }
    }

    private fun invokeMethod(method: String, arguments: Any) {
        handler!!.post {
            if (methodChannel != null) methodChannel!!.invokeMethod(
                method,
                arguments
            )
        }
    }

    private fun ismServiceConnectionUsable(tts: TextToSpeech?): Boolean {
        var isBindConnection = true
        if (tts == null) {
            return false
        }
        val fields: Array<Field> = tts.javaClass.declaredFields
        for (j in fields.indices) {
            fields[j].isAccessible = true
            if ("mServiceConnection" == fields[j].name && "android.speech.tts.TextToSpeech\$Connection" == fields[j].type.name) {
                try {
                    if (fields[j][tts] == null) {
                        isBindConnection = false
                        Log.e(tag, "*******TTS -> mServiceConnection == null*******")
                    }
                } catch (e: IllegalArgumentException) {
                    e.printStackTrace()
                } catch (e: IllegalAccessException) {
                    e.printStackTrace()
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
        return isBindConnection
    }

    // Method to set AudioAttributes for navigation usage
    private fun setAudioAttributesForNavigation() {
        if (tts != null) {
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            tts!!.setAudioAttributes(audioAttributes)
        }
    }

    private fun requestAudioFocus() {
        audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setOnAudioFocusChangeListener { /* opcional para monitorar mudanças de foco */ }
                .build()
            audioManager?.requestAudioFocus(audioFocusRequest!!)
        } else {
            audioManager?.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        }
    }

    private fun releaseAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager?.abandonAudioFocusRequest(it) }
        } else {
            audioManager?.abandonAudioFocus(null)
        }
        audioFocusRequest = null
    }
}
