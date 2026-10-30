/// SensorService
/// Manages real-time sensor data: accelerometer, gyroscope, and GPS.

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'permission_service.dart';

class SensorService extends ChangeNotifier {
  double _accelX = 0, _accelY = 0, _accelZ = 0;
  double _gyroX = 0, _gyroY = 0, _gyroZ = 0;
  double _accelMagnitude = 0;
  Position? _currentPosition;
  bool _isMonitoring = false;
  bool _fallDetected = false;
  bool _wasInFreefall = false;

  // Per-stream health flags — exposed so the dashboard can show which
  // sensors are actually delivering data vs. unavailable on this device.
  bool _accelStreamLive = false;
  bool _gyroStreamLive = false;
  bool _locationStreamLive = false;
  String? _accelError;
  String? _gyroError;
  String? _locationError;

  StreamSubscription? _accelSubscription;
  StreamSubscription? _gyroSubscription;
  StreamSubscription? _locationSubscription;
  Timer? _fallResetTimer;

  static const double _impactThreshold = 25.0;
  static const double _freefallThreshold = 3.5;
  static const double _severeImpactThreshold = 35.0;

  double get accelX => _accelX;
  double get accelY => _accelY;
  double get accelZ => _accelZ;
  double get gyroX => _gyroX;
  double get gyroY => _gyroY;
  double get gyroZ => _gyroZ;
  double get accelMagnitude => _accelMagnitude;
  Position? get currentPosition => _currentPosition;
  bool get isMonitoring => _isMonitoring;
  bool get fallDetected => _fallDetected;

  double get latitude => _currentPosition?.latitude ?? 0.0;
  double get longitude => _currentPosition?.longitude ?? 0.0;
  bool get hasValidLocation =>
      _currentPosition != null && latitude != 0.0 && longitude != 0.0;

  bool get accelStreamLive => _accelStreamLive;
  bool get gyroStreamLive => _gyroStreamLive;
  bool get locationStreamLive => _locationStreamLive;
  String? get accelError => _accelError;
  String? get gyroError => _gyroError;
  String? get locationError => _locationError;

  /// Diagnostic snapshot: which streams are healthy / which failed and why.
  Map<String, dynamic> get diagnostics => {
        'monitoring': _isMonitoring,
        'accelerometer': {
          'live': _accelStreamLive,
          'error': _accelError,
          'magnitude': _accelMagnitude,
        },
        'gyroscope': {
          'live': _gyroStreamLive,
          'error': _gyroError,
        },
        'location': {
          'live': _locationStreamLive,
          'error': _locationError,
          'hasFix': hasValidLocation,
          'lat': latitude,
          'lng': longitude,
        },
      };

  /// Start sensor streams.
  ///
  /// [skipPermissionRequest] avoids re-prompting when the caller has already
  /// run `PermissionService.requestMonitoringPermissions()` — for example
  /// `SafetyMonitoringService.startMonitoring()` does this once for the
  /// whole subsystem, so passing `true` from there prevents duplicate
  /// system dialogs and the slower start they cause.
  Future<void> startMonitoring({bool skipPermissionRequest = false}) async {
    if (_isMonitoring) return;

    if (!skipPermissionRequest) {
      final locationOk = await PermissionService.requestMonitoringPermissions();
      if (!locationOk) {
        debugPrint('⚠️ Sensor monitoring started without location permission');
      }
    }

    _isMonitoring = true;
    debugPrint('📡 Starting accelerometer + gyroscope streams');

    try {
      _accelSubscription = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 100),
      ).listen(
        (event) {
          if (!_accelStreamLive) {
            _accelStreamLive = true;
            _accelError = null;
          }
          _accelX = event.x;
          _accelY = event.y;
          _accelZ = event.z;
          _accelMagnitude =
              sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
          _checkFallDetection();
          notifyListeners();
        },
        onError: (e) {
          _accelStreamLive = false;
          _accelError = e.toString();
          debugPrint('❌ Accelerometer error: $e');
          notifyListeners();
        },
        cancelOnError: false,
      );
    } catch (e) {
      _accelError = e.toString();
      debugPrint('⚠️ Accelerometer stream unavailable: $e');
    }

    try {
      _gyroSubscription = gyroscopeEventStream(
        samplingPeriod: const Duration(milliseconds: 100),
      ).listen(
        (event) {
          if (!_gyroStreamLive) {
            _gyroStreamLive = true;
            _gyroError = null;
          }
          _gyroX = event.x;
          _gyroY = event.y;
          _gyroZ = event.z;
          notifyListeners();
        },
        onError: (e) {
          _gyroStreamLive = false;
          _gyroError = e.toString();
          debugPrint('❌ Gyroscope error: $e');
          notifyListeners();
        },
        cancelOnError: false,
      );
    } catch (e) {
      _gyroError = e.toString();
      debugPrint('⚠️ Gyroscope stream unavailable: $e');
    }

    await _startLocationTracking();
    notifyListeners();
    debugPrint(
        '✅ Sensor monitoring active (accel=$_accelStreamLive gyro=$_gyroStreamLive loc=$_locationStreamLive)');
  }

  void stopMonitoring() {
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
    _locationSubscription?.cancel();
    _fallResetTimer?.cancel();
    _accelSubscription = null;
    _gyroSubscription = null;
    _locationSubscription = null;
    _isMonitoring = false;
    _wasInFreefall = false;
    _accelStreamLive = false;
    _gyroStreamLive = false;
    _locationStreamLive = false;
    notifyListeners();
    debugPrint('🛑 Sensor monitoring stopped');
  }

  Future<void> _startLocationTracking() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _locationError = 'Location services are disabled on the device.';
      debugPrint('⚠️ Location services disabled');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _locationError = 'Location permission denied.';
      debugPrint('⚠️ Location permission denied');
      return;
    }

    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));
      debugPrint('📍 Initial GPS: $latitude, $longitude');
    } catch (e) {
      _locationError = 'Initial GPS fix failed: $e';
      debugPrint('⚠️ Initial GPS failed: $e');
    }

    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (position) {
        if (!_locationStreamLive) {
          _locationStreamLive = true;
          _locationError = null;
        }
        _currentPosition = position;
        notifyListeners();
      },
      onError: (e) {
        _locationStreamLive = false;
        _locationError = e.toString();
        debugPrint('❌ GPS stream error: $e');
        notifyListeners();
      },
      cancelOnError: false,
    );
  }

  /// Two-phase fall detection: freefall then impact, or severe impact alone.
  void _checkFallDetection() {
    if (_accelMagnitude < _freefallThreshold && _accelMagnitude > 0.8) {
      _wasInFreefall = true;
      return;
    }

    final impactAfterFreefall =
        _wasInFreefall && _accelMagnitude > _impactThreshold;
    final severeImpact = _accelMagnitude > _severeImpactThreshold;

    if (impactAfterFreefall || severeImpact) {
      _wasInFreefall = false;
      _setFallDetected();
      return;
    }

    if (_accelMagnitude > 12.0) {
      _wasInFreefall = false;
    }
  }

  void _setFallDetected() {
    if (_fallDetected) return;
    _fallDetected = true;
    debugPrint('⚠️ Fall detected (magnitude: ${_accelMagnitude.toStringAsFixed(1)})');
    notifyListeners();

    _fallResetTimer?.cancel();
    _fallResetTimer = Timer(const Duration(seconds: 15), () {
      _fallDetected = false;
      notifyListeners();
    });
  }

  void resetFallDetection() {
    _fallDetected = false;
    _wasInFreefall = false;
    _fallResetTimer?.cancel();
    notifyListeners();
  }

  Map<String, dynamic> get locationMap => {
        'latitude': latitude,
        'longitude': longitude,
      };

  List<double> get sensorVector => [
        _accelX,
        _accelY,
        _accelZ,
        _gyroX,
        _gyroY,
        _gyroZ,
        _accelMagnitude,
      ];

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
