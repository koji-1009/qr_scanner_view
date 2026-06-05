package com.koji_1009.app.qr_scanner_view

import android.graphics.Point
import com.google.mlkit.vision.barcode.common.Barcode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class BarcodeFormatsTest {

    @Test
    fun `code map covers all wire codes and round-trips`() {
        val expected = setOf(
            "qr", "aztec", "dataMatrix", "pdf417", "ean13", "ean8", "upcA",
            "upcE", "code39", "code93", "code128", "codabar", "itf",
        )
        assertEquals(expected, BarcodeFormats.CODE_TO_FORMAT.keys)
        for ((code, format) in BarcodeFormats.CODE_TO_FORMAT) {
            assertEquals(code, BarcodeFormats.wireCode(format))
        }
    }

    @Test
    fun `wireMap normalizes corners by the view size`() {
        val barcode = mock(Barcode::class.java)
        `when`(barcode.rawValue).thenReturn("hello")
        `when`(barcode.format).thenReturn(Barcode.FORMAT_QR_CODE)
        `when`(barcode.cornerPoints).thenReturn(arrayOf(Point(100, 50), Point(200, 100)))

        val map = BarcodeFormats.wireMap(barcode, width = 200, height = 100, emptyList())

        assertNotNull(map)
        assertEquals("hello", map!!["value"])
        assertEquals("qr", map["format"])
        assertEquals(
            listOf(
                mapOf("x" to 0.5, "y" to 0.5),
                mapOf("x" to 1.0, "y" to 1.0),
            ),
            map["corners"],
        )
    }

    @Test
    fun `wireMap drops barcodes without a value`() {
        val barcode = mock(Barcode::class.java)
        `when`(barcode.rawValue).thenReturn(null)
        assertNull(BarcodeFormats.wireMap(barcode, 100, 100, emptyList()))
    }

    @Test
    fun `wireMap reports unknown formats and tolerates a zero-sized view`() {
        val barcode = mock(Barcode::class.java)
        `when`(barcode.rawValue).thenReturn("v")
        `when`(barcode.format).thenReturn(-42)
        `when`(barcode.cornerPoints).thenReturn(arrayOf(Point(1, 1)))

        val map = BarcodeFormats.wireMap(barcode, width = 0, height = 0, emptyList())

        assertEquals("unknown", map!!["format"])
        assertEquals(emptyList<Any>(), map["corners"])
    }

    @Test
    fun `scannerOptions builds for empty, known and unknown formats`() {
        assertNotNull(BarcodeFormats.scannerOptions(emptyList()))
        assertNotNull(BarcodeFormats.scannerOptions(listOf("qr", "ean13")))
        assertNotNull(BarcodeFormats.scannerOptions(listOf("bogus")))
    }

    @Test
    fun `noneSupported is true only for a non-empty all-unknown request`() {
        assertFalse(BarcodeFormats.noneSupported(emptyList()))
        assertTrue(BarcodeFormats.noneSupported(listOf("bogus")))
        assertFalse(BarcodeFormats.noneSupported(listOf("qr", "bogus")))
    }

    @Test
    fun `resolveEmission mirrors the Swift upcA-ean13 contract`() {
        // Native UPC_A: kept when upcA is wanted (the empty request means all).
        assertEquals(
            "upcA" to "123456789012",
            BarcodeFormats.resolveEmission("upcA", "123456789012", emptyList()),
        )
        // A 13-digit zero-prefixed value is normalized to the 12-digit form.
        assertEquals(
            "upcA" to "123456789012",
            BarcodeFormats.resolveEmission("upcA", "0123456789012", listOf("upcA")),
        )
        // ean13-only request receives the same symbol as a zero-prefixed ean13.
        assertEquals(
            "ean13" to "0123456789012",
            BarcodeFormats.resolveEmission("upcA", "123456789012", listOf("ean13")),
        )
        assertNull(BarcodeFormats.resolveEmission("upcA", "123456789012", listOf("qr")))
        // ean13-typed results behave like the Swift paths.
        assertEquals(
            "upcA" to "123456789012",
            BarcodeFormats.resolveEmission("ean13", "0123456789012", listOf("upcA")),
        )
        assertEquals(
            "ean13" to "4901234567894",
            BarcodeFormats.resolveEmission("ean13", "4901234567894", listOf("ean13")),
        )
        assertNull(BarcodeFormats.resolveEmission("ean13", "4901234567894", listOf("upcA")))
        // Other codes pass through untouched.
        assertEquals("qr" to "v", BarcodeFormats.resolveEmission("qr", "v", listOf("ean13")))
    }

    @Test
    fun `wireMap folds a native UPC_A to ean13 when only ean13 was requested`() {
        val barcode = mock(Barcode::class.java)
        `when`(barcode.rawValue).thenReturn("123456789012")
        `when`(barcode.format).thenReturn(Barcode.FORMAT_UPC_A)
        `when`(barcode.cornerPoints).thenReturn(null)

        val map = BarcodeFormats.wireMap(barcode, 100, 100, listOf("ean13"))

        assertEquals("ean13", map!!["format"])
        assertEquals("0123456789012", map["value"])
    }
}
