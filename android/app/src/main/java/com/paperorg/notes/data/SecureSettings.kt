package com.paperorg.notes.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.paperorg.notes.domain.VocabularyPrompt
import com.paperorg.notes.domain.EmailAddresses
import java.util.UUID

class SecureSettings(context: Context) : TokenStore {
    private val prefs: SharedPreferences

    init {
        val master = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        prefs = EncryptedSharedPreferences.create(
            context,
            "paperorg-notes",
            master,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
        if (prefs.getString(DEVICE_ID, null).isNullOrBlank()) {
            prefs.edit().putString(DEVICE_ID, UUID.randomUUID().toString()).apply()
        }
    }

    override val deviceId: String
        get() = prefs.getString(DEVICE_ID, null) ?: error("Missing device id")

    override var accessToken: String?
        get() = prefs.getString(ACCESS_TOKEN, null)
        set(value) {
            prefs.edit().putString(ACCESS_TOKEN, value).apply()
        }

    var hasAcceptedPrivacy: Boolean
        get() = prefs.getBoolean(PRIVACY, false)
        set(value) { prefs.edit().putBoolean(PRIVACY, value).apply() }

    var defaultLanguage: String
        get() = prefs.getString(LANGUAGE, AppLanguageCode.default) ?: AppLanguageCode.default
        set(value) { prefs.edit().putString(LANGUAGE, value).apply() }

    var defaultOutputType: String
        get() = prefs.getString(OUTPUT, "meeting") ?: "meeting"
        set(value) { prefs.edit().putString(OUTPUT, value).apply() }

    var keepAudio: Boolean
        get() = prefs.getBoolean(KEEP_AUDIO, true)
        set(value) { prefs.edit().putBoolean(KEEP_AUDIO, value).apply() }

    var deleteAudioAfterTranscription: Boolean
        get() = prefs.getBoolean(DELETE_AUDIO, false)
        set(value) { prefs.edit().putBoolean(DELETE_AUDIO, value).apply() }

    var luxAsrEnabled: Boolean
        get() = prefs.getBoolean(LUXASR, true)
        set(value) { prefs.edit().putBoolean(LUXASR, value).apply() }

    var summaryLength: String
        get() = prefs.getString(SUMMARY_LENGTH, "detailed") ?: "detailed"
        set(value) { prefs.edit().putString(SUMMARY_LENGTH, value).apply() }

    var deleteAudioAfterDays: Int
        get() = prefs.getInt(DELETE_AUDIO_DAYS, 0)
        set(value) { prefs.edit().putInt(DELETE_AUDIO_DAYS, value).apply() }

    var customVocabulary: List<String>
        get() = prefs.getString(VOCABULARY, "")
            .orEmpty()
            .split('\n')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        set(value) { prefs.edit().putString(VOCABULARY, value.joinToString("\n")).apply() }

    fun transcriptionPrompt(): String? = VocabularyPrompt.from(customVocabulary)

    fun addVocabularyTerm(term: String, isPro: Boolean): Boolean {
        val trimmed = term.trim()
        if (trimmed.isEmpty() || customVocabulary.any { it.equals(trimmed, ignoreCase = true) }) return false
        if (!isPro && customVocabulary.size >= freeVocabularyLimit) return false
        customVocabulary = customVocabulary + trimmed
        return true
    }

    val freeVocabularyLimit: Int get() = 20

    fun removeVocabularyTerm(term: String) {
        customVocabulary = customVocabulary.filter { it != term }
    }

    var emailRecipients: List<String>
        get() = prefs.getString(EMAIL_RECIPIENTS, "")
            .orEmpty()
            .split('\n')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        set(value) { prefs.edit().putString(EMAIL_RECIPIENTS, value.joinToString("\n")).apply() }

    var sendEmailAfterTranscription: Boolean
        get() = prefs.getBoolean(SEND_EMAIL_AFTER, false)
        set(value) { prefs.edit().putBoolean(SEND_EMAIL_AFTER, value).apply() }

    var emailContent: String
        get() = prefs.getString(EMAIL_CONTENT, "both") ?: "both"
        set(value) { prefs.edit().putString(EMAIL_CONTENT, value).apply() }

    var emailAttachAudio: Boolean
        get() = prefs.getBoolean(EMAIL_ATTACH_AUDIO, false)
        set(value) { prefs.edit().putBoolean(EMAIL_ATTACH_AUDIO, value).apply() }

    var emailAttachPDF: Boolean
        get() = prefs.getBoolean(EMAIL_ATTACH_PDF, false)
        set(value) { prefs.edit().putBoolean(EMAIL_ATTACH_PDF, value).apply() }

    var emailAttachMarkdown: Boolean
        get() = prefs.getBoolean(EMAIL_ATTACH_MD, false)
        set(value) { prefs.edit().putBoolean(EMAIL_ATTACH_MD, value).apply() }

    var reviewBeforeEmail: Boolean
        get() = prefs.getBoolean(REVIEW_BEFORE_EMAIL, true)
        set(value) { prefs.edit().putBoolean(REVIEW_BEFORE_EMAIL, value).apply() }

    fun addEmailRecipient(email: String): String? {
        val trimmed = email.trim()
        if (!EmailAddresses.isValid(trimmed)) return "Enter a valid email address."
        if (emailRecipients.any { it.equals(trimmed, ignoreCase = true) }) {
            return "This recipient is already listed."
        }
        emailRecipients = emailRecipients + trimmed
        return null
    }

    fun removeEmailRecipient(email: String) {
        emailRecipients = emailRecipients.filter { it != email }
    }

    fun reset() {
        val id = deviceId
        prefs.edit().clear().putString(DEVICE_ID, id).apply()
    }

    private companion object {
        const val DEVICE_ID = "device_id"
        const val ACCESS_TOKEN = "access_token"
        const val PRIVACY = "has_accepted_privacy"
        const val LANGUAGE = "default_language"
        const val OUTPUT = "default_output"
        const val KEEP_AUDIO = "keep_audio"
        const val DELETE_AUDIO = "delete_audio"
        const val LUXASR = "luxasr_enabled"
        const val SUMMARY_LENGTH = "summary_length"
        const val DELETE_AUDIO_DAYS = "delete_audio_days"
        const val VOCABULARY = "custom_vocabulary"
        const val EMAIL_RECIPIENTS = "email_recipients"
        const val SEND_EMAIL_AFTER = "send_email_after_transcription"
        const val EMAIL_CONTENT = "email_content"
        const val EMAIL_ATTACH_AUDIO = "email_attach_audio"
        const val EMAIL_ATTACH_PDF = "email_attach_pdf"
        const val EMAIL_ATTACH_MD = "email_attach_markdown"
        const val REVIEW_BEFORE_EMAIL = "review_before_email"
    }
}

private object AppLanguageCode {
    const val default = "lb"
}
