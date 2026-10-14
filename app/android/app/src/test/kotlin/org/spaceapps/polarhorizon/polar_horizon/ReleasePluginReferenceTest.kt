package org.spaceapps.polarhorizon.polar_horizon

import io.flutter.plugins.webviewflutter.AndroidWebkitLibraryPigeonInstanceManager
import java.lang.ref.WeakReference
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// android-webviews: after a render-process death, MainActivity must drop the
// webview_flutter plugin's strong reference to the dead WebView, or the
// WebView can never be collected (meminfo WebViews grew 2 -> 4 -> 6).
class ReleasePluginReferenceTest {
    private fun manager() = AndroidWebkitLibraryPigeonInstanceManager.create(
        object : AndroidWebkitLibraryPigeonInstanceManager.PigeonFinalizationListener {
            override fun onFinalize(identifier: Long) {}
        },
    )

    /** Adds an instance the way the plugin does (from Dart), optionally releases it, keeps no local reference. */
    private fun addInstance(m: AndroidWebkitLibraryPigeonInstanceManager, release: Boolean): Pair<WeakReference<Any>, Boolean> {
        val instance = Any()
        m.addDartCreatedInstance(instance, 7L)
        val released = if (release) releasePluginReference(m, instance) else false
        return WeakReference(instance) to released
    }

    private fun collected(ref: WeakReference<Any>): Boolean {
        repeat(50) {
            System.gc()
            if (ref.get() == null) return true
            Thread.sleep(10)
        }
        return false
    }

    @Test
    fun withoutReleaseThePluginKeepsTheInstance() {
        // control: this is the leak the fix addresses
        val m = manager()
        val (ref, _) = addInstance(m, release = false)
        assertFalse(collected(ref))
        assertTrue(m.containsInstance(ref.get()))
    }

    @Test
    fun releasedInstanceCanBeCollected() {
        val m = manager()
        val (ref, released) = addInstance(m, release = true)
        assertTrue(released)
        assertTrue(collected(ref))
    }

    @Test
    fun releaseWorksAfterTheStrongReferenceWasAlreadyDropped() {
        val m = manager()
        val instance = Any()
        m.addDartCreatedInstance(instance, 9L)
        m.remove<Any>(9L) // Dart already let go
        assertTrue(releasePluginReference(m, instance))
        assertTrue(m.containsInstance(instance)) // weak bookkeeping stays until it is collected
    }

    @Test
    fun unknownInstanceIsNotReleased() {
        assertFalse(releasePluginReference(manager(), Any()))
    }
}
