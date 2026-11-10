package com.hermesagent.hermes_android

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.file.Files
import java.security.MessageDigest

class ApkUpdateTransferTest {
    private val payload = "verified APK bytes".toByteArray()
    private val sha = MessageDigest.getInstance("SHA-256").digest(payload)
        .joinToString("") { "%02x".format(it.toInt() and 0xff) }

    private fun receive(size: Long = payload.size.toLong(), digest: String = sha, check: () -> Unit = {}): ByteArray {
        val output = ByteArrayOutputStream()
        ApkUpdateTransfer.receive(ByteArrayInputStream(payload), output, size, digest, check, {})
        return output.toByteArray()
    }

    @Test fun correctBytesAreStreamedAndVerified() {
        assertArrayEquals(payload, receive())
    }

    @Test fun truncatedOversizedOrWrongHashFailsClosed() {
        assertTrue(runCatching { receive(size = payload.size + 1L) }.isFailure)
        assertTrue(runCatching { receive(size = payload.size - 1L) }.isFailure)
        assertTrue(runCatching { receive(digest = "0".repeat(64)) }.isFailure)
    }

    @Test fun cancellationStopsTransfer() {
        assertTrue(runCatching { receive(check = { throw IllegalStateException("cancelled") }) }.isFailure)
    }

    @Test fun restoredFileMustMatchBothSizeAndHash() {
        val file = Files.createTempFile("verified-update-", ".apk").toFile()
        try {
            file.writeBytes(payload)
            assertTrue(ApkUpdateTransfer.matches(file, payload.size.toLong(), sha))
            assertFalse(ApkUpdateTransfer.matches(file, payload.size + 1L, sha))
            assertFalse(ApkUpdateTransfer.matches(file, payload.size.toLong(), "0".repeat(64)))
        } finally {
            file.delete()
        }
    }
}
