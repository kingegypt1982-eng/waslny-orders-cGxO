package com.waslny.wasalny_orders

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Trip Alerts channel (high priority, custom sound, shows on lock screen)
            val tripAlertsChannel = NotificationChannel(
                "trip_alerts",
                getString(R.string.channel_name_trip_alerts),
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = getString(R.string.channel_description_trip_alerts)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                // Custom sound - will use default if custom sound file not present
                try {
                    val soundUri = Uri.parse("android.resource://$packageName/${R.raw.trip_alert_sound}")
                    val audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    setSound(soundUri, audioAttributes)
                } catch (e: Exception) {
                    // Custom sound not found, will use default notification sound
                }
            }
            manager.createNotificationChannel(tripAlertsChannel)
        }
    }
}
