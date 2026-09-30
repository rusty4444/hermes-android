package com.hermesagent.hermes_android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * Notification service helper for Android Auto.
 * Creates a persistent "start new conversation" entry and per-session
 * conversation notifications with voice reply actions.
 *
 * Keeps the most recent connection JSON in SharedPreferences so receivers
 * can start a foreground service and forward replies even when the app
 * process is not running.
 */
object HermesAutoNotifications {

    private const val CHANNEL_ID = "hermes_auto_messaging"
    private const val NEW_CHAT_NOTIFICATION_ID = 1001
    private const val PREFS_NAME = "hermes_auto"
    private const val PREF_LAST_CONNECTION_JSON = "last_connection_json"

    const val ACTION_VOICE_REPLY = "com.hermesagent.hermes_android.VOICE_REPLY"
    const val ACTION_NEW_CHAT = "com.hermesagent.hermes_android.NEW_CHAT"
    const val EXTRA_SESSION_ID = "session_id"
    const val EXTRA_CONNECTION_JSON = "connection_json"
    const val KEY_VOICE_REPLY = "voice_reply"

    const val NEW_SESSION_SENTINEL = "__new__"

    private val sessionNotificationIds = mutableMapOf<String, Int>()
    private var nextSessionNotificationId = 2000

    private fun getSessionNotificationId(sessionId: String): Int {
        return sessionNotificationIds.getOrPut(sessionId) {
            nextSessionNotificationId++
        }
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Hermes Agent",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Android Auto conversations and new chat entry"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun rememberConnectionJson(context: Context, connectionJson: String) {
        if (connectionJson.isEmpty()) return
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(PREF_LAST_CONNECTION_JSON, connectionJson)
            .apply()
    }

    internal fun getConnectionJson(context: Context, connectionJson: String?): String {
        if (!connectionJson.isNullOrEmpty()) return connectionJson
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(PREF_LAST_CONNECTION_JSON, "") ?: ""
    }

    private fun showNotification(context: Context, connectionJson: String, force: Boolean) {
        createChannel(context)

        val tapIntent = PendingIntent.getBroadcast(
            context,
            3,
            Intent(context, NewChatReceiver::class.java).apply {
                action = ACTION_NEW_CHAT
                putExtra(EXTRA_CONNECTION_JSON, connectionJson)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val replyIntent = Intent(context, VoiceReplyReceiver::class.java).apply {
            action = ACTION_VOICE_REPLY
            putExtra(EXTRA_SESSION_ID, NEW_SESSION_SENTINEL)
            putExtra(EXTRA_CONNECTION_JSON, connectionJson)
        }
        val replyPendingIntent = PendingIntent.getBroadcast(
            context,
            4,
            replyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
        val remoteInput = RemoteInput.Builder(KEY_VOICE_REPLY)
            .setLabel(context.getString(R.string.voice_reply_label))
            .build()
        val replyAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_btn_speak_now,
            context.getString(R.string.reply_action_label),
            replyPendingIntent,
        )
            .addRemoteInput(remoteInput)
            .setAllowGeneratedReplies(false)
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY)
            .build()

        val user = Person.Builder()
            .setName(context.getString(R.string.user_name))
            .setKey("user")
            .build()

        val hermes = Person.Builder()
            .setName(context.getString(R.string.new_chat_title))
            .setKey("hermes")
            .setImportant(true)
            .build()

        val style = NotificationCompat.MessagingStyle(user)
            .setConversationTitle(context.getString(R.string.new_chat_title))
            .addMessage(
                NotificationCompat.MessagingStyle.Message(
                    context.getString(R.string.new_chat_body_short),
                    System.currentTimeMillis(),
                    hermes,
                ),
            )
            .setGroupConversation(false)

        // Android Auto specific unread conversation so the car shows it as a message thread.
        val unreadConversation = NotificationCompat.CarExtender.UnreadConversation.Builder(
            context.getString(R.string.new_chat_title),
        )
            .addMessage(context.getString(R.string.new_chat_body_short))
            .setReadPendingIntent(tapIntent)
            .setReplyAction(replyPendingIntent, remoteInput)
            .setLatestTimestamp(System.currentTimeMillis())
            .build()

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_hermes)
            .setContentTitle(context.getString(R.string.new_chat_title))
            .setContentText(context.getString(R.string.new_chat_body_short))
            .setStyle(style)
            .setContentIntent(tapIntent)
            .setAutoCancel(false)
            .setSilent(false)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .addAction(replyAction)
            .extend(NotificationCompat.CarExtender().setUnreadConversation(unreadConversation))
            .build()

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NEW_CHAT_NOTIFICATION_ID, notification)
    }

    /**
     * Public entry used by Dart. Re-posts the entry so Android Auto surfaces it
     * and remembers the connection so the service can recover after app death.
     */
    fun showNewChatEntry(context: Context, connectionJson: String) {
        rememberConnectionJson(context, connectionJson)
        showNotification(context, connectionJson, force = true)
    }

    /**
     * Internal re-post when the receiver detects the app becoming foreground.
     */
    fun refreshNewChatEntry(context: Context, connectionJson: String) {
        rememberConnectionJson(context, connectionJson)
        showNotification(context, connectionJson, force = true)
    }

    fun showAssistantMessage(
        context: Context,
        sessionId: String,
        title: String,
        body: String,
        connectionJson: String,
    ) {
        rememberConnectionJson(context, connectionJson)
        createChannel(context)

        val replyIntent = Intent(context, VoiceReplyReceiver::class.java).apply {
            action = ACTION_VOICE_REPLY
            putExtra(EXTRA_SESSION_ID, sessionId)
            putExtra(EXTRA_CONNECTION_JSON, connectionJson)
        }
        val replyPendingIntent = PendingIntent.getBroadcast(
            context,
            sessionId.hashCode(),
            replyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )

        val remoteInput = RemoteInput.Builder(KEY_VOICE_REPLY)
            .setLabel(context.getString(R.string.voice_reply_label))
            .build()
        val replyAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_btn_speak_now,
            context.getString(R.string.reply_action_label),
            replyPendingIntent,
        )
            .addRemoteInput(remoteInput)
            .setAllowGeneratedReplies(false)
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY)
            .build()

        val user = Person.Builder()
            .setName(context.getString(R.string.user_name))
            .setKey("user")
            .build()

        val assistant = Person.Builder()
            .setName(title)
            .setKey("assistant_$sessionId")
            .build()

        val message = NotificationCompat.MessagingStyle.Message(
            body,
            System.currentTimeMillis(),
            assistant,
        )

        val style = NotificationCompat.MessagingStyle(user)
            .addMessage(message)
            .setGroupConversation(false)

        val contentIntent = PendingIntent.getActivity(
            context,
            sessionId.hashCode(),
            context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                putExtra("session_id", sessionId)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val unreadConversation = NotificationCompat.CarExtender.UnreadConversation.Builder(title)
            .addMessage(body)
            .setReadPendingIntent(contentIntent)
            .setReplyAction(replyPendingIntent, remoteInput)
            .setLatestTimestamp(System.currentTimeMillis())
            .build()

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_hermes)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(style)
            .setContentIntent(contentIntent)
            .setAutoCancel(false)
            .setOngoing(false)
            .setSilent(false)
            .addAction(replyAction)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setOnlyAlertOnce(false)
            .setShowWhen(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .extend(NotificationCompat.CarExtender().setUnreadConversation(unreadConversation))
            .build()

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(getSessionNotificationId(sessionId), notification)
    }

    fun cancelSessionNotification(context: Context, sessionId: String) {
        val id = sessionNotificationIds[sessionId] ?: return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(id)
    }
}

/**
 * Receiver for Android Auto voice replies.
 */
class VoiceReplyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val bundle = RemoteInput.getResultsFromIntent(intent) ?: return
        val message = bundle.getCharSequence(HermesAutoNotifications.KEY_VOICE_REPLY)?.toString() ?: return
        val sessionId = intent.getStringExtra(HermesAutoNotifications.EXTRA_SESSION_ID) ?: return
        val connectionJson = HermesAutoNotifications.getConnectionJson(
            context,
            intent.getStringExtra(HermesAutoNotifications.EXTRA_CONNECTION_JSON),
        )

        // Keep the process alive long enough to send the reply.
        HermesForegroundService.start(context)

        // Forward to Flutter if the engine is alive.
        val engine = FlutterEngineCache.getInstance().get("hermes_engine")
        if (engine != null) {
            val channel = MethodChannel(
                engine.dartExecutor.binaryMessenger,
                "com.hermesagent.hermes_android/auto",
            )
            channel.invokeMethod(
                "voiceReply",
                mapOf(
                    "sessionId" to sessionId,
                    "message" to message,
                    "connectionJson" to connectionJson,
                ),
            )
        } else {
            // If the process is dead, store the reply and launch the app.
            val prefs = context.getSharedPreferences("hermes_auto", Context.MODE_PRIVATE)
            prefs.edit()
                .putString("pending_voice_reply_session", sessionId)
                .putString("pending_voice_reply_message", message)
                .putString("pending_voice_reply_connection", connectionJson)
                .apply()
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                launch.putExtra("session_id", sessionId)
                launch.putExtra("voice_reply", message)
                launch.putExtra("connection_json", connectionJson)
                context.startActivity(launch)
            }
        }
        // Re-post the persistent entry so the microphone shortcut survives the reply.
        HermesAutoNotifications.refreshNewChatEntry(context, connectionJson)
    }
}

/**
 * Receiver for tapping the persistent "start new conversation" entry.
 */
class NewChatReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val connectionJson = HermesAutoNotifications.getConnectionJson(
            context,
            intent.getStringExtra(HermesAutoNotifications.EXTRA_CONNECTION_JSON),
        )

        // Keep the process alive while the user starts the conversation.
        HermesForegroundService.start(context)

        val engine = FlutterEngineCache.getInstance().get("hermes_engine")
        if (engine != null) {
            val channel = MethodChannel(
                engine.dartExecutor.binaryMessenger,
                "com.hermesagent.hermes_android/auto",
            )
            channel.invokeMethod("newChat", mapOf("connectionJson" to connectionJson))
        } else {
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                launch.putExtra("new_chat", true)
                launch.putExtra("connection_json", connectionJson)
                context.startActivity(launch)
            }
        }
        // Keep the entry alive so Android Auto keeps showing the shortcut.
        HermesAutoNotifications.refreshNewChatEntry(context, connectionJson)
    }
}
