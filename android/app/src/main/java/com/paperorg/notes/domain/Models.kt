package com.paperorg.notes.domain

enum class AppLanguage(val code: String, val displayName: String, val flag: String) {
    Auto("auto", "Auto-detect", "🌐"),
    Luxembourgish("lb", "Lëtzebuergesch", "🇱🇺"),
    German("de", "Deutsch", "🇩🇪"),
    French("fr", "Français", "🇫🇷"),
    English("en", "English", "🇬🇧"),
    Portuguese("pt", "Português", "🇵🇹");

    val isAuto: Boolean get() = this == Auto

    val openAiCode: String?
        get() = when (this) {
            Auto, Luxembourgish -> null
            else -> code
        }

    val elevenLabsCode: String?
        get() = when (this) {
            Auto -> null
            Luxembourgish -> "ltz"
            German -> "deu"
            French -> "fra"
            English -> "eng"
            Portuguese -> "por"
        }

    companion object {
        val spoken: List<AppLanguage> = entries.filterNot { it.isAuto }
        val recordPicker: List<AppLanguage> = listOf(Auto) + spoken

        fun fromCode(raw: String): AppLanguage {
            val normalized = raw.lowercase()
            return entries.find { it.code == normalized }
                ?: when (normalized) {
                    "ltz" -> Luxembourgish
                    "deu" -> German
                    "fra" -> French
                    "eng" -> English
                    "por" -> Portuguese
                    else -> entries.find { it.code == normalized.take(2) } ?: English
                }
        }
    }
}

enum class OutputType(val code: String, val displayName: String) {
    Meeting("meeting", "Meeting notes"),
    Brainstorm("brainstorm", "Brainstorm"),
    Memo("memo", "Personal memo"),
    ClientCall("client_call", "Client call"),
    Interview("interview", "Interview"),
    TaskList("task_list", "Task list"),
    Resume("resume", "Clean resume"),
    Raw("raw", "Transcript only");
}

enum class SummaryLength(val code: String, val displayName: String) {
    Short("short", "Short"),
    Detailed("detailed", "Detailed");

    companion object {
        fun fromCode(raw: String): SummaryLength =
            entries.find { it.code == raw.lowercase() } ?: Detailed
    }
}

enum class EmailContent(val code: String, val displayName: String) {
    SummaryOnly("summary", "Summary only"),
    FullTranscript("transcript", "Full transcript"),
    Both("both", "Summary and transcript");

    companion object {
        fun fromCode(raw: String): EmailContent =
            entries.find { it.code == raw.lowercase() } ?: Both
    }
}

data class EmailServerStatus(
    val available: Boolean,
    val fromName: String? = null,
    val fromAddress: String? = null,
    val smtpHost: String? = null,
)

object EmailAddresses {
    private val pattern = Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")

    fun isValid(email: String): Boolean = pattern.matches(email.trim())
}

object VocabularyPrompt {
    fun from(terms: List<String>): String? {
        val cleaned = terms.map { it.trim() }.filter { it.isNotEmpty() }
        if (cleaned.isEmpty()) return null
        return cleaned.take(40).joinToString(", ").take(900)
    }
}

enum class NoteStatus {
    Draft,
    Processing,
    WaitingForNetwork,
    Ready,
    Failed,
}

enum class ProcessingStage(val displayName: String) {
    Saving("Saving audio"),
    Transcribing("Transcribing"),
    Checking("Checking quality"),
    Summarizing("Summarizing"),
    Ready("Ready"),
}

enum class ProviderId(val id: String, val displayName: String) {
    LuxAsr("luxasr", "LuxASR"),
    OpenAi("openai", "OpenAI"),
    ElevenLabs("elevenlabs", "ElevenLabs");

    companion object {
        private val spacedName = Regex("(?i)lux\\s*asr")

        fun label(id: String?): String? =
            id?.takeIf { it.isNotBlank() }?.let { raw ->
                entries.find { it.id.equals(raw, ignoreCase = true) }?.displayName
                    ?: spacedName.replace(raw, "LuxASR")
            }
    }
}

object ProviderOrder {
    fun forLanguage(language: AppLanguage, luxAsrEnabled: Boolean = true): List<ProviderId> {
        val order = when (language) {
            AppLanguage.Luxembourgish -> listOf(ProviderId.LuxAsr, ProviderId.ElevenLabs, ProviderId.OpenAi)
            AppLanguage.Auto -> listOf(ProviderId.OpenAi, ProviderId.ElevenLabs)
            else -> listOf(ProviderId.OpenAi, ProviderId.ElevenLabs)
        }
        return if (luxAsrEnabled) order else order.filter { it != ProviderId.LuxAsr }
    }
}

object DurationFormat {
    fun format(seconds: Double): String {
        val total = seconds.toInt().coerceAtLeast(0)
        val minutes = total / 60
        val remainder = total % 60
        return "%02d:%02d".format(minutes, remainder)
    }
}

object IntegrityHash {
    fun hex(path: String, audio: ByteArray): String {
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        digest.update(path.toByteArray(Charsets.UTF_8))
        digest.update(audio)
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}

data class UsageInfo(
    val isPro: Boolean,
    val minutesLimit: Int,
    val minutesUsed: Double,
    val minutesRemaining: Double,
    val periodKey: String,
    val proExpiresAt: String?,
    val appAttestRequired: Boolean,
    val playIntegrityRequired: Boolean,
    // Ceiling on one upload, separate from the monthly allowance. Null on
    // servers that predate it, which means the cap is unknown rather than zero.
    val maxRecordingMinutes: Int? = null,
)

data class Note(
    val id: String,
    val title: String,
    val createdAtMillis: Long,
    val updatedAtMillis: Long,
    val durationSeconds: Double,
    val audioFileName: String,
    val language: String,
    val outputType: String,
    val status: String,
    val processingStage: String? = null,
    val isFavorite: Boolean = false,
    val projectName: String? = null,
    val rawTranscript: String? = null,
    val summaryShort: String? = null,
    val summaryDetailed: String? = null,
    val structuredJson: String? = null,
    val primaryProvider: String? = null,
    val errorMessage: String? = null,
    val tags: String = "",
) {
    val displayTranscript: String
        get() {
            val cleaned = TranscriptParser.readableText(rawTranscript).orEmpty()
            if (cleaned.isNotBlank()) return cleaned
            val raw = rawTranscript.orEmpty()
            return if (TranscriptParser.isRawJSON(raw)) "" else raw
        }

    val displaySummaryShort: String
        get() {
            val summary = summaryShort
            if (!summary.isNullOrBlank() && !TranscriptParser.isRawJSON(summary)) return summary
            return displayTranscript
        }

    val previewSnippet: String
        get() = displayTranscript.ifBlank { displaySummaryShort }

    fun matches(query: String): Boolean {
        if (query.isBlank()) return true
        val q = query.lowercase()
        return title.lowercase().contains(q) ||
            (projectName?.lowercase()?.contains(q) == true) ||
            displayTranscript.lowercase().contains(q) ||
            (rawTranscript?.lowercase()?.contains(q) == true) ||
            (summaryShort?.lowercase()?.contains(q) == true) ||
            tags.lowercase().contains(q)
    }
}
