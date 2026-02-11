package com.pmgvn.wms.wms_flutter.uhf;

import android.app.ActivityGroup;
import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.view.Window;

public class ScanModeGroup extends ActivityGroup {

	public ActivityGroup group;
	
	@Override
	protected void onCreate(Bundle savedInstanceState) {
		// TODO Auto-generated method stub
		super.onCreate(savedInstanceState);
		group = this;
	}
	
	@Override
	public void onBackPressed() {
		// TODO Auto-generated method stub
		group.getLocalActivityManager().getCurrentActivity().onBackPressed(); 
	}
	
	@Override  
    protected void onStart() {  
        super.onStart();
    }
}
