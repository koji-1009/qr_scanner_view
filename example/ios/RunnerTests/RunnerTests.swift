import AVFoundation
import XCTest

@testable import qr_scanner_view

final class BarcodeWireTests: XCTestCase {

  // MARK: - requestedCodes

  func testEmptyRequestMeansAllCodes() {
    let all = ["qr", "ean13", "upcA"]
    XCTAssertEqual(BarcodeWire.requestedCodes([], allCodes: all), all)
  }

  func testUpcAFoldsEan13IntoTheRequest() {
    XCTAssertEqual(
      BarcodeWire.requestedCodes(["upcA"], allCodes: []),
      ["upcA", "ean13"]
    )
    XCTAssertEqual(
      BarcodeWire.requestedCodes(["upcA", "ean13"], allCodes: []),
      ["upcA", "ean13"]
    )
  }

  // MARK: - resolveEmission

  func testNonEan13PassesThrough() {
    let resolved = BarcodeWire.resolveEmission(
      type: "qr", value: "hello", requestedFormats: ["qr"])
    XCTAssertEqual(resolved?.format, "qr")
    XCTAssertEqual(resolved?.value, "hello")
  }

  func testUpcANormalizedFromEan13WithLeadingZero() {
    let resolved = BarcodeWire.resolveEmission(
      type: "ean13", value: "0123456789012", requestedFormats: ["upcA"])
    XCTAssertEqual(resolved?.format, "upcA")
    XCTAssertEqual(resolved?.value, "123456789012")
  }

  func testEan13KeptWhenRequested() {
    let resolved = BarcodeWire.resolveEmission(
      type: "ean13", value: "4901234567894", requestedFormats: ["ean13"])
    XCTAssertEqual(resolved?.format, "ean13")
    XCTAssertEqual(resolved?.value, "4901234567894")
  }

  func testUnrequestedEan13IsDropped() {
    // upcA was folded into the native request; a non-zero-prefixed ean13
    // result must not leak through.
    XCTAssertNil(
      BarcodeWire.resolveEmission(
        type: "ean13", value: "4901234567894", requestedFormats: ["upcA"]))
  }

  func testEmptyRequestPrefersUpcAForLeadingZero() {
    let resolved = BarcodeWire.resolveEmission(
      type: "ean13", value: "0123456789012", requestedFormats: [])
    XCTAssertEqual(resolved?.format, "upcA")
  }
}

final class QrScannerPlatformViewHelperTests: XCTestCase {

  // MARK: - Format mapping

  func testMetadataTypesMapsKnownFormats() {
    let types = QrScannerPlatformView.metadataTypes(for: ["qr", "ean13"])
    XCTAssertTrue(types.contains(.qr))
    XCTAssertTrue(types.contains(.ean13))
  }

  func testItfCoversInterleaved2of5() {
    let types = QrScannerPlatformView.metadataTypes(for: ["itf"])
    XCTAssertTrue(types.contains(.itf14))
    XCTAssertTrue(types.contains(.interleaved2of5))
  }

  func testUnknownFormatsResolveToNoTypes() {
    XCTAssertTrue(QrScannerPlatformView.metadataTypes(for: ["bogus"]).isEmpty)
  }

  func testCodeRoundTripAndUnknown() {
    XCTAssertEqual(QrScannerPlatformView.code(for: .qr), "qr")
    XCTAssertEqual(QrScannerPlatformView.code(for: .interleaved2of5), "itf")
    XCTAssertEqual(QrScannerPlatformView.code(for: .face), "unknown")
  }

  // MARK: - Scan window parsing

  func testScanWindowParsesNormalizedRect() {
    let window = QrScannerPlatformView.scanWindow(
      from: ["left": 0.1, "top": 0.2, "right": 0.9, "bottom": 0.8])
    XCTAssertNotNil(window)
    XCTAssertEqual(window!.minX, 0.1, accuracy: 1e-9)
    XCTAssertEqual(window!.minY, 0.2, accuracy: 1e-9)
    XCTAssertEqual(window!.width, 0.8, accuracy: 1e-9)
    XCTAssertEqual(window!.height, 0.6, accuracy: 1e-9)
  }

  func testScanWindowRejectsPartialMaps() {
    XCTAssertNil(QrScannerPlatformView.scanWindow(from: nil))
    XCTAssertNil(QrScannerPlatformView.scanWindow(from: ["left": 0.1]))
  }

  // MARK: - Preview fit

  func testGravityMapping() {
    XCTAssertEqual(QrScannerPlatformView.gravity(for: "contain"), .resizeAspect)
    XCTAssertEqual(QrScannerPlatformView.gravity(for: "cover"), .resizeAspectFill)
    XCTAssertEqual(QrScannerPlatformView.gravity(for: "bogus"), .resizeAspectFill)
  }
}
