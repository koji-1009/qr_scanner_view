package com.koji_1009.app.qr_scanner_view

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Point
import android.graphics.PointF
import android.graphics.RectF
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.Looper
import android.view.View
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.mlkit.vision.MlKitAnalyzer
import androidx.camera.view.CameraController
import androidx.camera.view.CameraController.COORDINATE_SYSTEM_VIEW_REFERENCED
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.ProcessLifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.platform.PlatformView
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/**
 * Scanner platform view backed by CameraX and ML Kit. Detection results arrive
 * in [PreviewView] coordinates via [MlKitAnalyzer]; only decoded values cross
 * to Dart. The camera streams while the owned lifecycle is RESUMED and pauses
 * automatically while the app is in the background.
 */
class QrScannerView(
    context: Context,
    private val applicationContext: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    creationParams: Map<String, Any?>,
    private val activityBindingProvider: () -> ActivityPluginBinding?,
    private val onDisposed: (QrScannerView) -> Unit = {},
) : PlatformView,
    LifecycleOwner,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private val previewView = PreviewView(context)
    private val cameraController = LifecycleCameraController(applicationContext)

    private val methodChannel =
        MethodChannel(messenger, "${QrScannerViewPlugin.VIEW_TYPE}/scanner_$viewId")
    private val eventChannel =
        EventChannel(messenger, "${QrScannerViewPlugin.VIEW_TYPE}/scanner_$viewId/events")
    private val streamHandler = DisposeAwareStreamHandler(eventChannel, this)
    private var eventSink: EventChannel.EventSink? = null
    private var lastState: String? = null
    private var lastErrorEvent: Map<String, Any?>? = null

    private val lifecycleRegistry = LifecycleRegistry(this)
    override val lifecycle: Lifecycle get() = lifecycleRegistry

    private val mainExecutor = ContextCompat.getMainExecutor(applicationContext)

    /** Single thread owning ML Kit inference; shut down by [dispose].
     * [MlKitAnalyzer] and the GMS Tasks library post detection callbacks here
     * from their own threads without guarding rejection, so DiscardPolicy:
     * a callback landing after the shutdown must be dropped, not thrown. */
    private val analysisExecutor = ThreadPoolExecutor(
        1, 1, 0L, TimeUnit.MILLISECONDS,
        LinkedBlockingQueue(),
        ThreadPoolExecutor.DiscardPolicy(),
    )

    private val scanner: BarcodeScanner
    private val analyzer: MlKitAnalyzer

    /** Formats were requested but none resolve on this platform; mirrors the
     * iOS `unsupportedFormats` error instead of silently scanning everything. */
    private val formatsUnsupported: Boolean

    /** An empty request asks for no formats: the preview streams without any
     * inference and no `unsupportedFormats` error. */
    private val formatsEmpty: Boolean

    /** Wire codes from creationParams; read per frame by [onAnalysisResult]
     * for the upcA/ean13 emission folding. */
    private val requestedFormats: List<String>

    private var requestedLens: String =
        (creationParams["camera"] as? String) ?: "auto"
    private var requestedZoom: Float =
        ((creationParams["zoom"] as? Double) ?: 0.0).toFloat().coerceIn(0f, 1f)
    private var torchEnabled: Boolean =
        (creationParams["torch"] as? Boolean) ?: false

    // Written on the main thread, read by onAnalysisResult on the analysis
    // thread.
    @Volatile private var scanWindow: RectF? = null

    /** [PreviewView] size cached on the main thread for the analysis thread;
     * a View must not be measured off the main thread. */
    @Volatile private var viewWidth = 0

    @Volatile private var viewHeight = 0

    /** Normalized view-space focus point; null means continuous auto focus. */
    private var focusPoint: PointF? = null

    /** Whether the user asked for scanning; used to resume after backgrounding. */
    private var desiredScanning = false

    /** Detection suspended while the preview stays live. */
    @Volatile private var isPaused = false
    private var isDisposed = false

    /** The binding the permission listener is registered on; moved to the new
     * binding by [onActivityBindingChanged] across activity recreation. */
    private var permissionBinding: ActivityPluginBinding? = null

    /** True from the permission request until its result arrives; keeps the
     * pending state across binding swaps while the dialog is showing. */
    private var awaitingPermissionResult = false

    /** Unique per view so concurrent views receive only their own results. */
    private val permissionRequestCode = (BASE_PERMISSION_REQUEST_CODE + viewId) and 0xFFFF

    private val appLifecycleObserver = LifecycleEventObserver { _, event ->
        when (event) {
            Lifecycle.Event.ON_STOP -> {
                isBackgrounded = true
                if (desiredScanning &&
                    lifecycleRegistry.currentState.isAtLeast(Lifecycle.State.STARTED)
                ) {
                    lifecycleRegistry.currentState = Lifecycle.State.CREATED
                    if (!isPaused) emitState("ready")
                }
            }

            Lifecycle.Event.ON_START -> {
                isBackgrounded = false
                if (desiredScanning &&
                    lifecycleRegistry.currentState == Lifecycle.State.CREATED
                ) {
                    lifecycleRegistry.currentState = Lifecycle.State.RESUMED
                    applyCameraOptions()
                    emitStreamingState()
                }
            }

            else -> Unit
        }
    }

    /** Main-thread mirror of the process lifecycle, consulted by
     * [configureAndRun] so a bind resolving in the background stays at
     * CREATED until the ON_START handler resumes it. */
    private var isBackgrounded = false

    init {
        @Suppress("UNCHECKED_CAST")
        val formats = (creationParams["formats"] as? List<String>) ?: emptyList()
        requestedFormats = formats
        scanner = BarcodeScanning.getClient(BarcodeFormats.scannerOptions(formats))
        formatsUnsupported = BarcodeFormats.noneSupported(formats)
        formatsEmpty = formats.isEmpty()

        scanWindow = scanWindowFromMap(creationParams["scanWindow"] as? Map<*, *>)

        // TextureView keeps Flutter's texture-layer composition; the default
        // SurfaceView would force the hybrid-composition fallback, merging the
        // UI and raster threads and janking every Dart rebuild.
        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        previewView.scaleType =
            scaleTypeFor((creationParams["fit"] as? String) ?: "cover")
        previewView.controller = cameraController
        previewView.addOnLayoutChangeListener { _, left, top, right, bottom, _, _, _, _ ->
            viewWidth = right - left
            viewHeight = bottom - top
        }
        // Focus and zoom go through the Dart API only, keeping gesture
        // behavior and controller-tracked state consistent with iOS.
        cameraController.isTapToFocusEnabled = false
        cameraController.isPinchToZoomEnabled = false
        cameraController.setEnabledUseCases(CameraController.IMAGE_ANALYSIS)
        analyzer = MlKitAnalyzer(
            listOf(scanner),
            COORDINATE_SYSTEM_VIEW_REFERENCED,
            // Results are consumed on the analysis thread, keeping the
            // per-frame filtering and wire-map work off the UI thread;
            // emit() and the auto-zoom update hop back to main themselves.
            analysisExecutor,
        ) { result -> onAnalysisResult(result) }
        attachAnalyzer()
        cameraController.bindToLifecycle(this)

        methodChannel.setMethodCallHandler(this)
        streamHandler.attach()

        lifecycleRegistry.currentState = Lifecycle.State.CREATED
        val processLifecycle = ProcessLifecycleOwner.get().lifecycle
        isBackgrounded = !processLifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)
        processLifecycle.addObserver(appLifecycleObserver)
    }

    override fun getView(): View = previewView

    override fun dispose() {
        if (isDisposed) return
        isDisposed = true
        desiredScanning = false
        onDisposed(this)
        ProcessLifecycleOwner.get().lifecycle.removeObserver(appLifecycleObserver)
        unregisterPermissionListener()
        methodChannel.setMethodCallHandler(null)
        streamHandler.dispose()
        eventSink = null
        cameraController.clearImageAnalysisAnalyzer()
        previewView.controller = null
        lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
        // Closing on the analysis thread orders it after any in-flight frame.
        analysisExecutor.execute { scanner.close() }
        analysisExecutor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                isPaused = false
                attachAnalyzer()
                ensurePermissionThenStart()
                result.success(null)
            }

            "stop" -> {
                desiredScanning = false
                val wasStreaming =
                    lifecycleRegistry.currentState.isAtLeast(Lifecycle.State.STARTED)
                lifecycleRegistry.currentState = Lifecycle.State.CREATED
                // A stop during startup would otherwise leave 'initializing'
                // as the final state.
                if (wasStreaming || lastState == "initializing") emitState("ready")
                result.success(null)
            }

            "pause" -> {
                isPaused = true
                // Detach the analyzer so no inference runs while paused.
                cameraController.clearImageAnalysisAnalyzer()
                if (lifecycleRegistry.currentState.isAtLeast(Lifecycle.State.STARTED)) {
                    emitState("paused")
                }
                result.success(null)
            }

            "resume" -> {
                isPaused = false
                attachAnalyzer()
                if (desiredScanning &&
                    lifecycleRegistry.currentState.isAtLeast(Lifecycle.State.STARTED)
                ) {
                    emitStreamingState()
                }
                result.success(null)
            }

            "setTorch" -> {
                torchEnabled = call.argument<Boolean>("on") ?: false
                cameraController.enableTorch(torchEnabled)
                result.success(null)
            }

            "setCamera" -> {
                requestedLens = call.argument<String>("lens") ?: "auto"
                reconfigureCamera()
                result.success(null)
            }

            "setZoom" -> {
                requestedZoom = (call.argument<Double>("zoom") ?: 0.0)
                    .toFloat().coerceIn(0f, 1f)
                runCatching { cameraController.setLinearZoom(requestedZoom) }
                result.success(null)
            }

            "setScanWindow" -> {
                scanWindow = scanWindowFromMap(call.arguments as? Map<*, *>)
                result.success(null)
            }

            "setFit" -> {
                previewView.scaleType =
                    scaleTypeFor(call.argument<String>("fit") ?: "cover")
                result.success(null)
            }

            "setFocusPoint" -> {
                val x = call.argument<Double>("x")
                val y = call.argument<Double>("y")
                focusPoint =
                    if (x != null && y != null) PointF(x.toFloat(), y.toFloat()) else null
                applyFocusPoint()
                result.success(null)
            }

            "getCapabilities" -> getCapabilities(result)
            "dispose" -> {
                desiredScanning = false
                lifecycleRegistry.currentState = Lifecycle.State.CREATED
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        // Late subscribers still need the current state; replay the full error
        // event so its code is not lost.
        val state = lastState ?: return
        val errorReplay = if (state == "error") lastErrorEvent else null
        emit(errorReplay ?: mapOf("type" to "state", "state" to state))
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun ensurePermissionThenStart() {
        val activity = activityBindingProvider()?.activity
        if (activity == null) {
            emitError("activityUnavailable", "No foreground Activity is available.")
            return
        }
        val granted = ContextCompat.checkSelfPermission(
            activity, Manifest.permission.CAMERA,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            startCamera()
            return
        }
        if (!registerPermissionListener()) {
            emitError("activityUnavailable", "No foreground Activity is available.")
            return
        }
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.CAMERA),
            permissionRequestCode,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != permissionRequestCode) return false
        unregisterPermissionListener()
        val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            startCamera()
        } else {
            val permanentlyDenied =
                CameraPermission.isPermanentlyDenied(activityBindingProvider()?.activity)
            emitState(if (permanentlyDenied) "permissionPermanentlyDenied" else "permissionDenied")
        }
        return true
    }

    private fun registerPermissionListener(): Boolean {
        val binding = activityBindingProvider() ?: return false
        if (permissionBinding !== binding) {
            permissionBinding?.removeRequestPermissionsResultListener(this)
            binding.addRequestPermissionsResultListener(this)
            permissionBinding = binding
        }
        awaitingPermissionResult = true
        return true
    }

    private fun unregisterPermissionListener() {
        awaitingPermissionResult = false
        permissionBinding?.removeRequestPermissionsResultListener(this)
        permissionBinding = null
    }

    /** Moves a pending permission registration onto the new binding so the
     * result of a request spanning an activity recreation still arrives. */
    internal fun onActivityBindingChanged(binding: ActivityPluginBinding?) {
        if (binding === permissionBinding) return
        permissionBinding?.removeRequestPermissionsResultListener(this)
        permissionBinding = null
        if (awaitingPermissionResult && binding != null) {
            binding.addRequestPermissionsResultListener(this)
            permissionBinding = binding
        }
    }

    private fun startCamera() {
        emitState("initializing")
        desiredScanning = true
        val future = cameraController.initializationFuture
        future.addListener({
            try {
                configureAndRun()
            } catch (e: Exception) {
                desiredScanning = false
                emitError("configurationFailed", e.message)
            }
        }, mainExecutor)
    }

    private fun configureAndRun() {
        if (isDisposed || !desiredScanning) return
        val selector = resolveSelector(requestedLens)
        if (selector == null) {
            // Without the reset, the next foreground would resume into
            // 'scanning' over a camera that never bound.
            desiredScanning = false
            emitError("lensNotFound", lensNotFoundMessage())
            return
        }
        cameraController.cameraSelector = selector
        emitState("ready")
        // Backgrounded while initializing: stay at CREATED; the ON_START
        // handler resumes the bind on foreground.
        if (isBackgrounded) return
        lifecycleRegistry.currentState = Lifecycle.State.RESUMED
        applyCameraOptions()
        emitStreamingState()
    }

    private fun reconfigureCamera() {
        if (!cameraController.initializationFuture.isDone) return
        val selector = resolveSelector(requestedLens)
        if (selector == null) {
            emitError("lensNotFound", lensNotFoundMessage())
            return
        }
        cameraController.cameraSelector = selector
        applyCameraOptions()
        if (lifecycleRegistry.currentState.isAtLeast(Lifecycle.State.STARTED)) {
            emitStreamingState()
        }
    }

    /** Re-applies torch, zoom and focus point; a rebind resets them to
     * defaults. */
    private fun applyCameraOptions() {
        runCatching { cameraController.enableTorch(torchEnabled) }
        runCatching { cameraController.setLinearZoom(requestedZoom) }
        applyFocusPoint()
    }

    private fun scaleTypeFor(fit: String): PreviewView.ScaleType =
        if (fit == "contain") {
            PreviewView.ScaleType.FIT_CENTER
        } else {
            PreviewView.ScaleType.FILL_CENTER
        }

    /** Best-effort: focuses and meters at the stored view-space point, pinned
     * until reset with null. Requires a bound camera and a laid-out view; a
     * point set earlier is applied by the next [applyCameraOptions]. */
    private fun applyFocusPoint() {
        val control = cameraController.cameraControl ?: return
        val point = focusPoint
        if (point == null) {
            runCatching { control.cancelFocusAndMetering() }
            return
        }
        val w = previewView.width
        val h = previewView.height
        if (w == 0 || h == 0) return
        val meteringPoint =
            previewView.meteringPointFactory.createPoint(point.x * w, point.y * h)
        val action = FocusMeteringAction.Builder(meteringPoint)
            .disableAutoCancel()
            .build()
        runCatching { control.startFocusAndMetering(action) }
    }

    private fun lensNotFoundMessage() =
        "No camera available for lens '$requestedLens'."

    /** Lens preference order; the single source [resolveSelector] (binding)
     * and [resolveCharacteristics] (capabilities) both follow. */
    private fun lensPreference(lens: String): List<String> = when (lens) {
        "back" -> listOf("back")
        "front" -> listOf("front")
        else -> listOf("back", "front")
    }

    private fun resolveSelector(lens: String): CameraSelector? = try {
        lensPreference(lens).firstNotNullOfOrNull { facing ->
            val selector = if (facing == "back") {
                CameraSelector.DEFAULT_BACK_CAMERA
            } else {
                CameraSelector.DEFAULT_FRONT_CAMERA
            }
            selector.takeIf { cameraController.hasCamera(it) }
        }
    } catch (e: Exception) {
        null
    }

    private fun getCapabilities(result: MethodChannel.Result) {
        val future = cameraController.initializationFuture
        future.addListener({
            val lenses = mutableListOf<String>()
            var hasTorch = false
            var maxZoomRatio = 1.0
            if (!isDisposed) {
                runCatching {
                    if (cameraController.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)) {
                        lenses.add("back")
                    }
                    if (cameraController.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)) {
                        lenses.add("front")
                    }
                }
                // cameraInfo is null until the camera binds; fall back to the
                // static Camera2 characteristics so early queries (autoStart:
                // false, or before the bind completes) report real values
                // like iOS does.
                val info = cameraController.cameraInfo
                if (info != null) {
                    hasTorch = info.hasFlashUnit()
                    maxZoomRatio = (info.zoomState.value?.maxZoomRatio ?: 1f).toDouble()
                } else {
                    val characteristics = resolveCharacteristics()
                    hasTorch = characteristics
                        ?.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) ?: false
                    maxZoomRatio = characteristicsMaxZoom(characteristics)
                }
            }
            result.success(
                mapOf(
                    "hasTorch" to hasTorch,
                    "lenses" to lenses,
                    "maxZoomRatio" to maxZoomRatio,
                ),
            )
        }, mainExecutor)
    }

    /** Camera2 characteristics for [requestedLens], following the same
     * [lensPreference] order the binding path uses. */
    private fun resolveCharacteristics(): CameraCharacteristics? {
        val manager = applicationContext
            .getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            ?: return null
        return runCatching {
            lensPreference(requestedLens).firstNotNullOfOrNull { facing ->
                val wanted = if (facing == "back") {
                    CameraCharacteristics.LENS_FACING_BACK
                } else {
                    CameraCharacteristics.LENS_FACING_FRONT
                }
                manager.cameraIdList.firstNotNullOfOrNull { id ->
                    manager.getCameraCharacteristics(id)
                        .takeIf { it.get(CameraCharacteristics.LENS_FACING) == wanted }
                }
            }
        }.getOrNull()
    }

    private fun characteristicsMaxZoom(
        characteristics: CameraCharacteristics?,
    ): Double {
        if (characteristics == null) return 1.0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            characteristics.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)
                ?.let { return it.upper.toDouble() }
        }
        return (
                characteristics
                    .get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f
                ).toDouble()
    }

    /** Runs on the analysis thread. */
    private fun onAnalysisResult(result: MlKitAnalyzer.Result) {
        if (isPaused) return
        val barcodes = result.getValue(scanner) ?: return
        if (barcodes.isEmpty()) return
        val w = viewWidth
        val h = viewHeight
        // A configured scan window cannot be applied before the first layout;
        // hold the frame back rather than emit unfiltered detections.
        val window = scanWindow
        if (window != null && (w <= 0 || h <= 0)) return
        // Single pass: this runs per frame, so no intermediate lists.
        val mapped = ArrayList<Map<String, Any?>>(barcodes.size)
        for (barcode in barcodes) {
            if (window != null && !isInWindow(barcode.cornerPoints, window, w, h)) {
                continue
            }
            BarcodeFormats.wireMap(barcode, w, h, requestedFormats)?.let(mapped::add)
        }
        if (mapped.isNotEmpty()) {
            emit(mapOf("type" to "barcodes", "barcodes" to mapped))
        }
    }

    private fun attachAnalyzer() {
        // No format to detect; the preview stays live without inference.
        if (formatsUnsupported || formatsEmpty) return
        cameraController.setImageAnalysisAnalyzer(analysisExecutor, analyzer)
    }

    private fun emitStreamingState() {
        when {
            isPaused -> emitState("paused")
            formatsUnsupported -> emitError(
                "unsupportedFormats",
                "None of the requested formats are supported on this device.",
            )

            else -> emitState("scanning")
        }
    }

    private fun emitState(state: String) {
        if (state == lastState) return
        lastState = state
        emit(mapOf("type" to "state", "state" to state))
    }

    private fun emitError(code: String, message: String?) {
        lastState = "error"
        val event = mapOf("type" to "error", "code" to code, "message" to message)
        lastErrorEvent = event
        emit(event)
    }

    private fun emit(event: Map<String, Any?>) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            eventSink?.success(event)
        } else {
            mainExecutor.execute { eventSink?.success(event) }
        }
    }

    companion object {
        private const val BASE_PERMISSION_REQUEST_CODE = 0x1000

        internal fun scanWindowFromMap(map: Map<*, *>?): RectF? {
            if (map == null) return null
            val left = (map["left"] as? Number)?.toFloat() ?: return null
            val top = (map["top"] as? Number)?.toFloat() ?: return null
            val right = (map["right"] as? Number)?.toFloat() ?: return null
            val bottom = (map["bottom"] as? Number)?.toFloat() ?: return null
            return RectF(left, top, right, bottom)
        }

        /** Whether the centroid of [points] falls inside the normalized
         * [window]; barcodes without corners always pass. */
        internal fun isInWindow(
            points: Array<Point>?,
            window: RectF,
            width: Int,
            height: Int,
        ): Boolean {
            if (points == null || points.isEmpty()) return true
            // Runs per barcode per frame; avoids the boxed lists of map{}.
            var sumX = 0L
            var sumY = 0L
            for (point in points) {
                sumX += point.x
                sumY += point.y
            }
            val cx = (sumX.toDouble() / points.size).toFloat() / width
            val cy = (sumY.toDouble() / points.size).toFloat() / height
            return window.contains(cx, cy)
        }
    }
}
