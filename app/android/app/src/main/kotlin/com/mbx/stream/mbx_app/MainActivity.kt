package com.mbx.stream.mbx_app

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.mbx.stream/tv_mode"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isTvDevice" -> {
                    try {
                        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
                        val isTelevision = uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
                        val pm = packageManager
                        val hasLeanback = pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                        val hasTvFeature = pm.hasSystemFeature("android.hardware.type.television")
                        val noTouch = !pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
                        val isTv = isTelevision || hasLeanback || hasTvFeature || noTouch
                        result.success(isTv)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}

