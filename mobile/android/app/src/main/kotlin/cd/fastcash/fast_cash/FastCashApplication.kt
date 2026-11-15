package cd.fastcash.fast_cash

import android.app.Application
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskPlugin
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Enregistre le channel d’appel aussi sur le FlutterEngine du service foreground,
 * pour sonner immédiatement depuis l’isolate watchdog (sans attendre l’UI).
 */
class FastCashApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        IncomingCallNotifier.ensureChannel(this)
        FlutterForegroundTaskPlugin.addTaskLifecycleListener(object : FlutterForegroundTaskLifecycleListener {
            private var channel: MethodChannel? = null

            override fun onEngineCreate(flutterEngine: FlutterEngine?) {
                val engine = flutterEngine ?: return
                channel = MethodChannel(engine.dartExecutor.binaryMessenger, "fast_cash/incoming_call")
                channel?.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "ringNow", "showIncomingCall" -> {
                            val operationId = call.argument<Int>("operationId") ?: 0
                            val title = call.argument<String>("title") ?: "Appel Fast-Cash"
                            val body = call.argument<String>("body") ?: ""
                            val callerName = call.argument<String>("callerName") ?: "Client"
                            val waitSeconds = call.argument<Int>("waitSeconds") ?: 30
                            val payloadJson = call.argument<String>("payloadJson") ?: "{}"
                            IncomingCallNotifier.ring(
                                this@FastCashApplication,
                                operationId,
                                title,
                                body,
                                callerName,
                                waitSeconds,
                                payloadJson,
                            )
                            result.success(true)
                        }
                        "dismissIncomingCall" -> {
                            IncomingCallNotifier.dismiss(this@FastCashApplication)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                }
            }

            override fun onTaskStart(starter: FlutterForegroundTaskStarter) {}

            override fun onTaskRepeatEvent() {}

            override fun onTaskDestroy() {}

            override fun onEngineWillDestroy() {
                channel?.setMethodCallHandler(null)
                channel = null
            }
        })
    }
}
