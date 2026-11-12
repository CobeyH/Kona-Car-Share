package ca.konashare.kona_share

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.*

object TripReminders {
    const val CHANNEL = "kona_trips"
    const val GEOFENCE = "kona_home"
    const val FALLBACK = "ca.konashare.FALLBACK"
    fun prefs(c: Context) = c.getSharedPreferences("kona_phone", Context.MODE_PRIVATE)
    fun allowed(c: Context, permission: String) = ContextCompat.checkSelfPermission(c, permission) == PackageManager.PERMISSION_GRANTED
    fun notificationAllowed(c: Context) = (Build.VERSION.SDK_INT < 33 || allowed(c, Manifest.permission.POST_NOTIFICATIONS)) && NotificationManagerCompat.from(c).areNotificationsEnabled()
    fun backgroundAllowed(c: Context) = Build.VERSION.SDK_INT < 29 || allowed(c, Manifest.permission.ACCESS_BACKGROUND_LOCATION)
    fun channel(c: Context) {
        c.getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "Kona trip reminders", NotificationManager.IMPORTANCE_DEFAULT))
    }
    fun notify(c: Context, returned: Boolean) {
        if (!notificationAllowed(c)) return
        channel(c)
        val open = PendingIntent.getActivity(c, 5, Intent(c, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = NotificationCompat.Builder(c, CHANNEL).setSmallIcon(R.drawable.ic_trip)
            .setContentTitle(if (returned) "Home again? Finish your Kona trip" else "Kona trip in progress")
            .setContentText(if (returned) "Tap to confirm your return time and ending odometer." else "Tap when you return to enter the ending odometer.")
            .setContentIntent(open).setAutoCancel(returned).setOngoing(!returned).build()
        try { NotificationManagerCompat.from(c).notify(41, n) } catch (_: SecurityException) { }
    }
    fun pending(c: Context): PendingIntent {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
        return PendingIntent.getBroadcast(c, 1, Intent(c, TripReceiver::class.java), flags)
    }
    fun register(c: Context, done: (String) -> Unit = {}) {
        val p = prefs(c)
        if (!p.getBoolean("active", false)) { done("No active trip"); return }
        if (!p.contains("lat")) { done("Set home in Settings to enable arrival reminders."); return }
        if (!allowed(c, Manifest.permission.ACCESS_FINE_LOCATION) || !backgroundAllowed(c)) {
            done("Allow precise location all the time in Settings for home reminders."); return
        }
        val fence = Geofence.Builder().setRequestId(GEOFENCE)
            .setCircularRegion(p.getString("lat", "0")!!.toDouble(), p.getString("lng", "0")!!.toDouble(), 200f)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_EXIT or Geofence.GEOFENCE_TRANSITION_ENTER)
            .setExpirationDuration(Geofence.NEVER_EXPIRE).setNotificationResponsiveness(60000).build()
        val request = GeofencingRequest.Builder().setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_EXIT).addGeofence(fence).build()
        try {
            LocationServices.getGeofencingClient(c).addGeofences(request, pending(c))
                .addOnSuccessListener { done("Home reminder is on.") }
                .addOnFailureListener { done("Home reminder unavailable. Check location and Google Play services.") }
        } catch (_: SecurityException) { done("Location permission is required for home reminders.") }
    }
    fun start(c: Context, done: (String) -> Unit) {
        prefs(c).edit().putBoolean("active", true).putBoolean("left", false).remove("arrival").apply()
        notify(c, false)
        val intent = PendingIntent.getBroadcast(c, 2, Intent(c, TripReceiver::class.java).setAction(FALLBACK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        c.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP, System.currentTimeMillis() + 4 * 3600000L, intent)
        register(c, done)
    }
    fun stop(c: Context) {
        prefs(c).edit().putBoolean("active", false).putBoolean("left", false).remove("arrival").apply()
        LocationServices.getGeofencingClient(c).removeGeofences(pending(c))
        val intent = PendingIntent.getBroadcast(c, 2, Intent(c, TripReceiver::class.java).setAction(FALLBACK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        c.getSystemService(AlarmManager::class.java).cancel(intent)
        NotificationManagerCompat.from(c).cancel(41)
    }
}

class TripReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val p = TripReminders.prefs(context)
        if (!p.getBoolean("active", false)) return
        if (intent.action == TripReminders.FALLBACK) { TripReminders.notify(context, false); return }
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError() || event.triggeringGeofences?.none { it.requestId == TripReminders.GEOFENCE } != false) return
        when (event.geofenceTransition) {
            Geofence.GEOFENCE_TRANSITION_EXIT -> {
                p.edit().putBoolean("left", true).remove("arrival").apply()
                TripReminders.notify(context, false)
            }
            Geofence.GEOFENCE_TRANSITION_ENTER -> if (p.getBoolean("left", false) && !p.contains("arrival")) {
                p.edit().putLong("arrival", System.currentTimeMillis()).apply()
                TripReminders.notify(context, true)
            }
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        if (!TripReminders.prefs(context).getBoolean("active", false)) return
        val pending = goAsync()
        TripReminders.register(context) { pending.finish() }
        TripReminders.notify(context, false)
    }
}
