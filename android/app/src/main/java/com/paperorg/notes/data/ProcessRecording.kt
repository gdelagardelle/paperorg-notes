package com.paperorg.notes.data

import com.paperorg.notes.data.db.NotesRepository
import com.paperorg.notes.domain.AppLanguage
import com.paperorg.notes.domain.Note
import com.paperorg.notes.domain.NoteStatus
import com.paperorg.notes.domain.OutputType
import com.paperorg.notes.domain.ProcessingStage
import com.paperorg.notes.domain.ProviderOrder
import com.paperorg.notes.domain.SummaryParser
import com.paperorg.notes.domain.TranscriptParser
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.IOException
import org.json.JSONArray
import org.json.JSONObject

class ProcessRecording(
    private val api: NotesApi,
    private val notes: NotesRepository,
    private val settings: SecureSettings,
    private val recording: RecordingController,
) {
    private val processing = Mutex()

    suspend fun recover(noteId: String) = withContext(Dispatchers.IO) { processing.withLock {
        val note = notes.get(noteId) ?: return@withLock
        if (note.status == NoteStatus.Ready.name.lowercase()) return@withLock
        val segments = recording.segments(noteId) ?: return@withLock
        val audio = File(recording.recordingsDir, "$noteId.wav")
        try {
            if (!audio.exists()) segments.assemble(audio)
            notes.save(note.copy(durationSeconds = segments.durationSeconds(), audioFileName = audio.name,
                status = NoteStatus.WaitingForNetwork.name.lowercase(), processingStage = null))
        } catch (error: Exception) {
            notes.save(note.copy(status = NoteStatus.Failed.name.lowercase(),
                errorMessage = "Recovered audio is saved. Free storage and retry to prepare playback."))
        }
    } }

    /** One queue for live chunks, manual retries and recovered WorkManager jobs. */
    suspend fun drainSegments(noteId: String) = withContext(Dispatchers.IO) { processing.withLock {
        val note = notes.get(noteId) ?: return@withLock
        val segments = recording.segments(noteId) ?: return@withLock
        transcribeSegments(note, segments)
    } }

    private fun transcribeSegments(note: Note, segments: SegmentedAudio): String {
        val pending = segments.pending()
        if (pending.isEmpty()) return segments.combinedTranscript()
        api.requireSegmentedRecording()
        val language = AppLanguage.fromCode(note.language)
        segments.transcribePending { segment ->
            val hit = transcribe(segment.file, language, segment.durationSeconds, note.id, segment.index, segment.startSeconds)
            // Empty/silent chunks are valid: retain their completion so they are never charged repeatedly.
            TranscriptParser.readableText(hit.text)?.trim().orEmpty() to hit.providerId
        }
        return segments.combinedTranscript()
    }

    suspend fun delete(noteId: String) = withContext(Dispatchers.IO) { processing.withLock {
        recording.deleteAudio(noteId)
        notes.delete(noteId)
    } }

    suspend fun removeExpiredAudio(noteId: String) = withContext(Dispatchers.IO) { processing.withLock {
        val note = notes.get(noteId) ?: return@withLock
        // Pending sessions must retain their durable retry queue, even when old.
        if (recording.currentNoteId != noteId && note.status == NoteStatus.Ready.name.lowercase()) recording.deleteAudio(noteId)
    } }

    suspend fun deleteAll() = withContext(Dispatchers.IO) { processing.withLock {
        notes.deleteAll()
        recording.deleteAllAudio()
    } }

    suspend fun execute(note: Note, forceLegacyRetry: Boolean = false, onStage: (ProcessingStage) -> Unit) = withContext(Dispatchers.IO) { processing.withLock {
        val latest = notes.get(note.id) ?: return@withLock
        val segments = recording.segments(note.id)
        if (latest.status == NoteStatus.Ready.name.lowercase() && !(forceLegacyRetry && segments == null)) return@withLock
        if (recording.currentNoteId == note.id) return@withLock
        val audio = if (segments != null) File(recording.recordingsDir, "${note.id}.wav") else recording.audioFile(note.id)
        var updated = latest.copy(
            durationSeconds = segments?.durationSeconds() ?: latest.durationSeconds,
            audioFileName = audio.name,
            status = NoteStatus.Processing.name.lowercase(),
            processingStage = ProcessingStage.Transcribing.name.lowercase(),
            errorMessage = null,
        )
        notes.save(updated)
        onStage(ProcessingStage.Transcribing)
        try {
            if (segments != null && !audio.exists()) segments.assemble(audio)
            if (!audio.exists() || audio.length() < 1024) {
                error("Recording is too short or silent. Hold the mic closer and speak for a few seconds.")
            }
            val language = AppLanguage.fromCode(updated.language)
            val hit = if (segments != null) TranscriptHit(transcribeSegments(updated, segments), "segmented")
                else transcribe(audio, language, updated.durationSeconds)
            val text = TranscriptParser.readableText(hit.text)?.trim().orEmpty()
            if (text.length < 3 || TranscriptParser.isRawJSON(text)) {
                error("The transcript came back empty. Try recording again.")
            }
            updated = updated.copy(
                rawTranscript = text,
                primaryProvider = hit.providerId,
                processingStage = ProcessingStage.Summarizing.name.lowercase(),
            )
            notes.save(updated)
            onStage(ProcessingStage.Summarizing)
            updated = applySummary(updated, text, language)
            updated = updated.copy(
                status = NoteStatus.Ready.name.lowercase(),
                processingStage = ProcessingStage.Ready.name.lowercase(),
                updatedAtMillis = System.currentTimeMillis(),
            )
            notes.save(updated)
            if (!settings.keepAudio || settings.deleteAudioAfterTranscription) {
                recording.deleteAudio(note.id)
            }
            onStage(ProcessingStage.Ready)
        } catch (error: Exception) {
            val waiting = error is IOException && error !is NotesApiException ||
                error is NotesApiException && error.status in setOf(0, 408, 429, 502, 503, 504) ||
                error.message?.contains("Unable to resolve host", true) == true
            notes.save(
                updated.copy(
                    status = if (waiting) NoteStatus.WaitingForNetwork.name.lowercase() else NoteStatus.Failed.name.lowercase(),
                    processingStage = null,
                    errorMessage = UserFacingError.message(error),
                    updatedAtMillis = System.currentTimeMillis(),
                ),
            )
            throw error
        }
    } }

    suspend fun resummarize(note: Note, onStage: (ProcessingStage) -> Unit) = withContext(Dispatchers.IO) { processing.withLock {
        if (notes.get(note.id) == null) return@withLock
        val text = note.displayTranscript.trim()
        if (text.length < 3 || TranscriptParser.isRawJSON(text)) {
            error("No readable transcript to summarize.")
        }
        var updated = note.copy(
            rawTranscript = text,
            status = NoteStatus.Processing.name.lowercase(),
            processingStage = ProcessingStage.Summarizing.name.lowercase(),
            errorMessage = null,
        )
        notes.save(updated)
        onStage(ProcessingStage.Summarizing)
        try {
            val language = AppLanguage.fromCode(updated.language)
            updated = applySummary(updated, text, language)
            updated = updated.copy(
                status = NoteStatus.Ready.name.lowercase(),
                processingStage = ProcessingStage.Ready.name.lowercase(),
                updatedAtMillis = System.currentTimeMillis(),
            )
            notes.save(updated)
            onStage(ProcessingStage.Ready)
        } catch (error: Exception) {
            notes.save(
                updated.copy(
                    status = NoteStatus.Failed.name.lowercase(),
                    processingStage = null,
                    errorMessage = UserFacingError.message(error),
                    updatedAtMillis = System.currentTimeMillis(),
                ),
            )
            throw error
        }
    } }

    private fun applySummary(note: Note, text: String, language: AppLanguage): Note {
        val outputType = OutputType.entries.find { it.code == note.outputType } ?: OutputType.Meeting
        if (outputType == OutputType.Raw) return note
        val summary = SummaryParser.parse(api.summarize(text, outputType, language, settings.summaryLength))
        return note.copy(
            title = summary.title?.takeIf { it.isNotBlank() && (note.title == "Untitled Recording" || note.title.isBlank()) }
                ?: note.title,
            summaryShort = summary.shortSummary,
            summaryDetailed = summary.detailedSummary,
            structuredJson = JSONObject()
                .put("keyIdeas", jsonArray(summary.keyIdeas))
                .put("decisions", jsonArray(summary.decisions))
                .put("actionItems", jsonArray(summary.actionItems))
                .put("openQuestions", jsonArray(summary.openQuestions))
                .toString(),
        )
    }

    private fun transcribe(audio: File, language: AppLanguage, durationSeconds: Double,
        sessionId: String? = null, index: Int? = null, startSeconds: Double? = null): TranscriptHit {
        var lastError: Exception? = null
        for (provider in ProviderOrder.forLanguage(language, settings.luxAsrEnabled)) {
            try {
                val raw = api.transcribe(provider.id, audio, language, durationSeconds, settings.transcriptionPrompt(), sessionId, index, startSeconds)
                val actualProvider = runCatching { JSONObject(raw).optString("_recording_provider").takeIf { it.isNotBlank() } }.getOrNull() ?: provider.id
                val text = when (actualProvider) {
                    "luxasr" -> TranscriptParser.luxAsrText(raw)
                    else -> TranscriptParser.openaiText(raw)
                }
                if (text.isNotBlank() || sessionId != null) return TranscriptHit(text, actualProvider)
                lastError = IllegalStateException("Empty transcript from ${provider.id}")
            } catch (error: NotesApiException) {
                lastError = error
                if (error.status in setOf(401, 403, 408, 409, 413, 422, 429) || sessionId != null && error.status >= 500) throw error
            } catch (error: Exception) {
                if (sessionId != null) throw error // A timeout may already have reached the provider; never fallback blindly.
                lastError = error
            }
        }
        throw lastError ?: IllegalStateException("No transcription provider available.")
    }

    private fun jsonArray(items: List<String>): JSONArray {
        val array = JSONArray()
        items.forEach { array.put(it) }
        return array
    }

    private data class TranscriptHit(val text: String, val providerId: String)
}
