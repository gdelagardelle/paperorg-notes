package com.paperorg.notes.domain

import java.text.DateFormat
import java.util.Date
import java.util.Locale

data class NoteDocument(
    val title: String,
    val meta: String,
    val body: String,
)

object NoteExport {
    fun document(note: Note): NoteDocument {
        val language = AppLanguage.fromCode(note.language).displayName
        val date = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, Locale.getDefault())
            .format(Date(note.createdAtMillis))
        return NoteDocument(
            title = note.title.ifBlank { "Paperorg note" },
            meta = "$date · $language",
            body = pdfBody(note),
        )
    }

    fun pdfBody(note: Note): String {
        val parts = mutableListOf<String>()
        val summary = note.displaySummaryShort
        if (summary.isNotBlank()) {
            parts += "SUMMARY"
            parts += summary
            parts += ""
        }
        val structured = structured(note)
        if (structured.actionItems.isNotEmpty()) {
            parts += "ACTION ITEMS"
            structured.actionItems.forEach { parts += "- $it" }
            parts += ""
        }
        if (structured.decisions.isNotEmpty()) {
            parts += "DECISIONS"
            structured.decisions.forEach { parts += "- $it" }
            parts += ""
        }
        parts += "TRANSCRIPT"
        parts += note.displayTranscript
        return parts.joinToString("\n")
    }

    fun markdown(note: Note): String {
        val language = AppLanguage.fromCode(note.language).displayName
        val date = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, Locale.getDefault())
            .format(Date(note.createdAtMillis))
        val structured = structured(note)
        return buildString {
            appendLine("# ${note.title.ifBlank { "Paperorg note" }}")
            appendLine()
            appendLine("**Date:** $date  ")
            appendLine("**Language:** $language  ")
            appendLine()
            val summary = note.displaySummaryShort
            if (summary.isNotBlank()) {
                appendLine("## Summary")
                appendLine()
                appendLine(summary)
                appendLine()
            }
            if (structured.actionItems.isNotEmpty()) {
                appendLine("## Action Items")
                appendLine()
                structured.actionItems.forEach { appendLine("- [ ] $it") }
                appendLine()
            }
            if (structured.decisions.isNotEmpty()) {
                appendLine("## Decisions")
                appendLine()
                structured.decisions.forEach { appendLine("- $it") }
                appendLine()
            }
            appendLine("## Transcript")
            appendLine()
            appendLine(note.displayTranscript)
        }
    }

    private fun structured(note: Note): StructuredNote {
        val raw = note.structuredJson?.takeIf { it.isNotBlank() } ?: return emptyStructured()
        return runCatching { SummaryParser.parse(raw) }.getOrElse { emptyStructured() }
    }

    private fun emptyStructured() = StructuredNote(
        title = null,
        shortSummary = "",
        detailedSummary = "",
        keyIdeas = emptyList(),
        decisions = emptyList(),
        actionItems = emptyList(),
        openQuestions = emptyList(),
    )
}
