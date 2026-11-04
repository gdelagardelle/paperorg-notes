package com.paperorg.notes.auto

import com.paperorg.notes.domain.Note

/** What Android Auto lists, and how play/pause on the new-note row maps to the phone recorder. */
object AutoCatalog {
    const val ROOT_ID = "root"
    const val NEW_NOTE_ID = "paperorg-new-note"

    fun playable(notes: List<Note>, hasAudio: (noteId: String) -> Boolean): List<Note> =
        notes.filter { hasAudio(it.id) }

    /** The new-note row is always first. Saved notes still need a recording file on the phone. */
    fun rows(notes: List<Note>, hasAudio: (noteId: String) -> Boolean): List<String> =
        listOf(NEW_NOTE_ID) + playable(notes, hasAudio).map { it.id }

    /**
     * Play on the new-note row starts a take. Pause, or leaving that row, ends it.
     * A saved note never starts or stops the microphone.
     */
    fun playbackCommand(itemIsNewNote: Boolean, isPlaying: Boolean, carHasTake: Boolean): CarRecordCommand =
        when {
            itemIsNewNote && isPlaying && !carHasTake -> CarRecordCommand.Start
            carHasTake && (!itemIsNewNote || !isPlaying) -> CarRecordCommand.Stop
            else -> CarRecordCommand.Ignore
        }
}

enum class CarRecordCommand { Start, Stop, Ignore }
