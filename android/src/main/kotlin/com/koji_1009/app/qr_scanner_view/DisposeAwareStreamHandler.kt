package com.koji_1009.app.qr_scanner_view

import io.flutter.plugin.common.EventChannel

/**
 * Owns the event channel's handler registration for a platform view.
 *
 * The framework disposes the platform view before the Dart-side stream
 * subscription cancels, so unregistering at [dispose] would leave that late
 * cancel without a handler. While a subscription is active the registration
 * outlives [dispose] and is released by the cancel itself.
 */
internal class DisposeAwareStreamHandler(
    private val channel: EventChannel,
    private val delegate: EventChannel.StreamHandler,
) : EventChannel.StreamHandler {

    private var listenActive = false
    private var disposed = false

    fun attach() {
        channel.setStreamHandler(this)
    }

    fun dispose() {
        disposed = true
        if (!listenActive) channel.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        listenActive = true
        if (disposed) {
            events?.endOfStream()
            return
        }
        delegate.onListen(arguments, events)
    }

    override fun onCancel(arguments: Any?) {
        listenActive = false
        delegate.onCancel(arguments)
        if (disposed) channel.setStreamHandler(null)
    }
}
