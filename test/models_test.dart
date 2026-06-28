import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner_view/qr_scanner_view.dart';
import 'package:qr_scanner_view/src/wire.dart';

void main() {
  group('wire format parsing', () {
    test('resolves every enum name', () {
      for (final format in BarcodeFormat.values) {
        expect(formatFromWire(format.name), format);
      }
    });

    test('maps null and unknown codes to unknown', () {
      expect(formatFromWire(null), BarcodeFormat.unknown);
      expect(formatFromWire('nope'), BarcodeFormat.unknown);
      expect(formatFromWire(42), BarcodeFormat.unknown);
    });

    test('parses value, format and corners', () {
      final barcode = barcodeFromWire({
        'value': 'hello',
        'format': 'qr',
        'corners': [
          {'x': 0.1, 'y': 0.2},
          {'x': 0.9, 'y': 0.2},
          {'x': 0.9, 'y': 0.8},
          {'x': 0.1, 'y': 0.8},
        ],
      });
      expect(barcode.value, 'hello');
      expect(barcode.format, BarcodeFormat.qr);
      expect(barcode.corners, const [
        Offset(0.1, 0.2),
        Offset(0.9, 0.2),
        Offset(0.9, 0.8),
        Offset(0.1, 0.8),
      ]);
    });

    test('tolerates missing or malformed fields', () {
      final barcode = barcodeFromWire({
        'format': 'ean13',
        'corners': [
          {'x': 'bad', 'y': 0.2},
          'garbage',
          {'x': 0.5},
        ],
      });
      expect(barcode.value, '');
      expect(barcode.format, BarcodeFormat.ean13);
      expect(barcode.corners, isEmpty);
    });

    test('barcodesFromWire parses lists and rejects junk', () {
      final list = barcodesFromWire([
        {'value': 'a', 'format': 'qr'},
        'junk',
        {'value': 'b', 'format': 'ean8'},
      ]);
      expect(list.map((b) => b.value), ['a', 'b']);
      expect(barcodesFromWire(null), isEmpty);
      expect(barcodesFromWire('nope'), isEmpty);
    });
  });

  test('kAllFormats is every format except unknown', () {
    expect(
      kAllFormats,
      BarcodeFormat.values.where((f) => f != BarcodeFormat.unknown).toSet(),
    );
  });

  test('Barcode equality is by value', () {
    const a = Barcode(value: 'v', format: .qr);
    const b = Barcode(value: 'v', format: .qr);
    const c = Barcode(value: 'w', format: .qr);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });

  test('Barcode inequality includes corners', () {
    const a = Barcode(value: 'v', format: .qr, corners: [Offset(0, 0)]);
    const b = Barcode(value: 'v', format: .qr, corners: [Offset(1, 1)]);
    const c = Barcode(value: 'v', format: .qr);
    expect(a, isNot(b));
    expect(a, isNot(c));
  });

  test('corners list is unmodifiable', () {
    final barcode = barcodeFromWire({'value': 'v', 'format': 'qr'});
    expect(() => barcode.corners.add(Offset.zero), throwsUnsupportedError);
  });
}
