// Channel names and wire-format parsing. Not exported: the map shapes and
// format codes are internal contracts between the Dart and native layers.
import 'dart:collection' show UnmodifiableListView;
import 'dart:ui' show Offset, Rect;

import 'models.dart';

/// Plugin namespace: the plugin-level channel name, the registered platform
/// view type and the per-view channel prefix. Must match both native sides.
const String kViewType = 'qr_scanner_view';

String methodChannelName(int viewId) => '$kViewType/scanner_$viewId';

String eventChannelName(int viewId) => '$kViewType/scanner_$viewId/events';

final Map<String, BarcodeFormat> _formatByWireCode = BarcodeFormat.values
    .asNameMap();

BarcodeFormat formatFromWire(Object? code) =>
    (code is String ? _formatByWireCode[code] : null) ?? .unknown;

List<String> formatsToWire(Set<BarcodeFormat> formats) =>
    formats.map((f) => f.name).toList(growable: false);

Map<String, double> scanWindowToWire(Rect window) => <String, double>{
  'left': window.left,
  'top': window.top,
  'right': window.right,
  'bottom': window.bottom,
};

Barcode barcodeFromWire(Map<dynamic, dynamic> map) {
  final rawCorners = map['corners'];
  final corners = <Offset>[];
  if (rawCorners is List) {
    for (final point in rawCorners) {
      if (point is Map) {
        final x = point['x'];
        final y = point['y'];
        if (x is num && y is num) {
          corners.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }
  }
  return Barcode(
    value: map['value'] as String? ?? '',
    format: formatFromWire(map['format']),
    // A view, not a copy: this path runs per frame.
    corners: UnmodifiableListView(corners),
  );
}

List<Barcode> barcodesFromWire(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map<dynamic, dynamic>>()
      .map(barcodeFromWire)
      .toList(growable: false);
}
