import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:qr_scanner_view/qr_scanner_view.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'qr_scanner_view example',
      theme: ThemeData.dark(useMaterial3: true),
      home: const ScannerPage(),
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  QrScannerController? _controller;
  StreamSubscription<ScannerState>? _stateSub;
  StreamSubscription<List<Barcode>>? _framesSub;

  ScannerState _state = .initializing;
  Barcode? _lastBarcode;
  bool _torchOn = false;
  CameraLens _lens = .auto;
  PreviewFit _fit = .cover;

  // Per-frame corners feed the painter through a ValueNotifier so tracking
  // never rebuilds the page; the timer clears the outline once frames stop.
  final ValueNotifier<List<Barcode>> _visible = ValueNotifier(const []);
  Timer? _overlayClear;

  void _onDetect(Barcode barcode) {
    if (mounted) setState(() => _lastBarcode = barcode);
  }

  // The widget owns and disposes the controller; keep it for runtime control.
  void _onCreated(QrScannerController controller) {
    _controller = controller;
    _stateSub = controller.state.listen((state) {
      if (mounted) setState(() => _state = state);
    });
    _framesSub = controller.frames.listen((frame) {
      _visible.value = frame;
      _overlayClear?.cancel();
      _overlayClear = Timer(
        const Duration(milliseconds: 250),
        () => _visible.value = const [],
      );
    });
    // The zoom slider reads controller.zoom; show its initial value.
    if (mounted) setState(() {});
  }

  Future<void> _toggleTorch() async {
    final next = !_torchOn;
    await _controller?.setTorch(next);
    if (mounted) setState(() => _torchOn = next);
  }

  Future<void> _cycleLens() async {
    const order = CameraLens.values;
    final next = order[(_lens.index + 1) % order.length];
    await _controller?.setCamera(next);
    if (mounted) setState(() => _lens = next);
  }

  Future<void> _onZoom(double value) async {
    await _controller?.setZoom(value);
    if (mounted) setState(() {});
  }

  void _toggleFit() {
    setState(() {
      _fit = _fit == .cover ? .contain : .cover;
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _framesSub?.cancel();
    _overlayClear?.cancel();
    _visible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('qr_scanner_view')),
      body: Column(
        children: [
          Expanded(
            child: QrScannerView(
              onDetect: _onDetect,
              onCreated: _onCreated,
              fit: _fit,
              tapToFocus: true,
              placeholderBuilder: (context) => const ColoredBox(
                color: Colors.black,
                child: Center(child: CircularProgressIndicator()),
              ),
              errorBuilder: (context, state, error) => _Banner(switch (state) {
                .permissionDenied => 'Camera permission denied',
                .permissionPermanentlyDenied =>
                  'Camera permission denied — enable it in Settings',
                _ => 'Scanner error: ${error?.code.name ?? 'unknown'}',
              }),
              overlayBuilder: (context, constraints) =>
                  CustomPaint(painter: _CornerPainter(_visible)),
            ),
          ),
          _ControlPanel(
            state: _state,
            barcode: _lastBarcode,
            torchOn: _torchOn,
            lens: _lens,
            // The controller owns the value, so the slider matches the
            // initial CameraOptions.zoom and the clamped runtime value.
            zoom: _controller?.zoom ?? 0.0,
            fit: _fit,
            onToggleTorch: _toggleTorch,
            onCycleLens: _cycleLens,
            onZoom: _onZoom,
            onToggleFit: _toggleFit,
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}

/// One-line description of [Barcode.parsed] for the panel.
String describeParsed(ParsedValue value) => switch (value) {
  UrlValue(:final url) => 'URL → $url',
  WifiValue(:final ssid) => 'Wi-Fi → $ssid',
  EmailValue(:final address) => 'Email → $address',
  PhoneValue(:final number) => 'Phone → $number',
  SmsValue(:final number) => 'SMS → $number',
  GeoValue(:final latitude, :final longitude) => 'Geo → $latitude, $longitude',
  ContactValue(:final name) => 'Contact → ${name ?? '?'}',
  CalendarEventValue(:final summary) => 'Event → ${summary ?? '?'}',
  IsbnValue(:final isbn) => 'ISBN → $isbn',
  ProductValue(:final productCode) => 'Product → $productCode',
  TextValue() => 'Text',
};

/// Paints a constant reticle and outlines every visible barcode using the
/// normalized [Barcode.corners]. Repaints through the [frame] listenable,
/// without rebuilding any widget.
///
/// The reticle is not just decoration: it keeps Flutter compositing content
/// above the platform view at all times. On Android, overlay surfaces are
/// created the moment Flutter content first overlaps a platform view and
/// destroyed when it stops — each transition flashes the view black, so the
/// overlay must never be empty while the camera runs.
class _CornerPainter extends CustomPainter {
  _CornerPainter(this.frame) : super(repaint: frame);

  final ValueListenable<List<Barcode>> frame;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.6;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: size.center(Offset.zero),
          width: side,
          height: side,
        ),
        const Radius.circular(12),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white54,
    );
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.greenAccent;
    for (final barcode in frame.value) {
      final pts = barcode.corners;
      if (pts.length < 2) continue;
      final path = Path()
        ..addPolygon(
          pts
              .map((c) => Offset(c.dx * size.width, c.dy * size.height))
              .toList(growable: false),
          true,
        );
      canvas.drawPath(path, outline);
    }
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) => oldDelegate.frame != frame;
}

class _Banner extends StatelessWidget {
  const _Banner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        color: Colors.red.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.state,
    required this.barcode,
    required this.torchOn,
    required this.lens,
    required this.zoom,
    required this.fit,
    required this.onToggleTorch,
    required this.onCycleLens,
    required this.onZoom,
    required this.onToggleFit,
  });

  final ScannerState state;
  final Barcode? barcode;
  final bool torchOn;
  final CameraLens lens;
  final double zoom;
  final PreviewFit fit;
  final VoidCallback onToggleTorch;
  final VoidCallback onCycleLens;
  final ValueChanged<double> onZoom;
  final VoidCallback onToggleFit;

  @override
  Widget build(BuildContext context) {
    final b = barcode;
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fixed-height readouts: even a 1-2px line-height change (fallback
          // fonts for arrows/CJK in barcode payloads) resizes the preview
          // above, and CameraX rebinds the whole camera on any PreviewView
          // resize — blanking it for hundreds of ms.
          SizedBox(
            height: 20,
            child: Text('State: ${state.name}', maxLines: 1),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 20,
            child: Text(
              b == null
                  ? 'Last barcode: —'
                  : 'Last barcode: [${b.format.name}] ${b.value}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            height: 20,
            child: Text(
              b == null ? 'Parsed: —' : 'Parsed: ${describeParsed(b.parsed)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Row(
            children: [
              const Text('Zoom'),
              Expanded(
                child: Slider(value: zoom, onChanged: onZoom),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onToggleTorch,
                  icon: Icon(torchOn ? Icons.flash_on : Icons.flash_off),
                  label: Text(torchOn ? 'Torch on' : 'Torch off'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onCycleLens,
                  icon: const Icon(Icons.cameraswitch),
                  label: Text('Lens: ${lens.name}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onToggleFit,
            icon: const Icon(Icons.fit_screen),
            label: Text('Fit: ${fit.name}'),
          ),
        ],
      ),
    );
  }
}
