package com.koji_1009.app.qr_scanner_view

import io.flutter.plugin.common.EventChannel
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify

class DisposeAwareStreamHandlerTest {

    private class RecordingDelegate : EventChannel.StreamHandler {
        val calls = mutableListOf<String>()

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            calls.add("listen")
        }

        override fun onCancel(arguments: Any?) {
            calls.add("cancel")
        }
    }

    private val channel = mock(EventChannel::class.java)
    private val delegate = RecordingDelegate()
    private val handler = DisposeAwareStreamHandler(channel, delegate)

    @Test
    fun `attach registers itself on the channel`() {
        handler.attach()

        verify(channel).setStreamHandler(handler)
    }

    @Test
    fun `dispose without an active listen unregisters immediately`() {
        handler.dispose()

        verify(channel).setStreamHandler(null)
    }

    @Test
    fun `dispose during an active listen defers unregistration to the cancel`() {
        handler.onListen(null, null)
        handler.dispose()
        verify(channel, never()).setStreamHandler(null)

        handler.onCancel(null)

        verify(channel).setStreamHandler(null)
        assertEquals(listOf("listen", "cancel"), delegate.calls)
    }

    @Test
    fun `cancel before dispose keeps the live registration`() {
        handler.onListen(null, null)
        handler.onCancel(null)
        verify(channel, never()).setStreamHandler(null)

        handler.dispose()

        verify(channel).setStreamHandler(null)
    }

    @Test
    fun `listen after dispose ends the stream without reaching the delegate`() {
        handler.dispose()
        val sink = mock(EventChannel.EventSink::class.java)

        handler.onListen(null, sink)

        verify(sink).endOfStream()
        assertEquals(emptyList<String>(), delegate.calls)
    }

    @Test
    fun `forwards listen and cancel to the delegate while live`() {
        handler.onListen(null, null)
        handler.onCancel(null)

        assertEquals(listOf("listen", "cancel"), delegate.calls)
    }
}
