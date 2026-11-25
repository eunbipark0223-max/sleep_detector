package com.example.sleep_detector_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

// (11/24 사용자 요청) 운행 중 앱을 나가도 졸음 감지가 계속되게 — '운행 중' 알림을 띄우는 포그라운드 서비스
//   안드로이드는 화면 밖 앱의 카메라를 막는데, 카메라 종류 포그라운드 서비스가 켜져 있으면 계속 쓸 수 있음
//   운행 화면이 열릴 때 켜고(start), 운행이 끝나면 끔(stop) — MainActivity 의 'sleep_guard/bg' 채널
class DriveGuardService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val channelId = "drive_guard"
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(NotificationChannel(channelId, "운행 중 졸음 감지", NotificationManager.IMPORTANCE_LOW))
        }
        // 알림을 누르면 앱으로 돌아감
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, channelId) else Notification.Builder(this)
        val notification = builder
            .setContentTitle("졸음가드 운행 중")
            .setContentText("앱 밖에서도 졸음을 살피고 있어요")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
        } else {
            startForeground(1, notification)
        }
        return START_NOT_STICKY
    }
}
