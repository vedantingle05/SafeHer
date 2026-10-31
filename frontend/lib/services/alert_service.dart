/// AlertService
/// Manages safety alerts: create, fetch history, trigger emergencies.

import 'package:flutter/foundation.dart';
import '../models/data_models.dart';
import 'dart:async';
import 'api_service.dart';
import 'evidence_vault_service.dart';

/// Outcome of a /api/emergency call. Lets the UI render exact per-contact
/// delivery information rather than a misleading "alert sent" toast.
class EmergencyDeliveryResult {
  final bool anyReached;
  final int contactCount;
  final int reached;
  final int smsSent;
  final int smsFailed;
  final int callsPlaced;
  final int callsFailed;
  final List<Map<String, dynamic>> perContact;
  final String? errorCode;
  final String message;

  EmergencyDeliveryResult({
    required this.anyReached,
    required this.contactCount,
    required this.reached,
    required this.smsSent,
    required this.smsFailed,
    required this.callsPlaced,
    required this.callsFailed,
    required this.perContact,
    required this.message,
    this.errorCode,
  });

  factory EmergencyDeliveryResult.fromResponse(Map<String, dynamic> body) {
    final delivery = (body['data']?['delivery'] ?? {}) as Map<String, dynamic>;
    return EmergencyDeliveryResult(
      anyReached: body['success'] == true,
      contactCount: (delivery['contacts'] as num?)?.toInt() ?? 0,
      reached: (delivery['reached'] as num?)?.toInt() ?? 0,
      smsSent: (delivery['smsSent'] as num?)?.toInt() ?? 0,
      smsFailed: (delivery['smsFailed'] as num?)?.toInt() ?? 0,
      callsPlaced: (delivery['callsPlaced'] as num?)?.toInt() ?? 0,
      callsFailed: (delivery['callsFailed'] as num?)?.toInt() ?? 0,
      perContact: List<Map<String, dynamic>>.from(
        (delivery['perContact'] as List?) ?? const [],
      ),
      message: (body['message'] as String?) ??
          (body['success'] == true
              ? 'Emergency alert sent.'
              : 'Emergency alert failed.'),
      errorCode: body['code'] as String?,
    );
  }

  factory EmergencyDeliveryResult.failure(String message, {String? code}) {
    return EmergencyDeliveryResult(
      anyReached: false,
      contactCount: 0,
      reached: 0,
      smsSent: 0,
      smsFailed: 0,
      callsPlaced: 0,
      callsFailed: 0,
      perContact: const [],
      message: message,
      errorCode: code,
    );
  }
}

class AlertService extends ChangeNotifier {
  final ApiService apiService;

  List<AlertModel> _alerts = [];
  bool _isLoading = false;
  String? _error;
  EmergencyDeliveryResult? _lastDelivery;

  AlertService({required this.apiService}) {
    _loadInitialAlerts();
  }

  Future<void> _loadInitialAlerts() async {
    final cached = await EvidenceVaultService.loadLocalAlerts();
    if (cached.isNotEmpty) {
      _alerts = cached;
      notifyListeners();
    }
  }

  /// Creates a local forensic evidence record immediately on device and saves to persistent storage.
  /// Also kicks off background cloud upload to backend without blocking UI.
  Future<AlertModel> recordLocalEvidenceAlert({
    required String type,
    required double latitude,
    required double longitude,
    required List<String> evidenceUrls,
    double? confidence,
  }) async {
    final alert = AlertModel(
      id: 'vault_${DateTime.now().millisecondsSinceEpoch}',
      userId: 'local_user',
      type: type,
      location: AlertLocation(
        latitude: latitude,
        longitude: longitude,
      ),
      status: 'active',
      confidence: confidence ?? 0.95,
      evidenceUrls: List<String>.from(evidenceUrls),
      createdAt: DateTime.now(),
    );

    // 1. Immediately insert at top of alerts list and persist to disk
    _alerts.removeWhere((a) => a.id == alert.id);
    _alerts.insert(0, alert);
    await EvidenceVaultService.saveLocalAlerts(_alerts);
    notifyListeners();

    // 2. Background sync to cloud backend (non-blocking)
    unawaited(() async {
      try {
        final res = await apiService.post('/alert', {
          'type': type,
          'location': {'latitude': latitude, 'longitude': longitude},
          'confidence': confidence ?? 0.95,
          'evidenceUrls': evidenceUrls,
        });
        debugPrint('☁️ Local vault alert synced to backend: ${res['data']?['id']}');
      } catch (e) {
        debugPrint('ℹ️ Alert stored locally, will sync when network is online: $e');
      }
    }());

    return alert;
  }

  // ──── Getters ────
  List<AlertModel> get alerts => _alerts;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get totalAlerts => _alerts.length;
  EmergencyDeliveryResult? get lastDelivery => _lastDelivery;

  // ──── Fetch Alert History ────
  Future<void> fetchAlerts({int page = 1, int limit = 20}) async {
    _isLoading = true;
    notifyListeners();

    // First load from local persistent storage so list is NEVER empty
    final localCached = await EvidenceVaultService.loadLocalAlerts();
    if (localCached.isNotEmpty && _alerts.isEmpty) {
      _alerts = List.from(localCached);
      notifyListeners();
    }

    try {
      final response = await apiService.get('/alert?page=$page&limit=$limit');
      final alertsData = response['data']['alerts'] as List<dynamic>;
      final remoteAlerts = alertsData.map((a) => AlertModel.fromJson(a)).toList();

      // Merge remote alerts with local alerts (keep local pending ones, update matching)
      final Map<String, AlertModel> mergedMap = {};
      for (final a in localCached) {
        mergedMap[a.id] = a;
      }
      for (final r in remoteAlerts) {
        mergedMap[r.id] = r;
      }

      final mergedList = mergedMap.values.toList();
      mergedList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _alerts = mergedList;
      await EvidenceVaultService.saveLocalAlerts(_alerts);
      _error = null;
    } catch (e) {
      debugPrint('ℹ️ Using local evidence vault records (backend unavailable): $e');
      _error = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ──── Create Alert (local record) ────
  Future<AlertModel?> createAlert({
    required String type,
    required double latitude,
    required double longitude,
    double? confidence,
    List<String>? evidenceUrls,
  }) async {
    try {
      final response = await apiService.post('/alert', {
        'type': type,
        'location': {
          'latitude': latitude,
          'longitude': longitude,
        },
        if (confidence != null) 'confidence': confidence,
        if (evidenceUrls != null) 'evidenceUrls': evidenceUrls,
      });

      final alert = AlertModel.fromJson(response['data']);
      _alerts.insert(0, alert); // Add to top of list
      notifyListeners();
      return alert;
    } catch (e) {
      _error = 'Failed to create alert.';
      notifyListeners();
      return null;
    }
  }

  // ──── Trigger Full Emergency (alert + SMS + push) ────
  /// Posts to `/api/emergency` and returns a detailed delivery result.
  ///
  /// Retries up to [maxRetries] times on *network* failures (HTTP layer never
  /// responded). Application-level failures (e.g. backend returns 409
  /// NO_EMERGENCY_CONTACTS, or 0-of-N delivery) are NOT retried — they will
  /// fail the same way the second time and the user needs to see the real
  /// error immediately.
  Future<EmergencyDeliveryResult> triggerEmergency({
    required String type,
    required double latitude,
    required double longitude,
    Map<String, dynamic>? address,
    double? confidence,
    List<String>? evidenceUrls,
    int maxRetries = 2,
  }) async {
    _isLoading = true;
    notifyListeners();

    final payload = {
      'type': type,
      'location': {
        'latitude': latitude,
        'longitude': longitude,
        if (address != null) 'address': address,
      },
      if (confidence != null) 'confidence': confidence,
      if (evidenceUrls != null && evidenceUrls.isNotEmpty)
        'evidenceUrls': evidenceUrls,
    };

    debugPrint(
      '🚨 triggerEmergency type=$type lat=$latitude lng=$longitude '
      'evidence=${evidenceUrls?.length ?? 0}',
    );

    EmergencyDeliveryResult result;
    try {
      Map<String, dynamic>? response;
      Object? lastNetworkError;
      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          response = await apiService.post('/emergency', payload);
          break;
        } on ApiException catch (e) {
          // statusCode == 0 means "network never responded" — worth retrying.
          if (e.statusCode == 0 && attempt < maxRetries) {
            lastNetworkError = e;
            debugPrint('⚠️ Emergency network attempt $attempt failed; retrying');
            await Future.delayed(Duration(milliseconds: 500 * attempt));
            continue;
          }
          // 4xx/5xx — backend responded; surface the message immediately.
          result = EmergencyDeliveryResult.failure(
            _humaniseApiError(e),
            code: e.statusCode == 409 ? 'NO_EMERGENCY_CONTACTS' : null,
          );
          _lastDelivery = result;
          _error = result.message;
          notifyListeners();
          return result;
        }
      }

      if (response == null) {
        result = EmergencyDeliveryResult.failure(
          'Could not reach the backend after $maxRetries attempts. '
          'Please call 112 directly. (${lastNetworkError ?? "unknown error"})',
        );
        _lastDelivery = result;
        _error = result.message;
        notifyListeners();
        return result;
      }

      result = EmergencyDeliveryResult.fromResponse(response);
      _lastDelivery = result;
      _error = result.anyReached ? null : result.message;
      debugPrint(
        '${result.anyReached ? "✅" : "⚠️"} Emergency delivery: '
        'reached=${result.reached}/${result.contactCount} '
        'sms=${result.smsSent} calls=${result.callsPlaced}',
      );
      // Refresh alert history in the background; don't block the SOS reply.
      fetchAlerts().catchError((_) {});
      notifyListeners();
      return result;
    } catch (e) {
      debugPrint('❌ triggerEmergency unexpected: $e');
      result = EmergencyDeliveryResult.failure(
        'Unexpected error sending emergency. Please call 112 directly.',
      );
      _lastDelivery = result;
      _error = result.message;
      notifyListeners();
      return result;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String _humaniseApiError(ApiException e) {
    if (e.statusCode == 409) {
      return e.message; // backend NO_EMERGENCY_CONTACTS message is already clear.
    }
    if (e.statusCode == 401) {
      return 'Session expired. Sign in again before triggering emergency.';
    }
    if (e.statusCode >= 500) {
      return 'Server error sending emergency (${e.statusCode}). Please call 112 directly.';
    }
    return 'Emergency failed: ${e.message}';
  }

  // ──── Update Alert Status ────
  Future<bool> updateAlertStatus(String alertId, String status) async {
    try {
      await apiService.patch('/alert/$alertId/status', {'status': status});
      // Update local state
      final index = _alerts.indexWhere((a) => a.id == alertId);
      if (index != -1) {
        await fetchAlerts(); // Refresh from server
      }
      return true;
    } catch (e) {
      _error = 'Failed to update alert.';
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
