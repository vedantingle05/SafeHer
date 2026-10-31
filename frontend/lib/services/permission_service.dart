/// Centralized runtime permission requests for sensors and emergency features.

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Request all permissions needed for safety monitoring.
  /// Returns true if location is granted (minimum required for alerts).
  static Future<bool> requestMonitoringPermissions() async {
    debugPrint('🔐 Requesting monitoring permissions...');

    final mic = await Permission.microphone.request();
    debugPrint('   microphone: $mic');

    final camera = await Permission.camera.request();
    debugPrint('   camera: $camera');

    final sensors = await Permission.sensors.request();
    debugPrint('   sensors: $sensors');

    final activity = await Permission.activityRecognition.request();
    debugPrint('   activityRecognition: $activity');

    await Permission.notification.request();
    await Permission.sms.request();

    var location = await Geolocator.checkPermission();
    if (location == LocationPermission.denied) {
      location = await Geolocator.requestPermission();
    }
    debugPrint('   location: $location');

    final ok = location == LocationPermission.always ||
        location == LocationPermission.whileInUse;
    if (!ok) {
      debugPrint('❌ Location permission required for emergency alerts');
    }
    return ok;
  }
}
