package com.paperorg.notes

import com.paperorg.notes.domain.SummaryParser
import com.paperorg.notes.domain.TranscriptParser
import com.paperorg.notes.domain.UsageParser
import com.paperorg.notes.domain.Note
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ParserTest {
    @Test
    fun usageParserReadsPlayIntegrityFlag() {
        val usage = UsageParser.parse(
            """{"is_pro":false,"minutes_limit":30,"minutes_used":1.5,"minutes_remaining":28.5,"period_key":"2026-08","app_attest_required":false,"play_integrity_required":true}""",
        )
        assertEquals(30, usage.minutesLimit)
        assertTrue(usage.playIntegrityRequired)
        assertEquals(1.5, usage.minutesUsed, 0.01)
        assertNull(usage.maxRecordingMinutes)
    }

    @Test
    fun usageParserReadsThePerRecordingCap() {
        val usage = UsageParser.parse(
            """{"is_pro":true,"minutes_limit":600,"minutes_used":0,"minutes_remaining":600,"period_key":"2026-08","max_recording_minutes":180}""",
        )
        assertEquals(180, usage.maxRecordingMinutes)
    }

    @Test
    fun usageParserReadsTheCapFromThePlatformEnvelope() {
        val usage = UsageParser.parse(
            """{"period_key":"2026-08","is_pro":true,"max_recording_minutes":15,"metrics":{"transcription.minutes":{"used":0.0,"limit":30.0,"remaining":30.0}}}""",
        )
        assertEquals(15, usage.maxRecordingMinutes)
    }

    @Test
    fun openaiParserReadsTextField() {
        assertEquals("hello", TranscriptParser.openaiText("""{"text":"hello"}"""))
    }

    @Test
    fun luxAsrParserJoinsSegmentArray() {
        val text = TranscriptParser.luxAsrText(
            """[{"text":"An elo"},{"text":"geet et."}]""",
        )
        assertEquals("An elo geet et.", text)
    }

    @Test
    fun parserUnwrapsWrappedLuxAsrArrayInTextField() {
        val wrapped = org.json.JSONObject()
            .put("text", """[{"text":"An elo"},{"text":"geet et."}]""")
            .toString()
        assertEquals("An elo geet et.", TranscriptParser.readableText(wrapped))
    }

    @Test
    fun parserReadsLuxAsrNormalizedObject() {
        val raw = """{"text":"An elo geet et.","segments":[{"text":"An elo"},{"text":"geet et."}]}"""
        assertEquals("An elo geet et.", TranscriptParser.readableText(raw))
    }

    @Test
    fun displayTranscriptHidesRawJson() {
        val note = Note(
            id = "1",
            title = "Untitled",
            createdAtMillis = 1,
            updatedAtMillis = 1,
            durationSeconds = 1.0,
            audioFileName = "1.m4a",
            language = "lb",
            outputType = "meeting",
            status = "ready",
            rawTranscript = """{"shortSummary":"not spoken words"}""",
        )
        assertEquals("", note.displayTranscript)
    }

    @Test
    fun summaryParserReadsNewlineJoinedStoredJson() {
        val note = SummaryParser.parse(
            """{"title":"Standup","shortSummary":"We met.","keyIdeas":"Ship Android\nShip iOS","actionItems":"Record a demo"}""",
        )
        assertEquals("Standup", note.title)
        assertEquals(listOf("Ship Android", "Ship iOS"), note.keyIdeas)
        assertEquals(listOf("Record a demo"), note.actionItems)
    }

    @Test
    fun summaryParserReadsCamelCaseKeys() {
        val note = SummaryParser.parse(
            """{"title":"Standup","shortSummary":"We met.","keyIdeas":["Ship Android"],"actionItems":[{"text":"Record a demo"}]}""",
        )
        assertEquals("Standup", note.title)
        assertEquals("We met.", note.shortSummary)
        assertEquals(listOf("Ship Android"), note.keyIdeas)
        assertEquals(listOf("Record a demo"), note.actionItems)
    }
}
