package com.paperorg.notes

import android.app.Application
import androidx.room.Room
import com.paperorg.notes.data.AudioImport
import com.paperorg.notes.data.BillingRepository
import com.paperorg.notes.data.EmailComposer
import com.paperorg.notes.data.EmailDraft
import com.paperorg.notes.data.GdprExport
import com.paperorg.notes.data.NotesApi
import com.paperorg.notes.data.PdfNoteWriter
import com.paperorg.notes.data.PlayIntegrityClient
import com.paperorg.notes.data.ProcessRecording
import com.paperorg.notes.data.RecordingController
import com.paperorg.notes.data.SecureSettings
import com.paperorg.notes.data.db.NotesDatabase
import com.paperorg.notes.data.db.NotesRepository
import com.paperorg.notes.domain.Note
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class PaperorgNotesApp : Application() {
    lateinit var settings: SecureSettings
        private set
    lateinit var notes: NotesRepository
        private set
    lateinit var recording: RecordingController
        private set
    lateinit var api: NotesApi
        private set
    lateinit var processRecording: ProcessRecording
        private set
    lateinit var gdpr: GdprExport
        private set
    lateinit var billing: BillingRepository
        private set
    lateinit var audioImport: AudioImport
        private set

    /** Set by the record screen while it is alive so Stop on the notification can show progress. */
    var recordingStopHandler: (() -> Unit)? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        settings = SecureSettings(this)
        val db = Room.databaseBuilder(this, NotesDatabase::class.java, "notes.db").build()
        notes = NotesRepository(db.notes())
        recording = RecordingController(this)
        lateinit var notesApi: NotesApi
        val integrity = PlayIntegrityClient(this) { notesApi }
        notesApi = NotesApi(settings, integrity)
        api = notesApi
        processRecording = ProcessRecording(api, notes, settings, recording)
        gdpr = GdprExport(this, recording)
        billing = BillingRepository(this) { notesApi }
        audioImport = AudioImport(this, recording)
    }

    suspend fun emailNoteIfConfigured(noteId: String) {
        if (!settings.sendEmailAfterTranscription || settings.emailRecipients.isEmpty()) return
        val note = notes.get(noteId) ?: return
        if (note.displayTranscript.isBlank()) return
        val draft = emailDraft(note) ?: return
        withContext(Dispatchers.IO) { api.sendEmail(draft) }
    }

    fun emailDraft(note: Note): EmailDraft? {
        if (note.displayTranscript.isBlank() && note.displaySummaryShort.isBlank()) return null
        val audio = recording.audioFile(note.id).takeIf { it.exists() }
        val pdf = if (settings.emailAttachPDF) {
            runCatching { PdfNoteWriter.write(note, cacheDir) }.getOrNull()
        } else {
            null
        }
        val draft = EmailComposer.forNote(note, settings, audio, cacheDir, pdf)
        return draft.takeIf { it.body.isNotBlank() || it.attachments.isNotEmpty() }
    }

    companion object {
        lateinit var instance: PaperorgNotesApp
            private set
    }
}
