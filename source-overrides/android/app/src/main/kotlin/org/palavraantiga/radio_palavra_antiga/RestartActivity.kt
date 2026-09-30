package org.palavraantiga.radio_palavra_antiga

import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import com.ryanheise.audioservice.AudioService

/** A private, short-lived process survives while the player/WebView process exits. */
class RestartActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val previousPid = intent.getIntExtra("previousPid", -1)
        if (previousPid <= 0 || previousPid == Process.myPid()) {
            finishAndRemoveTask()
            return
        }
        stopService(Intent(this, AudioService::class.java))
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).cancelAll()
        Process.killProcess(previousPid)
        Handler(Looper.getMainLooper()).postDelayed({
            startActivity(Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            })
            finishAndRemoveTask()
            Process.killProcess(Process.myPid())
        }, 500)
    }
}
