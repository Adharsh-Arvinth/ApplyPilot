package org.applypilot.applypilot

import android.content.ComponentCallbacks2
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var aiChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        preferHighestRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        preferHighestRefreshRate()
    }

    /** On-device AI bridge: the cockpit (via the Flutter shell) asks; the model on this phone answers. */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        OnDeviceAI.init(this)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "applypilot/ondevice_ai")
        aiChannel = channel
        OnDeviceAI.emit = { event, data -> channel.invokeMethod(event, data) }
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(OnDeviceAI.status())
                    "download" -> result.success(OnDeviceAI.startDownload(call.argument<String>("model"), call.argument<Boolean>("allowMobileData") ?: false))
                    "cancel" -> { OnDeviceAI.cancelDownload(); result.success(true) }
                    "delete" -> { OnDeviceAI.delete(call.argument<String>("model")); result.success(true) }
                    "generate" -> OnDeviceAI.generate(
                        call.argument<String>("id") ?: "0", call.argument<String>("model"),
                        call.argument<String>("system") ?: "", call.argument<String>("prompt") ?: "",
                        call.argument<Double>("temperature") ?: 0.5,
                    ) { text, error -> if (error == null) result.success(text) else result.error("ondevice_ai", error, null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ondevice_ai", e.message, null)
            }
        }
    }

    /** Leaving the app frees the model's memory straight away, so it never slows the phone down. */
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN) OnDeviceAI.trimNow()
    }

    /**
     * Many phones keep apps at 60 Hz unless they ask for more. Pick the panel's fastest mode
     * (90/120/144 Hz) at the current resolution so scrolling and the cockpit's animations run
     * at the display's full rate. The system still drops it to save power when idle.
     */
    private fun preferHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display
                      else @Suppress("DEPRECATION") windowManager.defaultDisplay
        display ?: return
        val current = display.mode
        val best = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        val params = window.attributes
        if (params.preferredDisplayModeId != best.modeId) {
            params.preferredDisplayModeId = best.modeId
            window.attributes = params
        }
    }
}
