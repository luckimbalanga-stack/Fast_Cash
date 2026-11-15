package cd.fastcash.fast_cash

import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "fast_cash/incoming_call"
    private var methodChannel: MethodChannel? = null
    private var pendingCallPayload: HashMap<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Active les flags AVANT le premier frame si c’est un appel.
        if (intent?.getBooleanExtra(IncomingCallNotifier.EXTRA_CALL, false) == true ||
            intent?.action == IncomingCallNotifier.ACTION_INCOMING
        ) {
            enableIncomingCallWindow()
        }
        super.onCreate(savedInstanceState)
        handleIncomingIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "ringNow", "showIncomingCall" -> {
                    val operationId = call.argument<Int>("operationId") ?: 0
                    val title = call.argument<String>("title") ?: "Appel Fast-Cash"
                    val body = call.argument<String>("body") ?: ""
                    val callerName = call.argument<String>("callerName") ?: "Client"
                    val waitSeconds = call.argument<Int>("waitSeconds") ?: 30
                    val payloadJson = call.argument<String>("payloadJson") ?: "{}"
                    IncomingCallNotifier.ring(
                        this,
                        operationId,
                        title,
                        body,
                        callerName,
                        waitSeconds,
                        payloadJson,
                    )
                    enableIncomingCallWindow()
                    result.success(true)
                }
                "dismissIncomingCall" -> {
                    IncomingCallNotifier.dismiss(this)
                    result.success(true)
                }
                "bringToFront" -> {
                    val operationId = call.argument<Int>("operationId") ?: 0
                    val waitSeconds = call.argument<Int>("waitSeconds") ?: 30
                    val payloadJson = call.argument<String>("payloadJson") ?: "{}"
                    try {
                        IncomingCallNotifier.bringAppToFront(this, operationId, waitSeconds, payloadJson)
                        enableIncomingCallWindow()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("bring_failed", e.message, null)
                    }
                }
                "canUseFullScreenIntent" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        val nm = getSystemService(NotificationManager::class.java)
                        result.success(nm.canUseFullScreenIntent())
                    } else {
                        result.success(true)
                    }
                }
                "requestFullScreenIntentPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(intent)
                    }
                    result.success(true)
                }
                "consumePendingCall" -> {
                    val pending = pendingCallPayload
                    pendingCallPayload = null
                    result.success(pending)
                }
                else -> result.notImplemented()
            }
        }
        pendingCallPayload?.let { payload ->
            methodChannel?.invokeMethod("onIncomingCallIntent", payload)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return
        val isCall = intent.getBooleanExtra(IncomingCallNotifier.EXTRA_CALL, false) ||
            intent.action == IncomingCallNotifier.ACTION_INCOMING
        if (!isCall) return

        enableIncomingCallWindow()
        dismissKeyguard()

        val operationId = intent.getIntExtra(IncomingCallNotifier.EXTRA_OPERATION_ID, -1)
        val waitSeconds = intent.getIntExtra(IncomingCallNotifier.EXTRA_WAIT, 30)
        val payloadJson = intent.getStringExtra(IncomingCallNotifier.EXTRA_PAYLOAD) ?: "{}"
        if (operationId <= 0) return

        val map = hashMapOf<String, Any?>(
            "operationId" to operationId,
            "waitSeconds" to waitSeconds,
            "payloadJson" to payloadJson,
        )
        pendingCallPayload = map
        methodChannel?.invokeMethod("onIncomingCallIntent", map)
    }

    private fun enableIncomingCallWindow() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun dismissKeyguard() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val keyguard = getSystemService(KeyguardManager::class.java)
            keyguard?.requestDismissKeyguard(this, null)
        }
    }
}
