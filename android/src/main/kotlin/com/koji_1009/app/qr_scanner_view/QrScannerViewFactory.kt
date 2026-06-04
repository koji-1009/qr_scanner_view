package com.koji_1009.app.qr_scanner_view

import android.content.Context
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Builds a [QrScannerView] per platform view id. */
class QrScannerViewFactory(
    private val messenger: BinaryMessenger,
    private val applicationContext: Context,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    private val views = mutableSetOf<QrScannerView>()

    /** Kept up to date through [onActivityBindingChanged]. */
    private var activityBinding: ActivityPluginBinding? = null

    /** Called by [QrScannerViewPlugin] on every activity-binding change; live
     * views are notified so a pending permission request follows the binding. */
    fun onActivityBindingChanged(binding: ActivityPluginBinding?) {
        activityBinding = binding
        views.forEach { it.onActivityBindingChanged(binding) }
    }

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = (args as? Map<String, Any?>) ?: emptyMap()
        return QrScannerView(
            context = context,
            applicationContext = applicationContext,
            messenger = messenger,
            viewId = viewId,
            creationParams = params,
            activityBindingProvider = { activityBinding },
            onDisposed = views::remove,
        ).also(views::add)
    }
}
