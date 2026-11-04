package com.paperorg.notes

import com.paperorg.notes.auto.AutoCatalog
import com.paperorg.notes.auto.CarRecordCommand
import com.paperorg.notes.domain.Note
import org.junit.Assert.assertEquals
import org.junit.Test

class AutoCatalogTest {
    @Test
    fun carCatalogSkipsNotesWhoseRecordingIsGone() {
        val kept = note("kept")
        val missing = note("missing")
        val playable = AutoCatalog.playable(listOf(kept, missing)) { it == "kept" }
        assertEquals(listOf("kept"), playable.map { it.id })
    }

    @Test
    fun carListOpensWithANewNoteRow() {
        val rows = AutoCatalog.rows(listOf(note("kept"), note("missing"))) { it == "kept" }
        assertEquals(listOf(AutoCatalog.NEW_NOTE_ID, "kept"), rows)
    }

    @Test
    fun pauseOnTheNewNoteRowEndsTheTake() {
        assertEquals(
            CarRecordCommand.Start,
            AutoCatalog.playbackCommand(itemIsNewNote = true, isPlaying = true, carHasTake = false),
        )
        assertEquals(
            CarRecordCommand.Stop,
            AutoCatalog.playbackCommand(itemIsNewNote = true, isPlaying = false, carHasTake = true),
        )
        assertEquals(
            CarRecordCommand.Stop,
            AutoCatalog.playbackCommand(itemIsNewNote = false, isPlaying = true, carHasTake = true),
        )
        assertEquals(
            CarRecordCommand.Ignore,
            AutoCatalog.playbackCommand(itemIsNewNote = false, isPlaying = true, carHasTake = false),
        )
    }

    private fun note(id: String) = Note(
        id = id,
        title = id,
        createdAtMillis = 1,
        updatedAtMillis = 1,
        durationSeconds = 30.0,
        audioFileName = "$id.m4a",
        language = "lb",
        outputType = "meeting",
        status = "ready",
    )
}
