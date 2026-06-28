// Normalized-coordinate validation shared by the controller and widget. Not
// exported: these are internal guards, not public API.
import 'dart:ui' show Offset, Rect;

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
