package com.paperorg.notes

import android.app.Application
import androidx.room.Room
import com.paperorg.notes.data.BillingRepository
import com.paperorg.notes.data.GdprExport
import com.paperorg.notes.data.NotesApi
import com.paperorg.notes.data.PlayIntegrityClient
import com.paperorg.notes.data.ProcessRecording
import com.paperorg.notes.data.RecordingController
import com.paperorg.notes.data.SecureSettings
import com.paperorg.notes.data.db.NotesDatabase
import com.paperorg.notes.data.db.NotesRepository

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
    }

    companion object {
        lateinit var instance: PaperorgNotesApp
            private set
    }
}
