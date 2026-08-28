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
}
