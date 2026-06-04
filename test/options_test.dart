import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner_view/qr_scanner_view.dart';

void main() {
  test('CameraOptions defaults work out of the box', () {
    const options = CameraOptions();
    expect(options.lens, CameraLens.auto);
    expect(options.zoom, 0.0);
    expect(options.torch, isFalse);
  });

  test('CameraOptions rejects an out-of-range zoom', () {
    expect(() => CameraOptions(zoom: 1.5), throwsAssertionError);
    expect(() => CameraOptions(zoom: -0.1), throwsAssertionError);
  });

  test('DetectionOptions defaults work out of the box', () {
    const options = DetectionOptions();
    expect(options.formats, kAllFormats);
    expect(options.mode, DetectionMode.noDuplicates);
    expect(options.timeout, isNull);
    expect(options.scanWindow, isNull);
  });

  test('validateScanWindow rejects inverted or out-of-range rectangles', () {
    expect(
      () => validateScanWindow(const Rect.fromLTRB(0.7, 0.2, 0.3, 0.8)),
      throwsArgumentError,
    );
    expect(
      () => validateScanWindow(const Rect.fromLTRB(0, 0, 1.5, 1)),
      throwsArgumentError,
    );
    expect(
      () => validateScanWindow(const Rect.fromLTRB(0.2, 0.2, 0.2, 0.8)),
      throwsArgumentError,
    );
    expect(() => validateScanWindow(null), returnsNormally);
    expect(
      () => validateScanWindow(const Rect.fromLTRB(0, 0, 1, 1)),
      returnsNormally,
    );
  });

  test('validateFocusPoint rejects out-of-range or NaN points', () {
    expect(
      () => validateFocusPoint(const Offset(1.2, 0.5)),
      throwsArgumentError,
    );
    expect(
      () => validateFocusPoint(const Offset(0.5, -0.1)),
      throwsArgumentError,
    );
    expect(
      () => validateFocusPoint(const Offset(double.nan, 0.5)),
      throwsArgumentError,
    );
    expect(() => validateFocusPoint(null), returnsNormally);
    expect(() => validateFocusPoint(const Offset(0, 1)), returnsNormally);
    expect(() => validateFocusPoint(const Offset(0.5, 0.5)), returnsNormally);
  });

  test('options support value equality and copyWith', () {
    const camera = CameraOptions(zoom: 0.5, torch: true);
    expect(camera, camera.copyWith());
    expect(
      camera.copyWith(torch: false),
      const CameraOptions(zoom: 0.5, torch: false),
    );

    const detection = DetectionOptions(mode: .once);
    expect(detection, detection.copyWith());
    expect(detection.copyWith(mode: .all).mode, DetectionMode.all);
  });
}
