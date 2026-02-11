package com.pmgvn.wms.wms_flutter

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

import com.pmgvn.wms.wms_flutter.uhf.Reader 
import com.pmgvn.wms.wms_flutter.uhf.PowerUtils

import com.rfid.trans.ReadTag
import com.rfid.trans.TagCallback

class RfidScannerPlugin : FlutterPlugin, MethodCallHandler, TagCallback {
    companion object {
        const val TAG = "RfidScannerPlugin"
        const val METHOD_CHANNEL = "com.pmgvn.wms/rfid_scanner"
        const val TAG_EVENT_CHANNEL = "com.pmgvn.wms/rfid_scanner/tags"
        const val STATUS_EVENT_CHANNEL = "com.pmgvn.wms/rfid_scanner/status"
        const val ERROR_EVENT_CHANNEL = "com.pmgvn.wms/rfid_scanner/errors"
        const val DEV_PORT = "/dev/ttyHS1"

        // Static instance for MainActivity to access
        var instance: RfidScannerPlugin? = null
            private set
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var tagEventChannel: EventChannel
    private lateinit var statusEventChannel: EventChannel
    private lateinit var errorEventChannel: EventChannel

    private var tagEventSink: EventChannel.EventSink? = null
    private var statusEventSink: EventChannel.EventSink? = null
    private var errorEventSink: EventChannel.EventSink? = null

    // Handler to switch back to Main Thread for Flutter communication
    private val uiHandler = Handler(Looper.getMainLooper())

    private val seenTags = mutableSetOf<String>()
    private var uniqueTagsOnly = false

    // Public method for MainActivity to emit scan started event
    fun emitScanStarted() {
        uiHandler.post {
            statusEventSink?.success("SCAN_STARTED")
        }
    }

    // Public method for MainActivity to emit scan stopped event
    fun emitScanStopped() {
        uiHandler.post {
            statusEventSink?.success("SCAN_STOPPED")
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        instance = this

        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        tagEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, TAG_EVENT_CHANNEL)
        tagEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                tagEventSink = events
            }
            override fun onCancel(arguments: Any?) {
                tagEventSink = null
            }
        })

        statusEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, STATUS_EVENT_CHANNEL)
        statusEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                statusEventSink = events
            }
            override fun onCancel(arguments: Any?) {
                statusEventSink = null
            }
        })

        errorEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, ERROR_EVENT_CHANNEL)
        errorEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                errorEventSink = events
            }
            override fun onCancel(arguments: Any?) {
                errorEventSink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        tagEventChannel.setStreamHandler(null)
        statusEventChannel.setStreamHandler(null)
        errorEventChannel.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "init" -> init(result)
            "connect" -> connect(result)
            "disconnect" -> disconnect(result)
            "startScan" -> {
                val mode = call.argument<String>("mode") ?: "CONTINUOUS"
                val uniqueOnly = call.argument<Boolean>("uniqueOnly") ?: false
                startScan(mode, uniqueOnly, result)
            }
            "stopScan" -> stopScan(result)
            "clearSeenTags" -> clearSeenTags(result)
            "setPower" -> {
                val powerLevel = call.argument<Int>("powerLevel") ?: 20
                setPower(powerLevel, result)
            }
            "readTagData" -> {
                val tagId = call.argument<String>("tagId") ?: ""
                val memoryBank = call.argument<Int>("memoryBank") ?: 0
                val wordPtr = call.argument<Int>("wordPtr") ?: 0
                val length = call.argument<Int>("length") ?: 0
                val password = call.argument<String>("password") ?: "00000000"
                readTagData(tagId, memoryBank, wordPtr, length, password, result)
            }
            "writeTagData" -> {
                val tagId = call.argument<String>("tagId") ?: ""
                val memoryBank = call.argument<Int>("memoryBank") ?: 0
                val wordPtr = call.argument<Int>("wordPtr") ?: 0
                val dataHex = call.argument<String>("dataHex") ?: ""
                val password = call.argument<String>("password") ?: "00000000"
                writeTagData(tagId, memoryBank, wordPtr, dataHex, password, result)
            }
            "writeEPC" -> {
                val newEpc = call.argument<String>("newEpc") ?: ""
                val password = call.argument<String>("password") ?: "00000000"
                writeEPC(newEpc, password, result)
            }
            else -> result.notImplemented()
        }
    }

    // TagCallback implementation
    // SDK calls this from a background thread, so we must switch to UI thread to send events
    override fun tagCallback(readTag: ReadTag) {
        try {
            val epc = readTag.epcId?.uppercase() ?: ""
            if (epc.isNotEmpty()) {
                if (uniqueTagsOnly) {
                    if (seenTags.contains(epc)) {
                        return
                    }
                    seenTags.add(epc)
                }

                val tagData = mapOf(
                    "tagId" to epc,
                    "rssi" to readTag.rssi,
                    "memId" to readTag.memId?.uppercase()
                )

                // FIX: Post to UI Thread
                uiHandler.post {
                    tagEventSink?.success(tagData)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing tag callback", e)
            uiHandler.post {
                errorEventSink?.success("Tag processing error: ${e.message}")
            }
        }
    }

    override fun StopReadCallBack() {
        uiHandler.post {
            statusEventSink?.success("SCAN_STOPPED")
        }
    }

    private fun init(result: Result) {
        Log.d(TAG, "Initializing RFID SDK...")
        // Init is fast, but better safe than sorry if it blocks
        try {
            PowerUtils.powerCtrl(PowerUtils.VCC_PSAM_UP)
            Thread.sleep(500)
            Reader.rrlib.SetCallBack(this)
            
            uiHandler.post {
                statusEventSink?.success("POWER_ON")
            }
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Init failed", e)
            result.error("INIT_EXCEPTION", e.message, null)
        }
    }

    private fun connect(result: Result) {
        Log.d(TAG, "Connecting to $DEV_PORT...")
        Thread {
            try {
                var connectResult = Reader.rrlib.Connect(DEV_PORT, 57600, 1)

                if (connectResult != 0) {
                    Log.d(TAG, "57600 failed, trying 115200...")
                    connectResult = Reader.rrlib.Connect(DEV_PORT, 115200, 1)
                }

                if (connectResult == 0) {
                    try {
                        val param = Reader.rrlib.GetInventoryPatameter()
                        param.Session = 1
                        Reader.rrlib.SetInventoryPatameter(param)
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to set default params: ${e.message}")
                    }

                    Reader.rrlib.SetCallBack(this@RfidScannerPlugin)
                    
                    // FIX: Post to UI Thread
                    uiHandler.post {
                        statusEventSink?.success("CONNECTED")
                        result.success(true)
                    }
                } else {
                    // FIX: Post to UI Thread
                    uiHandler.post {
                        statusEventSink?.success("DISCONNECTED")
                        result.error("CONN_FAILED", "Could not connect (Result: $connectResult)", null)
                    }
                }
            } catch (e: Exception) {
                // FIX: Post to UI Thread
                uiHandler.post {
                    result.error("CONN_EXCEPTION", e.message, null)
                }
            }
        }.start()
    }

    private fun disconnect(result: Result) {
        try {
            PowerUtils.powerCtrl(PowerUtils.VCC_PSAM_DOWN)
            statusEventSink?.success("DISCONNECTED")
            result.success(true)
        } catch (e: Exception) {
            result.error("DISCONN_EXCEPTION", e.message, null)
        }
    }

    private fun startScan(mode: String, uniqueOnly: Boolean, result: Result) {
        // StartScan usually returns immediately, but if the SDK blocks, wrap in Thread
        try {
            Log.d(TAG, "Starting scan - Mode: $mode, UniqueOnly: $uniqueOnly")

            seenTags.clear()
            uniqueTagsOnly = uniqueOnly

            val scanResult = when (mode) {
                "SINGLE" -> Reader.rrlib.ScanRfid()
                "CONTINUOUS" -> Reader.rrlib.StartRead()
                else -> {
                    result.error("INVALID_MODE", "Mode must be SINGLE or CONTINUOUS", null)
                    return
                }
            }

            if (scanResult == 0) {
                uiHandler.post {
                    statusEventSink?.success("SCAN_STARTED")
                }
                result.success(true)
            } else {
                result.error("SCAN_FAILED", "StartRead returned error: $scanResult", null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Start scan error", e)
            result.error("SCAN_START_ERR", e.message, null)
        }
    }

    private fun stopScan(result: Result) {
        try {
            Reader.rrlib.StopRead()
            // We do NOT clear tags here based on your previous logic preference
            // seenTags.clear() 
            result.success(true)
        } catch (e: Exception) {
            result.error("SCAN_STOP_ERR", e.message, null)
        }
    }

    private fun clearSeenTags(result: Result) {
        try {
            seenTags.clear()
            Log.d(TAG, "Cleared seen tags")
            result.success(true)
        } catch (e: Exception) {
            result.error("CLEAR_TAGS_ERR", e.message, null)
        }
    }

    private fun setPower(powerLevel: Int, result: Result) {
        try {
            val setPowerResult = Reader.rrlib.SetRfPower(powerLevel.toByte())
            if (setPowerResult == 0) {
                result.success(true)
            } else {
                result.error("SET_POWER_FAILED", "Error: $setPowerResult", null)
            }
        } catch (e: Exception) {
            result.error("SET_POWER_EXCEPTION", e.message, null)
        }
    }

    private fun readTagData(
        tagId: String,
        memoryBank: Int,
        wordPtr: Int,
        length: Int,
        password: String,
        result: Result
    ) {
        Thread {
            try {
                val data = Reader.rrlib.ReadData_G2(
                    tagId,
                    memoryBank.toByte(),
                    wordPtr,
                    length.toByte(),
                    password
                )

                // FIX: Post to UI Thread
                uiHandler.post {
                    if (data != null) {
                        result.success(data)
                    } else {
                        result.error("READ_FAILED", "Read returned null", null)
                    }
                }
            } catch (e: Exception) {
                uiHandler.post {
                    result.error("READ_EXCEPTION", e.message, null)
                }
            }
        }.start()
    }

    private fun writeTagData(
        tagId: String,
        memoryBank: Int,
        wordPtr: Int,
        dataHex: String,
        password: String,
        result: Result
    ) {
        Thread {
            try {
                val writeResult = Reader.rrlib.WriteData_G2(
                    dataHex,
                    tagId,
                    memoryBank.toByte(),
                    wordPtr,
                    password
                )

                // FIX: Post to UI Thread
                uiHandler.post {
                    if (writeResult == 0) {
                        result.success(true)
                    } else {
                        result.error("WRITE_FAILED", "Error: $writeResult", null)
                    }
                }
            } catch (e: Exception) {
                uiHandler.post {
                    result.error("WRITE_EXCEPTION", e.message, null)
                }
            }
        }.start()
    }

    private fun writeEPC(newEpc: String, password: String, result: Result) {
        Thread {
            try {
                val writeResult = Reader.rrlib.WriteEPC_G2(newEpc, password)
                
                // FIX: Post to UI Thread
                uiHandler.post {
                    if (writeResult == 0) {
                        result.success(true)
                    } else {
                        result.error("WRITE_EPC_FAILED", "Error: $writeResult", null)
                    }
                }
            } catch (e: Exception) {
                uiHandler.post {
                    result.error("WRITE_EPC_EXCEPTION", e.message, null)
                }
            }
        }.start()
    }
}