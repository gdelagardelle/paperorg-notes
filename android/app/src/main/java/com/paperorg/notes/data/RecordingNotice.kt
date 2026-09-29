package com.paperorg.notes.data

object RecordingNotice {
    const val CHANNEL_ID = "recording_status"
    const val NOTIFICATION_ID = 41

    fun text(durationLabel: String): String = "Recording · $durationLabel"
}
