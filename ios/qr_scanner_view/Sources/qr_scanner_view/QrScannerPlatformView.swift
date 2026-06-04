import AVFoundation
import Flutter
import UIKit

/// Hosts the capture preview layer and keeps it sized and oriented.
final class ScannerPreviewView: UIView {
  let previewLayer = AVCaptureVideoPreviewLayer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    previewLayer.videoGravity = .resizeAspectFill
    layer.addSublayer(previewLayer)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    previewLayer.frame = bounds
    if let connection = previewLayer.connection,
      connection.isVideoOrientationSupported
    {
      connection.videoOrientation = currentVideoOrientation()
    }
  }

  private func currentVideoOrientation() -> AVCaptureVideoOrientation {
    let orientation = window?.windowScene?.interfaceOrientation ?? .portrait
    switch orientation {
    case .landscapeLeft: return .landscapeLeft
    case .landscapeRight: return .landscapeRight
    case .portraitUpsideDown: return .portraitUpsideDown
    default: return .portrait
    }
  }
}

/// FlutterEventChannel retains its stream handler for the engine's lifetime;
/// this weak hop keeps the platform view deallocatable.
final class WeakStreamHandler: NSObject, FlutterStreamHandler {
  weak var delegate: QrScannerPlatformView?

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    return delegate?.onListen(withArguments: arguments, eventSink: events)
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    return delegate?.onCancel(withArguments: arguments)
  }
}

/// Scanner platform view backed by AVFoundation. Session work runs on a
/// dedicated serial queue; detection, state events and the event sink stay on
/// the main thread. The session pauses automatically while the app is in the
/// background.
final class QrScannerPlatformView: NSObject,
  FlutterPlatformView,
  AVCaptureMetadataOutputObjectsDelegate,
  FlutterStreamHandler
{

  private let preview = ScannerPreviewView()
  private let session = AVCaptureSession()
  private let metadataOutput = AVCaptureMetadataOutput()
  private let sessionQueue = DispatchQueue(label: "qr_scanner_view.session")

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let streamProxy = WeakStreamHandler()
  private var eventSink: FlutterEventSink?
  private var lastState: String?
  private var lastErrorEvent: [String: Any]?

  private let requestedFormats: [String]
  /// Mutated only on the session queue after init.
  private var requestedLens: String
  private var requestedZoom: Double
  private var scanWindow: CGRect?
  /// Normalized view-space focus point; main thread only after init.
  private var focusPoint: CGPoint?
  private var videoInput: AVCaptureDeviceInput?
  private var isConfigured = false
  private var torchEnabled = false

  /// Cross-thread flags (written on main, read on the session queue), all
  /// guarded by the one shared lock.
  private let stateLock = NSLock()
  private var unsafeWantsRunning = false
  private var unsafeIsPaused = false
  private var unsafeIsBackgrounded = false
  private var unsafeIsTornDown = false
  private func locked<T>(_ body: () -> T) -> T {
    stateLock.lock()
    defer { stateLock.unlock() }
    return body()
  }
  private var wantsRunning: Bool {
    get { locked { unsafeWantsRunning } }
    set { locked { unsafeWantsRunning = newValue } }
  }
  private var isPaused: Bool {
    get { locked { unsafeIsPaused } }
    set { locked { unsafeIsPaused = newValue } }
  }
  private var isBackgrounded: Bool {
    get { locked { unsafeIsBackgrounded } }
    set { locked { unsafeIsBackgrounded = newValue } }
  }
  private var isTornDown: Bool {
    get { locked { unsafeIsTornDown } }
    set { locked { unsafeIsTornDown = newValue } }
  }

  init(
    frame: CGRect,
    viewId: Int64,
    args: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    methodChannel = FlutterMethodChannel(
      name: "qr_scanner_view/scanner_\(viewId)",
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: "qr_scanner_view/scanner_\(viewId)/events",
      binaryMessenger: messenger
    )
    let params = args as? [String: Any] ?? [:]
    requestedFormats = (params["formats"] as? [String]) ?? []
    requestedLens = (params["camera"] as? String) ?? "auto"
    requestedZoom = (params["zoom"] as? Double) ?? 0.0
    torchEnabled = (params["torch"] as? Bool) ?? false
    scanWindow = QrScannerPlatformView.scanWindow(
      from: params["scanWindow"] as? [String: Any]
    )
    super.init()

    unsafeIsBackgrounded = UIApplication.shared.applicationState == .background

    preview.frame = frame
    preview.previewLayer.session = session
    preview.previewLayer.videoGravity =
      Self.gravity(for: (params["fit"] as? String) ?? "cover")

    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    streamProxy.delegate = self
    eventChannel.setStreamHandler(streamProxy)

    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(appDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(appWillEnterForeground),
      name: UIApplication.willEnterForegroundNotification,
      object: nil
    )
  }

  func view() -> UIView { preview }

  deinit {
    teardown()
  }

  /// Releases channels, the metadata delegate and the session. Called from
  /// the 'dispose' method call and from deinit; idempotent.
  private func teardown() {
    if isTornDown { return }
    isTornDown = true
    wantsRunning = false
    NotificationCenter.default.removeObserver(self)
    methodChannel.setMethodCallHandler(nil)
    eventChannel.setStreamHandler(nil)
    eventSink = nil
    metadataOutput.setMetadataObjectsDelegate(nil, queue: nil)
    let capturedSession = session
    sessionQueue.async {
      if capturedSession.isRunning {
        capturedSession.stopRunning()
      }
    }
  }

  // MARK: - App lifecycle

  @objc private func appDidEnterBackground() {
    isBackgrounded = true
    sessionQueue.async { [weak self] in
      guard let self = self, self.wantsRunning, self.session.isRunning else { return }
      self.session.stopRunning()
      // A paused scanner stays 'paused' through backgrounding.
      if !self.isPaused {
        self.emitState("ready")
      }
    }
  }

  @objc private func appWillEnterForeground() {
    isBackgrounded = false
    sessionQueue.async { [weak self] in
      guard let self = self, self.wantsRunning, self.isConfigured,
        !self.session.isRunning
      else { return }
      self.runSession()
    }
  }

  // MARK: - MethodChannel

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      start()
      result(nil)
    case "stop":
      stop()
      result(nil)
    case "pause":
      pause()
      result(nil)
    case "resume":
      resume()
      result(nil)
    case "setTorch":
      let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
      setTorch(on)
      result(nil)
    case "setCamera":
      let lens = (call.arguments as? [String: Any])?["lens"] as? String ?? "auto"
      setCamera(lens)
      result(nil)
    case "setZoom":
      let zoom = (call.arguments as? [String: Any])?["zoom"] as? Double ?? 0.0
      setZoom(zoom)
      result(nil)
    case "setScanWindow":
      setScanWindow(call.arguments as? [String: Any])
      result(nil)
    case "setFit":
      let fit = (call.arguments as? [String: Any])?["fit"] as? String ?? "cover"
      setFit(fit)
      result(nil)
    case "setFocusPoint":
      setFocusPoint(call.arguments as? [String: Any])
      result(nil)
    case "getCapabilities":
      getCapabilities(result)
    case "dispose":
      teardown()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - FlutterStreamHandler

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    // Late subscribers still need the current state; replay the full error
    // event so its code is not lost.
    if let last = lastState {
      if last == "error", let errorEvent = lastErrorEvent {
        events(errorEvent)
      } else {
        events(["type": "state", "state": last])
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: - Permission + start

  private func start() {
    wantsRunning = true
    isPaused = false
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureAndStart()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        if granted {
          self?.configureAndStart()
        } else {
          // iOS records the denial and never prompts again, matching
          // what checkPermission/requestPermission report.
          self?.wantsRunning = false
          self?.emitState("permissionPermanentlyDenied")
        }
      }
    default:
      // .denied / .restricted require a change in system Settings.
      wantsRunning = false
      emitState("permissionPermanentlyDenied")
    }
  }

  private func configureAndStart() {
    emitState("initializing")
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      guard self.wantsRunning else { return }
      if !self.isConfigured {
        if !self.configureSession() {
          return
        }
        self.isConfigured = true
      }
      guard self.wantsRunning else { return }
      self.emitState("ready")
      // While backgrounded the OS rejects capture; the foreground
      // observer resumes.
      guard !self.isBackgrounded else { return }
      self.runSession()
    }
  }

  /// Starts capture and applies detection settings. Runs on the session
  /// queue with the session configured.
  private func runSession() {
    if !session.isRunning {
      session.startRunning()
    }
    guard wantsRunning else {
      session.stopRunning()
      return
    }
    if isPaused {
      metadataOutput.metadataObjectTypes = []
      emitState("paused")
    } else {
      // availableMetadataObjectTypes is only reliable on a running session.
      applyMetadataTypes()
      applyScanWindow()
      emitScanningOrUnsupported()
    }
    applyTorch()
    applyZoom(requestedZoom)
    applyFocusPoint()
  }

  /// Builds input + metadata output, rolling back and emitting an error on
  /// failure. Runs on the session queue.
  private func configureSession() -> Bool {
    session.beginConfiguration()

    guard let device = device(for: requestedLens) else {
      session.commitConfiguration()
      emitError("lensNotFound", Self.lensNotFoundMessage(requestedLens))
      return false
    }
    guard let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    else {
      session.commitConfiguration()
      emitError("configurationFailed", "Could not add the camera input.")
      return false
    }
    session.addInput(input)
    videoInput = input

    guard session.canAddOutput(metadataOutput) else {
      session.removeInput(input)
      videoInput = nil
      session.commitConfiguration()
      emitError("configurationFailed", "Could not add the metadata output.")
      return false
    }
    session.addOutput(metadataOutput)
    metadataOutput.setMetadataObjectsDelegate(self, queue: .main)

    session.commitConfiguration()
    return true
  }

  private func applyMetadataTypes() {
    let wanted = Self.metadataTypes(for: requestedFormats)
    let available = metadataOutput.availableMetadataObjectTypes
    metadataOutput.metadataObjectTypes = wanted.filter { available.contains($0) }
  }

  /// Emits 'scanning', or the unsupportedFormats error when none of the
  /// requested formats is detectable. Runs on the session queue after
  /// applyMetadataTypes.
  private func emitScanningOrUnsupported() {
    if metadataOutput.metadataObjectTypes.isEmpty && !requestedFormats.isEmpty {
      emitError(
        "unsupportedFormats",
        "None of the requested formats are supported on this device.")
    } else {
      emitState("scanning")
    }
  }

  // MARK: - Scan window

  private func setScanWindow(_ args: [String: Any]?) {
    scanWindow = Self.scanWindow(from: args)
    applyScanWindow()
  }

  static func scanWindow(from args: [String: Any]?) -> CGRect? {
    guard let args = args,
      let left = args["left"] as? Double,
      let top = args["top"] as? Double,
      let right = args["right"] as? Double,
      let bottom = args["bottom"] as? Double
    else { return nil }
    return CGRect(x: left, y: top, width: right - left, height: bottom - top)
  }

  /// Converts the normalized view-space window into the metadata output's
  /// coordinate space. Layer access happens on main, the assignment on the
  /// session queue; safe to call from any thread.
  private func applyScanWindow() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let converted = self.convertedScanWindow()
      let output = self.metadataOutput
      self.sessionQueue.async {
        output.rectOfInterest = converted
      }
    }
  }

  /// Main thread only.
  private func convertedScanWindow() -> CGRect {
    let bounds = preview.bounds
    guard let window = scanWindow, bounds.width > 0, bounds.height > 0 else {
      return CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    let layerRect = CGRect(
      x: window.minX * bounds.width,
      y: window.minY * bounds.height,
      width: window.width * bounds.width,
      height: window.height * bounds.height
    )
    return preview.previewLayer.metadataOutputRectConverted(fromLayerRect: layerRect)
  }

  // MARK: - Preview fit

  static func gravity(for fit: String) -> AVLayerVideoGravity {
    return fit == "contain" ? .resizeAspect : .resizeAspectFill
  }

  private func setFit(_ fit: String) {
    DispatchQueue.main.async { [weak self] in
      self?.preview.previewLayer.videoGravity = Self.gravity(for: fit)
    }
    // The layer-to-output mapping changed with the gravity; queued behind
    // the gravity update on the main queue.
    applyScanWindow()
  }

  // MARK: - Focus point

  private func setFocusPoint(_ args: [String: Any]?) {
    if let x = args?["x"] as? Double, let y = args?["y"] as? Double {
      focusPoint = CGPoint(x: x, y: y)
    } else {
      focusPoint = nil
    }
    applyFocusPoint()
  }

  /// Converts the normalized view-space point on main and applies it on the
  /// session queue; nil restores continuous auto focus/exposure. A point set
  /// before the view has a size stays recorded and is applied by the next
  /// runSession/setCamera. Safe to call from any thread.
  private func applyFocusPoint() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let bounds = self.preview.bounds
      var devicePoint: CGPoint?
      if let point = self.focusPoint, bounds.width > 0, bounds.height > 0 {
        let layerPoint = CGPoint(
          x: point.x * bounds.width,
          y: point.y * bounds.height
        )
        devicePoint = self.preview.previewLayer
          .captureDevicePointConverted(fromLayerPoint: layerPoint)
      }
      let wantsReset = self.focusPoint == nil
      self.sessionQueue.async { [weak self] in
        guard let device = self?.videoInput?.device else { return }
        do {
          try device.lockForConfiguration()
          if let devicePoint = devicePoint {
            if device.isFocusPointOfInterestSupported {
              device.focusPointOfInterest = devicePoint
              if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
              }
            }
            if device.isExposurePointOfInterestSupported {
              device.exposurePointOfInterest = devicePoint
              if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
              }
            }
          } else if wantsReset {
            let center = CGPoint(x: 0.5, y: 0.5)
            if device.isFocusPointOfInterestSupported {
              device.focusPointOfInterest = center
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
              device.focusMode = .continuousAutoFocus
            }
            if device.isExposurePointOfInterestSupported {
              device.exposurePointOfInterest = center
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
              device.exposureMode = .continuousAutoExposure
            }
          }
          device.unlockForConfiguration()
        } catch {
          // Best-effort.
        }
      }
    }
  }

  // MARK: - Camera selection

  private static func lensNotFoundMessage(_ lens: String) -> String {
    "No camera available for lens '\(lens)'."
  }

  private func device(for lens: String) -> AVCaptureDevice? {
    func camera(
      _ type: AVCaptureDevice.DeviceType,
      _ position: AVCaptureDevice.Position
    ) -> AVCaptureDevice? {
      AVCaptureDevice.default(type, for: .video, position: position)
    }
    switch lens {
    case "back": return camera(.builtInWideAngleCamera, .back)
    case "front": return camera(.builtInWideAngleCamera, .front)
    default:
      return camera(.builtInWideAngleCamera, .back)
        ?? camera(.builtInWideAngleCamera, .front)
    }
  }

  private func setCamera(_ lens: String) {
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      // Recorded even when not running so a later configure uses it.
      self.requestedLens = lens
      guard self.isConfigured, self.wantsRunning else { return }
      guard let newDevice = self.device(for: lens) else {
        self.emitError("lensNotFound", Self.lensNotFoundMessage(lens))
        return
      }
      guard let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
        self.emitError("configurationFailed", "Could not open lens '\(lens)'.")
        return
      }
      self.session.beginConfiguration()
      if let current = self.videoInput {
        self.session.removeInput(current)
      }
      guard self.session.canAddInput(newInput) else {
        // Roll back so the previous lens keeps streaming and
        // videoInput keeps describing the session's actual input.
        if let current = self.videoInput {
          self.session.addInput(current)
        }
        self.session.commitConfiguration()
        self.emitError("configurationFailed", "Could not switch to lens '\(lens)'.")
        return
      }
      self.session.addInput(newInput)
      self.videoInput = newInput
      self.session.commitConfiguration()
      if !self.isPaused {
        self.applyMetadataTypes()
        self.applyScanWindow()
      }
      self.applyTorch()
      self.applyZoom(self.requestedZoom)
      self.applyFocusPoint()
    }
  }

  // MARK: - Stop / pause / torch / zoom

  private func stop() {
    wantsRunning = false
    // A stop before the session ever ran (configure still in flight) would
    // otherwise leave 'initializing' as the final state.
    if lastState == "initializing" {
      emitState("ready")
    }
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      if self.session.isRunning {
        self.session.stopRunning()
        self.emitState("ready")
      }
    }
  }

  private func pause() {
    isPaused = true
    sessionQueue.async { [weak self] in
      guard let self = self, self.session.isRunning else { return }
      self.metadataOutput.metadataObjectTypes = []
      self.emitState("paused")
    }
  }

  private func resume() {
    isPaused = false
    sessionQueue.async { [weak self] in
      guard let self = self, self.wantsRunning, self.session.isRunning else { return }
      self.applyMetadataTypes()
      self.applyScanWindow()
      self.emitScanningOrUnsupported()
    }
  }

  private func setTorch(_ on: Bool) {
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      self.torchEnabled = on
      self.applyTorch()
    }
  }

  /// Runs on the session queue.
  private func applyTorch() {
    guard let device = videoInput?.device, device.hasTorch else { return }
    do {
      try device.lockForConfiguration()
      device.torchMode = torchEnabled ? .on : .off
      device.unlockForConfiguration()
    } catch {
      // Best-effort.
    }
  }

  private func setZoom(_ zoom: Double) {
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      self.requestedZoom = zoom
      self.applyZoom(zoom)
    }
  }

  /// Maps linear zoom (0.0..1.0) across the device's supported range,
  /// linearly in crop width like CameraX's setLinearZoom so both platforms
  /// magnify alike. Runs on the session queue.
  private func applyZoom(_ zoom: Double) {
    guard let device = videoInput?.device else { return }
    let clamped = CGFloat(max(0.0, min(1.0, zoom)))
    let minZoom = device.minAvailableVideoZoomFactor
    let maxZoom = device.maxAvailableVideoZoomFactor
    let factor = 1.0 / ((1.0 - clamped) / minZoom + clamped / maxZoom)
    do {
      try device.lockForConfiguration()
      device.videoZoomFactor = factor
      device.unlockForConfiguration()
    } catch {
      // Best-effort.
    }
  }

  // MARK: - Capabilities

  private func getCapabilities(_ result: @escaping FlutterResult) {
    sessionQueue.async { [weak self] in
      var lenses: [String] = []
      var hasTorch = false
      var maxZoomRatio = 1.0
      if let self = self, !self.isTornDown {
        for lens in ["back", "front"]
        where self.device(for: lens) != nil {
          lenses.append(lens)
        }
        let device =
          self.videoInput?.device
          ?? self.device(for: self.requestedLens)
        hasTorch = device?.hasTorch ?? false
        maxZoomRatio = Double(device?.maxAvailableVideoZoomFactor ?? 1.0)
      }
      DispatchQueue.main.async {
        result([
          "hasTorch": hasTorch,
          "lenses": lenses,
          "maxZoomRatio": maxZoomRatio,
        ])
      }
    }
  }

  // MARK: - Detection (delegate on main)

  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    // Corners are emitted normalized to 0..1 in the preview's space.
    let bounds = preview.bounds
    var barcodes: [[String: Any]] = []
    for object in metadataObjects {
      guard let code = object as? AVMetadataMachineReadableCodeObject,
        let rawValue = code.stringValue
      else { continue }
      guard
        let (format, value) = BarcodeWire.resolveEmission(
          type: Self.code(for: code.type),
          value: rawValue,
          requestedFormats: requestedFormats
        )
      else {
        continue
      }

      var corners: [[String: Double]] = []
      if bounds.width > 0, bounds.height > 0,
        let transformed = preview.previewLayer
          .transformedMetadataObject(for: code)
          as? AVMetadataMachineReadableCodeObject
      {
        corners = transformed.corners.map {
          [
            "x": Double($0.x / bounds.width),
            "y": Double($0.y / bounds.height),
          ]
        }
      }
      barcodes.append([
        "value": value,
        "format": format,
        "corners": corners,
      ])
    }
    if barcodes.isEmpty { return }
    eventSink?(["type": "barcodes", "barcodes": barcodes])
  }

  // MARK: - Emit

  /// `lastState` and `eventSink` are only touched on the main thread.
  private func emitState(_ state: String) {
    DispatchQueue.main.async { [weak self] in
      self?.applyState(state)
    }
  }

  private func applyState(_ state: String) {
    if state == lastState { return }
    lastState = state
    eventSink?(["type": "state", "state": state])
  }

  private func emitError(_ code: String, _ message: String) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let event: [String: Any] = ["type": "error", "code": code, "message": message]
      self.lastState = "error"
      self.lastErrorEvent = event
      self.eventSink?(event)
    }
  }

  // MARK: - Format mapping

  /// Wire code to metadata type; the reverse map is derived from this.
  /// upcA has no iOS type (UPC-A arrives as ean13); codabar is iOS 15.4+.
  private static let typeMap: [String: AVMetadataObject.ObjectType] = {
    var map: [String: AVMetadataObject.ObjectType] = [
      "qr": .qr,
      "aztec": .aztec,
      "dataMatrix": .dataMatrix,
      "pdf417": .pdf417,
      "ean13": .ean13,
      "ean8": .ean8,
      "upcE": .upce,
      "code39": .code39,
      "code93": .code93,
      "code128": .code128,
      "itf": .itf14,
    ]
    if #available(iOS 15.4, *) {
      map["codabar"] = .codabar
    }
    return map
  }()

  private static let codeMap: [AVMetadataObject.ObjectType: String] = {
    var inverse: [AVMetadataObject.ObjectType: String] = [:]
    for (code, type) in typeMap { inverse[type] = code }
    // Second metadata type behind the itf wire code (see metadataTypes).
    inverse[.interleaved2of5] = "itf"
    return inverse
  }()

  static func metadataTypes(
    for formats: [String]
  ) -> [AVMetadataObject.ObjectType] {
    let codes = BarcodeWire.requestedCodes(formats, allCodes: Array(typeMap.keys))
    var types = codes.compactMap { typeMap[$0] }
    // itf covers both ITF-14 and generic interleaved 2 of 5.
    if codes.contains("itf"), !types.contains(.interleaved2of5) {
      types.append(.interleaved2of5)
    }
    return types
  }

  static func code(for type: AVMetadataObject.ObjectType) -> String {
    return codeMap[type] ?? "unknown"
  }
}
