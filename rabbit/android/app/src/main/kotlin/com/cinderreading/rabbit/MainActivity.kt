package com.cinderreading.rabbit

import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var rabbitInputSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cinder_reading/rabbit_input"
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    rabbitInputSink = events
                }

                override fun onCancel(arguments: Any?) {
                    rabbitInputSink = null
                }
            }
        )
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        sendRabbitInput(
            mapOf(
                "type" to "key",
                "action" to event.action,
                "keyCode" to event.keyCode,
                "scanCode" to event.scanCode,
                "repeatCount" to event.repeatCount,
                "source" to event.source,
                "deviceId" to event.deviceId,
                "metaState" to event.metaState,
                "downTime" to event.downTime,
                "eventTime" to event.eventTime,
                "isLongPress" to event.isLongPress,
            )
        )
        return super.dispatchKeyEvent(event)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_SCROLL) {
            val axisScrollTotal = axisTotal(event, MotionEvent.AXIS_SCROLL)
            val axisVScrollTotal = axisTotal(event, MotionEvent.AXIS_VSCROLL)
            val axisHScrollTotal = axisTotal(event, MotionEvent.AXIS_HSCROLL)
            sendRabbitInput(
                mapOf(
                    "type" to "motion",
                    "action" to event.action,
                    "source" to event.source,
                    "deviceId" to event.deviceId,
                    "axisScroll" to event.getAxisValue(MotionEvent.AXIS_SCROLL),
                    "axisVScroll" to event.getAxisValue(MotionEvent.AXIS_VSCROLL),
                    "axisHScroll" to event.getAxisValue(MotionEvent.AXIS_HSCROLL),
                    "axisScrollTotal" to axisScrollTotal,
                    "axisVScrollTotal" to axisVScrollTotal,
                    "axisHScrollTotal" to axisHScrollTotal,
                    "historySize" to event.historySize,
                    "eventTime" to event.eventTime,
                )
            )
        }
        return super.dispatchGenericMotionEvent(event)
    }

    private fun axisTotal(event: MotionEvent, axis: Int): Float {
        var total = 0f
        for (index in 0 until event.historySize) {
            total += event.getHistoricalAxisValue(axis, index)
        }
        total += event.getAxisValue(axis)
        return total
    }

    private fun sendRabbitInput(event: Map<String, Any?>) {
        runOnUiThread {
            rabbitInputSink?.success(event)
        }
    }
}
