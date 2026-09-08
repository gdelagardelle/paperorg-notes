package com.paperorg.notes

import com.paperorg.notes.domain.AppLanguage
import com.paperorg.notes.domain.DurationFormat
import com.paperorg.notes.domain.IntegrityHash
import com.paperorg.notes.domain.EmailAddresses
import com.paperorg.notes.domain.Note
import com.paperorg.notes.domain.ProviderId
import com.paperorg.notes.domain.ProviderOrder
import com.paperorg.notes.domain.VocabularyPrompt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DomainTest {
    @Test
    fun durationPadsMinutesAndSeconds() {
        assertEquals("00:00", DurationFormat.format(0.0))
        assertEquals("00:09", DurationFormat.format(9.4))
        assertEquals("12:05", DurationFormat.format(725.0))
    }

    @Test
    fun luxembourgishProviderOrderStartsWithLuxAsr() {
        assertEquals(
            listOf(ProviderId.LuxAsr, ProviderId.ElevenLabs, ProviderId.OpenAi),
            ProviderOrder.forLanguage(AppLanguage.Luxembourgish),
        )
    }

    @Test
    fun luxAsrCanBeDroppedForTesting() {
        assertEquals(
            listOf(ProviderId.ElevenLabs, ProviderId.OpenAi),
            ProviderOrder.forLanguage(AppLanguage.Luxembourgish, luxAsrEnabled = false),
        )
    }

    @Test
    fun integrityHashIsStableAndPathSensitive() {
        val audio = "audio-bytes".toByteArray()
        val first = IntegrityHash.hex("/v1/transcribe/openai", audio)
        val second = IntegrityHash.hex("/v1/transcribe/openai", audio)
        assertEquals(64, first.length)
        assertEquals(first, second)
        assertFalse(first == IntegrityHash.hex("/v1/transcribe/luxasr", audio))
    }

    @Test
    fun integrityErrorIsMappedForAndroidUsers() {
        val message = com.paperorg.notes.data.UserFacingError.message(
            com.paperorg.notes.data.NotesApiException(403, "Device integrity verification is required."),
        )
        assertTrue(message.contains("recording was saved") || message.contains("Play Integrity"))
        assertFalse(message.contains("App Attest"))
    }

    @Test
    fun autoDetectSkipsLuxAsr() {
        assertEquals(
            listOf(ProviderId.OpenAi, ProviderId.ElevenLabs),
            ProviderOrder.forLanguage(AppLanguage.Auto),
        )
    }

    @Test
    fun providerLabelMapsKnownIds() {
        assertEquals("LuxASR", ProviderId.label("luxasr"))
        assertEquals("OpenAI", ProviderId.label("openai"))
        assertEquals("LuxASR", ProviderId.label("Lux ASR"))
        assertEquals("LuxASR", ProviderId.label("lux asr"))
        assertEquals("LuxASR", ProviderId.label("LuxAsr"))
    }

    @Test
    fun vocabularyPromptJoinsAndTruncates() {
        assertEquals("Acme, Dupont", VocabularyPrompt.from(listOf(" Acme ", "Dupont")))
        assertNull(VocabularyPrompt.from(listOf("  ", "")))
    }

    @Test
    fun searchMatchesTitleTranscriptAndSummary() {
        val note = Note(
            id = "1",
            title = "Team standup",
            createdAtMillis = 1,
            updatedAtMillis = 1,
            durationSeconds = 12.0,
            audioFileName = "1.m4a",
            language = "lb",
            outputType = "meeting",
            status = "ready",
            rawTranscript = "Mir hunn haut geschwat",
            summaryShort = "Standup notes",
        )
        assertTrue(note.matches("standup"))
        assertTrue(note.matches("haut"))
        assertTrue(note.matches("notes"))
        assertFalse(note.matches("invoice"))
    }

    @Test
    fun emailValidationMatchesIosRule() {
        assertTrue(EmailAddresses.isValid("notes@paperorg.com"))
        assertFalse(EmailAddresses.isValid("not-an-email"))
        assertFalse(EmailAddresses.isValid("missing@domain"))
    }

    @Test
    fun importSniffsMp3EvenWhenThePickerReportsOctetStream() {
        assertEquals(
            com.paperorg.notes.domain.AudioFormat.MP3,
            com.paperorg.notes.domain.AudioFormat.forImport("application/octet-stream", "meeting.mp3"),
        )
    }

    @Test
    fun importRefusesAnUnknownContainer() {
        assertNull(
            com.paperorg.notes.domain.AudioFormat.forImport("application/pdf", "notes.pdf"),
        )
    }

    @Test
    fun uploadMimeFollowsTheFileExtensionNotAHardcodedM4a() {
        assertEquals("audio/mpeg", com.paperorg.notes.domain.AudioFormat.forFileName("note.mp3").mimeType)
        assertEquals("audio/wav", com.paperorg.notes.domain.AudioFormat.forFileName("note.wav").mimeType)
        assertEquals("audio/m4a", com.paperorg.notes.domain.AudioFormat.forFileName("note.m4a").mimeType)
    }

    @Test
    fun importPolicyRefusesOverTheCapBeforeCopying() {
        val message = com.paperorg.notes.domain.ImportPolicy.refusal(
            seconds = 16 * 60.0,
            bytes = 1_000,
            maxRecordingMinutes = 3,
        )
        assertEquals(
            "This audio is longer than 3 minutes. Split it into shorter parts.",
            message,
        )
    }

    @Test
    fun importPolicyDoesNotInventACapTheServerHasNotSent() {
        assertNull(
            com.paperorg.notes.domain.ImportPolicy.refusal(
                seconds = 16 * 60.0,
                bytes = 1_000,
                maxRecordingMinutes = null,
            ),
        )
    }

    @Test
    fun oversizedAudioGetsTheServerDetailNotAGenericHttpString() {
        val message = com.paperorg.notes.data.UserFacingError.message(
            com.paperorg.notes.data.NotesApiException(
                413,
                "This audio is 20 minutes long. A single transcription can be at most 15 minutes.",
            ),
        )
        assertTrue(message.contains("15 minutes"))
        assertFalse(message.contains("HTTP 413"))
    }
}
