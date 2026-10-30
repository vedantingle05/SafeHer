/// EvidenceCaptureService
/// Captures photo/audio evidence and uploads via the backend.

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'api_service.dart';
import 'audio_recording_service.dart';

class EvidenceCaptureService {
  final _picker = ImagePicker();
  final _audio = AudioRecordingService();
  bool get isRecordingAudio => _audio.isRecording;

  Future<String?> capturePhoto({CameraDevice preferredCamera = CameraDevice.front}) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: preferredCamera,
        maxWidth: 1024,
        imageQuality: 70,
      );
      return photo?.path;
    } catch (e) {
      debugPrint('❌ Photo capture failed: $e');
      return null;
    }
  }

  Future<String?> captureAndUploadPhoto({required ApiService apiService}) async {
    final path = await capturePhoto();
    if (path == null) return null;
    try {
      final url = await apiService.uploadFile(folder: 'evidence', filePath: path);
      debugPrint('📦 Evidence photo uploaded: $url');
      return url;
    } catch (e) {
      debugPrint('❌ Evidence upload failed: $e');
      return null;
    }
  }

  Future<String?> startVoiceRecording() async {
    return _audio.startEvidenceRecording();
  }

  Future<String?> stopVoiceRecording() async {
    return _audio.stopEvidenceRecording();
  }

  Future<String?> uploadLocalFile({
    required ApiService apiService,
    required String filePath,
  }) async {
    try {
      final url = await apiService.uploadFile(folder: 'evidence', filePath: filePath);
      debugPrint('📦 Evidence file uploaded: $url');
      return url;
    } catch (e) {
      debugPrint('❌ Evidence upload failed: $e');
      return null;
    }
  }

  /// Silent/automatic capture for distress alerts (no user interaction).
  Future<List<String>> captureEmergencyEvidence({
    required ApiService apiService,
    CameraController? cameraController,
  }) async {
    final urls = <String>[];
    debugPrint('📸 Starting automatic emergency evidence capture...');

    if (cameraController != null && cameraController.value.isInitialized) {
      try {
        final photo = await cameraController.takePicture();
        final url = await apiService.uploadFile(
          folder: 'evidence',
          filePath: photo.path,
        );
        urls.add(url);
        debugPrint('📸 Emergency photo captured: $url');
      } catch (e) {
        debugPrint('⚠️ Emergency photo failed: $e');
      }
    } else {
      debugPrint('⚠️ Camera not ready — attempting fallback capture');
      final fallbackPath = await capturePhoto();
      if (fallbackPath != null) {
        try {
          final url = await apiService.uploadFile(
            folder: 'evidence',
            filePath: fallbackPath,
          );
          urls.add(url);
          debugPrint('📸 Emergency fallback photo uploaded: $url');
        } catch (e) {
          debugPrint('⚠️ Emergency fallback photo failed: $e');
        }
      } else {
        debugPrint('⚠️ Fallback photo capture failed or cancelled');
      }
    }

    try {
      await _audio.initialize();
      await _audio.startEvidenceRecording();
      await Future.delayed(const Duration(seconds: 6));
      final audioPath = await _audio.stopEvidenceRecording();
      if (audioPath != null) {
        final audioUrl = await uploadLocalFile(
          apiService: apiService,
          filePath: audioPath,
        );
        if (audioUrl != null) urls.add(audioUrl);
      }
    } catch (e) {
      debugPrint('⚠️ Emergency audio failed: $e');
    }

    debugPrint('📦 Emergency evidence complete: ${urls.length} file(s)');
    return urls;
  }

  Future<void> dispose() async {
    await _audio.dispose();
  }
}
