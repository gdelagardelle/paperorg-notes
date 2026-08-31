package com.paperorg.notes.data

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.paperorg.notes.MainActivity
import com.paperorg.notes.PaperorgNotesApp
import com.paperorg.notes.R
import com.paperorg.notes.domain.DurationFormat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Keeps the microphone recording alive when the screen locks or the user
 * leaves the app. The ViewModel still owns start/stop while it is alive;
 * this service also stops at the per-recording cap and from the notification.
 */
class RecordingForegroundService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var maxMinutes = 0
    private var finishing = false

    private val tick = object : Runnable {
        override fun run() {
            val app = application as PaperorgNotesApp
            if (app.recording.state == RecordingState.Idle) {
                stopSelf()
                return
            }
            val seconds = app.recording.durationSeconds()
            updateNotification(DurationFormat.format(seconds))
            if (maxMinutes > 0 && seconds >= maxMinutes * 60.0) {
                requestStop()
                return
            }
            handler.postDelayed(this, 500)
        }
    }

    override fun onBind(intent: Intent?) = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            requestStop()
            return START_NOT_STICKY
        }
        maxMinutes = intent?.getIntExtra(EXTRA_CAP, 0) ?: 0
        createChannel()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                RecordingNotice.NOTIFICATION_ID,
                notification(DurationFormat.format(0.0)),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(RecordingNotice.NOTIFICATION_ID, notification(DurationFormat.format(0.0)))
        }
        handler.removeCallbacks(tick)
        handler.post(tick)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        super.onDestroy()
    }

    private fun requestStop() {
        val app = application as PaperorgNotesApp
        val onStop = app.recordingStopHandler
        if (onStop != null) {
            onStop()
            return
        }
        finishInBackground()
    }

    private fun finishInBackground() {
        if (finishing) return
        val app = application as PaperorgNotesApp
        val noteId = app.recording.currentNoteId ?: run {
            stopSelf()
            return
        }
        val duration = app.recording.durationSeconds()
        if (runCatching { app.recording.stop() }.getOrNull() == null) {
            stopSelf()
            return
        }
        finishing = true
        stopForeground(STOP_FOREGROUND_REMOVE)
        scope.launch {
            val note = app.notes.get(noteId)?.copy(durationSeconds = duration) ?: return@launch
            app.notes.save(note)
            runCatching { app.processRecording.execute(note) { } }
            runCatching { app.emailNoteIfConfigured(noteId) }
            stopSelf()
        }
    }

    private fun createChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            RecordingNotice.CHANNEL_ID,
            getString(R.string.notification_recording),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            setSound(null, null)
            description = getString(R.string.notification_recording_channel)
        }
        manager.createNotificationChannel(channel)
    }

    private fun updateNotification(durationLabel: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(RecordingNotice.NOTIFICATION_ID, notification(durationLabel))
    }

    private fun notification(durationLabel: String): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, RecordingForegroundService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, RecordingNotice.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_mic)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.notification_recording_text, durationLabel))
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(0, getString(R.string.notification_stop), stop)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    companion object {
        const val ACTION_STOP = "com.paperorg.notes.STOP_RECORDING"
        private const val EXTRA_CAP = "max_minutes"

        fun start(context: Context, maxMinutes: Int?) {
            val intent = Intent(context, RecordingForegroundService::class.java)
                .putExtra(EXTRA_CAP, maxMinutes ?: 0)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, RecordingForegroundService::class.java))
        }
    }
}
