package com.michelesaladino.pania

import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebView
import androidx.activity.enableEdgeToEdge
import androidx.core.view.WindowCompat

class MainActivity : TauriActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
  }

  override fun onWebViewCreate(webView: WebView) {
    webView.addJavascriptInterface(SystemBars(), "PaniaSystemBars")
  }

  /**
   * Lets the web UI pick the status/navigation bar icon colour. The app theme can differ from the
   * system one (the user can force light or dark), so the automatic choice made by enableEdgeToEdge()
   * isn't always readable against the page background.
   */
  inner class SystemBars {
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
