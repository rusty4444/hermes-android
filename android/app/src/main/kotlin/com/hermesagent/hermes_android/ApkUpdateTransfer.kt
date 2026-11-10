package com.hermesagent.hermes_android

import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

/** Bounded streaming integrity check, independent of Android and networking. */
internal object ApkUpdateTransfer {
    private fun hex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }

    fun receive(
        input: InputStream,
        output: OutputStream,
        expectedSize: Long,
        expectedSha256: String,
        checkActive: () -> Unit,
        progress: (Long) -> Unit,
    ) {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            checkActive()
            val count = input.read(buffer)
            if (count < 0) break
            total += count
            check(total <= expectedSize)
            digest.update(buffer, 0, count)
            output.write(buffer, 0, count)
            progress(total)
        }
        checkActive()
        check(total == expectedSize)
        check(MessageDigest.isEqual(hex(digest.digest()).toByteArray(), expectedSha256.toByteArray()))
    }

    fun matches(file: File, expectedSize: Long, expectedSha256: String): Boolean {
        if (!file.isFile || file.length() != expectedSize) return false
        return runCatching {
            file.inputStream().use { input ->
                val sink = object : OutputStream() {
                    override fun write(value: Int) {}
                    override fun write(bytes: ByteArray, offset: Int, length: Int) {}
                }
                receive(input, sink, expectedSize, expectedSha256, {}, {})
            }
        }.isSuccess
    }
}
