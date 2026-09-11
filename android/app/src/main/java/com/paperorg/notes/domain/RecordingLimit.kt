package com.paperorg.notes.domain

object RecordingLimit {
    fun seconds(usage: UsageInfo?): Double {
        if (usage == null) return 180.0
        val planCap = if (usage.isPro) 180 else 3
        val perRecording = usage.maxRecordingMinutes?.takeIf { it > 0 } ?: planCap
        return minOf(perRecording.toDouble(), usage.minutesRemaining.coerceAtLeast(0.0)) * 60
    }
}
