package com.paperorg.notes.data

import com.paperorg.notes.BuildConfig
import com.paperorg.notes.domain.AppLanguage
import com.paperorg.notes.domain.EmailServerStatus
import com.paperorg.notes.domain.IntegrityHash
import com.paperorg.notes.domain.OutputType
import com.paperorg.notes.domain.UsageInfo
import com.paperorg.notes.domain.UsageParser
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

class NotesApiException(val status: Int, message: String) : IOException(message)

class NotesApi(
    private val tokenStore: TokenStore,
    private val integrity: PlayIntegrityGateway,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(300, TimeUnit.SECONDS)
        .writeTimeout(300, TimeUnit.SECONDS)
        .build(),
    private val baseUrl: String = BuildConfig.NOTES_API_URL.trimEnd('/'),
) {
    fun registerIfNeeded() {
        if (tokenStore.accessToken != null) return
        register()
    }

    fun register(): UsageInfo {
        val body = JSONObject().put("device_id", tokenStore.deviceId).toString()
        val request = Request.Builder()
            .url("$baseUrl/v1/auth/register")
            .post(body.toRequestBody(JSON))
            .header("Content-Type", "application/json")
            .build()
        val payload = execute(request)
        tokenStore.accessToken = payload.getString("access_token")
        return UsageParser.parse(payload.toString())
    }

    fun usage(): UsageInfo {
        registerIfNeeded()
        val request = authorized("$baseUrl/v1/usage").get().build()
        return UsageParser.parse(execute(request).toString())
    }

    fun transcribe(
        provider: String,
        audio: File,
        language: AppLanguage,
        durationSeconds: Double,
        prompt: String? = null,
    ): String {
        registerIfNeeded()
        val usage = runCatching { usage() }.getOrNull()
        val path = when (provider) {
            "luxasr" -> "/v1/transcribe/luxasr"
            "elevenlabs" -> "/v1/transcribe/elevenlabs"
            else -> "/v1/transcribe/openai"
        }
        val audioBytes = audio.readBytes()
        val builder = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("file", audio.name, audio.asRequestBody("audio/m4a".toMediaType()))
            .addFormDataPart("duration_seconds", "%.2f".format(durationSeconds))
        when (provider) {
            "luxasr" -> builder.addFormDataPart("language", "lb")
            "elevenlabs" -> {
                builder.addFormDataPart("language_code", language.elevenLabsCode ?: "auto")
                builder.addFormDataPart("diarize", "false")
            }
            else -> builder.addFormDataPart("language", language.openAiCode ?: "auto")
        }
        if (!prompt.isNullOrBlank()) {
            builder.addFormDataPart("prompt", prompt.take(900))
        }
        val requestBuilder = authorized("$baseUrl$path")
            .post(builder.build())
        if (usage?.playIntegrityRequired == true) {
            val hash = IntegrityHash.hex(path, audioBytes)
            val proof = integrity.prove(hash)
            requestBuilder
                .header("X-Paperorg-Play-Integrity-Nonce-Id", proof.nonceId)
                .header("X-Paperorg-Play-Integrity-Token", proof.token)
        }
        return executeRaw(requestBuilder.build())
    }

    fun summarize(
        transcript: String,
        outputType: OutputType,
        language: AppLanguage,
        summaryLength: String = "detailed",
    ): String {
        registerIfNeeded()
        val body = JSONObject()
            .put("transcript", transcript)
            .put("output_type", outputType.displayName)
            .put("language", language.displayName)
            .put("summary_length", summaryLength)
            .toString()
        val request = authorized("$baseUrl/v1/summarize")
            .post(body.toRequestBody(JSON))
            .header("Content-Type", "application/json")
            .build()
        return executeRaw(request)
    }

    fun emailStatus(): EmailServerStatus {
        registerIfNeeded()
        val request = authorized("$baseUrl/v1/email/status").get().build()
        val payload = execute(request)
        return EmailServerStatus(
            available = payload.optBoolean("available"),
            fromName = payload.optString("from_name").takeIf { it.isNotEmpty() && it != "null" },
            fromAddress = payload.optString("from_address").takeIf { it.isNotEmpty() && it != "null" },
            smtpHost = payload.optString("smtp_host").takeIf { it.isNotEmpty() && it != "null" },
        )
    }

    fun sendEmail(draft: EmailDraft) {
        registerIfNeeded()
        val usage = runCatching { usage() }.getOrNull()
        val recipientsJson = JSONArray().also { array ->
            draft.recipients.forEach { array.put(it) }
        }.toString()
        val builder = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("subject", draft.subject)
            .addFormDataPart("body", draft.body)
            .addFormDataPart("html_body", draft.htmlBody)
            .addFormDataPart("recipients", recipientsJson)
        draft.attachments.forEach { file ->
            val field = when {
                file.name.endsWith(".m4a", true) || file.name.endsWith(".mp3", true) -> "audio"
                file.name.endsWith(".pdf", true) -> "pdf"
                else -> "markdown"
            }
            val mime = when (field) {
                "audio" -> "audio/m4a"
                "pdf" -> "application/pdf"
                else -> "text/markdown"
            }
            builder.addFormDataPart(field, file.name, file.asRequestBody(mime.toMediaType()))
        }
        val requestBuilder = authorized("$baseUrl/v1/email/send").post(builder.build())
        if (usage?.playIntegrityRequired == true) {
            val payload = "${draft.subject}\n${draft.body}\n$recipientsJson".toByteArray(Charsets.UTF_8)
            val proof = integrity.prove(IntegrityHash.hex("/v1/email/send", payload))
            requestBuilder
                .header("X-Paperorg-Play-Integrity-Nonce-Id", proof.nonceId)
                .header("X-Paperorg-Play-Integrity-Token", proof.token)
        }
        execute(requestBuilder.build())
    }

    fun requestIntegrityNonce(requestHash: String): Pair<String, String> {
        registerIfNeeded()
        val body = JSONObject().put("request_hash", requestHash).toString()
        val request = authorized("$baseUrl/v1/play-integrity/nonce")
            .post(body.toRequestBody(JSON))
            .header("Content-Type", "application/json")
            .build()
        val payload = execute(request)
        return payload.getString("nonce_id") to payload.getString("nonce")
    }

    private fun authorized(url: String): Request.Builder {
        val token = tokenStore.accessToken ?: throw NotesApiException(401, "Not signed in.")
        return Request.Builder()
            .url(url)
            .header("Authorization", "Bearer $token")
            .header("X-Paperorg-Client-Platform", "android")
    }

    private fun executeRaw(request: Request): String {
        client.newCall(request).execute().use { response ->
            val raw = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                if (response.code == 401) tokenStore.accessToken = null
                val detail = runCatching { JSONObject(raw).optString("detail") }.getOrNull()
                    ?.takeIf { it.isNotBlank() }
                    ?: raw.ifBlank { "HTTP ${response.code}" }
                throw NotesApiException(response.code, detail)
            }
            return raw
        }
    }

    private fun execute(request: Request): JSONObject {
        val raw = executeRaw(request)
        if (raw.isBlank()) return JSONObject()
        return if (raw.trimStart().startsWith("[")) {
            JSONObject().put("text", raw)
        } else {
            JSONObject(raw)
        }
    }

    companion object {
        private val JSON = "application/json; charset=utf-8".toMediaType()
    }
}

interface TokenStore {
    val deviceId: String
    var accessToken: String?
}

data class IntegrityProof(val nonceId: String, val token: String)

interface PlayIntegrityGateway {
    fun prove(requestHash: String): IntegrityProof
}
