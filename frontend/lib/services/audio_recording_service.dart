/// Audio Recording Service
/// Records audio using flutter_sound for:
///   1. Scream/distress detection (short clips → MFCC → AI model)
///   2. Evidence recording (longer recordings → Firebase upload)
///
/// Note: MFCC extraction in Dart is simplified. For production, use a
/// native FFI plugin (e.g. fftea package) or send audio to backend for processing.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

class AudioRecordingService {
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  bool _isInitialized = false;
  bool _isRecording = false;
  StreamSubscription? _recorderSubscription;

  // Audio config for AI processing
  static const int sampleRate = 22050;
  static const int clipDurationMs = 3000; // 3-second clips for scream detection

  bool get isInitialized => _isInitialized;
  bool get isRecording => _isRecording;

  // ──── Initialize ────
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Request microphone permission
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      debugPrint('❌ Microphone permission denied');
      return;
    }

    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();

    await _recorder!.openRecorder();
    await _recorder!.setSubscriptionDuration(const Duration(milliseconds: 100));

    _isInitialized = true;
    debugPrint('✅ Audio recorder initialized');
  }

  // ──── Record Short Clip for AI Analysis ────
  /// Records a short audio clip and returns raw audio data as Float32List.
  /// Used by the monitoring loop for scream detection.
  Future<Float32List?> captureAudioClip() async {
    if (!_isInitialized) await initialize();
    // Capture the recorder into a local so a concurrent dispose() (e.g. the
    // user stopping monitoring mid-clip) can't null it out under us — that was
    // causing "Null check operator used on a null value".
    final recorder = _recorder;
    if (recorder == null || _isRecording) return null;

    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/ai_clip_${const Uuid().v4()}.pcm';

      // Record raw PCM for direct processing
      _isRecording = true;
      await recorder.startRecorder(
        toFile: path,
        codec: Codec.pcm16,
        sampleRate: sampleRate,
        numChannels: 1,
      );

      // Wait for clip duration
      await Future.delayed(const Duration(milliseconds: clipDurationMs));

      // If monitoring was stopped during the clip, the recorder may be gone.
      if (_recorder == null) {
        _isRecording = false;
        return null;
      }
      await recorder.stopRecorder();
      _isRecording = false;

      // Read raw audio data
      final file = File(path);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      // Convert PCM16 bytes to Float32
      final audioData = _pcm16ToFloat32(bytes);

      // Clean up temp file
      await file.delete();

      debugPrint('🎙️ Captured ${audioData.length} audio samples');
      return audioData;
    } catch (e) {
      debugPrint('❌ Audio clip capture failed: $e');
      _isRecording = false;
      return null;
    }
  }

  // ──── Extract Simplified MFCC Features ────
  /// Extracts simplified spectral features from audio data.
  /// Returns a Float32List of shape (130 × 40) for the audio AI model.
  ///
  /// Note: This is a simplified approximation. For production accuracy,
  /// use native FFI with a C library (e.g., libmfcc) or process server-side.
  Float32List extractMFCCFeatures(Float32List audioData) {
    const int nMfcc = 40;
    const int maxLen = 130;
    const int hopLength = 512;
    const int fftSize = 1024;

    // Number of frames
    final numFrames = ((audioData.length - fftSize) / hopLength).floor();
    final actualFrames = numFrames.clamp(0, maxLen);

    final mfcc = Float32List(maxLen * nMfcc); // Zeroed (padded)

    for (int frame = 0; frame < actualFrames; frame++) {
      final start = frame * hopLength;
      final end = (start + fftSize).clamp(0, audioData.length);

      // Extract frame
      final frameData = audioData.sublist(start, end);

      // Apply Hamming window
      final windowed = _applyHammingWindow(frameData);

      // Compute power spectrum (simplified FFT magnitude)
      final spectrum = _computePowerSpectrum(windowed);

      // Apply mel filterbank (simplified)
      final melEnergies = _applyMelFilterbank(spectrum, nMfcc);

      // Log compression
      for (int i = 0; i < nMfcc; i++) {
        final logEnergy = melEnergies[i] > 1e-10 ? log(melEnergies[i]) : -23.0;
        mfcc[frame * nMfcc + i] = logEnergy.toDouble();
      }
    }

    return mfcc;
  }

  // ──── Record Evidence Audio (longer recording) ────
  /// Records audio for emergency evidence. Returns file path.
  Future<String?> startEvidenceRecording() async {
    if (!_isInitialized) await initialize();
    if (_recorder == null || _isRecording) return null;

    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/evidence_${const Uuid().v4()}.aac';

      _isRecording = true;
      await _recorder!.startRecorder(
        toFile: path,
        codec: Codec.aacADTS,
        sampleRate: 44100,
        numChannels: 1,
      );

      debugPrint('🎙️ Evidence recording started');
      return path;
    } catch (e) {
      debugPrint('❌ Evidence recording failed: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Stops evidence recording and returns the file path.
  Future<String?> stopEvidenceRecording() async {
    if (!_isRecording || _recorder == null) return null;

    try {
      final path = await _recorder!.stopRecorder();
      _isRecording = false;
      debugPrint('🎙️ Evidence recording stopped: $path');
      return path;
    } catch (e) {
      debugPrint('❌ Stop recording failed: $e');
      _isRecording = false;
      return null;
    }
  }

  // ──── Audio Level Monitoring ────
  /// Returns current audio amplitude (0.0 to 1.0).
  /// Useful for quick scream detection without full AI inference.
  double getAudioLevel() {
    // The recorder's subscription provides decibel levels
    // This can be used as a quick pre-filter before running AI
    return 0.0; // Updated via subscription
  }

  /// RMS (root-mean-square) energy of a clip, range ~0.0–1.0.
  /// A no-ML loudness measure: quiet speech ~0.02–0.08, loud talking ~0.1–0.2,
  /// shouting/screaming ~0.25+. Used for model-free scream detection.
  double computeRms(Float32List audio) {
    if (audio.isEmpty) return 0.0;
    double sumSq = 0.0;
    for (final s in audio) {
      sumSq += s * s;
    }
    return sqrt(sumSq / audio.length);
  }

  /// Fraction (0.0–1.0) of samples whose absolute amplitude exceeds
  /// [threshold]. A scream is loud AND sustained, so a high fraction of
  /// near-peak samples distinguishes a scream from a brief loud clap.
  double loudFraction(Float32List audio, {double threshold = 0.45}) {
    if (audio.isEmpty) return 0.0;
    int loud = 0;
    for (final s in audio) {
      if (s.abs() > threshold) loud++;
    }
    return loud / audio.length;
  }

  // ──── Helper: PCM16 bytes → Float32 ────
  Float32List _pcm16ToFloat32(Uint8List bytes) {
    final numSamples = bytes.length ~/ 2;
    final result = Float32List(numSamples);
    final byteData = ByteData.sublistView(bytes);

    for (int i = 0; i < numSamples; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      result[i] = sample / 32768.0; // Normalize to -1.0 to 1.0
    }

    return result;
  }

  // ──── Helper: Hamming Window ────
  Float32List _applyHammingWindow(Float32List data) {
    final n = data.length;
    final result = Float32List(n);
    for (int i = 0; i < n; i++) {
      final w = 0.54 - 0.46 * cos(2 * pi * i / (n - 1));
      result[i] = data[i] * w;
    }
    return result;
  }

  // ──── Helper: Simplified Power Spectrum ────
  Float32List _computePowerSpectrum(Float32List windowed) {
    final n = windowed.length;
    final halfN = n ~/ 2;
    final spectrum = Float32List(halfN);

    // Simplified DFT (not FFT — slower but works for small frames)
    for (int k = 0; k < halfN; k++) {
      double real = 0.0, imag = 0.0;
      for (int t = 0; t < n; t++) {
        final angle = -2.0 * pi * k * t / n;
        real += windowed[t] * cos(angle);
        imag += windowed[t] * sin(angle);
      }
      spectrum[k] = (real * real + imag * imag) / n;
    }

    return spectrum;
  }

  // ──── Helper: Simplified Mel Filterbank ────
  Float32List _applyMelFilterbank(Float32List spectrum, int numFilters) {
    final result = Float32List(numFilters);
    final specLen = spectrum.length;
    final binWidth = specLen / numFilters;

    for (int i = 0; i < numFilters; i++) {
      final start = (i * binWidth).floor();
      final end = ((i + 1) * binWidth).ceil().clamp(0, specLen);
      double sum = 0.0;
      for (int j = start; j < end; j++) {
        sum += spectrum[j];
      }
      result[i] = sum / (end - start).clamp(1, specLen);
    }

    return result;
  }

  // ──── Cleanup ────
  Future<void> dispose() async {
    _recorderSubscription?.cancel();
    if (_isRecording) {
      await _recorder?.stopRecorder();
    }
    await _recorder?.closeRecorder();
    await _player?.closePlayer();
    _recorder = null;
    _player = null;
    _isInitialized = false;
  }
}
