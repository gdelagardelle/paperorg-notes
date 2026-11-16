package com.paperorg.notes

import com.paperorg.notes.auto.AutoCatalog
import com.paperorg.notes.auto.CarRecordCommand
import com.paperorg.notes.domain.Note
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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

    @Test
    fun spokenNewNoteRequestsStartARecordingInEveryAppLanguage() {
        val saved = listOf(note("a", "Budget meeting"))
        listOf(
            "new note",
            "a new note",
            "start recording",
            "nouvelle note",
            "Nouvel enregistrement",
            "neue Notiz",
            "Aufnahme starten",
            "nei Notiz",
        ).forEach { spoken ->
            assertEquals(spoken, AutoCatalog.NEW_NOTE_ID, AutoCatalog.searchTarget(spoken, saved))
        }
    }

    @Test
    fun spokenTitleOfASavedNotePlaysThatNote() {
        val saved = listOf(note("a", "Budget meeting"), note("b", "Récit du voyage"))
        assertEquals("a", AutoCatalog.searchTarget("budget meeting", saved))
        assertEquals("a", AutoCatalog.searchTarget("budget", saved))
        assertEquals("b", AutoCatalog.searchTarget("recit du voyage", saved))
    }

    @Test
    fun aSavedNoteTitledLikeACommandWinsOnAnExactMatch() {
        val saved = listOf(note("r", "Record of the board"))
        assertEquals("r", AutoCatalog.searchTarget("record of the board", saved))
        assertEquals(AutoCatalog.NEW_NOTE_ID, AutoCatalog.searchTarget("new recording", saved))
    }

    @Test
    fun anEmptyRequestPlaysTheNewestNoteAndNeverOpensTheMicrophone() {
        val saved = listOf(note("newest", "Today"), note("older", "Yesterday"))
        assertEquals("newest", AutoCatalog.searchTarget("", saved))
        assertEquals("newest", AutoCatalog.searchTarget("  ", saved))
        assertNull(AutoCatalog.searchTarget("", emptyList()))
    }

    @Test
    fun anUnknownRequestMatchesNothing() {
        assertNull(AutoCatalog.searchTarget("jazz", listOf(note("a", "Budget meeting"))))
    }

    private fun note(id: String, title: String = id) = Note(
        id = id,
        title = title,
        createdAtMillis = 1,
        updatedAtMillis = 1,
        durationSeconds = 30.0,
        audioFileName = "$id.m4a",
        language = "lb",
        outputType = "meeting",
        status = "ready",
    )
}
