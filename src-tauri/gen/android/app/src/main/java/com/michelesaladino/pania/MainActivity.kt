package com.michelesaladino.pania

import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebView
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat

class MainActivity : TauriActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
  }

  override fun onWebViewCreate(webView: WebView) {
    webView.addJavascriptInterface(SystemBars(), "PaniaSystemBars")

    // The window is edge-to-edge, so the page draws under the status bar. Hand its height to the
    // page as --safe-top (CSS px); Android WebView doesn't reliably expose it via env().
    ViewCompat.setOnApplyWindowInsetsListener(webView) { view, insets ->
      val top = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()).top
      topInsetCssPx = top / view.resources.displayMetrics.density
      pushTopInset(webView)
      insets
    }
  }

  private var topInsetCssPx = 0f

  private fun pushTopInset(webView: WebView) {
    webView.post {
      webView.evaluateJavascript(
        "document.documentElement.style.setProperty('--safe-top','${topInsetCssPx}px')",
        null,
      )
    }
  }

  /**
   * Lets the web UI pick the status/navigation bar icon colour. The app theme can differ from the
   * system one (the user can force light or dark), so the automatic choice made by enableEdgeToEdge()
   * isn't always readable against the page background.
   */
  inner class SystemBars {
    /** Status-bar height in CSS px, for pages that load after the insets were first delivered. */
    @JavascriptInterface
    fun topInset(): Float = topInsetCssPx

    @JavascriptInterface
    fun setDark(dark: Boolean) {
      runOnUiThread {
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller.isAppearanceLightStatusBars = !dark
        controller.isAppearanceLightNavigationBars = !dark
      }
    }
  }
}
