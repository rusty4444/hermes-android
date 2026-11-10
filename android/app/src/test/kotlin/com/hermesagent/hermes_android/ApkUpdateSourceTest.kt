package com.hermesagent.hermes_android

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.URL

class ApkUpdateSourceTest {
    private val tag = "v3.2.6"
    private val name = "app-arm64-v8a-release.apk"
    private val url = "https://github.com/rusty4444/hermes-android/releases/download/$tag/$name"
    private val sha = "0037e440f19dad89318902f90a6b8ef29cfe0289304e62fde6b9d4896a6fbff4"

    @Test fun acceptsOnlyExactOfficialReleaseMetadata() {
        assertNotNull(ApkUpdateSource.parse(tag, url, name, sha, 123L))
        assertNull(ApkUpdateSource.parse(tag, url.replace("https://", "http://"), name, sha, 123L))
        assertNull(ApkUpdateSource.parse(tag, url.replace("github.com", "evil.example"), name, sha, 123L))
        assertNull(ApkUpdateSource.parse(tag, "$url?evil=1", name, sha, 123L))
        assertNull(ApkUpdateSource.parse("v3.2.5", url, name, sha, 123L))
        assertNull(ApkUpdateSource.parse(tag, url, "../$name", sha, 123L))
        assertNull(ApkUpdateSource.parse(tag, url, name, "bad", 123L))
        assertNull(ApkUpdateSource.parse(tag, url, name, sha, 0L))
        assertNull(ApkUpdateSource.parse(tag, url, name, sha, 201L * 1024L * 1024L))
    }

    @Test fun redirectsMustGoToGitHubReleaseAssetsOverHttps() {
        assertTrue(ApkUpdateSource.allowedRedirect(URL("https://release-assets.githubusercontent.com/file?token=test")))
        assertFalse(ApkUpdateSource.allowedRedirect(URL("http://release-assets.githubusercontent.com/file")))
        assertFalse(ApkUpdateSource.allowedRedirect(URL("https://release-assets.githubusercontent.com.evil.example/file")))
        assertFalse(ApkUpdateSource.allowedRedirect(URL("https://evil.example/file")))
    }
}
