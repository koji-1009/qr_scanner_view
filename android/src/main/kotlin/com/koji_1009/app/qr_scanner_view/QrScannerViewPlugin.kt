package com.koji_1009.app.qr_scanner_view

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File

/**
 * Registers the platform view factory, tracks the current activity binding and
 * serves the plugin-level channel: still-image analysis and camera permission.
 */
class QrScannerViewPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private var factory: QrScannerViewFactory? = null
    private var channel: MethodChannel? = null
    private var applicationContext: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        val f = QrScannerViewFactory(binding.binaryMessenger, binding.applicationContext)
        factory = f
        binding.platformViewRegistry.registerViewFactory(VIEW_TYPE, f)

        channel = MethodChannel(binding.binaryMessenger, VIEW_TYPE).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        applicationContext = null
        factory = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "analyzeImage" -> analyzeImage(call, result)
            "checkPermission" -> result.success(permissionStatus())
            "requestPermission" -> requestPermission(result)
            "openAppSettings" -> openAppSettings(result)
            else -> result.notImplemented()
        }
    }

    // region Permission

    private fun permissionStatus(): String {
        val context = applicationContext ?: return "notDetermined"
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return "granted"
        }
        val activity = activityBinding?.activity
        // Before a request, a permanent denial cannot be distinguished from
        // never-asked.
        return if (activity != null &&
            ActivityCompat.shouldShowRequestPermissionRationale(
                activity, Manifest.permission.CAMERA,
            )
        ) {
            "denied"
        } else {
            "notDetermined"
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (permissionStatus() == "granted") {
            result.success("granted")
            return
        }
        val binding = activityBinding
        val activity = binding?.activity
        if (binding == null || activity == null) {
            result.error("activityUnavailable", "No foreground Activity is available.", null)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("requestInProgress", "A permission request is already in progress.", null)
            return
        }
        pendingPermissionResult = result
        binding.addRequestPermissionsResultListener(this)
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.CAMERA),
            PLUGIN_PERMISSION_REQUEST_CODE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PLUGIN_PERMISSION_REQUEST_CODE) return false
        val result = pendingPermissionResult ?: return true
        pendingPermissionResult = null
        activityBinding?.removeRequestPermissionsResultListener(this)
        val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
        val status = when {
            granted -> "granted"
            CameraPermission.isPermanentlyDenied(activityBinding?.activity) ->
                "permanentlyDenied"

            else -> "denied"
        }
        result.success(status)
        return true
    }

    private fun openAppSettings(result: MethodChannel.Result) {
        val context = applicationContext
        if (context == null) {
            result.success(false)
            return
        }
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", context.packageName, null),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
            .onSuccess { result.success(true) }
            .onFailure { result.success(false) }
    }

    // endregion

    private fun analyzeImage(call: MethodCall, result: MethodChannel.Result) {
        val context = applicationContext
        val path = call.argument<String>("path")
        if (context == null || path == null) {
            result.error("imageAnalysisFailed", "Missing image path.", null)
            return
        }
        val formats = call.argument<List<String>>("formats") ?: emptyList()

        val image = try {
            InputImage.fromFilePath(context, Uri.fromFile(File(path)))
        } catch (e: Exception) {
            result.error("imageAnalysisFailed", e.message, null)
            return
        }

        val client = BarcodeScanning.getClient(BarcodeFormats.scannerOptions(formats))
        client.process(image)
            .addOnSuccessListener { barcodes ->
                // ML Kit corners are in the EXIF-upright frame while
                // InputImage width/height report the pre-rotation bitmap;
                // swap for 90/270 so normalization matches the upright image.
                val rotated = image.rotationDegrees % 180 != 0
                val width = if (rotated) image.height else image.width
                val height = if (rotated) image.width else image.height
                val mapped = barcodes.mapNotNull {
                    BarcodeFormats.wireMap(it, width, height)
                }
                client.close()
                result.success(mapped)
            }
            .addOnFailureListener { e ->
                client.close()
                result.error("imageAnalysisFailed", e.message, null)
            }
    }

    /** A detach during a pending request would otherwise hang the Dart future
     * and wedge every later request behind the in-progress guard. */
    private fun failPendingPermission() {
        val pending = pendingPermissionResult ?: return
        pendingPermissionResult = null
        activityBinding?.removeRequestPermissionsResultListener(this)
        pending.error(
            "activityUnavailable",
            "The Activity was detached during the permission request.",
            null,
        )
    }

    private fun updateActivityBinding(binding: ActivityPluginBinding?) {
        activityBinding = binding
        factory?.onActivityBindingChanged(binding)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        updateActivityBinding(binding)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        updateActivityBinding(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        failPendingPermission()
        updateActivityBinding(null)
    }

    override fun onDetachedFromActivity() {
        failPendingPermission()
        updateActivityBinding(null)
    }

    companion object {
        const val VIEW_TYPE = "qr_scanner_view"
        private const val PLUGIN_PERMISSION_REQUEST_CODE = 0x0FAA
    }
}
