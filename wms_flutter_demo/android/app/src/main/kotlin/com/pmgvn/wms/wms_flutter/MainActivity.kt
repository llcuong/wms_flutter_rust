package com.pmgvn.wms.wms_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.device.DeviceManager
import android.view.KeyEvent
import com.pmgvn.wms.wms_flutter.uhf.Reader

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register the RFID Scanner plugin
        flutterEngine.plugins.add(RfidScannerPlugin())
    }

    private var lastClickTime: Long = 0
    private val DOUBLE_CLICK_TIME_DELTA: Long = 300 // Double click window in ms

    override fun onResume() {
        super.onResume()
        disableSystemScanKeys()
    }

    private fun disableSystemScanKeys() {
        try {
            val mDeviceManager = DeviceManager()
            // Disable system handling for scan keys (barcode) and rfid keys
            // This ensures button 566 (or others) don't trigger default badcode/rfid actions
            mDeviceManager.setSettingProperty("persist-persist.sys.scan.key", "0-")
            mDeviceManager.setSettingProperty("persist-persist.sys.rfid.key", "0-")
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        // Prevent default for RFID (566) and Barcode (556)
        if (keyCode == 566 || keyCode == 556) {
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == 566) {
            val clickTime = System.currentTimeMillis()
            if (clickTime - lastClickTime < DOUBLE_CLICK_TIME_DELTA) {
                // Double Click -> STOP RFID
                try {
                    Reader.rrlib.StopRead()
                    // StopReadCallBack in plugin will emit SCAN_STOPPED
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            } else {
                // Single Click -> START RFID
                try {
                    val result = Reader.rrlib.StartRead()
                    if (result == 0) {
                        // Emit SCAN_STARTED via plugin's static instance
                        RfidScannerPlugin.instance?.emitScanStarted()
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
            lastClickTime = clickTime
            return true
        }
        return super.onKeyUp(keyCode, event)
    }
}