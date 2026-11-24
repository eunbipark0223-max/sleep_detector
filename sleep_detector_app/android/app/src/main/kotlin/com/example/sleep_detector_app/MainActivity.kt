package com.example.sleep_detector_app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
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
