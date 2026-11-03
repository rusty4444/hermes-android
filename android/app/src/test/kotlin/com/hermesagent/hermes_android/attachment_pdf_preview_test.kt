package com.hermesagent.hermes_android

import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** Bounds/ownership tests, not a claim that Robolectric renders real PDF pages. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class AttachmentPdfPreviewTest {
    @Test fun portraitAndLandscapePreserveAspectRatioWithinBudget() {
        assertEquals(1536 to 2048, AttachmentPdfBounds.dimensions(600, 800, 1536, 2048))
        assertEquals(1536 to 768, AttachmentPdfBounds.dimensions(800, 400, 1536, 2048))
        val (width, height) = AttachmentPdfBounds.dimensions(100_000, 1, 1536, 2048)
        assertEquals(1536, width)
        assertEquals(1, height)
        assertTrue(width.toLong() * height <= AttachmentPdfBounds.MAX_PIXELS)
    }

    @Test fun zeroNegativeHugeAndOversizedRequestedDimensionsAreRejected() {
        for (dimensions in listOf(
            listOf(0, 1, 1536, 2048), listOf(1, -1, 1536, 2048),
            listOf(Int.MAX_VALUE, 1, 1536, 2048), listOf(600, 800, 4096, 2048),
            listOf(600, 800, 1536, 4096), listOf(600, 800, 0, 2048),
        )) {
            assertThrows(IllegalArgumentException::class.java) {
                AttachmentPdfBounds.dimensions(dimensions[0], dimensions[1], dimensions[2], dimensions[3])
            }
        }
    }

    @Test fun invalidAndOversizedInputNeverCreatesPrivateTemporaryFiles() {
        val directory = File(RuntimeEnvironment.getApplication().cacheDir, "attachment-test-${UUID.randomUUID()}")
        val store = AttachmentPdfStore(directory)
        try {
            assertThrows(IllegalArgumentException::class.java) { store.open(byteArrayOf()) }
            assertThrows(IllegalArgumentException::class.java) { store.open("not a PDF".toByteArray()) }
            val oversized = ByteArray(AttachmentPdfBounds.MAX_BYTES + 1)
            "%PDF-".toByteArray().copyInto(oversized)
            assertThrows(IllegalArgumentException::class.java) { store.open(oversized) }
            assertFalse(directory.exists())
        } finally { store.closeAll(); directory.deleteRecursively() }
    }

    @Test fun handlesAreNotPathsAndUnknownCloseIsIdempotent() {
        val directory = File(RuntimeEnvironment.getApplication().cacheDir, "attachment-test-${UUID.randomUUID()}")
        val store = AttachmentPdfStore(directory)
        try {
            for (id in listOf("/etc/passwd", "../../other-app.pdf", "content://remote/private", "missing")) {
                assertThrows(IllegalArgumentException::class.java) { store.render(id, 0, 1536, 2048) }
                store.close(id)
                store.close(id)
            }
            store.closeAll()
            store.closeAll()
            assertFalse(directory.exists())
        } finally { directory.deleteRecursively() }
    }
}
