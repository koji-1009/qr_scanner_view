import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner_view/qr_scanner_view.dart';
import 'package:qr_scanner_view/src/wire.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kViewType);

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('analyzeImage', () {
    test('passes path and formats, parses results', () async {
      late MethodCall received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return [
          {
            'value': 'hello',
            'format': 'qr',
            'corners': [
              {'x': 0.25, 'y': 0.5},
            ],
          },
        ];
      });

      final barcodes = await QrScanner.analyzeImage(
        '/tmp/image.png',
        formats: {.qr, .ean13},
      );

      expect(received.method, 'analyzeImage');
      expect(received.arguments['path'], '/tmp/image.png');
      expect(received.arguments['formats'], unorderedEquals(['qr', 'ean13']));
      expect(barcodes, hasLength(1));
      expect(barcodes.single.value, 'hello');
      expect(barcodes.single.format, BarcodeFormat.qr);
      expect(barcodes.single.corners.single.dx, 0.25);
    });

    test('returns an empty list for a null result', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await QrScanner.analyzeImage('/tmp/none.png'), isEmpty);
    });

    test('propagates platform exceptions', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
          code: 'imageAnalysisFailed',
          message: 'bad file',
        );
      });
      expect(
        () => QrScanner.analyzeImage('/tmp/broken.png'),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('permission', () {
    test('parses every status and falls back to denied', () async {
      for (final status in CameraPermissionStatus.values) {
        messenger.setMockMethodCallHandler(
          channel,
          (call) async => status.name,
        );
        expect(await QrScanner.checkPermission(), status);
        expect(await QrScanner.requestPermission(), status);
      }
      messenger.setMockMethodCallHandler(channel, (call) async => 'bogus');
      expect(await QrScanner.checkPermission(), CameraPermissionStatus.denied);
    });

    test('openAppSettings returns the native bool', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'openAppSettings');
        return true;
      });
      expect(await QrScanner.openAppSettings(), isTrue);
    });
  });
}
