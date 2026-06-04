package com.koji_1009.app.qr_scanner_view

import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.common.Barcode

internal object BarcodeFormats {
    /** Wire code to ML Kit format; the reverse map is derived from this. */
    val CODE_TO_FORMAT: Map<String, Int> = mapOf(
        "qr" to Barcode.FORMAT_QR_CODE,
        "aztec" to Barcode.FORMAT_AZTEC,
        "dataMatrix" to Barcode.FORMAT_DATA_MATRIX,
        "pdf417" to Barcode.FORMAT_PDF417,
        "ean13" to Barcode.FORMAT_EAN_13,
        "ean8" to Barcode.FORMAT_EAN_8,
        "upcA" to Barcode.FORMAT_UPC_A,
        "upcE" to Barcode.FORMAT_UPC_E,
        "code39" to Barcode.FORMAT_CODE_39,
        "code93" to Barcode.FORMAT_CODE_93,
        "code128" to Barcode.FORMAT_CODE_128,
        "codabar" to Barcode.FORMAT_CODABAR,
        "itf" to Barcode.FORMAT_ITF,
    )

    /** Inverse of [CODE_TO_FORMAT] as a primitive-int switch: runs per
     * barcode per frame, where a Map lookup would box the key. */
    fun wireCode(format: Int): String = when (format) {
        Barcode.FORMAT_QR_CODE -> "qr"
        Barcode.FORMAT_AZTEC -> "aztec"
        Barcode.FORMAT_DATA_MATRIX -> "dataMatrix"
        Barcode.FORMAT_PDF417 -> "pdf417"
        Barcode.FORMAT_EAN_13 -> "ean13"
        Barcode.FORMAT_EAN_8 -> "ean8"
        Barcode.FORMAT_UPC_A -> "upcA"
        Barcode.FORMAT_UPC_E -> "upcE"
        Barcode.FORMAT_CODE_39 -> "code39"
        Barcode.FORMAT_CODE_93 -> "code93"
        Barcode.FORMAT_CODE_128 -> "code128"
        Barcode.FORMAT_CODABAR -> "codabar"
        Barcode.FORMAT_ITF -> "itf"
        else -> "unknown"
    }

    /** Builds the wire map for one barcode, with corners normalized by the
     * given dimensions. Returns null when the barcode carries no value. */
    fun wireMap(barcode: Barcode, width: Int, height: Int): Map<String, Any?>? {
        val value = barcode.rawValue ?: return null
        val corners = barcode.cornerPoints
            ?.takeIf { width > 0 && height > 0 }
            ?.map {
                mapOf(
                    "x" to (it.x.toDouble() / width),
                    "y" to (it.y.toDouble() / height),
                )
            }
            ?: emptyList()
        return mapOf(
            "value" to value,
            "format" to wireCode(barcode.format),
            "corners" to corners,
        )
    }

    fun scannerOptions(formats: List<String>): BarcodeScannerOptions {
        val codes = formats.mapNotNull { CODE_TO_FORMAT[it] }
        if (codes.isEmpty()) {
            return BarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_ALL_FORMATS)
                .build()
        }
        return BarcodeScannerOptions.Builder()
            .setBarcodeFormats(codes.first(), *codes.drop(1).toIntArray())
            .build()
    }
}
