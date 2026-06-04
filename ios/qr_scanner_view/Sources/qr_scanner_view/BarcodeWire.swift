import Foundation

enum BarcodeWire {
  /// Wire codes to request from a detector. Neither AVFoundation nor Vision
  /// has a upcA type (UPC-A arrives as ean13), so asking for upcA folds
  /// ean13 into the request; an empty request means every supported code.
  static func requestedCodes(_ formats: [String], allCodes: [String]) -> [String] {
    var codes = formats.isEmpty ? allCodes : formats
    if codes.contains("upcA"), !codes.contains("ean13") {
      codes.append("ean13")
    }
    return codes
  }

  /// UPC-A arrives from AVFoundation/Vision as an ean13 with a leading zero;
  /// normalize it when the caller asked for upcA, and drop ean13 results the
  /// caller did not ask for. Returns nil when the result should be dropped.
  static func resolveEmission(
    type: String,
    value: String,
    requestedFormats: [String]
  ) -> (format: String, value: String)? {
    guard type == "ean13" else { return (type, value) }
    let wantsAll = requestedFormats.isEmpty
    let wantsUpcA = wantsAll || requestedFormats.contains("upcA")
    let wantsEan13 = wantsAll || requestedFormats.contains("ean13")
    if wantsUpcA, value.count == 13, value.hasPrefix("0") {
      return ("upcA", String(value.dropFirst()))
    }
    return wantsEan13 ? ("ean13", value) : nil
  }
}
