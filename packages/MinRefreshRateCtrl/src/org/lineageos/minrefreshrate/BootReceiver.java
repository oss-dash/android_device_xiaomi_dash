package org.lineageos.minrefreshrate;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.provider.Settings;
import android.util.Log;

public class BootReceiver extends BroadcastReceiver {
    private static final String TAG = "MinRefreshRateCtrl";
    static final float MIN_REFRESH_RATE_HZ = 60.0f;
    static final float PEAK_REFRESH_RATE_HZ = 120.0f;

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            return;
        }
        applyFloor(context);
    }

    static void applyFloor(Context context) {
        try {
            enforcePeak(context);
            float current = Settings.System.getFloat(
                    context.getContentResolver(), "min_refresh_rate", 0f);
            if (current >= MIN_REFRESH_RATE_HZ) {
                // Keep whatever the user selected in Settings (e.g. 90 or 120Hz).
                // Only values below the floor (including unset/0) need fixing.
                Log.i(TAG, "min_refresh_rate already " + current
                        + "Hz, keeping persisted value");
                return;
            }
            boolean applied = Settings.System.putFloat(
                    context.getContentResolver(),
                    "min_refresh_rate",
                    MIN_REFRESH_RATE_HZ);
            Log.i(TAG, applied
                    ? "min_refresh_rate enforced at " + MIN_REFRESH_RATE_HZ + "Hz"
                    : "min_refresh_rate write returned false");
        } catch (Exception e) {
            Log.e(TAG, "Failed to set min_refresh_rate", e);
        }
    }

    /* An unset peak_refresh_rate (null) collapses the SurfaceFlinger render
     * range to the minimum, so the UI stays at 60 Hz even when 120 Hz is
     * supported. Store the panel maximum explicitly when it is unset. */
    static void enforcePeak(Context context) {
        try {
            float peak = Settings.System.getFloat(
                    context.getContentResolver(), "peak_refresh_rate", 0f);
            if (peak <= 0f) {
                boolean applied = Settings.System.putFloat(
                        context.getContentResolver(),
                        "peak_refresh_rate",
                        PEAK_REFRESH_RATE_HZ);
                Log.i(TAG, applied
                        ? "peak_refresh_rate enforced at " + PEAK_REFRESH_RATE_HZ + "Hz"
                        : "peak_refresh_rate write returned false");
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to set peak_refresh_rate", e);
        }
    }
}
