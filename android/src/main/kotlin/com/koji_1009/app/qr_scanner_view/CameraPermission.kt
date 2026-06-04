package com.koji_1009.app.qr_scanner_view

import android.Manifest
import android.app.Activity
import androidx.core.app.ActivityCompat

internal object CameraPermission {
    /** After a denial, a false rationale means the OS won't prompt again. */
    fun isPermanentlyDenied(activity: Activity?): Boolean =
        activity != null &&
                !ActivityCompat.shouldShowRequestPermissionRationale(
                    activity, Manifest.permission.CAMERA,
                )
}
