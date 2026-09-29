package com.paperorg.notes.data

import android.app.Activity
import android.content.Context
import com.paperorg.notes.domain.UsageInfo
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

/** One buyable Paperorg Pro offer, priced by Google Play. */
data class ProPlan(
    val productId: String,
    val basePlanId: String,
    val offerToken: String,
    val price: String,
    val period: String,
    val lifetime: Boolean = false,
)

/**
 * Google Play Billing for Paperorg Pro on Android.
 *
 * A purchase is never trusted on the device: the token goes to notes-api,
 * which asks Google what it is worth, and only an entitlement confirmed
 * that way is acknowledged. Leaving a purchase unacknowledged for three
 * days makes Google refund it, so acknowledgement waits for the server but
 * must not wait longer.
 */
class BillingRepository(
    context: Context,
    private val api: () -> NotesApi,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val catalog = mutableMapOf<String, ProductDetails>()

    /** Publishes the server-verified allowance directly to the UI. */
    var onEntitlementChanged: ((UsageInfo) -> Unit)? = null
    var onMessage: ((String) -> Unit)? = null

    private val purchasesUpdated = PurchasesUpdatedListener { result, purchases ->
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                purchases.orEmpty().forEach { purchase ->
                    scope.launch { redeem(purchase, announce = true) }
                }
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> Unit
            else -> onMessage?.invoke(billingMessage(result))
        }
    }

    private val client = BillingClient.newBuilder(context.applicationContext)
        .setListener(purchasesUpdated)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()

    suspend fun connect(): Boolean = suspendCancellableCoroutine { continuation ->
        if (client.isReady) {
            continuation.resume(true)
            return@suspendCancellableCoroutine
        }
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (continuation.isActive) {
                    continuation.resume(result.responseCode == BillingClient.BillingResponseCode.OK)
                }
            }

            override fun onBillingServiceDisconnected() = Unit
        })
    }

    /** The offers this user may buy, priced and localised by Play. */
    suspend fun plans(): List<ProPlan> {
        if (!connect()) {
            onMessage?.invoke("Google Play Billing could not connect on this device.")
            return emptyList()
        }
        val subscriptions = queryProducts(BillingClient.ProductType.SUBS, PRO_PRODUCT_ID)
        val lifetime = queryProducts(BillingClient.ProductType.INAPP, LIFETIME_PRODUCT_ID)
        catalog.clear()
        (subscriptions + lifetime).forEach { catalog[it.productId] = it }
        val subscription = catalog[PRO_PRODUCT_ID]
        val offers = subscription?.subscriptionOfferDetails.orEmpty()
        if (subscription != null && offers.isEmpty()) {
            onMessage?.invoke("Play returned Pro but no active offers yet. Wait and reopen Settings.")
        }
        val periods = offers
            // One entry per billing period. Where Play reports an intro offer
            // the user is eligible for, its token is the one that gives them
            // the discount, so the first offer per base plan is the right one.
            .groupBy { it.basePlanId }
            .mapNotNull { (basePlanId, offerList) ->
                val offer = offerList.firstOrNull() ?: return@mapNotNull null
                val phase = offer.pricingPhases.pricingPhaseList.lastOrNull()
                    ?: return@mapNotNull null
                ProPlan(
                    productId = PRO_PRODUCT_ID,
                    basePlanId = basePlanId,
                    offerToken = offer.offerToken,
                    price = phase.formattedPrice,
                    period = periodLabel(phase.billingPeriod),
                )
            }
            .sortedBy { it.basePlanId }
        val once = catalog[LIFETIME_PRODUCT_ID]?.oneTimePurchaseOfferDetailsList.orEmpty()
            .map { offer ->
                ProPlan(
                    productId = LIFETIME_PRODUCT_ID,
                    basePlanId = "lifetime",
                    offerToken = offer.offerToken.orEmpty(),
                    price = offer.formattedPrice,
                    period = "once",
                    lifetime = true,
                )
            }
        return periods + once
    }

    private suspend fun queryProducts(type: String, productId: String): List<ProductDetails> {
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(
                listOf(
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(productId)
                        .setProductType(type)
                        .build(),
                ),
            )
            .build()
        return suspendCancellableCoroutine { continuation ->
            client.queryProductDetailsAsync(params) { result, queryResult ->
                if (!continuation.isActive) return@queryProductDetailsAsync
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    val fetched = queryResult.productDetailsList
                    val unfetched = queryResult.unfetchedProductList
                    if (fetched.isEmpty() && unfetched.isNotEmpty() && productId == PRO_PRODUCT_ID) {
                        val status = unfetched.joinToString { "${it.productId}:${it.statusCode}" }
                        onMessage?.invoke("Play has not published Pro to this install yet ($status).")
                    }
                    continuation.resume(fetched)
                } else {
                    if (productId == PRO_PRODUCT_ID) onMessage?.invoke(billingMessage(result))
                    continuation.resume(emptyList())
                }
            }
        }
    }

    fun purchase(activity: Activity, plan: ProPlan) {
        val details = catalog[plan.productId]
        if (details == null) {
            onMessage?.invoke("Paperorg Pro is not available from Google Play right now.")
            return
        }
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(
                listOf(
                    BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(details)
                        .setOfferToken(plan.offerToken)
                        .build(),
                ),
            )
            .build()
        val result = client.launchBillingFlow(activity, params)
        if (result.responseCode != BillingClient.BillingResponseCode.OK) {
            onMessage?.invoke(billingMessage(result))
        }
    }

    /**
     * Re-check what this Google account owns. This is the restore path: a
     * reinstall or a new phone has no local entitlement, and Play still
     * reports the active subscription.
     */
    suspend fun syncPurchases(): PurchaseSyncOutcome {
        if (!connect()) return PurchaseSyncOutcome.NoneFound
        val subscriptions = queryOwned(BillingClient.ProductType.SUBS)
        val ownedOnce = queryOwned(BillingClient.ProductType.INAPP)
        val purchases = subscriptions + ownedOnce
        var restored = false
        var verifyFailed = false
        purchases.forEach { purchase ->
            when (redeem(purchase, announce = false)) {
                RedeemOutcome.Granted -> restored = true
                RedeemOutcome.VerifyFailed -> verifyFailed = true
                RedeemOutcome.Skipped -> Unit
            }
        }
        if (restored) {
            return PurchaseSyncOutcome.Restored
        }
        if (verifyFailed) return PurchaseSyncOutcome.VerifyFailed
        return PurchaseSyncOutcome.NoneFound
    }

    private suspend fun queryOwned(type: String): List<Purchase> {
        val params = QueryPurchasesParams.newBuilder().setProductType(type).build()
        return suspendCancellableCoroutine { continuation ->
            client.queryPurchasesAsync(params) { _, purchases ->
                if (continuation.isActive) continuation.resume(purchases)
            }
        }
    }

    private suspend fun redeem(purchase: Purchase, announce: Boolean): RedeemOutcome {
        if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) {
            return RedeemOutcome.Skipped
        }
        val productId = purchase.products.firstOrNull { it == PRO_PRODUCT_ID || it == LIFETIME_PRODUCT_ID }
            ?: return RedeemOutcome.Skipped

        val verified = withContext(Dispatchers.IO) {
            runCatching { api().verifyPlayPurchase(purchase.purchaseToken, productId) }
        }
        verified.onFailure { error ->
            if (announce) {
                onMessage?.invoke(
                    UserFacingError.message(error as? Exception ?: Exception(error.message)),
                )
            }
            return RedeemOutcome.VerifyFailed
        }

        val usage = verified.getOrThrow()
        onEntitlementChanged?.invoke(usage)
        if (!purchase.isAcknowledged) acknowledge(purchase)
        val granted = usage.isPro
        if (announce) {
            onMessage?.invoke(
                if (granted) {
                    "Paperorg Pro is active."
                } else {
                    "Google Play is still processing this purchase."
                },
            )
        }
        return if (granted) RedeemOutcome.Granted else RedeemOutcome.VerifyFailed
    }

    private suspend fun acknowledge(purchase: Purchase) {
        val params = AcknowledgePurchaseParams.newBuilder()
            .setPurchaseToken(purchase.purchaseToken)
            .build()
        suspendCancellableCoroutine { continuation ->
            client.acknowledgePurchase(params) {
                if (continuation.isActive) continuation.resume(Unit)
            }
        }
    }

    enum class PurchaseSyncOutcome {
        Restored,
        NoneFound,
        /** Play lists a Pro purchase, but notes-api / Google could not confirm it. */
        VerifyFailed,
    }

    private enum class RedeemOutcome {
        Granted,
        Skipped,
        VerifyFailed,
    }

    companion object {
        const val PRO_PRODUCT_ID = "pro"
        const val LIFETIME_PRODUCT_ID = "pro_lifetime"

        fun manageSubscriptionsUrl(packageName: String): String =
            "https://play.google.com/store/account/subscriptions" +
                "?sku=$PRO_PRODUCT_ID&package=$packageName"

        /** Play sends ISO-8601 periods such as P1M or P1Y. */
        fun periodLabel(billingPeriod: String?): String = when (billingPeriod) {
            "P1W" -> "week"
            "P1M" -> "month"
            "P3M" -> "3 months"
            "P6M" -> "6 months"
            "P1Y" -> "year"
            else -> billingPeriod.orEmpty().removePrefix("P").lowercase()
        }

        fun billingMessage(result: BillingResult): String = when (result.responseCode) {
            BillingClient.BillingResponseCode.BILLING_UNAVAILABLE ->
                "Google Play billing is unavailable on this device."
            BillingClient.BillingResponseCode.ITEM_UNAVAILABLE ->
                "Paperorg Pro is not available on this account yet."
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED ->
                "This Google account already has Paperorg Pro. Tap Restore."
            BillingClient.BillingResponseCode.NETWORK_ERROR,
            BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE ->
                "Google Play could not be reached. Try again."
            else -> result.debugMessage.ifBlank { "Google Play could not complete the purchase." }
        }
    }
}
