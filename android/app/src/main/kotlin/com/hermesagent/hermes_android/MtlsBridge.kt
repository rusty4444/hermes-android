package com.hermesagent.hermes_android

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.KeyChain
import android.security.KeyChainAliasCallback
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.InterruptedIOException
import java.lang.ref.WeakReference
import java.net.Socket
import java.net.SocketTimeoutException
import java.security.KeyStore
import java.security.Principal
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.KeyManager
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLException
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.SSLPeerUnverifiedException
import javax.net.ssl.TrustManager
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509ExtendedKeyManager
import javax.net.ssl.X509TrustManager
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import okio.ByteString

internal class MtlsBridge(
    activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val activityReference = WeakReference(activity)
    private val context: Context = activity.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newCachedThreadPool()
    private val requests = ConcurrentHashMap<String, RequestState>()
    private val webSockets = ConcurrentHashMap<String, WebSocketState>()
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)

    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var detached = false
    @Volatile private var chooserResult: MethodChannel.Result? = null
    private val eventReadyResults = mutableListOf<MethodChannel.Result>()

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "chooseCertificate" -> chooseCertificate(call, result)
            "describeCertificate" -> describeCertificate(call, result)
            "waitUntilEventStreamReady" -> waitUntilEventStreamReady(result)
            "startRequest" -> startRequest(call, result)
            "cancelRequest" -> cancelRequest(call, result)
            "startWebSocket" -> startWebSocket(call, result)
            "sendWebSocket" -> sendWebSocket(call, result)
            "closeWebSocket" -> closeWebSocket(call, result)
            "close" -> {
                cancelAll(emitEvents = true)
                closeAllWebSockets(emitEvents = true)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        val readyResults = synchronized(eventReadyResults) {
            val results = eventReadyResults.toList()
            eventReadyResults.clear()
            results
        }
        readyResults.forEach { it.success(null) }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun waitUntilEventStreamReady(result: MethodChannel.Result) {
        if (detached) {
            result.error("activity_detached", "The secure transport is unavailable.", null)
            return
        }
        if (eventSink != null) {
            result.success(null)
            return
        }
        synchronized(eventReadyResults) {
            if (eventSink != null) {
                result.success(null)
            } else {
                eventReadyResults.add(result)
            }
        }
    }

    fun detach() {
        if (detached) return
        detached = true
        chooserResult?.error("activity_detached", "Certificate selection was interrupted.", null)
        chooserResult = null
        val readyResults = synchronized(eventReadyResults) {
            val results = eventReadyResults.toList()
            eventReadyResults.clear()
            results
        }
        readyResults.forEach {
            it.error("activity_detached", "The secure transport is unavailable.", null)
        }
        cancelAll(emitEvents = false)
        closeAllWebSockets(emitEvents = false)
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        ioExecutor.shutdownNow()
        activityReference.clear()
    }

    private fun chooseCertificate(call: MethodCall, result: MethodChannel.Result) {
        if (call.arguments != null && call.arguments !is Map<*, *>) {
            result.error("invalid_arguments", "Invalid certificate chooser arguments.", null)
            return
        }
        val arguments = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
        val hostValue = arguments["host"]
        val portValue = arguments["port"]
        val aliasValue = arguments["alias"]
        if ((hostValue != null && (hostValue !is String || hostValue.isBlank())) ||
            (portValue != null && (portValue !is Int || portValue !in 1..65535)) ||
            (aliasValue != null && (aliasValue !is String || aliasValue.isBlank()))
        ) {
            result.error("invalid_arguments", "Invalid certificate chooser arguments.", null)
            return
        }
        val currentActivity = activityReference.get()
        if (currentActivity == null || currentActivity.isFinishing || detached) {
            result.error("activity_unavailable", "Certificate selection is unavailable.", null)
            return
        }
        if (chooserResult != null) {
            result.error("chooser_active", "A certificate chooser is already active.", null)
            return
        }

        chooserResult = result
        val callback = ChooserCallback(this)
        try {
            KeyChain.choosePrivateKeyAlias(
                currentActivity,
                callback,
                arrayOf("RSA", "EC"),
                null,
                hostValue as String?,
                (portValue as Int?) ?: -1,
                aliasValue as String?,
            )
        } catch (_: RuntimeException) {
            chooserResult = null
            result.error("chooser_unavailable", "Certificate selection could not be opened.", null)
        }
    }

    private fun onAliasChosen(alias: String?) {
        if (detached || chooserResult == null) return
        if (alias == null) {
            runOnMain { finishChooser(null) }
            return
        }
        ioExecutor.execute {
            val description = certificateDescription(alias) ?: aliasDescription(alias)
            runOnMain { finishChooser(description) }
        }
    }

    private fun finishChooser(value: Map<String, String>?) {
        val result = chooserResult ?: return
        chooserResult = null
        if (!detached) result.success(value)
    }

    private fun describeCertificate(call: MethodCall, result: MethodChannel.Result) {
        val alias =
            when (val arguments = call.arguments) {
                is String -> arguments
                is Map<*, *> -> arguments["alias"]
                else -> null
            }
        if (alias !is String || alias.isBlank()) {
            result.error("invalid_arguments", "A non-empty alias is required.", null)
            return
        }
        ioExecutor.execute {
            val description = certificateDescription(alias)
            runOnMain {
                if (!detached) result.success(description)
            }
        }
    }

    private fun certificateDescription(alias: String): Map<String, String>? =
        try {
            val leaf = KeyChain.getCertificateChain(context, alias)?.firstOrNull() ?: return null
            val label = leaf.subjectX500Principal?.name?.takeIf { it.isNotBlank() } ?: alias
            mapOf("alias" to alias, "label" to label)
        } catch (_: Exception) {
            null
        }

    private fun aliasDescription(alias: String) = mapOf("alias" to alias, "label" to alias)

    private fun startRequest(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val requestId = arguments?.get("requestId")
        val alias = arguments?.get("alias")
        val methodValue = arguments?.get("method")
        val urlValue = arguments?.get("url")
        val headersValue = arguments?.get("headers")
        val bodyValue = arguments?.get("body")

        if (requestId !is String || requestId.isBlank() ||
            alias !is String || alias.isBlank() ||
            methodValue !is String || methodValue.isBlank() ||
            urlValue !is String ||
            headersValue !is Map<*, *> ||
            (bodyValue != null && bodyValue !is ByteArray)
        ) {
            result.error("invalid_arguments", "Invalid mTLS request arguments.", null)
            return
        }
        val url = urlValue.toHttpUrlOrNull()
        if (url == null || url.scheme != "https") {
            result.error("invalid_arguments", "The request URL must use HTTPS.", null)
            return
        }
        val headers = LinkedHashMap<String, String>()
        for ((name, value) in headersValue) {
            if (name !is String || value !is String) {
                result.error("invalid_arguments", "Headers must contain only string values.", null)
                return
            }
            headers[name] = value
        }
        val method = methodValue.uppercase(Locale.US)
        val body = bodyValue as ByteArray?
        if ((method == "GET" || method == "HEAD") && body != null) {
            result.error("invalid_arguments", "$method requests cannot contain a body.", null)
            return
        }
        val requestBody =
            when {
                body != null -> body.toRequestBody()
                method in METHODS_REQUIRING_BODY -> ByteArray(0).toRequestBody()
                else -> null
            }
        val request =
            try {
                Request.Builder().url(url).apply {
                    headers.forEach { (name, value) -> addHeader(name, value) }
                }.method(method, requestBody).build()
            } catch (_: IllegalArgumentException) {
                result.error("invalid_arguments", "The HTTP method or headers are invalid.", null)
                return
            }

        val state = RequestState(requestId, result)
        if (requests.putIfAbsent(requestId, state) != null) {
            result.error("duplicate_request", "That request ID is already active.", null)
            return
        }

        ioExecutor.execute {
            try {
                val keyManager = AliasKeyManager.load(context, alias)
                    ?: throw CertificateUnavailableException()
                val trustManager = systemTrustManager()
                val sslContext = SSLContext.getInstance("TLS").apply {
                    init(
                        arrayOf<KeyManager>(keyManager),
                        arrayOf<TrustManager>(trustManager),
                        SecureRandom(),
                    )
                }
                val client = OkHttpClient.Builder()
                    .sslSocketFactory(sslContext.socketFactory, trustManager)
                    .followRedirects(false)
                    .build()
                val okHttpCall = client.newCall(request)
                state.client = client
                state.call = okHttpCall
                if (state.cancelled.get() || detached) {
                    okHttpCall.cancel()
                    failRequest(state, "request_cancelled", "Request cancelled.")
                    return@execute
                }
                okHttpCall.enqueue(RequestCallback(state))
            } catch (_: CertificateUnavailableException) {
                failRequest(state, "certificate_unavailable", "The selected certificate is unavailable.")
            } catch (_: Exception) {
                failRequest(state, "request_failed", "The secure request could not be started.")
            }
        }
    }

    private fun cancelRequest(call: MethodCall, result: MethodChannel.Result) {
        val requestId =
            when (val arguments = call.arguments) {
                is String -> arguments
                is Map<*, *> -> arguments["requestId"]
                else -> null
            }
        if (requestId !is String || requestId.isBlank()) {
            result.error("invalid_arguments", "A non-empty request ID is required.", null)
            return
        }
        val state = requests.remove(requestId)
        if (state != null) {
            state.cancel()
            completeStartError(state, "request_cancelled", "Request cancelled.")
            emitError(state, "Request cancelled.")
            state.cleanup()
        }
        result.success(state != null)
    }

    private fun cancelAll(emitEvents: Boolean) {
        requests.entries.toList().forEach { (requestId, state) ->
            if (requests.remove(requestId, state)) {
                state.cancel()
                completeStartError(state, "request_cancelled", "Request cancelled.")
                if (emitEvents) emitError(state, "Request cancelled.")
                state.cleanup()
            }
        }
    }

        private fun startWebSocket(call: MethodCall, result: MethodChannel.Result) {
            val arguments = call.arguments as? Map<*, *>
            val socketId = arguments?.get("socketId")
            val alias = arguments?.get("alias")
            val urlValue = arguments?.get("url")
            if (socketId !is String || socketId.isBlank() ||
                alias !is String || alias.isBlank() ||
                urlValue !is String || !urlValue.startsWith("wss://", ignoreCase = true)
            ) {
                result.error("invalid_arguments", "Invalid mTLS WebSocket arguments.", null)
                return
            }
            val request =
                try {
                    Request.Builder().url(urlValue).build()
                } catch (_: IllegalArgumentException) {
                    result.error("invalid_arguments", "The WebSocket URL is invalid.", null)
                    return
                }
            val state = WebSocketState(socketId, result)
            if (webSockets.putIfAbsent(socketId, state) != null) {
                result.error("duplicate_websocket", "That WebSocket ID is already active.", null)
                return
            }

            ioExecutor.execute {
                try {
                    val client = secureClient(alias)
                    if (!state.attachClient(client)) {
                        failWebSocketStart(
                            state,
                            "request_cancelled",
                            "WebSocket connection cancelled.",
                        )
                        return@execute
                    }
                    val socket = client.newWebSocket(request, SecureWebSocketListener(state))
                    state.socket = socket
                    if (state.cancelled.get() || detached) {
                        socket.cancel()
                        failWebSocketStart(state, "request_cancelled", "WebSocket connection cancelled.")
                    }
                } catch (_: CertificateUnavailableException) {
                    failWebSocketStart(
                        state,
                        "certificate_unavailable",
                        "The selected certificate is unavailable.",
                    )
                } catch (_: Exception) {
                    failWebSocketStart(
                        state,
                        "websocket_failed",
                        "The secure WebSocket could not be started.",
                    )
                }
            }
        }

        private fun sendWebSocket(call: MethodCall, result: MethodChannel.Result) {
            val arguments = call.arguments as? Map<*, *>
            val socketId = arguments?.get("socketId")
            val data = arguments?.get("data")
            if (socketId !is String || socketId.isBlank() || data !is String) {
                result.error("invalid_arguments", "Invalid WebSocket message arguments.", null)
                return
            }
            val state = webSockets[socketId]
            if (state == null || !state.opened.get() || state.terminal.get()) {
                result.error("websocket_unavailable", "The secure WebSocket is not connected.", null)
                return
            }
            val sent =
                try {
                    state.socket?.send(data) == true
                } catch (_: RuntimeException) {
                    false
                }
            result.success(sent)
        }

        private fun closeWebSocket(call: MethodCall, result: MethodChannel.Result) {
            val arguments = call.arguments as? Map<*, *>
            val socketId = arguments?.get("socketId")
            val code = arguments?.get("code")
            val reason = arguments?.get("reason")
            if (socketId !is String || socketId.isBlank() ||
                code !is Int || reason !is String
            ) {
                result.error("invalid_arguments", "Invalid WebSocket close arguments.", null)
                return
            }
            val state = webSockets[socketId]
            if (state == null) {
                result.success(null)
                return
            }
            if (!state.opened.get()) {
                state.cancelled.set(true)
                state.socket?.cancel()
                failWebSocketStart(
                    state,
                    "request_cancelled",
                    "WebSocket connection cancelled.",
                )
                result.success(null)
                return
            }
            val closing =
                try {
                    state.socket?.close(code, reason) == true
                } catch (_: IllegalArgumentException) {
                    result.error("invalid_arguments", "Invalid WebSocket close code or reason.", null)
                    return
                }
            if (!closing) {
                finishWebSocket(state, code, reason, emitEvent = true)
            }
            result.success(null)
        }

        private fun closeAllWebSockets(emitEvents: Boolean) {
            webSockets.entries.toList().forEach { (_, state) ->
                state.cancelled.set(true)
                state.socket?.cancel()
                finishWebSocket(
                    state,
                    1001,
                    "Secure transport closed.",
                    emitEvent = emitEvents,
                )
            }
        }

        private inner class SecureWebSocketListener(
            private val state: WebSocketState,
        ) : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                state.socket = webSocket
                state.opened.set(true)
                runOnMain {
                    if (detached || state.cancelled.get() || state.terminal.get()) {
                        webSocket.cancel()
                        failWebSocketStart(
                            state,
                            "request_cancelled",
                            "WebSocket connection cancelled.",
                        )
                    } else if (state.resultCompleted.compareAndSet(false, true)) {
                        state.result.success(null)
                    }
                }
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                emitWebSocketData(state, text)
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                emitWebSocketData(state, bytes.utf8())
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(code, reason)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                finishWebSocket(state, code, reason, emitEvent = true)
            }

            override fun onFailure(webSocket: WebSocket, error: Throwable, response: Response?) {
                response?.close()
                if (state.resultCompleted.compareAndSet(false, true)) {
                    webSockets.remove(state.socketId, state)
                    runOnMain {
                        if (!detached) {
                            state.result.error(
                                "websocket_failed",
                                safeWebSocketFailureMessage(error),
                                null,
                            )
                        }
                    }
                    state.cleanup()
                } else {
                    failWebSocket(state, safeWebSocketFailureMessage(error))
                }
            }
        }

        private fun emitWebSocketData(state: WebSocketState, data: String) {
            if (!detached && state.opened.get() && !state.terminal.get()) {
                emit(
                    mapOf(
                        "requestId" to state.socketId,
                        "type" to "websocketData",
                        "data" to data,
                    ),
                )
            }
        }

        private fun failWebSocketStart(state: WebSocketState, code: String, message: String) {
            state.terminal.set(true)
            webSockets.remove(state.socketId, state)
            if (state.resultCompleted.compareAndSet(false, true)) {
                runOnMain {
                    if (!detached) state.result.error(code, message, null)
                }
            }
            state.cleanup()
        }

        private fun failWebSocket(state: WebSocketState, message: String) {
            if (!state.terminal.compareAndSet(false, true)) return
            webSockets.remove(state.socketId, state)
            emit(
                mapOf(
                    "requestId" to state.socketId,
                    "type" to "websocketError",
                    "message" to message,
                ),
            )
            state.cleanup()
        }

        private fun finishWebSocket(
            state: WebSocketState,
            code: Int,
            reason: String,
            emitEvent: Boolean,
        ) {
            if (!state.terminal.compareAndSet(false, true)) return
            webSockets.remove(state.socketId, state)
            if (emitEvent && !detached && state.resultCompleted.get()) {
                emit(
                    mapOf(
                        "requestId" to state.socketId,
                        "type" to "websocketClosed",
                        "code" to code,
                        "reason" to reason,
                    ),
                )
            } else if (!state.resultCompleted.get()) {
                completeWebSocketStartError(
                    state,
                    "websocket_closed",
                    "The secure WebSocket closed before connecting.",
                )
            }
            state.cleanup()
        }

        private fun completeWebSocketStartError(
            state: WebSocketState,
            code: String,
            message: String,
        ) {
            if (state.resultCompleted.compareAndSet(false, true)) {
                runOnMain {
                    if (!detached) state.result.error(code, message, null)
                }
            }
        }

        private fun safeWebSocketFailureMessage(error: Throwable): String =
            when (error) {
                is SSLHandshakeException,
                is SSLPeerUnverifiedException,
                is SSLException -> "Secure WebSocket connection failed."
                is SocketTimeoutException -> "Secure WebSocket connection timed out."
                else -> "Secure WebSocket network request failed."
            }

    private inner class RequestCallback(private val state: RequestState) : Callback {
        override fun onFailure(call: Call, error: IOException) {
            failRequest(state, "request_failed", safeFailureMessage(error, state.cancelled.get()))
        }

        override fun onResponse(call: Call, response: Response) {
            val body = response.body
            state.responseBody = body
            val metadata = mapOf(
                "requestId" to state.requestId,
                "statusCode" to response.code,
                "reasonPhrase" to response.message,
                "contentLength" to (body?.contentLength() ?: 0L),
                "headers" to combineHeaders(response),
            )
            runOnMain {
                if (detached || state.cancelled.get()) {
                    response.close()
                    failRequest(state, "request_cancelled", "Request cancelled.")
                    return@runOnMain
                }
                if (state.resultCompleted.compareAndSet(false, true)) {
                    state.result.success(metadata)
                    ioExecutor.execute { streamResponse(state, response) }
                } else {
                    response.close()
                    state.cleanup()
                }
            }
        }
    }

    private fun combineHeaders(response: Response): Map<String, String> =
        response.headers.names().associateWith { name ->
            val separator = if (name.equals("set-cookie", ignoreCase = true)) "\n" else ", "
            response.headers.values(name).joinToString(separator)
        }

    private fun streamResponse(state: RequestState, response: Response) {
        try {
            response.use {
                val responseBody = it.body ?: return@use
                responseBody.byteStream().use { input ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    while (true) {
                        if (state.cancelled.get()) throw InterruptedIOException()
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (count > 0) {
                            emitData(state, buffer.copyOf(count))
                        }
                    }
                }
            }
            if (state.cancelled.get()) {
                emitError(state, "Request cancelled.")
            } else {
                emitDone(state)
            }
        } catch (error: Exception) {
            emitError(state, safeFailureMessage(error, state.cancelled.get()))
        } finally {
            requests.remove(state.requestId, state)
            state.cleanup()
        }
    }

    private fun failRequest(state: RequestState, code: String, message: String) {
        requests.remove(state.requestId, state)
        state.responseBody?.closeSafely()
        completeStartError(state, code, message)
        emitError(state, message)
        state.cleanup()
    }

    private fun completeStartError(state: RequestState, code: String, message: String) {
        if (state.resultCompleted.compareAndSet(false, true)) {
            runOnMain {
                if (!detached) state.result.error(code, message, null)
            }
        }
    }

    private fun emitData(state: RequestState, data: ByteArray) {
        synchronized(state) {
            if (!detached && !state.cancelled.get() && !state.terminalEvent.get()) {
                emit(mapOf("requestId" to state.requestId, "type" to "data", "data" to data))
            }
        }
    }

    private fun emitDone(state: RequestState) {
        synchronized(state) {
            if (!detached && state.terminalEvent.compareAndSet(false, true)) {
                emit(mapOf("requestId" to state.requestId, "type" to "done"))
            }
        }
    }

    private fun emitError(state: RequestState, message: String) {
        synchronized(state) {
            if (!detached && state.terminalEvent.compareAndSet(false, true)) {
                emit(mapOf("requestId" to state.requestId, "type" to "error", "message" to message))
            }
        }
    }

    private fun emit(event: Map<String, Any>) {
        mainHandler.post {
            if (!detached) eventSink?.success(event)
        }
    }

    private fun safeFailureMessage(error: Exception, cancelled: Boolean): String =
        when {
            cancelled || error is InterruptedIOException && error !is SocketTimeoutException ->
                "Request cancelled."
            error is SocketTimeoutException -> "Request timed out."
            error is SSLHandshakeException ||
                error is SSLPeerUnverifiedException ||
                error is SSLException -> "Secure connection failed."
            else -> "Network request failed."
        }

    private fun runOnMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) action() else mainHandler.post(action)
    }

    private class ChooserCallback(bridge: MtlsBridge) : KeyChainAliasCallback {
        private val bridge = WeakReference(bridge)

        override fun alias(alias: String?) {
            bridge.get()?.onAliasChosen(alias)
        }
    }

    private class RequestState(
        val requestId: String,
        val result: MethodChannel.Result,
    ) {
        val cancelled = AtomicBoolean(false)
        val resultCompleted = AtomicBoolean(false)
        val terminalEvent = AtomicBoolean(false)
        private val cleaned = AtomicBoolean(false)

        @Volatile var call: Call? = null
        @Volatile var responseBody: ResponseBody? = null
        @Volatile var client: OkHttpClient? = null

        fun cancel() {
            cancelled.set(true)
            responseBody?.closeSafely()
            call?.cancel()
        }

        fun cleanup() {
            if (!cleaned.compareAndSet(false, true)) return
            client?.connectionPool?.evictAll()
            client?.dispatcher?.executorService?.shutdown()
        }
    }

    private class WebSocketState(
        val socketId: String,
        val result: MethodChannel.Result,
    ) {
        val opened = AtomicBoolean(false)
        val cancelled = AtomicBoolean(false)
        val resultCompleted = AtomicBoolean(false)
        val terminal = AtomicBoolean(false)
        private val cleaned = AtomicBoolean(false)

        @Volatile var socket: WebSocket? = null
        @Volatile var client: OkHttpClient? = null

        fun attachClient(value: OkHttpClient): Boolean =
            synchronized(this) {
                if (cleaned.get() || cancelled.get()) {
                    value.connectionPool.evictAll()
                    value.dispatcher.executorService.shutdown()
                    false
                } else {
                    client = value
                    true
                }
            }

        fun cleanup() {
            val activeClient =
                synchronized(this) {
                    if (!cleaned.compareAndSet(false, true)) return
                    client.also { client = null }
                }
            activeClient?.connectionPool?.evictAll()
            activeClient?.dispatcher?.executorService?.shutdown()
        }
    }

    private class CertificateUnavailableException : Exception()

    private fun secureClient(alias: String): OkHttpClient {
        val keyManager = AliasKeyManager.load(context, alias)
            ?: throw CertificateUnavailableException()
        val trustManager = systemTrustManager()
        val sslContext = SSLContext.getInstance("TLS").apply {
            init(
                arrayOf<KeyManager>(keyManager),
                arrayOf<TrustManager>(trustManager),
                SecureRandom(),
            )
        }
        return OkHttpClient.Builder()
            .sslSocketFactory(sslContext.socketFactory, trustManager)
            .followRedirects(false)
            .build()
    }

    companion object {
        private const val METHOD_CHANNEL = "com.hermesagent.hermes_android/mtls"
        private const val EVENT_CHANNEL = "com.hermesagent.hermes_android/mtls_events"
        private const val BUFFER_SIZE = 32 * 1024
        private val METHODS_REQUIRING_BODY = setOf("POST", "PUT", "PATCH", "PROPPATCH", "REPORT")

        private fun systemTrustManager(): X509TrustManager {
            val factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
            factory.init(null as KeyStore?)
            return factory.trustManagers.filterIsInstance<X509TrustManager>().singleOrNull()
                ?: throw IllegalStateException("No system X509 trust manager")
        }
    }
}

private fun ResponseBody.closeSafely() {
    try {
        close()
    } catch (_: Exception) {
        // Closing is best-effort during cancellation and teardown.
    }
}

private class AliasKeyManager(
    private val selectedAlias: String,
    private val privateKey: PrivateKey,
    private val certificateChain: Array<X509Certificate>,
) : X509ExtendedKeyManager() {
    private val algorithm = certificateChain.first().publicKey.algorithm

    override fun getClientAliases(
        keyType: String?,
        issuers: Array<out Principal>?,
    ): Array<String>? = if (eligible(keyType)) arrayOf(selectedAlias) else null

    override fun chooseClientAlias(
        keyTypes: Array<out String>?,
        issuers: Array<out Principal>?,
        socket: Socket?,
    ): String? = if (keyTypes?.any(::eligible) == true) selectedAlias else null

    override fun chooseEngineClientAlias(
        keyTypes: Array<out String>?,
        issuers: Array<out Principal>?,
        engine: SSLEngine?,
    ): String? = chooseClientAlias(keyTypes, issuers, null)

    override fun getCertificateChain(alias: String?): Array<X509Certificate>? =
        if (alias == selectedAlias) certificateChain.clone() else null

    override fun getPrivateKey(alias: String?): PrivateKey? =
        if (alias == selectedAlias) privateKey else null

    override fun getServerAliases(
        keyType: String?,
        issuers: Array<out Principal>?,
    ): Array<String>? = null

    override fun chooseServerAlias(
        keyType: String?,
        issuers: Array<out Principal>?,
        socket: Socket?,
    ): String? = null

    override fun chooseEngineServerAlias(
        keyType: String?,
        issuers: Array<out Principal>?,
        engine: SSLEngine?,
    ): String? = null

    private fun eligible(keyType: String?): Boolean {
        val requestedAlgorithm = keyType?.substringBefore('_')
        return requestedAlgorithm != null &&
            requestedAlgorithm.equals(algorithm, ignoreCase = true)
    }

    companion object {
        fun load(context: Context, alias: String): AliasKeyManager? =
            try {
                val key = KeyChain.getPrivateKey(context, alias) ?: return null
                val chain = KeyChain.getCertificateChain(context, alias) ?: return null
                if (chain.isEmpty()) return null
                val algorithm = chain.first().publicKey.algorithm
                if (!algorithm.equals("RSA", ignoreCase = true) &&
                    !algorithm.equals("EC", ignoreCase = true)
                ) {
                    return null
                }
                if (!key.algorithm.equals(algorithm, ignoreCase = true)) return null
                AliasKeyManager(alias, key, chain)
            } catch (_: Exception) {
                null
            }
    }
}
