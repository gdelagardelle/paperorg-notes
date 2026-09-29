package com.paperorg.notes.domain

import java.text.DateFormat
import java.util.Date
import java.util.Locale

data class NoteDocument(
    val title: String,
    val meta: String,
    val body: String,
)

data class EmailLetter(
    val plain: String,
    val html: String,
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

    fun emailLetter(note: Note, audioAttached: Boolean): EmailLetter {
        val summary = emailSummary(note)
        val transcript = note.displayTranscript
        val plain = buildString {
            if (summary.isNotBlank()) {
                appendLine("SUMMARY")
                appendLine(summary)
                appendLine()
            }
            appendLine("TRANSCRIPT")
            appendLine(transcript)
            if (audioAttached) {
                appendLine()
                appendLine("AUDIO")
                appendLine("The recording is attached.")
            }
        }.trimEnd()
        return EmailLetter(
            plain = plain,
            html = emailHtml(note, summary, transcript, audioAttached),
        )
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

    private fun emailSummary(note: Note): String {
        val lines = mutableListOf<String>()
        val short = note.summaryShort
            ?.takeIf { it.isNotBlank() && !TranscriptParser.isRawJSON(it) }
        val detailed = note.summaryDetailed
            ?.takeIf { it.isNotBlank() && it != short && !TranscriptParser.isRawJSON(it) }
        if (!short.isNullOrBlank()) lines += short
        if (!detailed.isNullOrBlank()) {
            if (lines.isNotEmpty()) lines += ""
            lines += detailed
        }
        val structured = structured(note)
        fun bullets(title: String, items: List<String>) {
            if (items.isEmpty()) return
            if (lines.isNotEmpty()) lines += ""
            lines += title
            items.forEach { lines += "• $it" }
        }
        bullets("Key ideas", structured.keyIdeas)
        bullets("Decisions", structured.decisions)
        bullets("Action items", structured.actionItems)
        bullets("Open questions", structured.openQuestions)
        return lines.joinToString("\n")
    }

    private fun emailHtml(
        note: Note,
        summary: String,
        transcript: String,
        audioAttached: Boolean,
    ): String {
        val title = escape(note.title.ifBlank { "Paperorg note" })
        val language = escape(AppLanguage.fromCode(note.language).displayName)
        val duration = escape(DurationFormat.format(note.durationSeconds))
        val sections = buildString {
            if (summary.isNotBlank()) append(emailSection("Summary", summary))
            append(emailSection("Transcript", transcript, top = if (summary.isNotBlank()) 8 else 16))
            if (audioAttached) {
                append(emailSection("Audio", "The recording is attached.", top = 8))
            }
        }
        val audioNote = if (audioAttached) " The recording is attached." else ""
        return """
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>$title</title>
            </head>
            <body style="margin:0;padding:0;background:#F5F7FB;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#14223D;">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#F5F7FB;padding:24px 12px;">
                <tr>
                  <td align="center">
                    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:640px;background:#FFFFFF;border:1px solid #E0E5EC;border-radius:16px;overflow:hidden;">
                      <tr>
                        <td style="background:#14223D;padding:24px 28px;">
                          <div style="font-size:20px;line-height:1.2;font-weight:700;color:#FFFFFF;">Paperorg Notes</div>
                          <div style="font-size:13px;line-height:1.4;color:rgba(255,255,255,0.78);margin-top:4px;">Capture · Transcribe · Send</div>
                        </td>
                      </tr>
                      <tr>
                        <td style="padding:28px 28px 8px 28px;border-left:4px solid #F56A0A;">
                          <div style="font-size:24px;line-height:1.3;font-weight:700;color:#14223D;">$title</div>
                          <div style="margin-top:12px;">
                            <span style="display:inline-block;margin:8px 8px 0 0;padding:6px 10px;border-radius:999px;background:#F5F7FB;border:1px solid #E0E5EC;font-size:12px;color:#4D607B;">$language</span>
                            <span style="display:inline-block;margin:8px 8px 0 0;padding:6px 10px;border-radius:999px;background:#F5F7FB;border:1px solid #E0E5EC;font-size:12px;color:#4D607B;">$duration</span>
                          </div>
                        </td>
                      </tr>
                      $sections
                      <tr>
                        <td style="padding:20px 28px 28px 28px;border-top:1px solid #E0E5EC;">
                          <div style="font-size:12px;line-height:1.5;color:#4D607B;">Sent by Paperorg Notes.$audioNote</div>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>
            </body>
            </html>
        """.trimIndent()
    }

    private fun emailSection(title: String, body: String, top: Int = 16): String {
        val text = escape(body).replace("\n", "<br>")
        return """
            <tr>
              <td style="padding:${top}px 28px 0 28px;">
                <div style="font-size:11px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#F56A0A;margin-bottom:8px;">${escape(title)}</div>
                <div style="font-size:15px;line-height:1.65;color:#14223D;background:#F5F7FB;border:1px solid #E0E5EC;border-radius:12px;padding:16px 18px;">$text</div>
              </td>
            </tr>
        """.trimIndent()
    }

    private fun escape(value: String) = value
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")

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
