import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PhoneService {
  static const _channel = MethodChannel('ca.konashare/phone');
  bool get android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<Map<String, dynamic>> status() async => android
      ? Map<String, dynamic>.from(await _channel.invokeMethod('status') as Map)
      : {'android': false};
  Future<Map<String, dynamic>> setHome() async {
    if (!android) {
      throw StateError('Home reminders are available in the Android app.');
    }
    return Map<String, dynamic>.from(
      await _channel.invokeMethod('setHome') as Map,
    );
  }

  Future<void> notifications() async {
    if (android) await _channel.invokeMethod('notifications');
  }

  Future<void> backgroundSettings() async {
    if (android) await _channel.invokeMethod('backgroundSettings');
  }

  Future<String> startTrip() async => android
      ? (await _channel.invokeMethod<String>('startTrip') ??
            'Reminder unavailable')
      : 'Home reminders are available on Android.';
  Future<void> endTrip() async {
    if (android) await _channel.invokeMethod('endTrip');
  }

  Future<void> reconcile(bool active) async {
    if (android) await _channel.invokeMethod('reconcile', {'active': active});
  }

  Future<List<String>> scan(String path) async {
    if (!android) {
      throw StateError('Photo reading is available in the Android app.');
    }
    return (await _channel.invokeListMethod<String>('scan', {'path': path})) ??
        [];
  }

  Future<void> calendar(Map<String, dynamic> booking, String driver) async {
    if (!android) {
      throw StateError('Calendar export is available in the Android app.');
    }
    await _channel.invokeMethod('calendar', {
      'title': 'Kona · $driver',
      'start': DateTime.parse(booking['startAt']).millisecondsSinceEpoch,
      'end': DateTime.parse(booking['endAt']).millisecondsSinceEpoch,
      'description':
          'Kona car booking. Estimated distance: ${booking['estimatedKm']} km. '
          'Charging included. Final cost uses actual time and odometer readings.',
    });
  }
}
