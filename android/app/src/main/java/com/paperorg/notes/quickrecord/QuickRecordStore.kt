package com.paperorg.notes.quickrecord

import android.content.Context
import android.content.Intent
import com.paperorg.notes.MainActivity

/** Mirrors iOS QuickRecordSharedStore — fresh requests auto-start within 15 seconds. */
object QuickRecordStore {
    const val ACTION_QUICK_RECORD = "com.paperorg.notes.action.QUICK_RECORD"

    private const val PREFS = "quick_record"
    private const val KEY_REQUESTED_AT = "requested_at"
    private const val AUTO_START_LIFETIME_MS = 15_000L

    fun markPending(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_REQUESTED_AT, System.currentTimeMillis())
            .apply()
    }

    fun consumeFreshRequest(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val requestedAt = prefs.getLong(KEY_REQUESTED_AT, 0L)
        prefs.edit().remove(KEY_REQUESTED_AT).apply()
        if (requestedAt <= 0L) return false
        val age = System.currentTimeMillis() - requestedAt
        return age in 0..AUTO_START_LIFETIME_MS
    }

    fun isQuickRecordIntent(intent: Intent?): Boolean =
        intent?.action == ACTION_QUICK_RECORD

    fun launchMainActivity(context: Context) {
        markPending(context)
        context.startActivity(launchIntent(context))
    }

    fun launchIntent(context: Context): Intent =
        Intent(context, MainActivity::class.java).apply {
            action = ACTION_QUICK_RECORD
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
}
