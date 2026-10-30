/// Background Service
/// Keeps SafeHer monitoring active when the app is in the background.
/// Uses Flutter's background execution capabilities via foreground service on Android
/// and background modes on iOS.
///
/// Note: This requires platform-specific setup (done in AndroidManifest.xml and Info.plist).
/// For production, consider using the 'flutter_background_service' package.

import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackgroundService {
  static const String _portName = 'safeher_background_port';
  static bool _isRunning = false;

  static bool get isRunning => _isRunning;

  /// Initialize the background service
  static Future<void> initialize() async {
    debugPrint('🔄 Background service initializing...');

    // Register a port for communication between background and foreground
    final receivePort = ReceivePort();
    IsolateNameServer.registerPortWithName(
      receivePort.sendPort,
      _portName,
    );

    receivePort.listen((message) {
      debugPrint('📩 Background message: $message');
      _handleBackgroundMessage(message);
    });

    debugPrint('✅ Background service initialized');
  }

  /// Start the background monitoring task
  static Future<void> start() async {
    if (_isRunning) return;

    _isRunning = true;
    debugPrint('🚀 Background monitoring started');

    // Save state so we can restore after app restart
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('background_monitoring_active', true);
  }

  /// Stop the background monitoring task
  static Future<void> stop() async {
    _isRunning = false;
    debugPrint('🛑 Background monitoring stopped');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('background_monitoring_active', false);
  }

  /// Check if monitoring was active before app was killed
  static Future<bool> wasRunning() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('background_monitoring_active') ?? false;
  }

  /// Handle messages from background isolate
  static void _handleBackgroundMessage(dynamic message) {
    if (message is Map<String, dynamic>) {
      final type = message['type'];
      switch (type) {
        case 'danger_detected':
          debugPrint('🚨 Background danger: ${message['alertType']}');
          // Forward to safety monitoring service
          break;
        case 'location_update':
          debugPrint('📍 Background location: ${message['lat']}, ${message['lng']}');
          break;
        case 'sensor_data':
          debugPrint('📊 Background sensor: magnitude=${message['magnitude']}');
          break;
      }
    }
  }

  /// Send a message to the background service
  static void sendMessage(Map<String, dynamic> message) {
    final sendPort = IsolateNameServer.lookupPortByName(_portName);
    sendPort?.send(message);
  }
}
