# Changelog

## 0.1.0

Initial release.

- Live QR / barcode scanning via a native PlatformView (AVFoundation on iOS 15+, CameraX + ML Kit on Android 5.0+).
- Out-of-the-box widget: owns its controller, auto-starts, auto-disposes and pauses while the app is in the background.
- Declarative `CameraOptions` / `DetectionOptions` plus runtime control: torch, linear zoom, lens switching, scan window, focus point, pause/resume, `scanOnce`, capabilities query.
- Preview fit (`cover` / `contain`), applied natively; coordinates stay normalized under either fit.
- Tap-to-focus (`tapToFocus`) and `placeholderBuilder` / `errorBuilder` / `overlayBuilder` on the widget.
- Detection modes: `all`, `noDuplicates` (the default; frame-aware, survives resume) and `once` (picks the code nearest the scan-window center).
- Normalized cross-platform corner coordinates; UPC-A normalization on iOS.
- Structured states and errors, current-state snapshot, per-frame stream.
- Still-image analysis (`QrScanner.analyzeImage`) and camera permission API (`checkPermission` / `requestPermission` / `openAppSettings`).
- Android ML Kit flavor switch: unbundled (Google Play services) by default; opt into the bundled model with `com.koji_1009.app.qr_scanner_view.useBundled=true` in `gradle.properties`.
- Typed value parsing (`barcode.parsed`): Wi-Fi, URL, email, phone, SMS, geo, contact (MECARD / vCard), calendar event, ISBN, product and text — implemented in Dart so both platforms parse identically.
