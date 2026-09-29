package com.paperorg.notes

import com.paperorg.notes.data.EmailAttachments
import com.paperorg.notes.data.RecordingNotice
import com.paperorg.notes.domain.Note
import com.paperorg.notes.domain.NoteExport
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.io.path.createTempDirectory

class ExportTest {
    private val note = Note(
        id = "n1",
        title = "Board meeting",
        createdAtMillis = 1_704_067_200_000L,
        updatedAtMillis = 1_704_067_200_000L,
        durationSeconds = 120.0,
        audioFileName = "n1.m4a",
        language = "lb",
        outputType = "meeting",
        status = "ready",
        rawTranscript = "We agreed to hire.",
        summaryShort = "Hire a designer.",
        structuredJson = """{"actionItems":["Hire a designer"],"decisions":["Go ahead"],"keyIdeas":["Headcount"]}""",
    )

    @Test
    fun pdfBodyMatchesTheIosSections() {
        val body = NoteExport.pdfBody(note)
        assertTrue(body.contains("SUMMARY\nHire a designer."))
        assertTrue(body.contains("ACTION ITEMS\n- Hire a designer"))
        assertTrue(body.contains("DECISIONS\n- Go ahead"))
        assertTrue(body.contains("TRANSCRIPT\nWe agreed to hire."))
        assertFalse(body.contains("Board meeting"))
    }

    @Test
    fun markdownIncludesTitleSummaryActionsAndTranscript() {
        val md = NoteExport.markdown(note)
        assertTrue(md.startsWith("# Board meeting\n"))
        assertTrue(md.contains("**Language:** Lëtzebuergesch"))
        assertTrue(md.contains("## Summary\n\nHire a designer."))
        assertTrue(md.contains("- [ ] Hire a designer"))
        assertTrue(md.contains("## Transcript\n\nWe agreed to hire."))
    }

    @Test
    fun emailCarriesTheFullSummaryTranscriptAndAudio() {
        val richer = note.copy(
            summaryDetailed = "The board wants a designer on the site.",
            structuredJson = """{"actionItems":["Hire a designer"],"decisions":["Go ahead"],"keyIdeas":["Headcount"],"openQuestions":["By when?"]}""",
        )
        val letter = NoteExport.emailLetter(richer, audioAttached = true)
        assertTrue(letter.plain.contains("SUMMARY\nHire a designer."))
        assertTrue(letter.plain.contains("The board wants a designer on the site."))
        assertTrue(letter.plain.contains("Key ideas\n• Headcount"))
        assertTrue(letter.plain.contains("Decisions\n• Go ahead"))
        assertTrue(letter.plain.contains("Action items\n• Hire a designer"))
        assertTrue(letter.plain.contains("Open questions\n• By when?"))
        assertTrue(letter.plain.contains("TRANSCRIPT\nWe agreed to hire."))
        assertTrue(letter.plain.contains("AUDIO\nThe recording is attached."))
        assertTrue(letter.html.contains(">Summary<"))
        assertTrue(letter.html.contains(">Transcript<"))
        assertTrue(letter.html.contains(">Audio<"))
        assertTrue(letter.html.contains("The board wants a designer on the site."))
        assertTrue(letter.html.contains("02:00"))
    }

    @Test
    fun documentMetaNamesTheSpokenLanguage() {
        val document = NoteExport.document(note)
        assertEquals("Board meeting", document.title)
        assertTrue(document.meta.contains("Lëtzebuergesch"))
        assertEquals(NoteExport.pdfBody(note), document.body)
    }

    @Test
    fun emailAttachmentsSkipMissingFilesAndKeepPdf() {
        val dir = createTempDirectory("paperorg-export").toFile()
        val audio = File(dir, "n1.m4a").apply { writeText("audio") }
        val pdf = File(dir, "n1.pdf").apply { writeText("pdf") }
        val missing = File(dir, "gone.md")
        assertEquals(
            listOf(audio, pdf),
            EmailAttachments.of(audio = audio, markdown = missing, pdf = pdf),
        )
    }

    @Test
    fun recordingNoticeShowsTheElapsedTime() {
        assertEquals("Recording · 03:12", RecordingNotice.text("03:12"))
    }
}
