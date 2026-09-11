package com.example.women_safety_app

import android.annotation.SuppressLint
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.example.women_safety_app/gps"

    @SuppressLint("MissingPermission")
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getGpsLocation") {
                val lm = getSystemService(LOCATION_SERVICE) as LocationManager
                var finished = false

                val listener = object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        if (!finished) {
                            finished = true
                            lm.removeUpdates(this)
                            result.success(mapOf("lat" to location.latitude, "lng" to location.longitude))
                        }
                    }
                }

                try {
                    lm.requestLocationUpdates(
                        LocationManager.GPS_PROVIDER,
                        0L,
                        0f,
                        listener,
                        Looper.getMainLooper()
                    )

                    Handler(Looper.getMainLooper()).postDelayed({
                        if (!finished) {
                            finished = true
                            lm.removeUpdates(listener)
                            result.error("TIMEOUT", "No GPS fix received", null)
                        }
                    }, 12000)
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}