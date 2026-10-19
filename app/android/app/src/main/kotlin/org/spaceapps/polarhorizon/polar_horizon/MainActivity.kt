package org.spaceapps.polarhorizon.polar_horizon

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.AndroidWebkitLibraryPigeonInstanceManager
import io.flutter.plugins.webviewflutter.WebViewFlutterPlugin
import io.flutter.plugins.webviewflutter.WebViewProxyApi

class MainActivity : FlutterActivity() {
    // Android 14 leak: a UiModeManager built on the Activity context registers a
    // binder callback that keeps the finished Activity (and its WebViews) alive
    // after a Back-exit. Build it on the application context instead.
    override fun getSystemService(name: String): Any? =
        if (name == Context.UI_MODE_SERVICE) applicationContext.getSystemService(name) else super.getSystemService(name)

    // new-android-4: when a chart WebView's render process dies (for example the
    // system reclaims it for memory), Chromium kills the whole app unless the
    // WebViewClient handles onRenderProcessGone. webview_flutter_android has no
    // hook for it, so every WebView in the window gets a delegating client that
    // handles it: the dead WebView is dropped and Dart builds fresh chart pages.
    private var channel: MethodChannel? = null
    private val scan = ViewTreeObserver.OnGlobalLayoutListener { guardWebViews(window.decorView) }

    // android-1: all chart WebViews share one render process, so one death is
    // reported by every WebView on it. Send Dart ONE notification per burst
    // (each extra one used to make every chart host build a throwaway WebView
    // that was never attached, never guarded, and killed the app on the next
    // death). Dart coalesces too; this is defence in depth.
    private val main = Handler(Looper.getMainLooper())
    private var gonePending = false
    private val notifyGone = Runnable {
        gonePending = false
        channel?.invokeMethod("renderProcessGone", null)
        guardWebViews(window.decorView)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "polar_horizon/webview")
        // android7-timeline: Dart shows chart WebViews with Hybrid Composition on old
        // Android (their default texture repainted only part of a chart there)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "polar_horizon/device").setMethodCallHandler { call, result ->
            if (call.method == "sdkInt") result.success(Build.VERSION.SDK_INT) else result.notImplemented()
        }
    }

    override fun onPostCreate(savedInstanceState: Bundle?) {
        super.onPostCreate(savedInstanceState)
        window.decorView.viewTreeObserver.addOnGlobalLayoutListener(scan)
    }

    override fun onDestroy() {
        window.decorView.viewTreeObserver.removeOnGlobalLayoutListener(scan)
        main.removeCallbacks(notifyGone)
        gonePending = false
        channel = null
        super.onDestroy()
    }

    private fun guardWebViews(v: View) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return // getWebViewClient / onRenderProcessGone
        if (v is WebView) {
            val current = v.webViewClient
            if (current !is RenderGuard) v.webViewClient = RenderGuard(current) { onRenderGone(it) }
            return
        }
        if (v is ViewGroup) for (i in 0 until v.childCount) guardWebViews(v.getChildAt(i))
    }

    private fun onRenderGone(view: WebView) {
        // the WebView cannot be used again: take it out and destroy it
        (view.parent as? ViewGroup)?.removeView(view)
        // android-webviews: the webview_flutter plugin keeps a strong reference
        // to every object Dart made until Dart garbage-collects the matching Dart
        // object, which may be never (Dart GC is lazy, and a runJavaScript stuck
        // on the dead page keeps it alive). Dropping only the WebView's reference
        // (round 2) was not enough: the plugin also holds its WebSettings, and
        // Chromium's settings lead back to the WebView, so every death still
        // kept its WebViews (meminfo WebViews 3 -> 6). Drop the plugin's
        // reference to everything that leads back to the dead WebView. Collect
        // them first: for a plugin WebView the plugin's remove() destroys it.
        val released = releaseFromPlugin(pluginObjectsOf(view))
        if (!(released && view is WebViewProxyApi.WebViewPlatformView)) view.destroy()
        if (!gonePending) {
            gonePending = true
            main.postDelayed(notifyGone, GONE_BURST_MS)
        }
    }

    /** True when the plugin released the WebView itself (the first of [objects]). */
    private fun releaseFromPlugin(objects: List<Any>): Boolean =
        try {
            val plugin = flutterEngine?.plugins?.get(WebViewFlutterPlugin::class.java) as? WebViewFlutterPlugin
            val manager = plugin?.instanceManager
            manager != null && releasePluginReferences(manager, objects)
        } catch (e: RuntimeException) {
            false // plugin detached (engine going away): nothing left to release
        }

    private companion object {
        /** Reports of one render-process death arrive within a few ms of each other. */
        const val GONE_BURST_MS = 100L
    }
}

/**
 * Drops the webview_flutter plugin's strong reference to [instance] (android-webviews).
 * Returns false when the plugin does not know it. The plugin's weak bookkeeping stays,
 * so once the instance is collected the plugin tells Dart to forget it as usual.
 */
internal fun releasePluginReference(manager: AndroidWebkitLibraryPigeonInstanceManager, instance: Any): Boolean {
    if (!manager.containsInstance(instance)) return false
    // re-adds the strong reference if only a weak one was left, so remove() drops it either way
    val id = manager.getIdentifierForStrongReference(instance) ?: return false
    manager.remove<Any>(id)
    return true
}

/**
 * Releases each of [objects] (see [releasePluginReference]); the first is the dead WebView.
 * Returns whether the plugin knew (and released) that WebView.
 */
internal fun releasePluginReferences(manager: AndroidWebkitLibraryPigeonInstanceManager, objects: List<Any>): Boolean {
    var first = false
    objects.forEachIndexed { i, o ->
        val released = releasePluginReference(manager, o)
        if (i == 0) first = released
    }
    return first
}

/**
 * The dead [view] and the plugin objects that lead back to it, view first: its WebSettings
 * (Chromium's settings object holds the WebView's AwContents, which holds the WebView), its
 * WebChromeClient, and its WebViewClient (the plugin's client inside our [RenderGuard]).
 * The clients do not lead back today; they are released so nothing of a dead page stays.
 * Called before the WebView is destroyed. [sdk]: the client getters need Android 8 (O).
 */
@SuppressLint("NewApi") // checked against [sdk]
internal fun pluginObjectsOf(view: WebView, sdk: Int = Build.VERSION.SDK_INT): List<Any> {
    val settings = try {
        view.settings
    } catch (e: RuntimeException) {
        null // a WebView in a bad state: release what we can
    }
    val newer = sdk >= Build.VERSION_CODES.O
    return pluginObjects(view, settings, if (newer) view.webChromeClient else null, if (newer) view.webViewClient else null)
}

/** [pluginObjectsOf] without the WebView getters: view first, [client] unwrapped from [RenderGuard], no repeats. */
internal fun pluginObjects(view: Any, settings: Any?, chrome: Any?, client: Any?): List<Any> {
    val out = listOfNotNull(view, settings, chrome, (client as? RenderGuard)?.inner ?: client)
    return out.filterIndexed { i, o -> out.indexOfFirst { it === o } == i } // by identity
}

/**
 * Forwards to the plugin's client; handles a dead render process instead of crashing.
 * After the death it forwards nothing (android-webviews): each callback the plugin passes
 * to Dart would give the plugin a new strong reference to the dead WebView.
 */
internal class RenderGuard(val inner: WebViewClient, private val gone: (WebView) -> Unit) : WebViewClient() {
    /** Set once the render process died; the WebView is gone for good. */
    var dead = false
        private set

    override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail?): Boolean {
        if (!dead) {
            dead = true
            gone(view)
        }
        return true
    }

    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
        dead || inner.shouldOverrideUrlLoading(view, request)

    override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
        if (!dead) inner.onPageStarted(view, url, favicon)
    }

    override fun onPageFinished(view: WebView, url: String?) {
        if (!dead) inner.onPageFinished(view, url)
    }

    override fun onPageCommitVisible(view: WebView, url: String?) {
        if (!dead) inner.onPageCommitVisible(view, url)
    }

    override fun onLoadResource(view: WebView, url: String?) {
        if (!dead) inner.onLoadResource(view, url)
    }

    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
        if (dead) null else inner.shouldInterceptRequest(view, request)

    override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
        if (!dead) inner.onReceivedError(view, request, error)
    }

    override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, errorResponse: WebResourceResponse) {
        if (!dead) inner.onReceivedHttpError(view, request, errorResponse)
    }

    override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
        if (dead) handler.cancel() else inner.onReceivedSslError(view, handler, error)
    }

    override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) {
        if (!dead) inner.doUpdateVisitedHistory(view, url, isReload)
    }
}
