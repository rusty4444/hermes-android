package com.hermesagent.hermes_android

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Native authority and pending hints survive process death, but never backup.
 * Every field (including endpoint/auth secret and challenge) is AES-GCM sealed
 * with a non-exportable Android Keystore key. No Flutter engine is required. */
internal object MobilePushStore {
    private const val ALIAS = "hermes_mobile_push_v1"
    // Injectable key acquisition only for JVM tests; production always uses Keystore.
    internal var keyProvider: () -> SecretKey = ::key
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun read(context: Context): JSONObject {
        val prefs = context.getSharedPreferences("mobile_push_sealed", Context.MODE_PRIVATE)
        val raw = prefs.getString("state", null) ?: return JSONObject()
        val bytes = Base64.decode(raw, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, keyProvider(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        return JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
    }
    fun write(context: Context, state: JSONObject) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, keyProvider())
        val bytes = cipher.iv + cipher.doFinal(state.toString().toByteArray(Charsets.UTF_8))
        check(context.getSharedPreferences("mobile_push_sealed", Context.MODE_PRIVATE).edit()
            .putString("state", Base64.encodeToString(bytes, Base64.NO_WRAP)).commit())
    }
}
