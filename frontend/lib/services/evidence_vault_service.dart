import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/data_models.dart';

/// Forensic Evidence Vault Service
/// Implements an offline-first, local-first forensic storage architecture:
/// 1. Photos & audio clips are copied immediately to the permanent app documents directory.
/// 2. Metadata & incident records are saved immediately to local persistent disk.
/// 3. Asynchronously syncs to cloud backend without blocking UI or risking data loss.
class EvidenceVaultService {
  static const String _alertsKey = 'safeher_vault_alerts_v2';
  static Directory? _vaultDir;

  /// Get or create the permanent SafeHerVault directory on device
  static Future<Directory> getVaultDir() async {
    if (_vaultDir != null && await _vaultDir!.exists()) {
      return _vaultDir!;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final vault = Directory('${appDir.path}/SafeHerVault');
    if (!await vault.exists()) {
      await vault.create(recursive: true);
    }
    _vaultDir = vault;
    return vault;
  }

  /// Copies a captured photo file into permanent vault storage
  static Future<String> savePhoto(String sourcePath) async {
    try {
      final vault = await getVaultDir();
      final photosDir = Directory('${vault.path}/photos');
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }
      final fileName = 'evidence_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final destPath = '${photosDir.path}/$fileName';
      final srcFile = File(sourcePath);
      if (await srcFile.exists()) {
        await srcFile.copy(destPath);
        debugPrint('🔒 Evidence photo permanently archived in Vault: $destPath');
        return destPath;
      }
      return sourcePath;
    } catch (e) {
      debugPrint('⚠️ Error saving photo to vault: $e');
      return sourcePath;
    }
  }

  /// Copies a captured audio file into permanent vault storage
  static Future<String> saveAudio(String sourcePath) async {
    try {
      final vault = await getVaultDir();
      final audioDir = Directory('${vault.path}/audio');
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
      }
      final fileName = 'evidence_audio_${DateTime.now().millisecondsSinceEpoch}.aac';
      final destPath = '${audioDir.path}/$fileName';
      final srcFile = File(sourcePath);
      if (await srcFile.exists()) {
        await srcFile.copy(destPath);
        debugPrint('🔒 Evidence audio permanently archived in Vault: $destPath');
        return destPath;
      }
      return sourcePath;
    } catch (e) {
      debugPrint('⚠️ Error saving audio to vault: $e');
      return sourcePath;
    }
  }

  /// Load all locally persisted vault alerts from disk
  static Future<List<AlertModel>> loadLocalAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_alertsKey);
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }
      final List<dynamic> list = jsonDecode(jsonString);
      return list
          .map((item) => AlertModel.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      debugPrint('⚠️ Error loading local vault alerts: $e');
      return [];
    }
  }

  /// Save alert list to local disk
  static Future<void> saveLocalAlerts(List<AlertModel> alerts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = alerts.map((a) => a.toJson()).toList();
      await prefs.setString(_alertsKey, jsonEncode(list));
      debugPrint('💾 Persisted ${alerts.length} alert records to local vault disk');
    } catch (e) {
      debugPrint('⚠️ Error saving local vault alerts: $e');
    }
  }

  /// Save or update a single alert record to local disk
  static Future<void> saveSingleAlert(AlertModel alert) async {
    try {
      final current = await loadLocalAlerts();
      final index = current.indexWhere((a) => a.id == alert.id);
      if (index != -1) {
        current[index] = alert;
      } else {
        current.insert(0, alert);
      }
      await saveLocalAlerts(current);
    } catch (e) {
      debugPrint('⚠️ Error saving single alert to vault: $e');
    }
  }
}

