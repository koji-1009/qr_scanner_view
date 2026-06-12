import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';

import 'models.dart';

/// Camera lens selection.
///
/// [auto] prefers the back lens and falls back to front. Selecting an
/// unavailable lens surfaces `ScannerErrorCode.lensNotFound`. There is no
/// ultra-wide/telephoto selection: zoom is the cross-platform abstraction for
/// field of view (`setZoom`), and on devices exposing a logical multi-camera
/// the zoom range spans the physical lenses.
enum CameraLens { auto, back, front }

/// How the camera image is fitted into the view, applied natively
/// (`PreviewView.ScaleType` on Android, `videoGravity` on iOS).
///
/// `Barcode.corners` and the scan window stay in the displayed preview's
/// normalized coordinates under either fit.
enum PreviewFit {
  /// Fills the view, cropping the image where aspect ratios differ.
  cover,

  /// Shows the whole image, letterboxing where aspect ratios differ.
  contain,
}

/// How detections are forwarded to `QrScannerController.barcodes`.
enum DetectionMode {
  /// Every detection, including the same code on consecutive frames.
  all,

  /// The default. Suppresses a code while it stays in view; one unseen for
  /// [DetectionOptions.timeout] (or about a second when no timeout is set) is
  /// reported as new again. With a [DetectionOptions.timeout] a continuously
  /// visible code is also re-emitted after the timeout elapses. Suppression
  /// state survives `stop`/`start` so resuming does not re-count a code still
  /// in view.
  noDuplicates,

  /// Emits one detection, then stops the scanner; with several codes in view
  /// the one nearest the scan-window (or preview) center wins. `start()`
  /// re-arms it.
  once,
}

bool _isNormalizedWindow(Rect rect) =>
    rect.left >= 0 &&
    rect.top >= 0 &&
    rect.right <= 1 &&
    rect.bottom <= 1 &&
    rect.left < rect.right &&
    rect.top < rect.bottom;

/// Throws when [window] is not a normalized (0..1), positive-area rectangle.
void validateScanWindow(Rect? window) {
  if (window != null && !_isNormalizedWindow(window)) {
    throw ArgumentError.value(
      window,
      'scanWindow',
      'must be normalized to 0.0..1.0 with left < right and top < bottom',
    );
  }
}

/// Throws when [point] is not normalized to 0..1 on both axes.
void validateFocusPoint(Offset? point) {
  if (point != null &&
      !(point.dx >= 0 && point.dx <= 1 && point.dy >= 0 && point.dy <= 1)) {
    throw ArgumentError.value(
      point,
      'focusPoint',
      'must be normalized to 0.0..1.0 on both axes',
    );
  }
}

/// Initial camera configuration. Every field can also be changed at runtime
/// through the controller (`setCamera`, `setZoom`, `setTorch`).
@immutable
class CameraOptions {
  const CameraOptions({this.lens = .auto, this.zoom = 0.0, this.torch = false})
    : assert(zoom >= 0.0 && zoom <= 1.0, 'zoom must be in 0.0..1.0');

  /// Lens to open.
  final CameraLens lens;

  /// Linear zoom, 0.0 (widest) to 1.0 (max).
  final double zoom;

  /// Whether the torch starts on.
  final bool torch;

  CameraOptions copyWith({CameraLens? lens, double? zoom, bool? torch}) =>
      CameraOptions(
        lens: lens ?? this.lens,
        zoom: zoom ?? this.zoom,
        torch: torch ?? this.torch,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraOptions &&
          other.lens == lens &&
          other.zoom == zoom &&
          other.torch == torch;

  @override
  int get hashCode => Object.hash(lens, zoom, torch);
}

/// Detection configuration.
///
/// [scanWindow] can also be changed at runtime through the controller
/// (`setScanWindow`). [formats], [mode] and [timeout] are fixed at creation;
/// change the widget's `key` to apply new values.
@immutable
class DetectionOptions {
  const DetectionOptions({
    this.formats = kAllFormats,
    this.mode = .noDuplicates,
    this.timeout,
    this.scanWindow,
  });

  /// Symbologies to detect. An empty set detects nothing: the preview
  /// streams without any detection. See [BarcodeFormat.codabar] for its iOS
  /// version floor.
  final Set<BarcodeFormat> formats;

  /// How detections are forwarded; see [DetectionMode].
  final DetectionMode mode;

  /// In [DetectionMode.noDuplicates], how long a continuously visible code
  /// stays suppressed. When null it stays suppressed while it remains in
  /// view. Non-positive values are treated as null.
  final Duration? timeout;

  /// Restricts detection to this region, in the same normalized 0.0..1.0
  /// preview coordinates as [Barcode.corners]. Null scans the whole preview.
  final Rect? scanWindow;

  DetectionOptions copyWith({
    Set<BarcodeFormat>? formats,
    DetectionMode? mode,
    Duration? timeout,
    Rect? scanWindow,
  }) => DetectionOptions(
    formats: formats ?? this.formats,
    mode: mode ?? this.mode,
    timeout: timeout ?? this.timeout,
    scanWindow: scanWindow ?? this.scanWindow,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DetectionOptions &&
          setEquals(other.formats, formats) &&
          other.mode == mode &&
          other.timeout == timeout &&
          other.scanWindow == scanWindow;

  @override
  int get hashCode =>
      Object.hash(Object.hashAllUnordered(formats), mode, timeout, scanWindow);
}
