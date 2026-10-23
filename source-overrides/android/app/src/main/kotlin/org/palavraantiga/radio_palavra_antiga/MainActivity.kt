package org.palavraantiga.radio_palavra_antiga

import android.content.Intent
import android.os.Process
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun onResume() {
        super.onResume()
        redrawPhoneWindow()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) redrawPhoneWindow()
    }

    private fun redrawPhoneWindow() {
        // The Flutter canvas and the hybrid WebView have separate Android
        // surfaces. Invalidate their parent after Android restores the window.
        val root = window.decorView
        root.post {
            if (!isFinishing && !isDestroyed && hasWindowFocus()) {
                root.requestApplyInsets()
                root.requestLayout()
                root.postInvalidateOnAnimation()
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.palavraantiga.radio/restart")
            .setMethodCallHandler { call, result ->
                if (call.method != "restart") {
                    result.notImplemented()
                } else {
                    try {
                        startActivity(Intent(this, RestartActivity::class.java).apply {
                            putExtra("previousPid", Process.myPid())
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
                        })
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("restart_failed", error.message, null)
                    }
                }
            }
    }
}

