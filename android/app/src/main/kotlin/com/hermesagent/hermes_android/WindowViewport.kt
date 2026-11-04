package com.hermesagent.hermes_android

import android.view.View

/** Re-dispatch actual OS insets after resume/intent; never invent a keyboard height. */
internal object WindowViewport {
    fun refresh(root: View) {
        root.post {
            if (root.isAttachedToWindow) {
                root.requestApplyInsets()
                root.requestLayout()
            }
        }
    }
}
