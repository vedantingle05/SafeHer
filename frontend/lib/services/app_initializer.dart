/// AppInitializer
/// Handles lazy initialization of services with proper sequencing and error handling.
/// Ensures critical services (auth) load before optional ones (monitoring).

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'sensor_service.dart';
import 'alert_service.dart';
import 'ai_inference_service.dart';
import 'evidence_service.dart';
import 'safety_monitoring_service.dart';

class AppInitializationStatus {
  final bool authReady;
  final bool apiReady;
  final bool profileLoaded;
  final bool monitoringReady;
  final String? errorMessage;

  AppInitializationStatus({
    this.authReady = false,
    this.apiReady = false,
    this.profileLoaded = false,
    this.monitoringReady = false,
    this.errorMessage,
  });

  bool get isReady => authReady && apiReady && profileLoaded;
  bool get isPartiallyReady => authReady && apiReady;
}

class AppInitializer {
  static final AppInitializer _instance = AppInitializer._();

  factory AppInitializer() => _instance;

  AppInitializer._();

  final _statusController = StreamController<AppInitializationStatus>.broadcast();
  Stream<AppInitializationStatus> get statusStream => _statusController.stream;

  AppInitializationStatus _status = AppInitializationStatus();

  Future<void> initializeApp({
    required ApiService apiService,
    required AuthService authService,
    required SensorService sensorService,
    required AlertService alertService,
  }) async {
    try {
      _updateStatus(
        apiReady: false,
        authReady: false,
        profileLoaded: false,
      );

      // Step 1: API service is already initialized
      _updateStatus(apiReady: true);
      debugPrint('✅ API service ready');

      // Step 2: Auth service is already initialized, check session
      final hasSession = authService.isAuthenticated;
      _updateStatus(authReady: true);
      debugPrint('✅ Auth service ready (session: $hasSession)');

      // Step 3: If authenticated, load profile with timeout
      if (hasSession) {
        try {
          final profileLoaded = await Future.any([
            authService.ensureProfileLoaded(),
            Future.delayed(const Duration(seconds: 10), () => false),
          ]);

          if (profileLoaded) {
            _updateStatus(profileLoaded: true);
            debugPrint('✅ Profile loaded');
          } else {
            debugPrint('⚠️ Profile loading timed out');
          }
        } catch (e) {
          debugPrint('⚠️ Profile loading error: $e');
        }
      }

      _updateStatus(monitoringReady: true);
    } catch (e) {
      debugPrint('❌ Initialization error: $e');
      _updateStatus(
        errorMessage: 'Initialization failed: $e',
      );
    }
  }

  void _updateStatus({
    bool? apiReady,
    bool? authReady,
    bool? profileLoaded,
    bool? monitoringReady,
    String? errorMessage,
  }) {
    _status = AppInitializationStatus(
      apiReady: apiReady ?? _status.apiReady,
      authReady: authReady ?? _status.authReady,
      profileLoaded: profileLoaded ?? _status.profileLoaded,
      monitoringReady: monitoringReady ?? _status.monitoringReady,
      errorMessage: errorMessage ?? _status.errorMessage,
    );
    _statusController.add(_status);
  }

  void dispose() {
    _statusController.close();
  }
}
