import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'models.dart';
import 'options.dart';
import 'qr_scanner_controller.dart';
import 'wire.dart';

/// Live camera preview that scans QR codes and barcodes.
///
/// Works out of the box — the widget owns its [QrScannerController], starts
/// the camera when ready and disposes everything on removal:
///
/// ```dart
/// QrScannerView(onDetect: (barcode) => print(barcode.value))
/// ```
///
/// Initial behavior is configured declaratively with [camera] and
/// [detection]; rebuilding with different [CameraOptions] or a different
/// [DetectionOptions.scanWindow] applies the change to the running camera.
/// [DetectionOptions.formats], [DetectionOptions.mode] and
/// [DetectionOptions.timeout] are fixed at creation — change the widget [key]
/// to apply new values (this recreates the camera session). Runtime control
/// also goes through the controller received in [onCreated].
class QrScannerView extends StatefulWidget {
  const QrScannerView({
    super.key,
    this.onDetect,
    this.onCreated,
    this.camera = const CameraOptions(),
    this.detection = const DetectionOptions(),
    this.fit = .cover,
    this.autoStart = true,
    this.tapToFocus = false,
    this.placeholderBuilder,
    this.errorBuilder,
    this.overlayBuilder,
  });

  /// Called for every detection that passes [DetectionOptions.mode].
  final void Function(Barcode barcode)? onDetect;

  /// Called once with the controller bound to this view.
  final void Function(QrScannerController controller)? onCreated;

  /// Camera configuration; changes are applied on rebuild.
  final CameraOptions camera;

  /// Detection configuration; only [DetectionOptions.scanWindow] is applied on
  /// rebuild.
  final DetectionOptions detection;

  /// How the camera image is fitted into the view; changes are applied on
  /// rebuild.
  final PreviewFit fit;

  /// Whether to start scanning as soon as the view is ready.
  final bool autoStart;

  /// Whether a tap on the preview focuses the camera at the tapped point
  /// (see [QrScannerController.setFocusPoint]).
  final bool tapToFocus;

  /// Shown over the view while the camera is not streaming — before the
  /// first frame and after [QrScannerController.stop] — and no error or
  /// permission state is active.
  final Widget Function(BuildContext context)? placeholderBuilder;

  /// Shown over the view in [ScannerState.error] and the permission-denied
  /// states. `error` carries the [ScannerError] for [ScannerState.error] and
  /// is null for the permission states.
  final Widget Function(
    BuildContext context,
    ScannerState state,
    ScannerError? error,
  )?
  errorBuilder;

  /// Built above the preview (and above [placeholderBuilder] /
  /// [errorBuilder]) with the view's constraints, for scan-window frames and
  /// controls.
  final Widget Function(BuildContext context, BoxConstraints constraints)?
  overlayBuilder;

  @override
  State<QrScannerView> createState() => _QrScannerViewState();
}

class _QrScannerViewState extends State<QrScannerView> {
  QrScannerController? _controller;
  StreamSubscription<Barcode>? _detectSubscription;
  StreamSubscription<ScannerState>? _stateSubscription;
  StreamSubscription<ScannerError>? _errorSubscription;

  // Mirrors of the controller streams driving placeholderBuilder/errorBuilder.
  ScannerState? _viewState;
  ScannerError? _viewError;

  // What the platform view was created with; used to catch up on changes that
  // happened between creation and the controller becoming available. Captured
  // once in initState — the framework sends creation params only once, so a
  // rebuild must not move this baseline before the controller exists.
  late CameraOptions _sentCamera;
  Rect? _sentScanWindow;
  late PreviewFit _sentFit;

  @override
  void initState() {
    super.initState();
    validateScanWindow(widget.detection.scanWindow);
    _sentCamera = widget.camera;
    _sentScanWindow = widget.detection.scanWindow;
    _sentFit = widget.fit;
  }

  Map<String, dynamic> get _creationParams {
    final camera = _sentCamera;
    final scanWindow = _sentScanWindow;
    return <String, dynamic>{
      'formats': formatsToWire(widget.detection.formats),
      'camera': camera.lens.name,
      'zoom': camera.zoom,
      'torch': camera.torch,
      'fit': _sentFit.name,
      if (scanWindow != null) 'scanWindow': scanWindowToWire(scanWindow),
    };
  }

  void _onPlatformViewCreated(int id) {
    if (!mounted) return;
    final controller = QrScannerController(
      id,
      detection: widget.detection,
      camera: _sentCamera,
      fit: _sentFit,
    );
    _controller = controller;
    // The listener reads widget.onDetect at call time, so rebuilding with a
    // new closure needs no resubscription.
    _detectSubscription = controller.barcodes.listen(
      (barcode) => widget.onDetect?.call(barcode),
    );
    _stateSubscription = controller.state.listen((state) {
      if (mounted && state != _viewState) {
        setState(() => _viewState = state);
      }
    });
    _errorSubscription = controller.errors.listen((error) {
      if (mounted && error != _viewError) {
        setState(() => _viewError = error);
      }
    });
    widget.onCreated?.call(controller);
    // Catch up on option changes that raced platform-view creation.
    _applyOptionsDiff(controller, _sentCamera, _sentScanWindow, _sentFit);
    if (widget.autoStart) {
      controller.start().ignore();
    }
  }

  void _applyOptionsDiff(
    QrScannerController controller,
    CameraOptions oldCamera,
    Rect? oldScanWindow,
    PreviewFit oldFit,
  ) {
    final camera = widget.camera;
    if (camera.torch != oldCamera.torch) {
      controller.setTorch(camera.torch).ignore();
    }
    if (camera.lens != oldCamera.lens) {
      controller.setCamera(camera.lens).ignore();
    }
    if (camera.zoom != oldCamera.zoom) {
      controller.setZoom(camera.zoom).ignore();
    }
    if (widget.detection.scanWindow != oldScanWindow) {
      controller.setScanWindow(widget.detection.scanWindow).ignore();
    }
    if (widget.fit != oldFit) {
      controller.setFit(widget.fit).ignore();
    }
    _sentCamera = camera;
    _sentScanWindow = widget.detection.scanWindow;
    _sentFit = widget.fit;
  }

  @override
  void didUpdateWidget(QrScannerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    validateScanWindow(widget.detection.scanWindow);
    assert(
      setEquals(widget.detection.formats, oldWidget.detection.formats) &&
          widget.detection.mode == oldWidget.detection.mode &&
          widget.detection.timeout == oldWidget.detection.timeout,
      'DetectionOptions.formats/mode/timeout are fixed at creation; '
      'change the QrScannerView key to apply new values.',
    );
    final controller = _controller;
    if (controller == null) {
      // The platform view is not up yet; _onPlatformViewCreated catches up
      // from _sentCamera/_sentScanWindow/_sentFit.
      return;
    }
    _applyOptionsDiff(
      controller,
      oldWidget.camera,
      oldWidget.detection.scanWindow,
      oldWidget.fit,
    );
  }

  @override
  void dispose() {
    _detectSubscription?.cancel();
    _stateSubscription?.cancel();
    _errorSubscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _onTapToFocus(TapUpDetails details, BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    if (width <= 0 || height <= 0 || !width.isFinite || !height.isFinite) {
      return;
    }
    final point = Offset(
      (details.localPosition.dx / width).clamp(0.0, 1.0),
      (details.localPosition.dy / height).clamp(0.0, 1.0),
    );
    _controller?.setFocusPoint(point).ignore();
  }

  bool get _showsPlaceholder => switch (_viewState) {
    null || .initializing || .ready => true,
    _ => false,
  };

  bool get _showsError => switch (_viewState) {
    .error || .permissionDenied || .permissionPermanentlyDenied => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final Widget view = switch (defaultTargetPlatform) {
      .iOS => UiKitView(
        viewType: kViewType,
        creationParams: _creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
      .android => _buildAndroid(context),
      _ => const SizedBox.shrink(),
    };
    if (!widget.tapToFocus &&
        widget.placeholderBuilder == null &&
        widget.errorBuilder == null &&
        widget.overlayBuilder == null) {
      return view;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Error UI sits above the focus gesture so its controls stay tappable;
        // the overlay is topmost like a caller-side Stack would put it.
        return Stack(
          fit: StackFit.expand,
          children: [
            view,
            if (widget.tapToFocus)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _onTapToFocus(details, constraints),
              ),
            if (widget.placeholderBuilder != null && _showsPlaceholder)
              widget.placeholderBuilder!(context),
            if (widget.errorBuilder != null && _showsError)
              widget.errorBuilder!(
                context,
                _viewState!,
                _viewState == .error ? _viewError : null,
              ),
            if (widget.overlayBuilder != null)
              widget.overlayBuilder!(context, constraints),
          ],
        );
      },
    );
  }

  Widget _buildAndroid(BuildContext context) {
    final layoutDirection =
        Directionality.maybeOf(context) ?? TextDirection.ltr;
    return PlatformViewLink(
      viewType: kViewType,
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initSurfaceAndroidView(
          id: params.id,
          viewType: kViewType,
          layoutDirection: layoutDirection,
          creationParams: _creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        );
        controller
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..addOnPlatformViewCreatedListener(_onPlatformViewCreated)
          ..create();
        return controller;
      },
    );
  }
}
