package com.pmgvn.wms.wms_flutter.uhf;

import java.sql.Date;
import java.text.SimpleDateFormat;
import android.widget.TextView;

import com.rfid.trans.ReaderHelp;
public class Reader  {
	public static ReaderHelp rrlib = new ReaderHelp();
	public  static void writelog(String log,TextView tvResult)
	{
		SimpleDateFormat simpleDateFormat = new SimpleDateFormat("HH:mm:ss");// HH:mm:ss
		Date date = new Date(System.currentTimeMillis());
		String textlog = simpleDateFormat.format(date)+" "+log;
		tvResult.setText(textlog);
	}

}
