package com.paperorg.notes.data

import android.content.Context
import androidx.work.*
import com.paperorg.notes.PaperorgNotesApp
import com.paperorg.notes.domain.NoteStatus
import java.io.IOException
import java.util.concurrent.TimeUnit

/** Durable network-constrained queue. A worker never owns or restarts the microphone. */
class RecordingWork(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        val app = applicationContext as PaperorgNotesApp
        val noteId = inputData.getString("note_id") ?: return Result.failure()
        val note = app.notes.get(noteId) ?: return Result.success()
        if (note.status == NoteStatus.Ready.name.lowercase()) return Result.success()
        return try {
            if (app.recording.currentNoteId == noteId) app.processRecording.drainSegments(noteId)
            else app.processRecording.execute(note) {}
            Result.success()
        } catch (error: Exception) {
            // Ambiguous requests (409) are deliberately not blindly retried/fallen back.
            val retry = error is IOException && error !is NotesApiException ||
                error is NotesApiException && error.status in setOf(0, 408, 429, 502, 503, 504)
            if (retry) Result.retry() else Result.failure()
        }
    }

    companion object {
        fun enqueue(context: Context, noteId: String) {
            val request = OneTimeWorkRequestBuilder<RecordingWork>()
                .setInputData(workDataOf("note_id" to noteId))
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                "recording-$noteId", ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        }

        fun cancel(context: Context, noteId: String) {
            WorkManager.getInstance(context).cancelUniqueWork("recording-$noteId")
        }
    }
}
