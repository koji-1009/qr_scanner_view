import 'dart:ui' show Rect;

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

  test('DetectionOptions inequality covers every field', () {
    const base = DetectionOptions();
    expect(base, isNot(const DetectionOptions(formats: {BarcodeFormat.qr})));
    expect(base, isNot(const DetectionOptions(mode: .once)));
    expect(base, isNot(const DetectionOptions(timeout: Duration(seconds: 1))));
    expect(
      base,
      isNot(const DetectionOptions(scanWindow: Rect.fromLTRB(0, 0, 1, 1))),
    );
  });
}
