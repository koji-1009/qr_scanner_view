# Changelog

## 0.2.3

- iOS now re-converts the scan window's `rectOfInterest` whenever the preview's bounds or orientation change, so a rotation or resize no longer filters detections against the stale layout.
- An empty `formats` set now detects nothing: the preview streams without detection and `analyzeImage` resolves to an empty list (previously an empty set scanned every supported format).
- An Android `start()` issued while the camera-permission dialog is already on screen no longer fires a second OS request; the in-flight request's result drives both calls.

## 0.2.2

- Fixed a fatal `RejectedExecutionException` on Android when an ML Kit detection was still in flight while the scanner view was disposed.
- The disposed Android view is released right away instead of staying retained until the event stream's late `cancel` arrives.

## 0.2.1

- Fixed the `MissingPluginException` reported for the event channel's `cancel` after leaving the scanner screen: the channel registration now stays alive until the Dart-side cancel lands (Android and iOS).

## 0.2.0

- `analyzeImage` now reports `unsupportedFormats` when none of the requested formats is available on the device, instead of detecting every symbology.
- Requesting only `ean13` now yields UPC-A symbols as zero-prefixed ean13 results on Android too, matching iOS.
- `scanOnce` settles on the code nearest the scan-window / preview center, matching `DetectionMode.once`.
- `requestPermission` always resolves to a status on Android: no foreground Activity returns `notDetermined`, concurrent calls share one request, and a request survives Activity recreation.
- The Android camera no longer binds while the app is backgrounded when start resolves mid-initialization; scan-window frames wait for the first layout.
- iOS re-resolves the scanning / `unsupportedFormats` state after a lens switch and holds the metadata delegate weakly.
- Fixed vCard parsing dropping the property after a malformed quoted-printable trailing `=`.
- Non-positive `DetectionOptions.timeout` is treated as null; the widget ignores non-finite zoom in release builds.
- Documented codabar's iOS floors and the UPC-A / EAN-13 contract.

## 0.1.1

- Lowered the iOS minimum to 13.0 and raised the Android minimum SDK to 24, matching Flutter 3.44's supported platforms.
- `analyzeImage` now detects codabar from iOS 15.0 (previously gated at 15.4).
- Shortened the pubspec description so pub.dev displays it fully.

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
