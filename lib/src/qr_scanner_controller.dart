import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/services.dart';

import 'models.dart';
import 'options.dart';
import 'wire.dart';

/// Lifecycle / permission state of a scanner.
///
/// [permissionDenied] means the request was declined but may be re-prompted;
/// [permissionPermanentlyDenied] means the OS will no longer prompt and the
/// user must change the setting in system Settings. [paused] means the
/// preview is live but detection is suspended (see
/// `QrScannerController.pause`).
enum ScannerState {
  initializing,
  ready,
  scanning,
  paused,
  permissionDenied,
  permissionPermanentlyDenied,
  error,
}

/// Machine-readable reason accompanying [ScannerState.error].
enum ScannerErrorCode {
  lensNotFound,
  configurationFailed,
  unsupportedFormats,
  activityUnavailable,
  unknown,
}

/// An error surfaced by the native scanner.
@immutable
class ScannerError {
  const ScannerError(this.code, [this.message]);

  final ScannerErrorCode code;
  final String? message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScannerError && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() =>
      'ScannerError(${code.name}${message == null ? '' : ', $message'})';
}

/// What the current device's camera supports.
class ScannerCapabilities {
  const ScannerCapabilities({
    this.hasTorch = false,
    this.availableLenses = const {},
    this.maxZoomRatio = 1.0,
  });

  /// Whether the active camera has a torch.
  final bool hasTorch;

  /// Lenses that can be selected on this device.
  final Set<CameraLens> availableLenses;

  /// The camera's maximum zoom ratio (informational;
  /// [QrScannerController.setZoom] stays linear 0.0..1.0 across the supported
  /// range).
  final double maxZoomRatio;
}

final Map<String, ScannerState> _scannerStateByName = ScannerState.values
    .asNameMap();
final Map<String, ScannerErrorCode> _errorCodeByName = ScannerErrorCode.values
    .asNameMap();
final Map<String, CameraLens> _lensByName = CameraLens.values.asNameMap();

/// Controls a single `QrScannerView`, identified by its platform view id.
///
/// Created and disposed by `QrScannerView`; access it through
/// `QrScannerView.onCreated` for torch, zoom and camera control. Setters
/// issued before scanning starts are buffered natively and applied when the
/// camera comes up.
class QrScannerController {
  QrScannerController(
    this.viewId, {
    this.detection = const DetectionOptions(),
    CameraOptions camera = const CameraOptions(),
    this._fit = .cover,
  }) : _torchEnabled = camera.torch,
       _zoom = camera.zoom,
       _lens = camera.lens,
       _scanWindow = detection.scanWindow,
       _methodChannel = MethodChannel(methodChannelName(viewId)),
       _eventChannel = EventChannel(eventChannelName(viewId)) {
    validateScanWindow(detection.scanWindow);
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _onEvent,
      onError: _onChannelError,
    );
  }

  /// Platform view id this controller is bound to.
  final int viewId;

  /// Detection behavior; [DetectionOptions.mode] and [DetectionOptions.timeout]
  /// are applied here before events reach [barcodes].
  final DetectionOptions detection;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  late final StreamSubscription<dynamic> _eventSubscription;

  final StreamController<Barcode> _barcodes =
      StreamController<Barcode>.broadcast();
  final StreamController<List<Barcode>> _frames =
      StreamController<List<Barcode>>.broadcast();
  final StreamController<ScannerState> _state =
      StreamController<ScannerState>.broadcast();
  final StreamController<ScannerError> _errors =
      StreamController<ScannerError>.broadcast();

  bool _disposed = false;
  ScannerState? _lastState;
  bool _torchEnabled;
  double _zoom;
  CameraLens _lens;
  Rect? _scanWindow;
  PreviewFit _fit;
  Offset? _focusPoint;

  // Duplicate suppression state, on a monotonic clock (wall-clock changes must
  // not freeze the timeout). Deliberately NOT reset by start()/stop(), so
  // pausing and resuming does not re-count a code still in view.
  final Stopwatch _clock = Stopwatch()..start();
  final Map<(BarcodeFormat, String), Duration> _lastSeenAt = {};
  final Map<(BarcodeFormat, String), Duration> _lastEmitAt = {};
  bool _onceFired = false;

  /// How long a code must stay out of view before [DetectionMode.noDuplicates]
  /// treats its return as a new detection, when no
  /// [DetectionOptions.timeout] is configured.
  static const Duration _reappearFallback = Duration(seconds: 1);

  /// Detections, filtered according to [DetectionOptions.mode].
  Stream<Barcode> get barcodes => _barcodes.stream;

  /// All barcodes detected in a single camera frame, unfiltered by
  /// [DetectionOptions.mode] (the scan window still applies).
  Stream<List<Barcode>> get frames => _frames.stream;

  /// Lifecycle / permission transitions. A broadcast stream does not replay,
  /// so read [currentState] for the value at subscription time.
  Stream<ScannerState> get state => _state.stream;

  /// Errors with a machine-readable [ScannerErrorCode]. Every error is also
  /// reflected on [state] as [ScannerState.error].
  Stream<ScannerError> get errors => _errors.stream;

  /// The most recently observed [ScannerState], or null before the first one.
  ScannerState? get currentState => _lastState;

  /// The most recently requested torch state. The native side re-applies it
  /// across lens switches when the new lens has a torch.
  bool get torchEnabled => _torchEnabled;

  /// The most recently requested linear zoom.
  double get zoom => _zoom;

  /// The most recently requested lens.
  CameraLens get lens => _lens;

  /// The most recently requested preview fit.
  PreviewFit get fit => _fit;

  /// The most recently requested focus point, or null for continuous
  /// auto focus.
  Offset? get focusPoint => _focusPoint;

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    switch (event['type']) {
      case 'barcodes':
        // Skip deserialization for frames nothing can observe.
        if (_disposed) return;
        if (detection.mode == .once && _onceFired && !_frames.hasListener) {
          return;
        }
        _handleFrame(barcodesFromWire(event['barcodes']));
      case 'state':
        final s = _scannerStateByName[event['state']];
        if (s != null) {
          _lastState = s;
          _addIfOpen(_state, s);
        }
      case 'error':
        final code = _errorCodeByName[event['code']] ?? .unknown;
        _emitError(ScannerError(code, event['message'] as String?));
    }
  }

  void _handleFrame(List<Barcode> frame) {
    if (frame.isEmpty || _disposed) return;
    final visible = _filterByScanWindow(frame);
    if (visible.isEmpty) return;
    if (!_frames.isClosed && _frames.hasListener) _frames.add(visible);
    if (_barcodes.isClosed) return;
    switch (detection.mode) {
      case .all:
        visible.forEach(_barcodes.add);
      case .noDuplicates:
        _emitNoDuplicates(visible);
      case .once:
        if (_onceFired) return;
        _onceFired = true;
        _barcodes.add(_selectOnceTarget(visible));
        stop().ignore();
    }
  }

  /// Emits the codes in [visible] that just (re)entered view or whose
  /// [DetectionOptions.timeout] elapsed; the caller has checked [_barcodes]
  /// is open.
  void _emitNoDuplicates(List<Barcode> visible) {
    final now = _clock.elapsed;
    // A non-positive timeout cannot suppress anything (DetectionMode.all is
    // the emit-every-frame mode), so treat it as null.
    final raw = detection.timeout;
    final timeout = raw != null && raw > Duration.zero ? raw : null;
    final reappear = timeout ?? _reappearFallback;
    for (final barcode in visible) {
      final key = (barcode.format, barcode.value);
      final lastSeen = _lastSeenAt[key];
      final lastEmit = _lastEmitAt[key];
      final wasAway = lastSeen == null || now - lastSeen >= reappear;
      final timedOut =
          timeout != null && lastEmit != null && now - lastEmit >= timeout;
      if (lastEmit == null || wasAway || timedOut) {
        _lastEmitAt[key] = now;
        _barcodes.add(barcode);
      }
      _lastSeenAt[key] = now;
    }
    // An entry past the reappear window no longer affects emission (the next
    // sighting re-emits either way), so drop it to keep the maps bounded over
    // long sessions. Pruning is memory hygiene only; skip the sweeps while
    // this frame just refreshed every entry.
    if (_lastSeenAt.length > visible.length) {
      _lastSeenAt.removeWhere((_, seen) => now - seen >= reappear);
      _lastEmitAt.removeWhere((key, _) => !_lastSeenAt.containsKey(key));
    }
  }

  /// Drops barcodes whose centroid lies outside the active scan window.
  /// Belt-and-suspenders over the native filtering: covers frames already in
  /// flight while a window change crosses the channel, and on iOS the gap
  /// before rectOfInterest takes effect.
  List<Barcode> _filterByScanWindow(List<Barcode> frame) {
    final window = _scanWindow;
    if (window == null) return frame;
    return frame
        .where((barcode) {
          final centroid = _centroid(barcode.corners);
          return centroid == null || window.contains(centroid);
        })
        .toList(growable: false);
  }

  /// The code a [DetectionMode.once] emission settles on: corner centroid
  /// nearest the scan-window (or preview) center. Detector enumeration order
  /// differs per platform, so the pick must not rely on it; corner-less codes
  /// are considered only when no code carries corners.
  Barcode _selectOnceTarget(List<Barcode> visible) {
    final center = _scanWindow?.center ?? const Offset(0.5, 0.5);
    Barcode? nearest;
    var nearestDistance = double.infinity;
    for (final barcode in visible) {
      final centroid = _centroid(barcode.corners);
      if (centroid == null) continue;
      final distance = (centroid - center).distanceSquared;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = barcode;
      }
    }
    return nearest ?? visible.first;
  }

  static Offset? _centroid(List<Offset> corners) {
    if (corners.isEmpty) return null;
    var x = 0.0;
    var y = 0.0;
    for (final corner in corners) {
      x += corner.dx;
      y += corner.dy;
    }
    return Offset(x / corners.length, y / corners.length);
  }

  void _onChannelError(Object error, StackTrace stackTrace) {
    _emitError(ScannerError(.unknown, '$error'));
  }

  void _emitError(ScannerError error) {
    _addIfOpen(_errors, error);
    _lastState = .error;
    _addIfOpen(_state, ScannerState.error);
  }

  /// Events can race [dispose] (a native reply already in flight when the
  /// subscription is cancelled), so every late add goes through this guard.
  void _addIfOpen<T>(StreamController<T> controller, T event) {
    if (!controller.isClosed) controller.add(event);
  }

  /// Starts detection, triggering the runtime permission request when needed.
  ///
  /// The returned future completes when the request is acknowledged, not when
  /// the camera runs; observe [state]/[errors] for the outcome. Re-arms
  /// [DetectionMode.once] and discards a [pause] issued before this call;
  /// duplicate-suppression state is kept.
  Future<void> start() {
    _onceFired = false;
    return _invoke('start');
  }

  /// Stops the capture session. Resources are retained.
  Future<void> stop() => _invoke('stop');

  /// Suspends detection while keeping the preview live and the camera warm.
  /// A pause issued before [start] is discarded by [start].
  Future<void> pause() => _invoke('pause');

  /// Resumes detection after [pause].
  Future<void> resume() => _invoke('resume');

  /// Starts (if needed) and completes with the next detection, then stops.
  ///
  /// When several codes are visible in the first frame, settles on the one
  /// nearest the scan-window (or preview) center, like [DetectionMode.once].
  /// Returns null when [timeout] elapses or the controller is disposed first.
  Future<Barcode?> scanOnce({Duration? timeout}) async {
    // Subscribe before starting so a detection arriving while start() is in
    // flight is not lost; ignore() silences the abandoned future on timeout.
    final first = frames.first;
    first.ignore();
    try {
      await start();
      final frame = await (timeout == null ? first : first.timeout(timeout));
      return _selectOnceTarget(frame);
    } on TimeoutException {
      return null;
    } on StateError {
      return null;
    } finally {
      await stop();
    }
  }

  /// Turns the torch on or off.
  Future<void> setTorch(bool on) {
    _torchEnabled = on;
    return _invoke('setTorch', {'on': on});
  }

  /// Switches the active camera at runtime.
  Future<void> setCamera(CameraLens lens) {
    _lens = lens;
    return _invoke('setCamera', {'lens': lens.name});
  }

  /// Sets the linear zoom, 0.0 (widest) to 1.0 (max). Values are clamped.
  Future<void> setZoom(double zoom) {
    if (zoom.isNaN) {
      throw ArgumentError.value(zoom, 'zoom', 'must not be NaN');
    }
    _zoom = zoom.clamp(0.0, 1.0);
    return _invoke('setZoom', {'zoom': _zoom});
  }

  /// Changes how the camera image is fitted into the view.
  Future<void> setFit(PreviewFit fit) {
    _fit = fit;
    return _invoke('setFit', {'fit': fit.name});
  }

  /// Focuses (and meters exposure) at [point], expressed in the same
  /// normalized 0.0..1.0 preview coordinates as [Barcode.corners]. The point
  /// stays in effect — and is re-applied across camera switches — until reset
  /// with null, which restores continuous auto focus. Best-effort: ignored by
  /// cameras without focus support. Throws [ArgumentError] for a
  /// non-normalized point.
  Future<void> setFocusPoint(Offset? point) {
    validateFocusPoint(point);
    _focusPoint = point;
    return _invoke(
      'setFocusPoint',
      point == null ? null : {'x': point.dx, 'y': point.dy},
    );
  }

  /// Restricts detection to [window], expressed in the same normalized
  /// 0.0..1.0 preview coordinates as [Barcode.corners]. Pass null to scan the
  /// whole preview again. Throws [ArgumentError] for a non-normalized or
  /// inverted rectangle.
  Future<void> setScanWindow(Rect? window) {
    validateScanWindow(window);
    _scanWindow = window;
    return _invoke(
      'setScanWindow',
      window == null ? null : scanWindowToWire(window),
    );
  }

  /// Queries what the device's camera supports. Returns an empty
  /// [ScannerCapabilities] once this controller is disposed.
  Future<ScannerCapabilities> getCapabilities() async {
    if (_disposed) return const ScannerCapabilities();
    final map = await _methodChannel.invokeMapMethod<dynamic, dynamic>(
      'getCapabilities',
    );
    if (_disposed || map == null) return const ScannerCapabilities();
    final lenses =
        (map['lenses'] as List?)
            ?.whereType<String>()
            .map((name) => _lensByName[name])
            .whereType<CameraLens>()
            .toSet() ??
        const <CameraLens>{};
    return ScannerCapabilities(
      hasTorch: map['hasTorch'] as bool? ?? false,
      availableLenses: lenses,
      maxZoomRatio: (map['maxZoomRatio'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Future<void> _invoke(String method, [dynamic arguments]) {
    if (_disposed) return Future<void>.value();
    return _methodChannel.invokeMethod<void>(method, arguments);
  }

  /// Releases this controller. Called by `QrScannerView`; idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _methodChannel.invokeMethod<void>('dispose');
    } catch (_) {
      // The platform view may already be gone; teardown still proceeds.
    }
    await _eventSubscription.cancel();
    await _barcodes.close();
    await _frames.close();
    await _state.close();
    await _errors.close();
  }
}
