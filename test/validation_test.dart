import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner_view/src/validation.dart';

void main() {
  group('validateScanWindow', () {
    test('rejects inverted, out-of-range or degenerate rectangles', () {
      expect(
        () => validateScanWindow(const Rect.fromLTRB(0.7, 0.2, 0.3, 0.8)),
        throwsArgumentError,
      );
      expect(
        () => validateScanWindow(const Rect.fromLTRB(0, 0, 1.5, 1)),
        throwsArgumentError,
      );
      expect(
        () => validateScanWindow(const Rect.fromLTRB(0, -0.1, 1, 1)),
        throwsArgumentError,
      );
      expect(
        () => validateScanWindow(const Rect.fromLTRB(0.2, 0.2, 0.2, 0.8)),
        throwsArgumentError,
      );
    });

    test('accepts null and the full normalized rectangle', () {
      expect(() => validateScanWindow(null), returnsNormally);
      expect(
        () => validateScanWindow(const Rect.fromLTRB(0, 0, 1, 1)),
        returnsNormally,
      );
    });
  });

  group('validateFocusPoint', () {
    test('rejects out-of-range or NaN points', () {
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
    });

    test('accepts null and normalized points', () {
      expect(() => validateFocusPoint(null), returnsNormally);
      expect(() => validateFocusPoint(const Offset(0, 1)), returnsNormally);
      expect(() => validateFocusPoint(const Offset(0.5, 0.5)), returnsNormally);
    });
  });
}
