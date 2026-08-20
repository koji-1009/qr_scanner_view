import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner_view/qr_scanner_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The iOS path is exercised because UiKitView reaches the platform-views
  // channel directly; both platforms read the same creation-params map.
  late List<Map<Object?, Object?>> creationParams;

  setUp(() {
    creationParams = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
          if (call.method != 'create') return null;
          final args = call.arguments as Map<Object?, Object?>;
          final encoded = args['params'] as Uint8List;
          creationParams.add(
            const StandardMessageCodec().decodeMessage(
                  ByteData.view(
                    encoded.buffer,
                    encoded.offsetInBytes,
                    encoded.lengthInBytes,
                  ),
                )
                as Map<Object?, Object?>,
          );
          // The texture id UiKitView expects back from 'create'.
          return 0;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  /// The platform override has to be cleared inside the test body: the test
  /// framework verifies the foundation debug variables before tearDown runs.
  Future<void> pumpOnIos(
    WidgetTester tester,
    Future<void> Function(Future<void> Function(Widget view) pump) body,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body((view) async {
        await tester.pumpWidget(
          Directionality(textDirection: TextDirection.ltr, child: view),
        );
        await tester.pump();
      });
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('sends autoRequestPermission: true by default', (tester) async {
    await pumpOnIos(tester, (pump) async {
      await pump(const QrScannerView(autoStart: false));

      expect(creationParams, hasLength(1));
      expect(creationParams.single['autoRequestPermission'], isTrue);
    });
  });

  testWidgets('forwards autoRequestPermission: false to the view', (
    tester,
  ) async {
    await pumpOnIos(tester, (pump) async {
      await pump(
        const QrScannerView(autoStart: false, autoRequestPermission: false),
      );

      expect(creationParams, hasLength(1));
      expect(creationParams.single['autoRequestPermission'], isFalse);
    });
  });

  testWidgets('asserts when autoRequestPermission changes on rebuild', (
    tester,
  ) async {
    await pumpOnIos(tester, (pump) async {
      await pump(const QrScannerView(autoStart: false));
      await pump(
        const QrScannerView(autoStart: false, autoRequestPermission: false),
      );

      expect(tester.takeException(), isAssertionError);
    });
  });
}
