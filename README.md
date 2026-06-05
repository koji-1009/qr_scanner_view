# qr_scanner_view

Live camera QR / barcode scanner for Flutter (iOS 13+ / Android 7.0+).

The native side owns the camera, preview and detector (AVFoundation on iOS, CameraX + ML Kit on Android); only decoded values cross to Dart. The widget owns its controller, requests permission, starts the camera, pauses while the app is in the background and cleans everything up on removal.

## Quick start

```dart
import 'package:qr_scanner_view/qr_scanner_view.dart';

QrScannerView(onDetect: (barcode) => print(barcode.value))
```

### Setup

- **iOS**: add `NSCameraUsageDescription` to your app's `Info.plist` (the app crashes without it). Minimum iOS 13.0.
- **Android**: nothing — the camera permission is declared and requested by the plugin. Minimum SDK 24.

## Configuration

Initial behavior is declarative; runtime control goes through the controller.

```dart
QrScannerView(
  camera: const CameraOptions(lens: CameraLens.back, zoom: 0.2, torch: false),
  detection: const DetectionOptions(
    formats: {BarcodeFormat.qr},
    mode: DetectionMode.once,            // all / noDuplicates (default) / once
    scanWindow: Rect.fromLTRB(0.1, 0.3, 0.9, 0.7), // normalized 0..1
  ),
  fit: PreviewFit.cover,                 // or contain (letterboxed)
  tapToFocus: true,                      // tap the preview to focus there
  placeholderBuilder: (context) => const ColoredBox(color: Colors.black),
  errorBuilder: (context, state, error) => MyErrorPanel(state, error),
  overlayBuilder: (context, constraints) => const MyScanFrame(),
  onDetect: (barcode) => ...,
  onCreated: (controller) => _controller = controller,
)
```

`placeholderBuilder` covers the view while the camera is not streaming, `errorBuilder` covers it in the error and permission-denied states, and `overlayBuilder` is built on top of everything.

```dart
// Runtime control:
await controller.setTorch(true);
await controller.setZoom(0.5);                 // linear 0..1
await controller.setCamera(CameraLens.front);
await controller.setFocusPoint(Offset(0.5, 0.4)); // normalized; null resets
await controller.setFit(PreviewFit.contain);
await controller.setScanWindow(null);          // scan the whole preview
await controller.pause();                      // keep preview, stop detecting
await controller.resume();
final barcode = await controller.scanOnce(timeout: Duration(seconds: 30));
final capabilities = await controller.getCapabilities(); // hasTorch, lenses…
```

Streams: `controller.barcodes` (filtered by `DetectionMode`), `controller.frames` (all codes per camera frame), `controller.state` (+ `currentState`), `controller.errors` (machine-readable codes).

`DetectionOptions.formats` / `mode` / `timeout` are fixed at creation — change the widget `key` to apply new values (this recreates the camera session). Everything else can change on rebuild or through the controller.

## Still images & permission

```dart
final barcodes = await QrScanner.analyzeImage(file.path);

switch (await QrScanner.checkPermission()) {
  case CameraPermissionStatus.permanentlyDenied:
    await QrScanner.openAppSettings();
  default:
    await QrScanner.requestPermission();
}
```

## Typed values

`barcode.parsed` interprets `Barcode.value` as a Wi-Fi config, URL, email, phone, SMS, geo position, contact (MECARD / vCard), calendar event, ISBN, product code or plain text. Parsing is implemented in Dart on the decoded string, so the result is identical on both platforms and also applies to `QrScanner.analyzeImage` results.

```dart
switch (barcode.parsed) {
  case WifiValue(:final ssid, :final password, :final security):
    ...
  case UrlValue(:final url):
    ...
  case TextValue(:final text):
    ...
  // EmailValue, PhoneValue, SmsValue, GeoValue, ContactValue,
  // CalendarEventValue, IsbnValue, ProductValue
}
```

A payload that announces a type but fails to parse (e.g. `WIFI:` without an SSID) falls back to `TextValue`.

## Overlays

`Barcode.corners` are normalized (0..1, origin top-left) in the displayed preview's space on **both platforms** and under either `PreviewFit` — multiply by the widget's rendered size to draw a box over the code, e.g. from `overlayBuilder`. See `example/` for a working overlay, zoom slider and torch toggle.

## Android: keep the view's size stable

Two Android-specific rules for a smooth preview; neither applies to iOS:

- **Don't resize the view while scanning.** CameraX rebinds the whole camera whenever the preview's size changes — even by a pixel — blanking it for a few hundred ms. Give `QrScannerView` a layout-stable size: fix the height of surrounding panels (beware text metrics — fallback fonts for CJK or symbols change line heights) or overlay controls on top of the preview instead of laying them out next to it.
- **Keep an overlay painted.** Flutter creates the compositing surface for content above a platform view when something overlapping is first drawn, and destroys it when the overlap ends; each transition can flash. When drawing over the preview (corner outlines etc.), paint something constant — a reticle, a scrim — rather than only while a code is visible.

See `example/` for both rules applied.

## Platform notes

| | iOS | Android |
|---|---|---|
| Detection engine | AVFoundation metadata output (system) | ML Kit (unbundled by default, bundled opt-in below) |
| `analyzeImage` | Apple Vision (system) | ML Kit |
| `setZoom(0.0)` (widest) | the selected lens's widest | the device's widest — may engage the ultra-wide on logical multi-cameras |
| UPC-A | normalized from EAN-13 (leading 0) | native |
| codabar | live scan iOS 15.4+; `analyzeImage` iOS 15.0+ | supported |

By default Android resolves barcodes through Google Play services (unbundled ML Kit): nothing is added to your APK, but devices without Play services cannot scan and the first scan on a device may wait for the model download. To bundle the model into the app instead, add to your app's `android/gradle.properties`:

```properties
com.koji_1009.app.qr_scanner_view.useBundled=true
```

`ScannerErrorCode`: `lensNotFound`, `configurationFailed`, `unsupportedFormats`, `activityUnavailable`, `unknown`.
