package com.example.sleep_detector_app

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // (11/24 사용자 요청) 운행 중 앱을 나가도 졸음 감지 — 운행 화면이 켜고(start) 끔(stop)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sleep_guard/bg").setMethodCallHandler { call, result ->
            val intent = Intent(this, DriveGuardService::class.java)
            try {
                when (call.method) {
                    "start" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                        result.success(true)
                    }
                    "stop" -> {
                        stopService(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.success(false)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // (11/23 사용자 요청) 앱이 켜져 있는 동안 화면이 어두워지거나 꺼지지 않게 — 운전 중 다시 켜는 조작을 없앰
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    // (11/24 사용자 요청) 다른 앱 · 잠금 화면에서 돌아와도 다시 '화면 켜 두기' (어두워지거나 꺼지지 않게)
    override fun onResume() {
        super.onResume()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
