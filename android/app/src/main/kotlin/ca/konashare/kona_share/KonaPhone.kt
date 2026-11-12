package ca.konashare.kona_share

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.CalendarContract
import android.provider.Settings
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class KonaPhone(private val activity: MainActivity, engine: FlutterEngine) {
    private var locationResult: MethodChannel.Result? = null
    private var notificationResult: MethodChannel.Result? = null
    init {
        MethodChannel(engine.dartExecutor.binaryMessenger, "ca.konashare/phone").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> {
                    val p = TripReminders.prefs(activity)
                    result.success(mapOf("android" to true, "homeSet" to p.contains("lat"),
                        "background" to TripReminders.backgroundAllowed(activity),
                        "precise" to TripReminders.allowed(activity, Manifest.permission.ACCESS_FINE_LOCATION),
                        "notifications" to TripReminders.notificationAllowed(activity),
                        "arrival" to if (p.contains("arrival")) p.getLong("arrival", 0) else null))
                }
                "notifications" -> {
                    TripReminders.channel(activity)
                    if (Build.VERSION.SDK_INT >= 33 && !TripReminders.allowed(activity, Manifest.permission.POST_NOTIFICATIONS)) {
                        if (notificationResult != null) result.error("busy", "A permission request is already open.", null)
                        else { notificationResult = result; activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 42) }
                    } else result.success(null)
                }
                "setHome" -> {
                    if (locationResult != null) result.error("busy", "A location request is already open.", null)
                    else if (!TripReminders.allowed(activity, Manifest.permission.ACCESS_FINE_LOCATION)) {
                        locationResult = result
                        activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 43)
                    } else saveHome(result)
                }
                "backgroundSettings" -> {
                    activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")))
                    result.success(null)
                }
                "startTrip" -> TripReminders.start(activity) { result.success(it) }
                "endTrip" -> { TripReminders.stop(activity); result.success(null) }
                "reconcile" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    if (!active) TripReminders.stop(activity)
                    else if (!TripReminders.prefs(activity).getBoolean("active", false)) TripReminders.start(activity) { }
                    else TripReminders.register(activity)
                    result.success(null)
                }
                "scan" -> {
                    val path = call.argument<String>("path")
                    if (path == null || !File(path).isFile) result.error("photo", "The photo could not be opened.", null)
                    else {
                        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                        try {
                            recognizer.process(InputImage.fromFilePath(activity, Uri.fromFile(File(path))))
                                .addOnSuccessListener { text ->
                                    val values = Regex("(?<![0-9])[0-9]{2,3}(?:[, ][0-9]{3})+(?![0-9])|(?<![0-9])[0-9]{3,7}(?![0-9])")
                                        .findAll(text.text).map { it.value.replace(",", "").replace(" ", "") }
                                        .filter { it.toIntOrNull() != null }.distinct().toList()
                                    result.success(values)
                                }.addOnFailureListener { result.error("scan", "Could not read this photo. Try typing the odometer.", null) }
                                .addOnCompleteListener { recognizer.close() }
                        } catch (_: Exception) { recognizer.close(); result.error("scan", "Could not read this photo.", null) }
                    }
                }
                "calendar" -> {
                    val intent = Intent(Intent.ACTION_INSERT).setData(CalendarContract.Events.CONTENT_URI)
                        .putExtra(CalendarContract.Events.TITLE, call.argument<String>("title"))
                        .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, call.argument<Number>("start")?.toLong())
                        .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, call.argument<Number>("end")?.toLong())
                        .putExtra(CalendarContract.Events.DESCRIPTION, call.argument<String>("description"))
                        .putExtra(CalendarContract.Events.EVENT_TIMEZONE, "America/Vancouver")
                    try { activity.startActivity(intent); result.success(null) }
                    catch (_: android.content.ActivityNotFoundException) { result.error("calendar", "Install a calendar app to add this booking.", null) }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun saveHome(result: MethodChannel.Result) {
        val cancel = CancellationTokenSource()
        activity.window.decorView.postDelayed({ cancel.cancel() }, 20000)
        try {
            LocationServices.getFusedLocationProviderClient(activity)
                .getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, cancel.token)
                .addOnSuccessListener { location ->
                    if (location == null || location.accuracy > 200) result.error("location", "Could not get a precise position. Try again near a window.", null)
                    else {
                        TripReminders.prefs(activity).edit().putString("lat", location.latitude.toString())
                            .putString("lng", location.longitude.toString()).apply()
                        TripReminders.register(activity)
                        result.success(mapOf("saved" to true))
                    }
                }.addOnFailureListener { result.error("location", "Turn on location services and try again.", null) }
                .addOnCanceledListener { result.error("location", "Location timed out. Try again.", null) }
        } catch (_: SecurityException) { result.error("location", "Precise location permission is required.", null) }
    }
    fun permissionResult(code: Int) {
        if (code == 42) { notificationResult?.success(null); notificationResult = null }
        if (code == 43) {
            val result = locationResult; locationResult = null
            if (result != null) {
                if (TripReminders.allowed(activity, Manifest.permission.ACCESS_FINE_LOCATION)) saveHome(result)
                else result.error("location", "Precise location is needed to set home. You can still log trips manually.", null)
            }
        }
    }
}
