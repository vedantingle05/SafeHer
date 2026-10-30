/// AI Inference Service
/// Runs TensorFlow Lite models on-device for real-time distress detection.
/// Models: emotion (face), audio (scream/distress), motion (fall).
///
/// All detection methods read the model's actual input/output tensor shapes
/// at runtime, so a model with a different class count or input size won't
/// crash — it adapts (emotion) or skips gracefully with a clear log (audio).

import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class AIInferenceService {
  Interpreter? _emotionInterpreter;
  Interpreter? _audioInterpreter;
  Interpreter? _motionInterpreter;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool get emotionModelLoaded => _emotionInterpreter != null;
  bool get audioModelLoaded => _audioInterpreter != null;
  bool get motionModelLoaded => _motionInterpreter != null;

  // One-time warning guards so a shape mismatch logs once, not every cycle.
  bool _audioShapeWarned = false;
  bool _emotionShapeWarned = false;

  // ──── Emotion Detection Config ────
  static const int emotionImgSize = 48;
  // 7-class FER-2013 order.
  static const List<String> emotionLabels7 = [
    'angry', 'disgust', 'fear', 'happy', 'neutral', 'sad', 'surprise'
  ];
  // 8-class order (FER+/AffectNet style — adds 'contempt'). NOTE: if your
  // model was trained in a different order, reorder this list to match, or
  // emotion labels will be mismapped. Detection won't crash either way.
  static const List<String> emotionLabels8 = [
    'neutral', 'happy', 'surprise', 'sad', 'angry', 'disgust', 'fear', 'contempt'
  ];
  static const Set<String> distressEmotions = {'angry', 'disgust', 'fear', 'sad'};

  // ──── Motion Detection Config ────
  static const List<String> motionLabels = [
    'WALKING', 'WALKING_UPSTAIRS', 'WALKING_DOWNSTAIRS',
    'SITTING', 'STANDING', 'LAYING'
  ];

  /// Initialize all TFLite models. Models live in `frontend/assets/models/`.
  Future<void> initialize() async {
    _emotionInterpreter = await _tryLoad('assets/models/emotion_model.tflite', 'Emotion');
    _audioInterpreter = await _tryLoad('assets/models/audio_model.tflite', 'Audio');
    _motionInterpreter = await _tryLoad('assets/models/motion_model.tflite', 'Motion');

    _isInitialized = true;
    debugPrint(
      '🧠 AI init: emotion=$emotionModelLoaded audio=$audioModelLoaded motion=$motionModelLoaded',
    );
  }

  Future<Interpreter?> _tryLoad(String asset, String label) async {
    try {
      final interp = await Interpreter.fromAsset(asset);
      final inS = interp.getInputTensor(0).shape;
      final outS = interp.getOutputTensor(0).shape;
      debugPrint('✅ $label model loaded — input=$inS output=$outS');
      return interp;
    } catch (e) {
      debugPrint('⚠️ $label model not loaded: $e');
      return null;
    }
  }

  /// Detect emotion from a grayscale face image (48x48). Adapts to the model's
  /// actual output class count (7 or 8).
  Map<String, dynamic>? detectEmotion(Float32List grayscalePixels) {
    final interp = _emotionInterpreter;
    if (interp == null) return null;

    try {
      final inShape = interp.getInputTensor(0).shape; // e.g. [1,48,48,1]
      final inElems = inShape.fold<int>(1, (a, b) => a * b);
      if (inElems != grayscalePixels.length) {
        if (!_emotionShapeWarned) {
          _emotionShapeWarned = true;
          debugPrint('⚠️ Emotion model expects $inElems input values '
              '(shape $inShape) but app produced ${grayscalePixels.length}. '
              'Emotion detection disabled until they match.');
        }
        return null;
      }
      final input = grayscalePixels.reshape(inShape);

      final outShape = interp.getOutputTensor(0).shape; // e.g. [1,7] or [1,8]
      final numClasses = outShape[outShape.length - 1];
      final output = List.filled(numClasses, 0.0).reshape([1, numClasses]);

      interp.run(input, output);

      final probs = _softmax((output[0] as List).cast<double>());
      int maxIdx = 0;
      double maxProb = probs[0];
      for (int i = 1; i < probs.length; i++) {
        if (probs[i] > maxProb) {
          maxProb = probs[i];
          maxIdx = i;
        }
      }

      final labels = numClasses == 8
          ? emotionLabels8
          : (numClasses == 7 ? emotionLabels7 : null);
      final label = (labels != null && maxIdx < labels.length)
          ? labels[maxIdx]
          : 'class$maxIdx';

      return {
        'label': label,
        'confidence': maxProb,
        'isDistress': distressEmotions.contains(label),
      };
    } catch (e) {
      debugPrint('Emotion detection error: $e');
      return null;
    }
  }

  /// Detect distress from MFCC audio features. Reads the model's expected input
  /// size; if the app's feature vector doesn't match (e.g. the model wants
  /// MFCC+deltas), it skips gracefully and logs the expected shape once.
  Map<String, dynamic>? detectAudioDistress(Float32List mfccFeatures) {
    final interp = _audioInterpreter;
    if (interp == null) return null;

    try {
      final inShape = interp.getInputTensor(0).shape;
      final inElems = inShape.fold<int>(1, (a, b) => a * b);
      if (inElems != mfccFeatures.length) {
        if (!_audioShapeWarned) {
          _audioShapeWarned = true;
          debugPrint('⚠️ Audio model expects $inElems input values '
              '(shape $inShape) but app produced ${mfccFeatures.length} MFCC '
              'values. Likely trained with MFCC + delta + delta-delta. '
              'Scream detection disabled until features match the model.');
        }
        return null;
      }
      final input = mfccFeatures.reshape(inShape);

      final outShape = interp.getOutputTensor(0).shape;
      final numClasses = outShape[outShape.length - 1];
      final output = List.filled(numClasses, 0.0).reshape([1, numClasses]);

      interp.run(input, output);

      final probs = _softmax((output[0] as List).cast<double>());
      int maxIdx = 0;
      double maxProb = probs[0];
      for (int i = 1; i < probs.length; i++) {
        if (probs[i] > maxProb) {
          maxProb = probs[i];
          maxIdx = i;
        }
      }

      // Treat the first classes as the "danger" set (scream/shout/cry) per
      // common training order. Adjust if your model uses a different order.
      const dangerClassIndices = {0, 1, 2, 3};
      final isDanger = dangerClassIndices.contains(maxIdx) && maxProb > 0.5;

      return {
        'classIndex': maxIdx,
        'confidence': maxProb,
        'isDanger': isDanger,
      };
    } catch (e) {
      debugPrint('Audio detection error: $e');
      return null;
    }
  }

  /// Detect activity from motion sensor data.
  Map<String, dynamic>? detectMotion(Float32List sensorFeatures) {
    final interp = _motionInterpreter;
    if (interp == null) return null;

    try {
      final inputShape = interp.getInputTensor(0).shape;
      final inElems = inputShape.fold<int>(1, (a, b) => a * b);
      if (inElems != sensorFeatures.length) return null;
      final inputTensor = sensorFeatures.reshape(inputShape);

      final outShape = interp.getOutputTensor(0).shape;
      final numClasses = outShape[outShape.length - 1];
      final output = List.filled(numClasses, 0.0).reshape([1, numClasses]);

      interp.run(inputTensor, output);

      final probs = _softmax((output[0] as List).cast<double>());
      int maxIdx = 0;
      double maxProb = probs[0];
      for (int i = 1; i < probs.length; i++) {
        if (probs[i] > maxProb) {
          maxProb = probs[i];
          maxIdx = i;
        }
      }

      final activity =
          maxIdx < motionLabels.length ? motionLabels[maxIdx] : 'class$maxIdx';
      final isFallRisk = activity == 'LAYING' && maxProb > 0.7;

      return {
        'activity': activity,
        'confidence': maxProb,
        'isFallRisk': isFallRisk,
      };
    } catch (e) {
      debugPrint('Motion detection error: $e');
      return null;
    }
  }

  /// Convert raw model logits to a probability distribution (sums to 1).
  /// Models that already output softmax are unaffected in argmax; only the
  /// confidence value is normalised. Fixes "confidence > 100%".
  List<double> _softmax(List<double> logits) {
    if (logits.isEmpty) return logits;
    final maxLogit = logits.reduce(max);
    final exps = logits.map((l) => exp(l - maxLogit)).toList();
    final sumExp = exps.fold<double>(0.0, (a, b) => a + b);
    if (sumExp == 0) return logits;
    return exps.map((e) => e / sumExp).toList();
  }

  void dispose() {
    _emotionInterpreter?.close();
    _audioInterpreter?.close();
    _motionInterpreter?.close();
  }
}
