package com.pmgvn.wms.wms_flutter.uhf;

import android.util.Log;

import java.io.FileOutputStream;

public class PowerUtils {
    private static final String TAG = "PowerUtils";
    public static final int VCC_GP_DOWN = 0;
    public static final int VCC_RFID_DOWN = 4;
    public static final int VCC_RFID_UP = 5;
    public static final int VCC_PSAM_DOWN = 6;
    public static final int VCC_PSAM_UP = 7;
    public static final int VCC_ID_DOWN = 8;
    public static final int VCC_ID_UP = 9;
    public static final int VCC_MISC_DOWN = 10;
    public static final int VCC_MISC_UP = 11;
    public static final int VCC_OTG_DOWN = 12;
    public static final int VCC_OTG_UP = 13;

    public static final int VCC_DOWN_FORCE = 24;
    public static final int VCC_UP_FORCE = 25;

    private static final String POGO_VBATT_SEL_FILE_PATH = "/sys/class/pigpig/pogo_vcc_sel/value";

    public static void powerCtrl(int type){
        try {
            FileOutputStream fOVbatSel = new FileOutputStream(POGO_VBATT_SEL_FILE_PATH);
            fOVbatSel.write(Integer.toString(type).getBytes());
            fOVbatSel.close();
            Log.d(TAG,"Power control type: " + type);
        }catch (Exception e){
            e.printStackTrace();
        }
    }
}
