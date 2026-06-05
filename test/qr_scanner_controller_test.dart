import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner_view/qr_scanner_view.dart';
import 'package:qr_scanner_view/src/wire.dart' as wire;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const viewId = 7;
  final methodChannel = MethodChannel(wire.methodChannelName(viewId));
  final eventChannelName = wire.eventChannelName(viewId);
  const codec = StandardMethodCodec();

  late List<MethodCall> calls;
  dynamic capabilitiesResponse;

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    calls = [];
    capabilitiesResponse = null;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      if (call.method == 'getCapabilities') return capabilitiesResponse;
      return null;
    });
    messenger.setMockMethodCallHandler(
      MethodChannel(eventChannelName),
      (call) async => null,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockMethodCallHandler(MethodChannel(eventChannelName), null);
  });

  Future<void> pushEvent(Map<String, dynamic> event) async {
    await messenger.handlePlatformMessage(
      eventChannelName,
      codec.encodeSuccessEnvelope(event),
      (_) {},
    );
    // Let the event propagate through the stream to listeners.
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> pushFrame(List<Map<String, dynamic>> barcodes) =>
      pushEvent({'type': 'barcodes', 'barcodes': barcodes});

  Future<void> pushBarcode(String value, {String format = 'qr'}) => pushFrame([
    {'value': value, 'format': format},
  ]);

  group('method invocations', () {
    test('forwards lifecycle and option calls with their arguments', () async {
      final controller = QrScannerController(viewId);
      await controller.start();
      await controller.stop();
      await controller.pause();
      await controller.resume();
      await controller.setTorch(true);
      await controller.setCamera(.front);
      await controller.setZoom(2.0);
      await controller.setScanWindow(const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8));
      await controller.setScanWindow(null);

      expect(calls.map((c) => c.method).toList(), [
        'start',
        'stop',
        'pause',
        'resume',
        'setTorch',
        'setCamera',
        'setZoom',
        'setScanWindow',
        'setScanWindow',
      ]);
      expect(calls[4].arguments, {'on': true});
      expect(calls[5].arguments, {'lens': 'front'});
      expect(calls[6].arguments, {'zoom': 1.0}, reason: 'zoom is clamped');
      expect(calls[7].arguments, {
        'left': 0.1,
        'top': 0.2,
        'right': 0.9,
        'bottom': 0.8,
      });
      expect(calls[8].arguments, isNull);

      await controller.dispose();
    });

    test('tracks requested camera state', () async {
      final controller = QrScannerController(
        viewId,
        camera: const CameraOptions(torch: true, zoom: 0.5),
      );
      expect(controller.torchEnabled, isTrue);
      expect(controller.zoom, 0.5);
      expect(controller.lens, CameraLens.auto);

      await controller.setTorch(false);
      await controller.setZoom(0.25);
      await controller.setCamera(.front);
      expect(controller.torchEnabled, isFalse);
      expect(controller.zoom, 0.25);
      expect(controller.lens, CameraLens.front);

      await controller.dispose();
    });

    test('rejects invalid scanWindow and NaN zoom', () async {
      final controller = QrScannerController(viewId);
      expect(
        () => controller.setScanWindow(const Rect.fromLTRB(0.7, 0.2, 0.3, 0.8)),
        throwsArgumentError,
      );
      expect(
        () => controller.setScanWindow(const Rect.fromLTRB(-0.1, 0, 1, 1)),
        throwsArgumentError,
      );
      expect(() => controller.setZoom(double.nan), throwsArgumentError);
      await controller.dispose();
    });

    test('forwards setFit and setFocusPoint and tracks them', () async {
      final controller = QrScannerController(viewId);
      expect(controller.fit, PreviewFit.cover);
      expect(controller.focusPoint, isNull);

      await controller.setFit(.contain);
      await controller.setFocusPoint(const Offset(0.25, 0.75));
      await controller.setFocusPoint(null);

      expect(calls.map((c) => c.method).toList(), [
        'setFit',
        'setFocusPoint',
        'setFocusPoint',
      ]);
      expect(calls[0].arguments, {'fit': 'contain'});
      expect(calls[1].arguments, {'x': 0.25, 'y': 0.75});
      expect(calls[2].arguments, isNull);
      expect(controller.fit, PreviewFit.contain);
      expect(controller.focusPoint, isNull);

      await controller.dispose();
    });

    test('rejects a non-normalized focus point', () async {
      final controller = QrScannerController(viewId);
      expect(
        () => controller.setFocusPoint(const Offset(1.2, 0.5)),
        throwsArgumentError,
      );
      expect(
        () => controller.setFocusPoint(const Offset(0.5, -0.1)),
        throwsArgumentError,
      );
      expect(
        () => controller.setFocusPoint(const Offset(double.nan, 0.5)),
        throwsArgumentError,
      );
      await controller.dispose();
    });

    test('getCapabilities parses the native map', () async {
      capabilitiesResponse = {
        'hasTorch': true,
        'lenses': ['back', 'front', 'bogus'],
        'maxZoomRatio': 8.0,
      };
      final controller = QrScannerController(viewId);
      final capabilities = await controller.getCapabilities();
      expect(capabilities.hasTorch, isTrue);
      expect(capabilities.availableLenses, {CameraLens.back, CameraLens.front});
      expect(capabilities.maxZoomRatio, 8.0);
      await controller.dispose();
    });

    test('dispose invokes native dispose once and is idempotent', () async {
      final controller = QrScannerController(viewId);
      await controller.dispose();
      await controller.dispose();
      expect(calls.where((c) => c.method == 'dispose').length, 1);

      await controller.start();
      expect(
        calls.where((c) => c.method == 'start'),
        isEmpty,
        reason: 'calls after dispose are dropped',
      );
    });
  });

  group('events', () {
    test('state events update the stream and currentState', () async {
      final controller = QrScannerController(viewId);
      final states = <ScannerState>[];
      controller.state.listen(states.add);

      await pushEvent({'type': 'state', 'state': 'initializing'});
      await pushEvent({'type': 'state', 'state': 'paused'});
      await pushEvent({'type': 'state', 'state': 'bogus'});

      expect(states, [ScannerState.initializing, ScannerState.paused]);
      expect(controller.currentState, ScannerState.paused);

      await controller.dispose();
    });

    test('error events surface a coded error and an error state', () async {
      final controller = QrScannerController(viewId);
      final errors = <ScannerError>[];
      final states = <ScannerState>[];
      controller.errors.listen(errors.add);
      controller.state.listen(states.add);

      await pushEvent({
        'type': 'error',
        'code': 'lensNotFound',
        'message': 'no tele',
      });
      await pushEvent({'type': 'error', 'code': 'bogus'});

      expect(errors, hasLength(2));
      expect(errors[0], const ScannerError(.lensNotFound, 'no tele'));
      expect(errors[1].code, ScannerErrorCode.unknown);
      expect(states, [ScannerState.error, ScannerState.error]);
      expect(controller.currentState, ScannerState.error);

      await controller.dispose();
    });

    test('frames stream delivers the whole frame unfiltered', () async {
      final controller = QrScannerController(
        viewId,
        detection: const DetectionOptions(mode: .noDuplicates),
      );
      final frames = <List<Barcode>>[];
      controller.frames.listen(frames.add);

      await pushFrame([
        {'value': 'a', 'format': 'qr'},
        {'value': 'b', 'format': 'qr'},
      ]);
      await pushFrame([
        {'value': 'a', 'format': 'qr'},
        {'value': 'b', 'format': 'qr'},
      ]);

      expect(frames, hasLength(2));
      expect(frames[1].map((b) => b.value), ['a', 'b']);

      await controller.dispose();
    });
  });

  group('detection modes', () {
    test('all forwards consecutive duplicates', () async {
      final controller = QrScannerController(
        viewId,
        detection: const DetectionOptions(mode: .all),
      );
      final seen = <String>[];
      controller.barcodes.listen((b) => seen.add(b.value));

      await pushBarcode('a');
      await pushBarcode('a');
      await pushBarcode('b');

      expect(seen, ['a', 'a', 'b']);
      await controller.dispose();
    });

    test(
      'noDuplicates suppresses recently seen codes, even across flicker',
      () async {
        final controller = QrScannerController(
          viewId,
          detection: const DetectionOptions(mode: .noDuplicates),
        );
        final seen = <String>[];
        controller.barcodes.listen((b) => seen.add(b.value));

        await pushBarcode('a');
        await pushBarcode('a');
        await pushBarcode('b');
        await pushBarcode('a');

        expect(seen, [
          'a',
          'b',
        ], reason: 'a was seen moments ago; a one-frame dropout is flicker');
        await controller.dispose();
      },
    );

    test(
      'noDuplicates handles multiple codes per frame without thrash',
      () async {
        final controller = QrScannerController(
          viewId,
          detection: const DetectionOptions(mode: .noDuplicates),
        );
        final seen = <String>[];
        controller.barcodes.listen((b) => seen.add(b.value));

        final frame = [
          {'value': 'a', 'format': 'qr'},
          {'value': 'b', 'format': 'qr'},
        ];
        await pushFrame(frame);
        await pushFrame(frame);
        await pushFrame(frame);

        expect(seen, ['a', 'b']);
        await controller.dispose();
      },
    );

    test(
      'noDuplicates state survives stop/start (no re-count on resume)',
      () async {
        final controller = QrScannerController(
          viewId,
          detection: const DetectionOptions(mode: .noDuplicates),
        );
        final seen = <String>[];
        controller.barcodes.listen((b) => seen.add(b.value));

        await pushBarcode('a');
        await controller.stop();
        await controller.start();
        await pushBarcode('a');

        expect(seen, ['a'], reason: 'a is still in view across the resume');
        await controller.dispose();
      },
    );

    test('noDuplicates re-emits after timeout', () async {
      final controller = QrScannerController(
        viewId,
        detection: const DetectionOptions(
          mode: .noDuplicates,
          timeout: Duration(milliseconds: 20),
        ),
      );
      final seen = <String>[];
      controller.barcodes.listen((b) => seen.add(b.value));

      await pushBarcode('a');
      await pushBarcode('a');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await pushBarcode('a');

      expect(seen, ['a', 'a']);
      await controller.dispose();
    });

    test('noDuplicates treats a non-positive timeout as null', () async {
      final controller = QrScannerController(
        viewId,
        detection: const DetectionOptions(
          mode: .noDuplicates,
          timeout: Duration.zero,
        ),
      );
      final seen = <String>[];
      controller.barcodes.listen((b) => seen.add(b.value));

      await pushBarcode('a');
      await pushBarcode('a');

      expect(seen, ['a']);
      await controller.dispose();
    });

    test('scanWindow drops barcodes outside the window', () async {
      final controller = QrScannerController(
        viewId,
        detection: const DetectionOptions(
          scanWindow: Rect.fromLTRB(0, 0, 0.5, 0.5),
        ),
      );
      final seen = <String>[];
      controller.barcodes.listen((b) => seen.add(b.value));

      await pushFrame([
        {
          'value': 'in',
          'format': 'qr',
          'corners': [
            {'x': 0.2, 'y': 0.2},
            {'x': 0.3, 'y': 0.3},
          ],
        },
        {
          'value': 'out',
          'format': 'qr',
          'corners': [
            {'x': 0.8, 'y': 0.8},
            {'x': 0.9, 'y': 0.9},
          ],
        },
        {'value': 'noCorners', 'format': 'qr'},
      ]);

      expect(seen, [
        'in',
        'noCorners',
      ], reason: 'corner-less barcodes cannot be judged and pass through');
      await controller.dispose();
    });

    test('once picks the code nearest the preview center', () async {
      final controller = QrScannerController(
        viewId,
        detection: const DetectionOptions(mode: .once),
      );
      final seen = <String>[];
      controller.barcodes.listen((b) => seen.add(b.value));

      await pushFrame([
        {
          'value': 'edge',
          'format': 'qr',
          'corners': [
            {'x': 0.0, 'y': 0.0},
            {'x': 0.1, 'y': 0.1},
          ],
        },
        {
          'value': 'center',
          'format': 'qr',
          'corners': [
            {'x': 0.45, 'y': 0.45},
            {'x': 0.55, 'y': 0.55},
          ],
        },
      ]);

      expect(seen, [
        'center',
      ], reason: 'detector enumeration order must not decide the pick');
      await controller.dispose();
    });

    test('once picks the code nearest the scan-window center', () async {
      final controller = QrScannerController(
        viewId,
        detection: const DetectionOptions(
          mode: .once,
          scanWindow: Rect.fromLTRB(0.5, 0.0, 1.0, 1.0),
        ),
      );
      final seen = <String>[];
      controller.barcodes.listen((b) => seen.add(b.value));

      // Both inside the window (center 0.75, 0.5); the first is farther.
      await pushFrame([
        {
          'value': 'far',
          'format': 'qr',
          'corners': [
            {'x': 0.9, 'y': 0.45},
            {'x': 1.0, 'y': 0.55},
          ],
        },
        {
          'value': 'near',
          'format': 'qr',
          'corners': [
            {'x': 0.7, 'y': 0.45},
            {'x': 0.8, 'y': 0.55},
          ],
        },
      ]);

      expect(seen, ['near']);
      await controller.dispose();
    });

    test('once emits a single detection and stops the scanner', () async {
      final controller = QrScannerController(
        viewId,
        detection: const DetectionOptions(mode: .once),
      );
      final seen = <String>[];
      controller.barcodes.listen((b) => seen.add(b.value));

      await pushBarcode('a');
      await pushBarcode('b');
      await Future<void>.delayed(Duration.zero);

      expect(seen, ['a']);
      expect(calls.map((c) => c.method), contains('stop'));

      // start() re-arms the once mode.
      await controller.start();
      await pushBarcode('c');
      expect(seen, ['a', 'c']);

      await controller.dispose();
    });
  });

  group('scanOnce', () {
    test('picks the code nearest the preview center', () async {
      final controller = QrScannerController(viewId);
      final future = controller.scanOnce();
      await Future<void>.delayed(Duration.zero);

      await pushFrame([
        {
          'value': 'edge',
          'format': 'qr',
          'corners': [
            {'x': 0.0, 'y': 0.0},
            {'x': 0.1, 'y': 0.1},
          ],
        },
        {
          'value': 'center',
          'format': 'qr',
          'corners': [
            {'x': 0.45, 'y': 0.45},
            {'x': 0.55, 'y': 0.55},
          ],
        },
      ]);

      expect((await future)?.value, 'center');
      await controller.dispose();
    });

    test('starts, completes with the first detection, then stops', () async {
      final controller = QrScannerController(viewId);
      final future = controller.scanOnce();
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((c) => c.method), contains('start'));

      await pushBarcode('hello');
      final barcode = await future;
      expect(barcode?.value, 'hello');
      expect(calls.map((c) => c.method), contains('stop'));

      await controller.dispose();
    });

    test('returns null on timeout', () async {
      final controller = QrScannerController(viewId);
      final barcode = await controller.scanOnce(
        timeout: const Duration(milliseconds: 20),
      );
      expect(barcode, isNull);
      expect(calls.map((c) => c.method), contains('stop'));
      await controller.dispose();
    });
  });
}
