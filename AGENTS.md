# AGENTS.md

Flutter plugin: live QR / barcode scanning via a native PlatformView.
Three layers that must stay in sync — Dart (`lib/`), Kotlin (`android/`),
Swift (`ios/`).

## Architecture invariants

- The wire contract (channel names, method names, map keys, enum string
  values) spans all three languages. `lib/src/wire.dart` owns the Dart side;
  `android/.../QrScannerView.kt` and `ios/.../QrScannerPlatformView.swift`
  mirror it. A change to any wire shape must be applied to all three layers.
- Channel names derive from one prefix: `kViewType` (`wire.dart`),
  `QrScannerViewPlugin.VIEW_TYPE` (Kotlin) and `QrScannerViewPlugin.viewType`
  (Swift). Build names from those constants, never as bare literals.
- Only decoded values cross the platform channel. Payload parsing
  (`ParsedValue`) is Dart-only so both platforms behave identically.
- The analyzer / metadata-delegate callbacks are per-frame hot paths; avoid
  adding allocations or channel traffic there.

## Commands

- Dart: `flutter analyze` / `flutter test`
- Android native tests (also compiles the plugin Kotlin):
  `cd example/android && ./gradlew :qr_scanner_view:testDebugUnitTest`
- iOS compile check:
  `cd example && flutter build ios --debug --simulator`
- CI runs the same set: `.github/workflows/ci.yml`

## Formatting

- Dart: `dart format .`
- Swift: `swift-format` default style (no config file), e.g.
  `xcrun swift-format format --in-place ios/qr_scanner_view/Sources/qr_scanner_view/*.swift`
- Kotlin: IntelliJ / Android Studio default Kotlin style

## Conventions

- Commits follow Conventional Commits 1.0.0
  (https://www.conventionalcommits.org/en/v1.0.0/).
- The version lives in `pubspec.yaml`, `android/build.gradle.kts` and
  `CHANGELOG.md`; keep them in agreement and do not bump unless instructed.
- `pubspec.lock` is not committed (library package).
- Comments: only what a maintainer needs — no fix narration, no spec
  references.
