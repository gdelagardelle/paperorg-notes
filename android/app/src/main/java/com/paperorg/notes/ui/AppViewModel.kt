package com.paperorg.notes.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.paperorg.notes.PaperorgNotesApp
import com.paperorg.notes.data.EmailComposer
import com.paperorg.notes.data.UserFacingError
import com.paperorg.notes.domain.EmailAddresses
import com.paperorg.notes.domain.EmailServerStatus
import com.paperorg.notes.data.RecordingState
import com.paperorg.notes.domain.AppLanguage
import com.paperorg.notes.domain.DurationFormat
import com.paperorg.notes.domain.Note
import com.paperorg.notes.domain.NoteStatus
import com.paperorg.notes.domain.OutputType
import com.paperorg.notes.domain.ProcessingStage
import com.paperorg.notes.domain.UsageInfo
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class RecordUiState(
    val language: AppLanguage = AppLanguage.Luxembourgish,
    val outputType: OutputType = OutputType.Meeting,
    val recordingState: RecordingState = RecordingState.Idle,
    val durationLabel: String = "00:00",
    val processing: Boolean = false,
    val processingStage: ProcessingStage? = null,
    val error: String? = null,
    val usage: UsageInfo? = null,
)

class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val app = application as PaperorgNotesApp

    val notes: StateFlow<List<Note>> = app.notes.observeNotes()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    private val _privacy = MutableStateFlow(app.settings.hasAcceptedPrivacy)
    val privacyAccepted: StateFlow<Boolean> = _privacy.asStateFlow()

    private val _record = MutableStateFlow(RecordUiState())
    val record: StateFlow<RecordUiState> = _record.asStateFlow()

    private val _search = MutableStateFlow("")
    val search: StateFlow<String> = _search.asStateFlow()

    private val _playingNoteId = MutableStateFlow<String?>(null)
    val playingNoteId: StateFlow<String?> = _playingNoteId.asStateFlow()

    val settings get() = app.settings
    val gdpr get() = app.gdpr
    val recording get() = app.recording

    private var ticker: Job? = null

    init {
        val language = AppLanguage.fromCode(app.settings.defaultLanguage)
        val output = OutputType.entries.find { it.code == app.settings.defaultOutputType } ?: OutputType.Meeting
        _record.update { it.copy(language = language, outputType = output) }
        viewModelScope.launch {
            runCatching { app.api.usage() }.onSuccess { usage ->
                _record.update { it.copy(usage = usage) }
            }
        }
    }

    fun setLanguage(language: AppLanguage) {
        app.settings.defaultLanguage = language.code
        _record.update { it.copy(language = language) }
    }

    fun setOutput(outputType: OutputType) {
        app.settings.defaultOutputType = outputType.code
        _record.update { it.copy(outputType = outputType) }
    }

    fun setSearch(query: String) {
        _search.value = query
    }

    fun acceptPrivacy() {
        app.settings.hasAcceptedPrivacy = true
        _privacy.value = true
    }

    fun startRecording() {
        stopPlayback()
        val noteId = UUID.randomUUID().toString()
        viewModelScope.launch {
            val now = System.currentTimeMillis()
            val note = Note(
                id = noteId,
                title = "Untitled Recording",
                createdAtMillis = now,
                updatedAtMillis = now,
                durationSeconds = 0.0,
                audioFileName = "$noteId.m4a",
                language = _record.value.language.code,
                outputType = _record.value.outputType.code,
                status = NoteStatus.Draft.name.lowercase(),
            )
            app.notes.save(note)
            try {
                withContext(Dispatchers.Main) {
                    app.recording.start(noteId)
                }
                _record.update { it.copy(recordingState = RecordingState.Recording, error = null) }
                startTicker()
            } catch (error: Exception) {
                app.notes.delete(noteId)
                _record.update { it.copy(error = error.message ?: "Could not start the microphone.") }
            }
        }
    }

    fun pauseOrResume() {
        when (app.recording.state) {
            RecordingState.Recording -> {
                app.recording.pause()
                _record.update { it.copy(recordingState = RecordingState.Paused) }
            }
            RecordingState.Paused -> {
                app.recording.resume()
                _record.update { it.copy(recordingState = RecordingState.Recording) }
            }
            RecordingState.Idle -> Unit
        }
    }

    fun stopAndProcess() {
        viewModelScope.launch {
            val noteId = app.recording.currentNoteId ?: return@launch
            val duration = app.recording.durationSeconds()
            try {
                app.recording.stop()
            } catch (error: Exception) {
                _record.update { it.copy(error = error.message, recordingState = RecordingState.Idle) }
                return@launch
            }
            ticker?.cancel()
            _record.update {
                it.copy(
                    recordingState = RecordingState.Idle,
                    processing = true,
                    processingStage = ProcessingStage.Saving,
                    durationLabel = DurationFormat.format(duration),
                )
            }
            val note = app.notes.get(noteId)?.copy(durationSeconds = duration) ?: return@launch
            app.notes.save(note)
            try {
                app.processRecording.execute(note) { stage ->
                    _record.update { state -> state.copy(processingStage = stage) }
                }
                sendEmailAfterTranscription(noteId)
            } catch (error: Exception) {
                val message = humanError(error)
                _record.update { it.copy(error = message) }
            } finally {
                _record.update { it.copy(processing = false, processingStage = null) }
                runCatching { app.api.usage() }.onSuccess { usage ->
                    _record.update { it.copy(usage = usage) }
                }
            }
        }
    }

    fun retry(note: Note, language: AppLanguage = AppLanguage.fromCode(note.language)) {
        viewModelScope.launch {
            stopPlayback()
            val updated = note.copy(language = language.code)
            app.notes.save(updated)
            _record.update { it.copy(processing = true, error = null) }
            try {
                app.processRecording.execute(updated) { stage ->
                    _record.update { state -> state.copy(processingStage = stage) }
                }
                sendEmailAfterTranscription(updated.id)
            } catch (error: Exception) {
                _record.update { it.copy(error = humanError(error)) }
            } finally {
                _record.update { it.copy(processing = false, processingStage = null) }
                runCatching { app.api.usage() }.onSuccess { usage ->
                    _record.update { it.copy(usage = usage) }
                }
            }
        }
    }

    fun resummarize(note: Note) {
        viewModelScope.launch {
            stopPlayback()
            _record.update { it.copy(processing = true, error = null) }
            try {
                app.processRecording.resummarize(note) { stage ->
                    _record.update { state -> state.copy(processingStage = stage) }
                }
            } catch (error: Exception) {
                _record.update { it.copy(error = humanError(error)) }
            } finally {
                _record.update { it.copy(processing = false, processingStage = null) }
            }
        }
    }

    fun hasAudio(note: Note): Boolean = app.recording.hasAudio(note.id)

    fun togglePlayback(note: Note) {
        if (_playingNoteId.value == note.id) {
            stopPlayback()
            return
        }
        try {
            app.recording.play(note.id) { _playingNoteId.value = null }
            _playingNoteId.value = note.id
        } catch (error: Exception) {
            _playingNoteId.value = null
            _record.update { it.copy(error = error.message ?: "Could not play the recording.") }
        }
    }

    fun stopPlayback() {
        app.recording.stopPlayback()
        _playingNoteId.value = null
    }

    fun delete(note: Note) {
        viewModelScope.launch {
            stopPlayback()
            app.recording.deleteAudio(note.id)
            app.notes.delete(note.id)
        }
    }

    fun toggleFavorite(note: Note) {
        viewModelScope.launch {
            app.notes.save(note.copy(isFavorite = !note.isFavorite, updatedAtMillis = System.currentTimeMillis()))
        }
    }

    fun deleteAll() {
        viewModelScope.launch {
            stopPlayback()
            app.notes.deleteAll()
            app.recording.deleteAllAudio()
            app.settings.reset()
            _privacy.value = false
            _record.update { RecordUiState() }
        }
    }

    fun setSummaryLength(code: String) {
        app.settings.summaryLength = code
    }

    fun purgeExpiredAudio(notes: List<Note>) {
        val days = app.settings.deleteAudioAfterDays
        if (days <= 0) return
        val cutoff = System.currentTimeMillis() - days * 24L * 60 * 60 * 1000
        viewModelScope.launch {
            notes.filter { it.createdAtMillis < cutoff }.forEach { note ->
                app.recording.deleteAudio(note.id)
            }
        }
    }

    fun dismissError() {
        _record.update { it.copy(error = null) }
    }

    suspend fun emailStatus(): EmailServerStatus? = withContext(Dispatchers.IO) {
        runCatching { app.api.emailStatus() }.getOrNull()
    }

    fun sendTestEmail(address: String, onResult: (String) -> Unit) {
        viewModelScope.launch {
            val trimmed = address.trim()
            if (!EmailAddresses.isValid(trimmed)) {
                onResult("Enter a valid email address.")
                return@launch
            }
            val draft = EmailComposer.testDraft(trimmed)
            val result = withContext(Dispatchers.IO) {
                runCatching { app.api.sendEmail(draft) }
            }
            result.fold(
                onSuccess = { onResult("✓ Test email sent to $trimmed") },
                onFailure = { error ->
                    onResult(UserFacingError.message(error as? Exception ?: Exception(error.message)))
                },
            )
        }
    }

    fun sendNoteEmail(note: Note, onResult: (String) -> Unit) {
        viewModelScope.launch {
            if (app.settings.emailRecipients.isEmpty()) {
                onResult("Add at least one recipient in Settings.")
                return@launch
            }
            val audio = app.recording.audioFile(note.id).takeIf { it.exists() }
            val draft = EmailComposer.forNote(note, app.settings, audio, getApplication<Application>().cacheDir)
            if (draft.body.isBlank()) {
                onResult("This note has nothing to send yet.")
                return@launch
            }
            val result = withContext(Dispatchers.IO) {
                runCatching { app.api.sendEmail(draft) }
            }
            result.fold(
                onSuccess = { onResult("Email sent.") },
                onFailure = { error ->
                    onResult(UserFacingError.message(error as? Exception ?: Exception(error.message)))
                },
            )
        }
    }

    private suspend fun sendEmailAfterTranscription(noteId: String) {
        if (!app.settings.sendEmailAfterTranscription || app.settings.emailRecipients.isEmpty()) return
        val note = app.notes.get(noteId) ?: return
        if (note.displayTranscript.isBlank()) return
        val audio = app.recording.audioFile(note.id).takeIf { it.exists() }
        val draft = EmailComposer.forNote(note, app.settings, audio, getApplication<Application>().cacheDir)
        if (draft.body.isBlank()) return
        runCatching {
            withContext(Dispatchers.IO) { app.api.sendEmail(draft) }
        }
    }

    override fun onCleared() {
        stopPlayback()
        super.onCleared()
    }

    private fun humanError(error: Exception): String = UserFacingError.message(error)

    private fun startTicker() {
        ticker?.cancel()
        ticker = viewModelScope.launch {
            while (true) {
                _record.update {
                    it.copy(
                        durationLabel = DurationFormat.format(app.recording.durationSeconds()),
                        recordingState = app.recording.state,
                    )
                }
                delay(250)
            }
        }
    }
}
