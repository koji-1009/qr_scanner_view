package com.koji_1009.app.qr_scanner_view

import android.graphics.Point
import com.google.mlkit.vision.barcode.common.Barcode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
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

        val map = BarcodeFormats.wireMap(barcode, width = 200, height = 100)

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
        assertNull(BarcodeFormats.wireMap(barcode, 100, 100))
    }

    @Test
    fun `wireMap reports unknown formats and tolerates a zero-sized view`() {
        val barcode = mock(Barcode::class.java)
        `when`(barcode.rawValue).thenReturn("v")
        `when`(barcode.format).thenReturn(-42)
        `when`(barcode.cornerPoints).thenReturn(arrayOf(Point(1, 1)))

        val map = BarcodeFormats.wireMap(barcode, width = 0, height = 0)

        assertEquals("unknown", map!!["format"])
        assertEquals(emptyList<Any>(), map["corners"])
    }

    @Test
    fun `scannerOptions builds for empty, known and unknown formats`() {
        assertNotNull(BarcodeFormats.scannerOptions(emptyList()))
        assertNotNull(BarcodeFormats.scannerOptions(listOf("qr", "ean13")))
        assertNotNull(BarcodeFormats.scannerOptions(listOf("bogus")))
    }
}
