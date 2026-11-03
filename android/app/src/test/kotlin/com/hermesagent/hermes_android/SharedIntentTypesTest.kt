package com.hermesagent.hermes_android

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Parcelable
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class SharedIntentTypesTest {
    @Suppress("UNCHECKED_CAST")
    private fun read(intent: Intent): List<Uri> {
        val method = MainActivity::class.java.getDeclaredMethod("sharedUris", Intent::class.java)
        method.isAccessible = true
        return method.invoke(MainActivity(), intent) as List<Uri>
    }

    @Test fun wrongSingleParcelableDoesNotHideValidClipData() {
        val uri = Uri.parse("content://fixture/image")
        val intent = Intent(Intent.ACTION_SEND).apply {
            putExtra(Intent.EXTRA_STREAM, Bundle())
            clipData = ClipData.newRawUri("fixture", uri)
        }
        assertEquals(listOf(uri), read(intent))
    }

    @Test fun mixedMultipleStreamsAreFilteredAndDeduplicated() {
        val uri = Uri.parse("content://fixture/image")
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, arrayListOf<Parcelable>(Bundle(), uri))
            clipData = ClipData.newRawUri("fixture", uri)
        }
        assertEquals(listOf(uri), read(intent))
    }

    @Test fun malformedStreamWithPlainClipHasNoFiles() {
        val intent = Intent(Intent.ACTION_SEND).apply {
            putExtra(Intent.EXTRA_STREAM, Bundle())
            clipData = ClipData.newPlainText("fixture", "benign")
        }
        assertEquals(emptyList<Uri>(), read(intent))
    }
}
