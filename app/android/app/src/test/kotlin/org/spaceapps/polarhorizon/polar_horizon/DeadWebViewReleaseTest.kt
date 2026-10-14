package org.spaceapps.polarhorizon.polar_horizon

import android.content.ContextWrapper
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugins.webviewflutter.AndroidWebkitLibraryPigeonInstanceManager
import java.lang.ref.WeakReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

// android-webviews round 3: releasing only the WebView was not enough (meminfo
// WebViews stayed 3 -> 6). The plugin also holds the dead WebView's WebSettings
// (and clients) until Dart garbage-collects their Dart objects, and Chromium's
// settings lead back to the WebView. MainActivity now releases all of them, and
// RenderGuard stops forwarding callbacks (each would re-add a strong reference).
class DeadWebViewReleaseTest {
    private fun manager() = AndroidWebkitLibraryPigeonInstanceManager.create(
        object : AndroidWebkitLibraryPigeonInstanceManager.PigeonFinalizationListener {
            override fun onFinalize(identifier: Long) {}
        },
    )

    private fun collected(ref: WeakReference<*>): Boolean {
        repeat(50) {
            System.gc()
            if (ref.get() == null) return true
            Thread.sleep(10)
        }
        return false
    }

    /** Stands in for Chromium's settings object: it leads back to its WebView. */
    private class Settings(@Suppress("unused") val back: Any)

    /**
     * A "dead WebView" graph registered the way the plugin does it: the view and its
     * settings, with the settings pointing back at the view. Keeps no local reference.
     */
    private fun deadGraph(m: AndroidWebkitLibraryPigeonInstanceManager, release: (List<Any>) -> Unit): WeakReference<Any> {
        val view = Any()
        val settings = Settings(view)
        m.addDartCreatedInstance(view, 1L)
        m.addDartCreatedInstance(settings, 2L)
        release(listOf(view, settings))
        return WeakReference(view)
    }

    @Test
    fun releasingOnlyTheViewStillLeaksItThroughItsSettings() {
        // control: this is round 2's fix, which the gate's release APK showed is not enough
        val m = manager()
        val ref = deadGraph(m) { releasePluginReference(m, it[0]) }
        assertFalse(collected(ref))
    }

    @Test
    fun releasingTheViewAndItsSettingsLetsTheViewBeCollected() {
        val m = manager()
        var released = false
        val ref = deadGraph(m) { released = releasePluginReferences(m, it) }
        assertTrue(released)
        assertTrue(collected(ref))
    }

    @Test
    fun releaseReportsWhetherTheViewItselfWasKnown() {
        val m = manager()
        val known = Any()
        m.addDartCreatedInstance(known, 3L)
        // a WebView the plugin did not make (first) is not released, its known settings are
        assertFalse(releasePluginReferences(m, listOf(Any(), known)))
        assertTrue(releasePluginReferences(manager().also { it.addDartCreatedInstance(known, 4L) }, listOf(known)))
    }

    @Test
    fun pluginObjectsAreTheViewItsSettingsAndBothClients() {
        val view = Any()
        val settings = Any()
        val chrome = WebChromeClient()
        val pluginClient = WebViewClient()
        val guard = RenderGuard(pluginClient) {}
        val objects = pluginObjects(view, settings, chrome, guard)
        assertSame(view, objects[0]) // the view first: its release decides whether to destroy it
        assertEquals(4, objects.size)
        assertTrue(objects.any { it === settings })
        assertTrue(objects.any { it === chrome })
        assertTrue(objects.any { it === pluginClient }) // unwrapped from RenderGuard
        assertFalse(objects.any { it === guard })
    }

    @Test
    fun missingObjectsAndRepeatsAreSkipped() {
        val view = Any()
        val client = WebViewClient()
        assertEquals(listOf(view), pluginObjects(view, null, null, null))
        assertEquals(listOf(view, client), pluginObjects(view, null, null, client)) // an unguarded client as is
        assertEquals(listOf(view), pluginObjects(view, view, null, null))
    }

    @Test
    fun aDeadGuardForwardsNothingAndReportsTheDeathOnce() {
        var deaths = 0
        val pageEvents = mutableListOf<String>()
        val inner = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String?) {
                pageEvents.add("finished")
            }
            override fun onLoadResource(view: WebView, url: String?) {
                pageEvents.add("resource")
            }
        }
        val guard = RenderGuard(inner) { deaths++ }
        val view = WebView(ContextWrapper(null)) // Android stubs (unit tests): only passed through
        guard.onPageFinished(view, "file:///a")
        assertEquals(listOf("finished"), pageEvents)
        assertTrue(guard.onRenderProcessGone(view, null))
        assertTrue(guard.onRenderProcessGone(view, null)) // a second report of the same death
        assertEquals(1, deaths)
        assertTrue(guard.dead)
        guard.onPageFinished(view, "file:///a")
        guard.onLoadResource(view, "file:///b")
        assertEquals(listOf("finished"), pageEvents) // nothing reached the plugin's client
    }
}
