import 'package:flutter/services.dart';

import 'models.dart';
import 'wire.dart';

/// Camera permission status, queryable without starting the camera.
enum CameraPermissionStatus {
  granted,

  /// Not asked yet. On Android this is also returned when a permanent denial
  /// cannot be distinguished before a request.
  notDetermined,

  /// Denied, but the OS may prompt again.
  denied,

  /// Denied and the OS will not prompt again; the user must change it in
  /// system Settings (see [QrScanner.openAppSettings]).
  permanentlyDenied,

  /// Blocked by device policy (e.g. parental controls); cannot be granted.
  /// Only reported on iOS; Android cannot distinguish this state.
  restricted,
}

final Map<String, CameraPermissionStatus> _permissionStatusByName =
    CameraPermissionStatus.values.asNameMap();

/// View-independent entry points: still-image analysis and camera permission.
abstract final class QrScanner {
  static const MethodChannel _channel = MethodChannel(kViewType);

  /// Scans a still image file at [path] for barcodes.
  ///
  /// Uses ML Kit on Android and Apple Vision on iOS. Returned
  /// [Barcode.corners] are normalized 0.0..1.0 in the EXIF-upright image's
  /// coordinate space (matching how `Image.file` renders it). Throws a
  /// [PlatformException] when the image cannot be read or analyzed, or with
  /// code `unsupportedFormats` when none of the requested [formats] is
  /// detectable on the device (e.g. [BarcodeFormat.codabar] needs iOS 15.0+).
  static Future<List<Barcode>> analyzeImage(
    String path, {
    Set<BarcodeFormat> formats = kAllFormats,
  }) async {
    final results = await _channel.invokeListMethod<dynamic>('analyzeImage', {
      'path': path,
      'formats': formatsToWire(formats),
    });
    return barcodesFromWire(results);
  }

  /// Returns the camera permission status without prompting.
  static Future<CameraPermissionStatus> checkPermission() async {
    final status = await _channel.invokeMethod<String>('checkPermission');
    return _permissionStatusByName[status] ?? .denied;
  }

  /// Prompts for camera permission when the OS still allows prompting, and
  /// returns the resulting status.
  ///
  /// On Android this throws a [PlatformException] when no foreground Activity
  /// is available or the Activity is detached mid-request (code
  /// `activityUnavailable`), or when another request is already in progress
  /// (code `requestInProgress`); iOS always returns a status.
  static Future<CameraPermissionStatus> requestPermission() async {
    final status = await _channel.invokeMethod<String>('requestPermission');
    return _permissionStatusByName[status] ?? .denied;
  }

  /// Opens the app's page in system Settings, for recovering from
  /// [CameraPermissionStatus.permanentlyDenied].
  static Future<bool> openAppSettings() async {
    return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
  }
}
