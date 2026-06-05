import AVFoundation
import Flutter
import UIKit
import Vision

/// Registers the platform view factory and the plugin-level channel used for
/// still-image analysis and camera permission.
public class QrScannerViewPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let factory = QrScannerViewFactory(messenger: registrar.messenger())
    registrar.register(factory, withId: "qr_scanner_view")

    let channel = FlutterMethodChannel(
      name: "qr_scanner_view",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(QrScannerViewPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "analyzeImage":
      let args = call.arguments as? [String: Any]
      guard let path = args?["path"] as? String else {
        result(
          FlutterError(
            code: "imageAnalysisFailed",
            message: "Missing image path.",
            details: nil
          ))
        return
      }
      let formats = (args?["formats"] as? [String]) ?? []
      Self.analyzeImage(path: path, formats: formats, result: result)
    case "checkPermission":
      result(Self.permissionStatus())
    case "requestPermission":
      Self.requestPermission(result)
    case "openAppSettings":
      Self.openAppSettings(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Permission

  private static func permissionStatus() -> String {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: return "granted"
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    // iOS never re-prompts after a denial.
    default: return "permanentlyDenied"
    }
  }

  private static func requestPermission(_ result: @escaping FlutterResult) {
    guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else {
      result(permissionStatus())
      return
    }
    AVCaptureDevice.requestAccess(for: .video) { _ in
      DispatchQueue.main.async {
        result(permissionStatus())
      }
    }
  }

  private static func openAppSettings(_ result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString),
      UIApplication.shared.canOpenURL(url)
    else {
      result(false)
      return
    }
    UIApplication.shared.open(url) { opened in
      result(opened)
    }
  }

  // MARK: - Still-image analysis (Apple Vision)

  private static func analyzeImage(
    path: String,
    formats: [String],
    result: @escaping FlutterResult
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let url = URL(fileURLWithPath: path)
      let request = VNDetectBarcodesRequest()
      let symbologies = Self.symbologies(for: formats)
      if !symbologies.isEmpty {
        request.symbologies = symbologies
      }

      let handler = VNImageRequestHandler(url: url, options: [:])
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "imageAnalysisFailed",
              message: error.localizedDescription,
              details: nil
            ))
        }
        return
      }

      let observations = request.results ?? []
      let barcodes = observations.compactMap { observation in
        Self.barcodeMap(for: observation, formats: formats)
      }
      DispatchQueue.main.async {
        result(barcodes)
      }
    }
  }

  private static func barcodeMap(
    for observation: VNBarcodeObservation,
    formats: [String]
  ) -> [String: Any]? {
    guard let rawValue = observation.payloadStringValue else { return nil }
    guard
      let (format, value) = BarcodeWire.resolveEmission(
        type: code(for: observation.symbology),
        value: rawValue,
        requestedFormats: formats
      )
    else { return nil }

    // Vision points are normalized with a lower-left origin; flip to the
    // top-left origin used by the rest of the plugin.
    let corners = [
      observation.topLeft,
      observation.topRight,
      observation.bottomRight,
      observation.bottomLeft,
    ].map { point in
      ["x": Double(point.x), "y": Double(1.0 - point.y)]
    }

    return [
      "value": value,
      "format": format,
      "corners": corners,
    ]
  }

  /// codabar is iOS 15.0+ in Vision (the live path's AVFoundation type is 15.4+).
  private static let symbologyMap: [String: [VNBarcodeSymbology]] = {
    var map: [String: [VNBarcodeSymbology]] = [
      "qr": [.qr],
      "aztec": [.aztec],
      "dataMatrix": [.dataMatrix],
      "pdf417": [.pdf417],
      "ean13": [.ean13],
      "ean8": [.ean8],
      "upcE": [.upce],
      "code39": [.code39],
      "code93": [.code93],
      "code128": [.code128],
      "itf": [.itf14, .i2of5],
    ]
    if #available(iOS 15.0, *) {
      map["codabar"] = [.codabar]
    }
    return map
  }()

  private static func symbologies(for formats: [String]) -> [VNBarcodeSymbology] {
    let codes = BarcodeWire.requestedCodes(formats, allCodes: Array(symbologyMap.keys))
    return codes.flatMap { symbologyMap[$0] ?? [] }
  }

  private static func code(for symbology: VNBarcodeSymbology) -> String {
    for (code, symbologies) in symbologyMap where symbologies.contains(symbology) {
      return code
    }
    return "unknown"
  }
}

/// Builds a `QrScannerPlatformView` per platform view id and decodes
/// creationParams with the standard message codec.
class QrScannerViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    return QrScannerPlatformView(
      frame: frame,
      viewId: viewId,
      args: args,
      messenger: messenger
    )
  }
}
