package com.koji_1009.app.qr_scanner_view

import android.graphics.Point
import android.graphics.RectF
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class QrScannerViewHelpersTest {

    @Test
    fun `scanWindowFromMap parses a complete map and rejects partial ones`() {
        val window = QrScannerView.scanWindowFromMap(
            mapOf("left" to 0.1, "top" to 0.2, "right" to 0.9, "bottom" to 0.8),
        )
        assertEquals(RectF(0.1f, 0.2f, 0.9f, 0.8f), window)

        assertNull(QrScannerView.scanWindowFromMap(null))
        assertNull(QrScannerView.scanWindowFromMap(mapOf("left" to 0.1)))
        assertNull(
            QrScannerView.scanWindowFromMap(
                mapOf("left" to "a", "top" to 0.0, "right" to 1.0, "bottom" to 1.0),
            ),
        )
    }

    @Test
    fun `isInWindow tests the centroid against the normalized window`() {
        val window = RectF(0.25f, 0.25f, 0.75f, 0.75f)
        val inside = arrayOf(Point(40, 40), Point(60, 60))
        val outside = arrayOf(Point(0, 0), Point(20, 20))

        assertTrue(QrScannerView.isInWindow(inside, window, 100, 100))
        assertFalse(QrScannerView.isInWindow(outside, window, 100, 100))
    }

    @Test
    fun `isInWindow passes barcodes without corners`() {
        val window = RectF(0.25f, 0.25f, 0.75f, 0.75f)
        assertTrue(QrScannerView.isInWindow(null, window, 100, 100))
        assertTrue(QrScannerView.isInWindow(emptyArray(), window, 100, 100))
    }

}
