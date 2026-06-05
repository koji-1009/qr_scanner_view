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

    /** A non-empty request none of whose codes is supported; the live path
     * and analyzeImage must agree on when this raises unsupportedFormats. */
    fun noneSupported(formats: List<String>): Boolean =
        formats.isNotEmpty() && formats.none { it in CODE_TO_FORMAT }

    /** UPC-A is the zero-prefixed subset of EAN-13 (the symbols are
     * identical). Mirrors `BarcodeWire.resolveEmission` (Swift): emit upcA
     * when the caller asked for upcA, fold to a zero-prefixed ean13 when only
     * ean13 was asked, and drop what the caller did not ask for (null). */
    fun resolveEmission(
        code: String,
        value: String,
        requestedFormats: List<String>,
    ): Pair<String, String>? {
        if (code != "upcA" && code != "ean13") return code to value
        val wantsAll = requestedFormats.isEmpty()
        val wantsUpcA = wantsAll || "upcA" in requestedFormats
        val wantsEan13 = wantsAll || "ean13" in requestedFormats
        return when {
            code == "upcA" && wantsUpcA -> "upcA" to upcAValue(value)
            code == "upcA" && wantsEan13 -> "ean13" to ean13Value(value)
            code == "ean13" && wantsUpcA && value.length == 13 && value.startsWith("0") ->
                "upcA" to value.drop(1)

            code == "ean13" && wantsEan13 -> "ean13" to value
            else -> null
        }
    }

    /** ML Kit reports UPC-A values as 12 digits; tolerate a 13-digit
     * zero-prefixed form. */
    private fun upcAValue(value: String) =
        if (value.length == 13 && value.startsWith("0")) value.drop(1) else value

    private fun ean13Value(value: String) =
        if (value.length == 12) "0$value" else value

    /** Builds the wire map for one barcode, with corners normalized by the
     * given dimensions. Returns null when the barcode carries no value or
     * [resolveEmission] drops it. */
    fun wireMap(
        barcode: Barcode,
        width: Int,
        height: Int,
        requestedFormats: List<String>,
    ): Map<String, Any?>? {
        val raw = barcode.rawValue ?: return null
        val code = wireCode(barcode.format)
        val format: String
        val value: String
        // resolveEmission stays the single upcA/ean13 fold contract; other
        // codes skip it to keep the per-frame path allocation-free.
        if (code == "upcA" || code == "ean13") {
            val resolved = resolveEmission(code, raw, requestedFormats) ?: return null
            format = resolved.first
            value = resolved.second
        } else {
            format = code
            value = raw
        }
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
            "format" to format,
            "corners" to corners,
        )
    }

    fun scannerOptions(formats: List<String>): BarcodeScannerOptions {
        val codes = formats.mapNotNull { CODE_TO_FORMAT[it] }.toMutableList()
        // A UPC-A is a zero-prefixed EAN-13, but ML Kit classifies those
        // symbols as UPC_A: an ean13 request must also detect UPC_A, folded
        // back by resolveEmission.
        if (Barcode.FORMAT_EAN_13 in codes && Barcode.FORMAT_UPC_A !in codes) {
            codes.add(Barcode.FORMAT_UPC_A)
        }
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
