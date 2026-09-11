package com.paperorg.notes

import com.paperorg.notes.data.*
import com.paperorg.notes.domain.AppLanguage
import java.nio.file.Files
import okhttp3.*
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import org.junit.Assert.*
import org.junit.Test

class SegmentApiTest {
    @Test fun everyProviderSendsStableIdentityAndCumulativeOffset() {
        for (provider in listOf("openai", "luxasr", "elevenlabs")) {
            var upload = ""
            val client = OkHttpClient.Builder().addInterceptor { chain ->
                val request = chain.request()
                val body = if (request.url.encodedPath == "/v1/usage") "{}" else {
                    upload = Buffer().also { request.body!!.writeTo(it) }.readUtf8()
                    "{\"text\":\"hello\"}"
                }
                Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK").body(body.toResponseBody()).build()
            }.build()
            val api = NotesApi(object : TokenStore { override val deviceId = "test"; override var accessToken: String? = "test" },
                object : PlayIntegrityGateway { override fun prove(requestHash: String): IntegrityProof = error("Unexpected integrity") }, client, "https://example.test")
            val file = Files.createTempFile("chunk", ".wav").toFile().also { it.writeBytes(ByteArray(100)) }
            api.transcribe(provider, file, AppLanguage.English, 120.0, recordingSessionId = "session", segmentIndex = 2, segmentStartSeconds = 240.0)
            fun field(name: String, value: String) = Regex("name=\"$name\"\\r\\n(?:[^\\r]+\\r\\n)*\\r\\n${Regex.escape(value)}\\r\\n").containsMatchIn(upload)
            assertTrue(upload, field("recording_session_id", "session"))
            assertTrue(upload, field("segment_index", "2"))
            assertTrue(upload, field("segment_start_seconds", "240.00"))
            file.delete()
        }
    }
}
