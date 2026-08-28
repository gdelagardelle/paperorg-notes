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
import org.json.JSONArray
import org.json.JSONObject

class ProcessRecording(
    private val api: NotesApi,
    private val notes: NotesRepository,
    private val settings: SecureSettings,
    private val recording: RecordingController,
) {
    suspend fun execute(note: Note, onStage: (ProcessingStage) -> Unit) = withContext(Dispatchers.IO) {
        val audio = recording.audioFile(note.id)
        var updated = note.copy(
            status = NoteStatus.Processing.name.lowercase(),
            processingStage = ProcessingStage.Transcribing.name.lowercase(),
            errorMessage = null,
        )
        notes.save(updated)
        onStage(ProcessingStage.Transcribing)
        try {
            if (!audio.exists() || audio.length() < 1024) {
                error("Recording is too short or silent. Hold the mic closer and speak for a few seconds.")
            }
            val language = AppLanguage.fromCode(updated.language)
            val hit = transcribe(audio, language, updated.durationSeconds)
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
            if (!settings.keepAudio || settings.deleteAudioAfterTranscription) {
                recording.deleteAudio(note.id)
            }
            updated = updated.copy(
                status = NoteStatus.Ready.name.lowercase(),
                processingStage = ProcessingStage.Ready.name.lowercase(),
                updatedAtMillis = System.currentTimeMillis(),
            )
            notes.save(updated)
            onStage(ProcessingStage.Ready)
        } catch (error: Exception) {
            val waiting = error is NotesApiException && error.status in setOf(0, 408) ||
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
    }

    suspend fun resummarize(note: Note, onStage: (ProcessingStage) -> Unit) = withContext(Dispatchers.IO) {
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
    }

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

    private fun transcribe(audio: File, language: AppLanguage, durationSeconds: Double): TranscriptHit {
        var lastError: Exception? = null
        for (provider in ProviderOrder.forLanguage(language, settings.luxAsrEnabled)) {
            try {
                val raw = api.transcribe(provider.id, audio, language, durationSeconds, settings.transcriptionPrompt())
                val text = when (provider.id) {
                    "luxasr" -> TranscriptParser.luxAsrText(raw)
                    else -> TranscriptParser.openaiText(raw)
                }
                if (text.isNotBlank()) return TranscriptHit(text, provider.id)
                lastError = IllegalStateException("Empty transcript from ${provider.id}")
            } catch (error: NotesApiException) {
                lastError = error
                if (error.status == 403) throw error
            } catch (error: Exception) {
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
