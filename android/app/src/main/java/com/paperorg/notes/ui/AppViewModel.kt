package com.paperorg.notes.ui

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.paperorg.notes.PaperorgNotesApp
import com.paperorg.notes.R
import com.paperorg.notes.data.BillingRepository
import com.paperorg.notes.data.EmailComposer
import com.paperorg.notes.data.PdfNoteWriter
import com.paperorg.notes.data.ProPlan
import com.paperorg.notes.data.RecordingForegroundService
import com.paperorg.notes.data.RecordingWork
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
import com.paperorg.notes.domain.RecordingLimit
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

    private val _plans = MutableStateFlow<List<ProPlan>>(emptyList())
    val plans: StateFlow<List<ProPlan>> = _plans.asStateFlow()

    private val _billingMessage = MutableStateFlow<String?>(null)
    val billingMessage: StateFlow<String?> = _billingMessage.asStateFlow()

    val settings get() = app.settings
    val gdpr get() = app.gdpr
    val recording get() = app.recording

    private var ticker: Job? = null
    private var stopping = false

    init {
        val language = AppLanguage.fromCode(app.settings.defaultLanguage)
        val output = OutputType.entries.find { it.code == app.settings.defaultOutputType } ?: OutputType.Meeting
        _record.update { it.copy(language = language, outputType = output) }
        app.billing.onEntitlementChanged = { usage ->
            _record.update { it.copy(usage = usage) }
        }
        app.billing.onMessage = { message -> _billingMessage.value = message }
        app.recordingStopHandler = { stopAndProcess() }
        viewModelScope.launch {
            // Restores Pro after a reinstall or on a new phone, where Play
            // still knows about the subscription and this install does not.
            refreshUsage()
            app.billing.syncPurchases()
            _plans.value = app.billing.plans()
        }
    }

    fun buyPro(activity: Activity, plan: ProPlan) {
        app.billing.purchase(activity, plan)
    }

    fun restorePurchases() {
        viewModelScope.launch {
            val resources = getApplication<Application>()
            _billingMessage.value = when (app.billing.syncPurchases()) {
                BillingRepository.PurchaseSyncOutcome.Restored ->
                    resources.getString(R.string.billing_restored)
                BillingRepository.PurchaseSyncOutcome.VerifyFailed ->
                    resources.getString(R.string.billing_verify_failed)
                BillingRepository.PurchaseSyncOutcome.NoneFound ->
                    resources.getString(R.string.billing_none)
            }
        }
    }

    fun dismissBillingMessage() {
        _billingMessage.value = null
    }

    private suspend fun refreshUsage() {
        runCatching { withContext(Dispatchers.IO) { app.api.usage() } }.onSuccess { usage ->
            _record.update { it.copy(usage = usage) }
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
        if (_record.value.processing || app.recording.state != RecordingState.Idle) return
        _record.update { it.copy(processing = true) }
        stopPlayback()
        val noteId = UUID.randomUUID().toString()
        viewModelScope.launch {
            val now = System.currentTimeMillis()
            val note = Note(
                id = noteId,
                title = getApplication<Application>().getString(R.string.note_untitled),
                createdAtMillis = now,
                updatedAtMillis = now,
                durationSeconds = 0.0,
                audioFileName = "$noteId.wav",
                language = _record.value.language.code,
                outputType = _record.value.outputType.code,
                status = NoteStatus.Draft.name.lowercase(),
            )
            app.notes.save(note)
            try {
                withContext(Dispatchers.Main) {
                    app.recording.start(noteId, RecordingLimit.seconds(_record.value.usage))
                }
                RecordingForegroundService.start(getApplication(), _record.value.usage?.maxRecordingMinutes)
                _record.update { it.copy(recordingState = RecordingState.Recording, processing = false, error = null) }
                startTicker()
            } catch (error: Exception) {
                app.recording.cancel()
                app.notes.delete(noteId)
                _record.update { it.copy(processing = false, error = error.message ?: getApplication<Application>().getString(R.string.error_mic)) }
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
        if (stopping) return
        stopping = true
        viewModelScope.launch {
          try {
            val noteId = app.recording.currentNoteId ?: return@launch
            val duration = app.recording.durationSeconds()
            if (withContext(Dispatchers.IO) { app.recording.stop() } == null) return@launch
            RecordingForegroundService.stop(getApplication())
            ticker?.cancel()
            _record.update {
                it.copy(
                    recordingState = RecordingState.Idle,
                    processing = true,
                    processingStage = ProcessingStage.Saving,
                    durationLabel = DurationFormat.format(duration),
                    error = app.recording.captureError,
                )
            }
            val note = app.notes.get(noteId)?.copy(durationSeconds = duration) ?: return@launch
            // execute derives the final duration under its queue lock. Do not overwrite
            // a Ready note if an already-running durable worker wins this race.
            RecordingWork.enqueue(getApplication(), noteId)
            try {
                app.processRecording.execute(note) { stage ->
                    _record.update { state -> state.copy(processingStage = stage) }
                }
                app.emailNoteIfConfigured(noteId)
            } catch (error: Exception) {
                val message = humanError(error)
                _record.update { it.copy(error = message) }
            } finally {
                _record.update { it.copy(processing = false, processingStage = null) }
                refreshUsage()
            }
          } catch (error: Exception) {
              _record.update { it.copy(processing = false, error = humanError(error)) }
          } finally { stopping = false }
        }
    }

    /**
     * Runs an imported file through the same pipeline a recording uses, so the
     * transcript, summary and email behave identically either way.
     */
    fun importAudio(uri: Uri) {
        if (_record.value.processing || app.recording.state != RecordingState.Idle) return
        viewModelScope.launch {
            stopPlayback()
            val noteId = UUID.randomUUID().toString()
            _record.update {
                it.copy(processing = true, processingStage = ProcessingStage.Saving, error = null)
            }
            val imported = try {
                app.audioImport.import(uri, noteId, _record.value.usage?.maxRecordingMinutes)
            } catch (error: Exception) {
                _record.update {
                    it.copy(processing = false, processingStage = null, error = humanError(error))
                }
                return@launch
            }

            val now = System.currentTimeMillis()
            val note = Note(
                id = noteId,
                title = getApplication<Application>().getString(R.string.note_untitled),
                createdAtMillis = now,
                updatedAtMillis = now,
                durationSeconds = imported.seconds,
                audioFileName = imported.file.name,
                language = _record.value.language.code,
                outputType = _record.value.outputType.code,
                status = NoteStatus.Processing.name.lowercase(),
            )
            app.notes.save(note)
            _record.update { it.copy(durationLabel = DurationFormat.format(imported.seconds)) }
            try {
                app.processRecording.execute(note) { stage ->
                    _record.update { state -> state.copy(processingStage = stage) }
                }
                app.emailNoteIfConfigured(noteId)
            } catch (error: Exception) {
                _record.update { it.copy(error = humanError(error)) }
            } finally {
                _record.update { it.copy(processing = false, processingStage = null) }
                refreshUsage()
            }
        }
    }

    fun retry(note: Note, language: AppLanguage = AppLanguage.fromCode(note.language)) {
        if (_record.value.processing || app.recording.state != RecordingState.Idle) return
        viewModelScope.launch {
            stopPlayback()
            val updated = note.copy(language = language.code)
            if (app.recording.segments(note.id) != null && note.status == NoteStatus.Ready.name.lowercase()) {
                _record.update { it.copy(error = "This recording already has a saved transcript. Use Summarize again to update its summary; saved segments are not billed again.") }
                return@launch
            }
            if (language.code != note.language) {
                if (app.recording.segments(note.id) != null) {
                    _record.update { it.copy(error = "This recording already has saved transcription segments. Retry in its original language.") }
                    return@launch
                }
                app.notes.save(updated)
            }
            _record.update { it.copy(processing = true, error = null) }
            try {
                app.processRecording.execute(updated, forceLegacyRetry = true) { stage ->
                    _record.update { state -> state.copy(processingStage = stage) }
                }
                app.emailNoteIfConfigured(updated.id)
            } catch (error: Exception) {
                _record.update { it.copy(error = humanError(error)) }
            } finally {
                _record.update { it.copy(processing = false, processingStage = null) }
                refreshUsage()
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
            _record.update { it.copy(error = error.message ?: getApplication<Application>().getString(R.string.error_play)) }
        }
    }

    fun stopPlayback() {
        app.recording.stopPlayback()
        _playingNoteId.value = null
    }

    fun delete(note: Note) {
        viewModelScope.launch {
            stopPlayback()
            if (app.recording.currentNoteId == note.id) {
                app.recording.cancel()
                ticker?.cancel()
                RecordingForegroundService.stop(getApplication())
                _record.update { it.copy(recordingState = RecordingState.Idle) }
            }
            RecordingWork.cancel(getApplication(), note.id)
            app.processRecording.delete(note.id)
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
            if (app.recording.state != RecordingState.Idle) app.recording.cancel()
            notes.value.forEach { RecordingWork.cancel(getApplication(), it.id) }
            app.processRecording.deleteAll()
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
                app.processRecording.removeExpiredAudio(note.id)
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
                onSuccess = { onResult("✓ " + getApplication<Application>().getString(R.string.email_test_sent, trimmed)) },
                onFailure = { error ->
                    onResult(UserFacingError.message(error as? Exception ?: Exception(error.message)))
                },
            )
        }
    }

    fun sendNoteEmail(note: Note, onResult: (String) -> Unit) {
        viewModelScope.launch {
            if (app.settings.emailRecipients.isEmpty()) {
                onResult(getApplication<Application>().getString(R.string.error_no_recipients))
                return@launch
            }
            val draft = app.emailDraft(note)
            if (draft == null || draft.body.isBlank()) {
                onResult(getApplication<Application>().getString(R.string.error_empty_note))
                return@launch
            }
            val result = withContext(Dispatchers.IO) {
                runCatching { app.api.sendEmail(draft) }
            }
            result.fold(
                onSuccess = { onResult(getApplication<Application>().getString(R.string.email_sent)) },
                onFailure = { error ->
                    onResult(UserFacingError.message(error as? Exception ?: Exception(error.message)))
                },
            )
        }
    }

    fun sharePdf(context: android.content.Context, note: Note, onResult: (String) -> Unit) {
        viewModelScope.launch {
            val file = withContext(Dispatchers.IO) {
                runCatching { PdfNoteWriter.write(note, getApplication<Application>().cacheDir) }
            }.getOrElse { error ->
                onResult(error.message ?: getApplication<Application>().getString(R.string.error_pdf))
                return@launch
            }
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
            val share = Intent(Intent.ACTION_SEND).apply {
                type = "application/pdf"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(Intent.createChooser(share, context.getString(R.string.chooser_pdf)))
        }
    }

    override fun onCleared() {
        if (app.recordingStopHandler != null) {
            app.recordingStopHandler = null
        }
        stopPlayback()
        super.onCleared()
    }

    private fun humanError(error: Exception): String = UserFacingError.message(error)

    private fun startTicker() {
        ticker?.cancel()
        ticker = viewModelScope.launch {
            while (true) {
                val seconds = app.recording.durationSeconds()
                _record.update {
                    it.copy(
                        durationLabel = DurationFormat.format(seconds),
                        recordingState = app.recording.state,
                    )
                }
                if (app.recording.state == RecordingState.Idle) break
                if (app.recording.captureFinished) {
                    stopAndProcess()
                    break
                }
                val cap = _record.value.usage?.maxRecordingMinutes
                if (cap != null && cap > 0 && seconds >= cap * 60.0) {
                    stopAndProcess()
                    break
                }
                delay(250)
            }
        }
    }
}
