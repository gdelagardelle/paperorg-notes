package com.paperorg.notes.data

import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import com.paperorg.notes.BuildConfig
import android.content.Context
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class PlayIntegrityClient(
    context: Context,
    private val api: () -> NotesApi,
) : PlayIntegrityGateway {
    private val manager = IntegrityManagerFactory.create(context.applicationContext)

    override fun prove(requestHash: String): IntegrityProof {
        val project = BuildConfig.PLAY_CLOUD_PROJECT_NUMBER
        if (project <= 0L) {
            throw NotesApiException(
                403,
                "Play Integrity is not configured on this build. Set playCloudProjectNumber in android/local.properties to the Google Cloud project number.",
            )
        }
        val (nonceId, nonce) = api().requestIntegrityNonce(requestHash)
        val token = AtomicReference<String>()
        val error = AtomicReference<Exception>()
        val done = CountDownLatch(1)
        val request = IntegrityTokenRequest.builder()
            .setNonce(nonce)
            .setCloudProjectNumber(project)
            .build()
        manager.requestIntegrityToken(request).addOnSuccessListener { response ->
            token.set(response.token())
            done.countDown()
        }.addOnFailureListener { failure ->
            error.set(
                NotesApiException(
                    403,
                    failure.message ?: "Play Integrity failed on this device.",
                ),
            )
            done.countDown()
        }
        if (!done.await(20, TimeUnit.SECONDS)) {
            throw NotesApiException(403, "Device integrity timed out.")
        }
        error.get()?.let { throw it }
        val value = token.get() ?: throw NotesApiException(403, "Device integrity failed.")
        return IntegrityProof(nonceId, token = value)
    }
}
