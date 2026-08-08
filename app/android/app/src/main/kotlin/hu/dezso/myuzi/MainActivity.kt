package hu.dezso.myuzi

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Enables show-when-locked only for incoming calls.
 * Pref [flutter.incoming_call_lock] is written by Dart (incl. FCM isolate)
 * so we can turn the screen on *in onCreate* before Flutter paints —
 * required when the app was killed and FSI launches us.
 */
class MainActivity : FlutterActivity() {
  private val channelName = "hu.dezso.myuzi/call_lock"
  private val prefName = "FlutterSharedPreferences"
  private val lockKey = "flutter.incoming_call_lock"

  override fun onCreate(savedInstanceState: Bundle?) {
    if (shouldShowOverLock(intent)) {
      applyIncomingCallUi(true)
    }
    super.onCreate(savedInstanceState)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    if (shouldShowOverLock(intent)) {
      applyIncomingCallUi(true)
    }
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "setIncomingCallUi" -> {
            val enabled = call.argument<Boolean>("enabled") ?: false
            applyIncomingCallUi(enabled)
            result.success(null)
          }
          else -> result.notImplemented()
        }
      }
  }

  private fun shouldShowOverLock(intent: Intent?): Boolean {
    val prefs = getSharedPreferences(prefName, MODE_PRIVATE)
    if (prefs.getBoolean(lockKey, false)) return true
    // Notification / FSI launch often carries payload or is not a plain launcher tap.
    val extras = intent?.extras ?: return false
    if (extras.containsKey("callId") || extras.containsKey("payload")) return true
    return false
  }

  private fun applyIncomingCallUi(enabled: Boolean) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
      setShowWhenLocked(enabled)
      setTurnScreenOn(enabled)
    }
    @Suppress("DEPRECATION")
    if (enabled) {
      window.addFlags(
        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
          WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
          WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
          WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
          WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
      )
    } else {
      window.clearFlags(
        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
          WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
          WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
          WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
          WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
      )
    }
  }
}
