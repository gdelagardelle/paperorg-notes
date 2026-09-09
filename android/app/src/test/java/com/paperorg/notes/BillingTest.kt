package com.paperorg.notes

import com.paperorg.notes.data.BillingRepository
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BillingTest {
    @Test
    fun playBillingPeriodsBecomeReadableLabels() {
        assertEquals("month", BillingRepository.periodLabel("P1M"))
        assertEquals("year", BillingRepository.periodLabel("P1Y"))
        assertEquals("3 months", BillingRepository.periodLabel("P3M"))
    }

    @Test
    fun anUnexpectedPeriodStillReadsAsSomething() {
        assertEquals("2y", BillingRepository.periodLabel("P2Y"))
        assertEquals("", BillingRepository.periodLabel(null))
    }

    @Test
    fun manageUrlPointsAtThisAppsSubscription() {
        val url = BillingRepository.manageSubscriptionsUrl("com.paperorg.notes")
        assertTrue(url.startsWith("https://play.google.com/store/account/subscriptions"))
        assertTrue(url.contains("sku=pro"))
        assertTrue(url.contains("package=com.paperorg.notes"))
    }
}
