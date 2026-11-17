package com.paperorg.notes.auto

import com.paperorg.notes.domain.Note
import java.text.Normalizer

/** What Android Auto lists, and how play/pause on the new-note row maps to the phone recorder. */
object AutoCatalog {
    const val ROOT_ID = "root"
    const val NEW_NOTE_ID = "paperorg-new-note"

    /**
     * Spoken ways to ask for a new recording, after [normalize]. A query containing
     * one of these starts a note, unless it is exactly the title of a saved note.
     */
    private val NEW_NOTE_PHRASES = listOf(
        "new note", "new recording", "record", "start recording",
        "nouvelle note", "nouvel enregistrement", "enregistr",
        "neue notiz", "neue aufnahme", "aufnehmen", "aufnahme starten",
        "nei notiz", "nei opnam", "ophuelen",
    )

    fun playable(notes: List<Note>, hasAudio: (noteId: String) -> Boolean): List<Note> =
        notes.filter { hasAudio(it.id) }

    /** The new-note row is always first. Saved notes still need a recording file on the phone. */
    fun rows(notes: List<Note>, hasAudio: (noteId: String) -> Boolean): List<String> =
        listOf(NEW_NOTE_ID) + playable(notes, hasAudio).map { it.id }

    /**
     * Voice requests ("Hey Google, play new note on Paperorg Notes") arrive as a search
     * query instead of a row id. Returns the row to play, or null when nothing fits.
     * An empty query ("play Paperorg Notes") plays the newest saved note and never
     * opens the microphone, so a vague request cannot start a recording.
     */
    fun searchTarget(query: String, notes: List<Note>): String? {
        val wanted = normalize(query)
        if (wanted.isEmpty()) return notes.firstOrNull()?.id
        notes.firstOrNull { normalize(it.title) == wanted }?.let { return it.id }
        if (NEW_NOTE_PHRASES.any { wanted.contains(it) }) return NEW_NOTE_ID
        return notes.firstOrNull {
            val title = normalize(it.title)
            title.isNotEmpty() && title.contains(wanted)
        }?.id
    }

    /** Lower case, no accents, no punctuation, single spaces. */
    fun normalize(text: String): String =
        Normalizer.normalize(text, Normalizer.Form.NFD)
            .replace(Regex("\\p{M}+"), "")
            .lowercase()
            .replace(Regex("[^a-z0-9]+"), " ")
            .trim()

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
