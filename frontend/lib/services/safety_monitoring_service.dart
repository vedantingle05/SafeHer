/// Safety Monitoring Service
/// The core brain of SafeHer: continuously reads sensor data, runs AI inference,
/// and auto-triggers emergency alerts when danger is detected.
///
/// Flow: Sensors → AI Models → Threshold Check → Emergency Trigger

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:geolocator/geolocator.dart';
import 'sensor_service.dart';
import 'ai_inference_service.dart';
import 'alert_service.dart';
import 'api_service.dart';
import 'evidence_service.dart';
import 'audio_recording_service.dart';
import 'permission_service.dart';

/// Configuration thresholds for triggering alerts
class SafetyThresholds {
  static const double screamConfidence = 0.80;
  static const double emotionConfidence = 0.70;
  // Loudness-based scream detection (used when the ML audio model is
  // missing/incompatible). Tune these per device mic sensitivity — watch the
  // "🎤 Audio (loudness)" logs to see what a real scream produces.
  static const double screamRmsThreshold = 0.18;
  static const double screamLoudFraction = 0.10;
  static const double fallAccelThreshold = 25.0;
  static const double freefallThreshold = 3.0;
  static const Duration cooldownPeriod = Duration(minutes: 2);
  static const Duration motionCheckInterval = Duration(milliseconds: 500);
  static const Duration audioCheckInterval = Duration(seconds: 3);
  static const Duration emotionCheckInterval = Duration(seconds: 5);
}

class SafetyMonitoringService extends ChangeNotifier {
  final SensorService sensorService;
  final AIInferenceService aiService;
  final AlertService alertService;
  final EvidenceCaptureService evidenceService;
  final ApiService apiService;

  // Audio & camera services (initialized lazily)
  AudioRecordingService? _audioService;
  CameraController? _cameraController;
  CameraController? get cameraController => _cameraController;

  /// Captures a photo silently in background using internal CameraController without opening any external camera app.
  Future<String?> captureSilentPhoto() async {
    CameraController? controller = _cameraController;
    bool temporary = false;
    try {
      if (controller == null || !controller.value.isInitialized) {
        final cameras = await availableCameras();
        if (cameras.isNotEmpty) {
          final cam = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
            orElse: () => cameras.first,
          );
          controller = CameraController(
            cam,
            ResolutionPreset.medium,
            enableAudio: false,
          );
          await controller.initialize();
          temporary = true;
        }
      }

      if (controller != null && controller.value.isInitialized) {
        final photo = await controller.takePicture();
        final url = await apiService.uploadFile(folder: 'evidence', filePath: photo.path);
        debugPrint('📸 Silent in-app photo captured & uploaded: $url');
        return url;
      }
    } catch (e) {
      debugPrint('⚠️ Silent photo capture error: $e');
    } finally {
      if (temporary && controller != null) {
        try {
          await controller.dispose();
        } catch (_) {}
      }
    }
    return null;
  }

  // ──── State ────
  bool _isMonitoring = false;
  bool _appPaused = false;
  DateTime? _lastAlertTime;
  String _currentStatus = 'idle';
  Map<String, dynamic>? _lastEmotionResult;
  Map<String, dynamic>? _lastAudioResult;
  Map<String, dynamic>? _lastMotionResult;

  Timer? _motionTimer;
  Timer? _audioTimer;
  Timer? _emotionTimer;

  // ──── Getters ────
  bool get isMonitoring => _isMonitoring;
  String get currentStatus => _currentStatus;
  Map<String, dynamic>? get lastEmotionResult => _lastEmotionResult;
  Map<String, dynamic>? get lastAudioResult => _lastAudioResult;
  Map<String, dynamic>? get lastMotionResult => _lastMotionResult;

  SafetyMonitoringService({
    required this.sensorService,
    required this.aiService,
    required this.alertService,
    required this.evidenceService,
    required this.apiService,
  });

  // ──── Start Full Monitoring Loop ────
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;

    debugPrint('🛡️ SafeHer monitoring starting...');
    _isMonitoring = true;
    _currentStatus = 'starting';
    notifyListeners();

    // Step 1 — Permissions (done ONCE for the whole subsystem; sensorService
    // and audio/camera init below all skip their own requests).
    final permsOk = await PermissionService.requestMonitoringPermissions();
    if (!permsOk) {
      debugPrint('⚠️ Some permissions denied — monitoring may be limited');
    }

    // Step 2 — Sensors first. These are the cheapest to start and the user
    // gets immediate visible feedback (live accel/gyro values, GPS fix).
    await sensorService.startMonitoring(skipPermissionRequest: true);
    _currentStatus = 'sensors_live';
    _startMotionMonitoring();
    notifyListeners();

    // Step 3 — Heavy services initialize in background so they don't block
    // the "monitoring active" feedback. Each is independent and failure-
    // isolated; if one fails the others keep running.
    unawaited(_initializeHeavyServices());

    debugPrint('🛡️ SafeHer monitoring active — sensors live, AI bootstrapping');
  }

  Future<void> _initializeHeavyServices() async {
    // 3a — AI models (TFLite). Takes ~500ms-2s depending on device.
    if (!aiService.isInitialized) {
      try {
        await aiService.initialize();
        debugPrint('✅ AI models loaded');
      } catch (e) {
        debugPrint('⚠️ AI model load failed: $e');
      }
    }

    // 3b — Audio service
    try {
      _audioService = AudioRecordingService();
      await _audioService!.initialize();
      _startAudioMonitoring();
      debugPrint('✅ Audio service ready');
    } catch (e) {
      debugPrint('⚠️ Audio init failed: $e');
      _audioService = null;
    }

    // 3c — Front camera for emotion detection (slow on cold start)
    await _initCamera();

    if (_isMonitoring) {
      _currentStatus = 'monitoring';
      notifyListeners();
    }
  }

  /// Create (or recreate) the front-camera controller and start the emotion
  /// timer. Safe to call repeatedly — any existing controller is disposed
  /// first. Used both on initial monitoring start and on app-resume.
  Future<void> _initCamera() async {
    // Always tear down any prior controller before creating a new one. Failing
    // to do this is what causes the BLASTBufferQueue "can't acquire next
    // buffer" SurfaceView deadlock when the app is backgrounded and resumed.
    await _disposeCamera();
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint('⚠️ No cameras found on device');
        return;
      }
      final frontCam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        frontCam,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await controller.initialize();
      _cameraController = controller;
      _startEmotionMonitoring();
      debugPrint('✅ Camera ready for emotion detection');
    } catch (e) {
      debugPrint('⚠️ Camera init failed (emotion detection disabled): $e');
      _cameraController = null;
    }
  }

  Future<void> _disposeCamera() async {
    _emotionTimer?.cancel();
    final cam = _cameraController;
    _cameraController = null;
    if (cam != null) {
      try {
        await cam.dispose();
      } catch (e) {
        debugPrint('⚠️ Camera dispose error: $e');
      }
    }
  }

  /// Called by the host screen when the app goes to the background.
  /// Releases the camera SurfaceView so its buffers are freed; the OS would
  /// otherwise hold them and deadlock the renderer on resume.
  Future<void> handleAppPaused() async {
    if (!_isMonitoring) return;
    debugPrint('⏸️ App paused — releasing camera');
    _appPaused = true;
    await _disposeCamera();
  }

  /// Called by the host screen when the app returns to the foreground.
  /// Recreates the camera controller that was released in [handleAppPaused].
  Future<void> handleAppResumed() async {
    if (!_isMonitoring || !_appPaused) return;
    debugPrint('▶️ App resumed — reinitializing camera');
    _appPaused = false;
    await _initCamera();
  }

  // ──── Stop Monitoring ────
  void stopMonitoring() {
    _isMonitoring = false;
    _appPaused = false;
    _currentStatus = 'idle';
    _motionTimer?.cancel();
    _audioTimer?.cancel();
    _emotionTimer?.cancel();
    // Fire-and-forget camera teardown (dispose is async).
    _disposeCamera();
    _audioService?.dispose();
    _audioService = null;
    sensorService.stopMonitoring();
    notifyListeners();
    debugPrint('🛑 SafeHer monitoring stopped');
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  MOTION / FALL DETECTION
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  void _startMotionMonitoring() {
    _motionTimer = Timer.periodic(
      SafetyThresholds.motionCheckInterval,
      (_) => _checkMotion(),
    );
  }

  void _checkMotion() {
    if (!_isMonitoring) return;

    final magnitude = sensorService.accelMagnitude;

    // Threshold-based fall detection (always active, no model needed)
    if (magnitude > SafetyThresholds.fallAccelThreshold) {
      debugPrint('⚠️ Impact detected! Magnitude: ${magnitude.toStringAsFixed(1)}');
      _handleDangerDetected('fall', 0.85);
      return;
    }
    if (magnitude < SafetyThresholds.freefallThreshold && magnitude > 0.1) {
      debugPrint('⚠️ Freefall detected! Magnitude: ${magnitude.toStringAsFixed(1)}');
      _handleDangerDetected('fall', 0.75);
      return;
    }

    // AI model-based detection (if model loaded)
    final sensorData = Float32List.fromList(sensorService.sensorVector);
    final result = aiService.detectMotion(sensorData);
    if (result != null) {
      _lastMotionResult = result;
      if (result['isFallRisk'] == true) {
        _handleDangerDetected('fall', (result['confidence'] as double));
      }
      notifyListeners();
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  AUDIO / SCREAM DETECTION
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  void _startAudioMonitoring() {
    _audioTimer = Timer.periodic(
      SafetyThresholds.audioCheckInterval,
      (_) => _checkAudio(),
    );
  }

  Future<void> _checkAudio() async {
    if (!_isMonitoring || _audioService == null) return;

    try {
      // 1. Record a 3-second audio clip
      final audioData = await _audioService!.captureAudioClip();
      if (audioData == null || audioData.isEmpty) return;

      // 2. Extract MFCC features (130 × 40)
      final mfccFeatures = _audioService!.extractMFCCFeatures(audioData);

      // 3. Try the ML model first (works only if its features match the app's).
      final result = aiService.detectAudioDistress(mfccFeatures);
      if (result != null) {
        _lastAudioResult = result;
        notifyListeners();
        final conf = ((result['confidence'] as double) * 100).toStringAsFixed(0);
        debugPrint('🎤 Audio model → class=${result['classIndex']} '
            'conf=$conf% danger=${result['isDanger']}');
        if (result['isDanger'] == true &&
            (result['confidence'] as double) > SafetyThresholds.screamConfidence) {
          debugPrint('🔊 Scream detected (model)! conf=${result['confidence']}');
          _handleDangerDetected('scream', result['confidence'] as double);
        }
        return;
      }

      // 4. Fallback — loudness heuristic (no ML model needed). The app's
      //    simplified MFCC can't match a librosa-trained model, so we detect a
      //    scream as a loud, SUSTAINED sound: high RMS energy + a high fraction
      //    of near-peak samples.
      final rms = _audioService!.computeRms(audioData);
      final loud = _audioService!.loudFraction(audioData);
      debugPrint('🎤 Audio (loudness) → rms=${rms.toStringAsFixed(3)} '
          'loud=${(loud * 100).toStringAsFixed(0)}%');
      if (rms > SafetyThresholds.screamRmsThreshold &&
          loud > SafetyThresholds.screamLoudFraction) {
        debugPrint('🔊 Loud sustained sound (possible scream) detected '
            'rms=${rms.toStringAsFixed(3)}');
        _handleDangerDetected('scream', 0.85);
      }
    } catch (e) {
      debugPrint('⚠️ Audio check error: $e');
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  FACIAL EMOTION DETECTION
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  void _startEmotionMonitoring() {
    _emotionTimer = Timer.periodic(
      SafetyThresholds.emotionCheckInterval,
      (_) => _checkEmotion(),
    );
  }

  Future<void> _checkEmotion() async {
    if (!_isMonitoring || _cameraController == null) return;
    if (!_cameraController!.value.isInitialized) return;

    try {
      // 1. Capture a camera frame
      final XFile imageFile = await _cameraController!.takePicture();
      final bytes = await imageFile.readAsBytes();

      // 2. Decode and preprocess: resize to 48×48 grayscale
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;

      final resized = img.copyResize(decoded, width: 48, height: 48);
      final grayscale = img.grayscale(resized);

      // 3. Convert to Float32List normalized to 0-1
      final pixels = Float32List(48 * 48);
      for (int y = 0; y < 48; y++) {
        for (int x = 0; x < 48; x++) {
          final pixel = grayscale.getPixel(x, y);
          // luminance channel, normalize to 0-1
          pixels[y * 48 + x] = img.getLuminance(pixel) / 255.0;
        }
      }

      // 4. Run through emotion AI model
      final result = aiService.detectEmotion(pixels);
      if (result != null) {
        _lastEmotionResult = result;
        notifyListeners();

        // TEST LOG: prints every prediction so you can verify the model
        // reacts to your facial expressions without triggering a real alert.
        final conf = ((result['confidence'] as double) * 100).toStringAsFixed(0);
        debugPrint('🙂 Emotion model → ${result['label']} '
            'conf=$conf% distress=${result['isDistress']}');

        // 5. Check for distress emotions
        if (result['isDistress'] == true &&
            (result['confidence'] as double) > SafetyThresholds.emotionConfidence) {
          debugPrint('😰 Distress emotion detected: ${result['label']} '
              '(${result['confidence']})');
          _handleDangerDetected('emotion', result['confidence']);
        }
      }

      // Clean up temp file
      try { await File(imageFile.path).delete(); } catch (_) {}
    } catch (e) {
      debugPrint('⚠️ Emotion check error: $e');
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  DANGER → EMERGENCY ALERT
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> _handleDangerDetected(String type, double confidence) async {
    // Cooldown: don't spam alerts
    if (_lastAlertTime != null) {
      final elapsed = DateTime.now().difference(_lastAlertTime!);
      if (elapsed < SafetyThresholds.cooldownPeriod) {
        debugPrint('⏳ Cooldown active (${elapsed.inSeconds}s / '
            '${SafetyThresholds.cooldownPeriod.inSeconds}s)');
        return;
      }
    }

    debugPrint('🚨 DANGER: $type (confidence: ${confidence.toStringAsFixed(2)})');
    _currentStatus = 'danger_detected';
    _lastAlertTime = DateTime.now();
    notifyListeners();

    // 1. Capture evidence (photo + audio) before alerting contacts
    List<String> evidenceUrls = [];
    try {
      evidenceUrls = await evidenceService.captureEmergencyEvidence(
        apiService: apiService,
        cameraController: _cameraController,
      );
    } catch (e) {
      debugPrint('⚠️ Evidence capture failed: $e');
    }

    // 2. Fresh GPS for alert payload
    double lat = sensorService.latitude;
    double lng = sensorService.longitude;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 5),
      );
      lat = pos.latitude;
      lng = pos.longitude;
      debugPrint('📍 Emergency location: $lat, $lng');
    } catch (e) {
      debugPrint('⚠️ Live GPS failed, using last known: $e');
    }

    // 3. Trigger full emergency (alert + SMS + push to contacts)
    final result = await alertService.triggerEmergency(
      type: type,
      latitude: lat,
      longitude: lng,
      confidence: confidence,
      evidenceUrls: evidenceUrls.isNotEmpty ? evidenceUrls : null,
    );

    if (!result.anyReached) {
      debugPrint(
        '⚠️ Emergency delivery failed for type=$type at $lat,$lng: ${result.message}',
      );
    }
    _currentStatus = result.anyReached ? 'alert_sent' : 'alert_failed';
    notifyListeners();

    // 3. Reset to monitoring after 30s
    Future.delayed(const Duration(seconds: 30), () {
      if (_isMonitoring) {
        _currentStatus = 'monitoring';
        notifyListeners();
      }
    });
  }

  /// User confirms they're safe
  void confirmSafe() {
    _currentStatus = 'monitoring';
    sensorService.resetFallDetection();
    notifyListeners();
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
