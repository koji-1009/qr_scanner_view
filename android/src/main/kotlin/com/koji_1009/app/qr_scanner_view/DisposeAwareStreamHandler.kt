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
    delegate: EventChannel.StreamHandler,
) : EventChannel.StreamHandler {

    /** Cleared at [dispose] (doubling as the disposed mark) so the deferred
     * registration does not keep the disposed view reachable while waiting
     * for the Dart-side cancel. */
    private var delegate: EventChannel.StreamHandler? = delegate
    private var listenActive = false

    fun attach() {
        channel.setStreamHandler(this)
    }

    fun dispose() {
        delegate = null
        if (!listenActive) channel.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        listenActive = true
        val delegate = this.delegate
        if (delegate == null) {
            events?.endOfStream()
            return
        }
        delegate.onListen(arguments, events)
    }

    override fun onCancel(arguments: Any?) {
        listenActive = false
        val delegate = this.delegate
        delegate?.onCancel(arguments)
        if (delegate == null) channel.setStreamHandler(null)
    }
}
