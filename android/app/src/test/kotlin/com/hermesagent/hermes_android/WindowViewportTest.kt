package com.hermesagent.hermes_android

import android.app.Activity
import android.content.Context
import android.os.Looper
import android.view.View
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class WindowViewportTest {
    private class Probe(context: Context) : View(context) {
        var freshInsets = 0
        var layouts = 0
        override fun requestApplyInsets() { freshInsets++ }
        override fun requestLayout() { layouts++; super.requestLayout() }
    }
    @Test fun refreshesActualAttachedViewportWithoutChangingItsPadding() {
        val owner = Robolectric.buildActivity(Activity::class.java).setup()
        val view = Probe(owner.get())
        owner.get().setContentView(view)
        shadowOf(Looper.getMainLooper()).idle()
        view.setPadding(1, 2, 3, 4)
        val previousLayouts = view.layouts
        WindowViewport.refresh(view)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(view.freshInsets > 0)
        assertTrue(view.layouts > previousLayouts)
        assertEquals(4, view.paddingBottom)
        owner.pause().stop().destroy()
    }
}
