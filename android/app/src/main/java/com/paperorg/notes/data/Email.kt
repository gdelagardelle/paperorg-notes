package com.paperorg.notes.data

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import com.paperorg.notes.domain.EmailContent
import com.paperorg.notes.domain.Note
import java.io.File

data class EmailDraft(
    val recipients: List<String>,
    val subject: String,
    val body: String,
    val htmlBody: String,
    val attachments: List<File> = emptyList(),
)

object EmailComposer {
    fun testDraft(address: String) = EmailDraft(
        recipients = listOf(address),
        subject = "Paperorg Notes test email",
        body = "This is a test email from Paperorg Notes. If you can read this, hands-free email delivery is working.",
        htmlBody = html("Paperorg Notes test email", "This is a test email from Paperorg Notes. If you can read this, hands-free email delivery is working."),
    )

    fun forNote(note: Note, settings: SecureSettings, audio: File?, cacheDir: File): EmailDraft {
        val transcript = note.displayTranscript
        val summary = note.displaySummaryShort
        val body = when (EmailContent.fromCode(settings.emailContent)) {
            EmailContent.SummaryOnly -> summary
            EmailContent.FullTranscript -> transcript
            EmailContent.Both -> "SUMMARY\n$summary\n\n---\n\nTRANSCRIPT\n$transcript"
        }
        val attachments = mutableListOf<File>()
        if (settings.emailAttachAudio && audio != null && audio.exists()) {
            attachments += audio
        }
        if (settings.emailAttachMarkdown) {
            val md = File(cacheDir, "${note.id}.md")
            md.writeText(
                "# ${note.title}\n\n## Summary\n\n$summary\n\n## Transcript\n\n$transcript\n",
            )
            attachments += md
        }
        return EmailDraft(
            recipients = settings.emailRecipients,
            subject = note.title.ifBlank { "Paperorg note" },
            body = body,
            htmlBody = html(note.title, body),
            attachments = attachments,
        )
    }

    private fun html(title: String, body: String): String {
        fun escape(value: String) = value
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\n", "<br>")
        return "<html><body><h1>${escape(title)}</h1><p>${escape(body)}</p></body></html>"
    }
}

object EmailIntents {
    fun share(context: Context, draft: EmailDraft): Intent {
        val intent = Intent(if (draft.attachments.isEmpty()) Intent.ACTION_SEND else Intent.ACTION_SEND_MULTIPLE).apply {
            type = "message/rfc822"
            putExtra(Intent.EXTRA_EMAIL, draft.recipients.toTypedArray())
            putExtra(Intent.EXTRA_SUBJECT, draft.subject)
            putExtra(Intent.EXTRA_TEXT, draft.body)
            if (draft.attachments.isNotEmpty()) {
                val uris = ArrayList(
                    draft.attachments.map { file ->
                        FileProvider.getUriForFile(context, "${context.packageName}.files", file)
                    },
                )
                if (draft.attachments.size == 1) {
                    putExtra(Intent.EXTRA_STREAM, uris.first())
                } else {
                    putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                }
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        return Intent.createChooser(intent, "Send email")
    }
}
