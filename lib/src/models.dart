import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// Barcode symbology recognized by the scanner.
///
/// [unknown] is used when the native side reports a symbology that has no
/// Dart counterpart.
enum BarcodeFormat {
  qr,
  aztec,
  dataMatrix,
  pdf417,
  ean13,
  ean8,

  /// A UPC-A symbol is a zero-prefixed [ean13] (the bars are identical).
  /// Reported as upcA (12 digits) when requested; a request for only [ean13]
  /// receives the same symbol as a 13-digit zero-prefixed ean13. Identical
  /// on both platforms.
  upcA,
  upcE,
  code39,
  code93,
  code128,

  /// On iOS, detected by `QrScanner.analyzeImage` from iOS 15.0 and by live
  /// scanning from iOS 15.4; never detected on earlier versions. No
  /// constraint on Android.
  codabar,
  itf,
  unknown,
}

/// All recognizable formats except [BarcodeFormat.unknown]; the default for
/// `DetectionOptions.formats`.
const Set<BarcodeFormat> kAllFormats = <BarcodeFormat>{
  .qr,
  .aztec,
  .dataMatrix,
  .pdf417,
  .ean13,
  .ean8,
  .upcA,
  .upcE,
  .code39,
  .code93,
  .code128,
  .codabar,
  .itf,
};

/// A single decoded barcode.
///
/// [value] and [format] are the firm contract. [corners] is best-effort.
@immutable
class Barcode {
  const Barcode({
    required this.value,
    required this.format,
    this.corners = const <Offset>[],
  });

  /// Decoded string contents.
  final String value;

  /// Detected symbology.
  final BarcodeFormat format;

  /// Detected corner points, normalized to 0.0..1.0 with origin top-left in
  /// the displayed preview's coordinate space, consistently on both platforms
  /// (for `QrScanner.analyzeImage`, in the EXIF-upright image's space).
  /// Multiply by the rendered size of the `QrScannerView` to overlay the
  /// preview. May be empty when the platform reports no corners.
  final List<Offset> corners;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Barcode &&
          other.value == value &&
          other.format == format &&
          listEquals(other.corners, corners);

  @override
  int get hashCode => Object.hash(value, format, Object.hashAll(corners));

  @override
  String toString() =>
      'Barcode(${format.name}, "$value", ${corners.length} corners)';
}
