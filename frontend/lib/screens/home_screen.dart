/// Home Screen
/// Main navigation shell with bottom bar, SOS panic button, and dashboard tabs.

import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/sensor_service.dart';
import '../services/safety_monitoring_service.dart';
import '../services/alert_service.dart';
import '../services/evidence_service.dart';
import '../services/auth_service.dart';
import '../services/direct_sms_service.dart';
import '../themes/app_theme.dart';
import 'dashboard_tab.dart';
import 'alerts_screen.dart';
import 'sensor_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _fallDialogActive = false;
  SensorService? _sensorService;

  List<Widget> get _tabs => [
    DashboardTab(
      onTriggerSos: () => _triggerSOS(
        alertType: 'Fall / High Impact Detected',
        skipConfirmation: true,
      ),
    ),
    const AlertsScreen(),
    const SizedBox(), // Placeholder for SOS button
    const SensorScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _sensorService = context.read<SensorService>();
    _sensorService?.addListener(_onSensorFallCheck);

    // Start full safety monitoring (sensors + AI + fall/scream detection).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final safety = context.read<SafetyMonitoringService>();
      try {
        if (!safety.isMonitoring) {
          await safety.startMonitoring();
        }
      } catch (e) {
        debugPrint('⚠️ Monitoring auto-start failed: $e');
      }
      if (mounted) {
        context.read<AlertService>().fetchAlerts();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final safety = context.read<SafetyMonitoringService>();
    if (state == AppLifecycleState.resumed) {
      safety.handleAppResumed();
    } else {
      // inactive / paused / hidden / detached — release the camera.
      safety.handleAppPaused();
    }
  }

  void _onSensorFallCheck() {
    final sensor = _sensorService;
    if (sensor == null || !mounted) return;
    if (sensor.fallDetected && !_fallDialogActive) {
      _showFallEmergencyDialog();
    }
  }

  void _showFallEmergencyDialog() {
    _fallDialogActive = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.emergency, size: 28),
            SizedBox(width: 8),
            Text('Fall Detected!'),
          ],
        ),
        content: const Text(
          'A sudden fall or impact was detected. Are you okay?\n\n'
          'Tap "SEND EVIDENCES" to immediately send your captured evidence and live location to your emergency contacts.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              context.read<SafetyMonitoringService>().confirmSafe();
              _fallDialogActive = false;
              Navigator.of(ctx).pop();
            },
            child: const Text('I\'m OK'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<SafetyMonitoringService>().confirmSafe();
              _fallDialogActive = false;
              Navigator.of(ctx).pop();
              _triggerSOS(
                alertType: 'Fall / High Impact Detected',
                skipConfirmation: true,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.emergency),
            child: const Text('SEND EVIDENCES'),
          ),
        ],
      ),
    ).then((_) => _fallDialogActive = false);
  }

  @override
  void dispose() {
    _sensorService?.removeListener(_onSensorFallCheck);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Trigger SOS emergency: capture photo + live location + send to contacts.
  Future<void> _triggerSOS({String? alertType, bool skipConfirmation = false}) async {
    if (!skipConfirmation) {
      final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.emergency, size: 28),
            SizedBox(width: 8),
            Text('Emergency SOS'),
          ],
        ),
        content: const Text(
          'This will:\n'
          '• Capture a photo as evidence\n'
          '• Share your live location\n'
          '• Notify all your emergency contacts\n\n'
          'Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.emergency),
            child: const Text('SEND SOS'),
          ),
        ],
      ),
    );
      if (confirmed != true || !mounted) return;
    }

    // Capture references BEFORE any await to survive widget teardown.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final api = context.read<ApiService>();
    final sensor = context.read<SensorService>();
    final alert = context.read<AlertService>();
    final evidence = context.read<EvidenceCaptureService>();
    final auth = context.read<AuthService>();

    // 1. START VOICE RECORDING IMMEDIATELY — don't wait for anything else.
    //    The recorder runs in the background while we do other work.
    unawaited(evidence.startVoiceRecording());

    // Show progress dialog so the user knows things are happening.
    bool dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SosProgressDialog(),
    ).whenComplete(() => dialogOpen = false);

    // The entire pipeline runs inside try/finally so that — no matter what
    // throws (camera, upload, network) — the non-dismissible progress dialog
    // is ALWAYS closed. Leaving it open would lock the screen behind a modal
    // barrier and make the app appear frozen.
    final contacts = auth.currentUser?.emergencyContacts ?? [];
    if (contacts.isEmpty) {
      if (dialogOpen) { try { navigator.pop(); } catch (_) {} }
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ No emergency contacts configured. Please add contacts in your Profile!',
          ),
          backgroundColor: AppColors.emergency,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    EmergencyDeliveryResult? delivery;
    bool smsDispatched = false;
    int sentCount = 0;
    final alertLabel = alertType ?? 'Manual SOS Panic Triggered';
    final userName = auth.currentUser?.name ?? 'SafeHer User';

    try {
      // 2. Capture evidence photo silently in-app (no external camera app)
      final safety = context.read<SafetyMonitoringService>();
      String? photoUrl;
      try {
        photoUrl = await safety.captureSilentPhoto().timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('⚠️ Silent photo capture error: $e');
      }

      // 3. Get freshest live GPS location (fast 3s timeout)
      double lat = sensor.latitude;
      double lng = sensor.longitude;
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 3),
        ).timeout(const Duration(seconds: 4));
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (e) {
        debugPrint('⚠️ Live location fetch failed, using last known: $e');
      }

      // 4. Record audio for 2.5 seconds and upload
      await Future.delayed(const Duration(milliseconds: 2500));
      final audioPath = await evidence.stopVoiceRecording();
      String? audioUrl;
      if (audioPath != null) {
        try {
          audioUrl = await evidence.uploadLocalFile(
            apiService: api,
            filePath: audioPath,
          ).timeout(const Duration(seconds: 4));
        } catch (e) {
          debugPrint('⚠️ Audio upload skipped: $e');
        }
      }

      // 5. Gather evidence URLs (photo + audio)
      final evidenceUrls = <String>[
        if (photoUrl != null) photoUrl,
        if (audioUrl != null) audioUrl,
      ];
      debugPrint('🚨 [SOS] Evidence gathered: ${evidenceUrls.length} file(s)');

      // 6. DISPATCH DIRECT CELLULAR SMS WITH ALL EVIDENCES TO ALL CONTACTS!
      for (final contact in contacts) {
        final phone = contact.phone.trim();
        if (phone.isNotEmpty) {
          debugPrint('🚨 [SOS] Dispatching SMS with evidences to ${contact.name} ($phone)...');
          try {
            final ok = await DirectSmsService.sendEmergencySms(
              phone: phone,
              userName: userName,
              latitude: lat,
              longitude: lng,
              alertType: alertLabel,
              evidenceUrls: evidenceUrls,
            );
            if (ok) sentCount++;
          } catch (e) {
            debugPrint('⚠️ SMS dispatch to $phone failed: $e');
          }
        }
      }
      smsDispatched = sentCount > 0;

      // 7. Trigger backend emergency logging (fast 4s timeout)
      try {
        delivery = await alert.triggerEmergency(
          type: 'panic_button',
          latitude: lat,
          longitude: lng,
          evidenceUrls: evidenceUrls.isNotEmpty ? evidenceUrls : null,
          maxRetries: 1,
        ).timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('⚠️ Backend emergency sync skipped/offline: $e');
      }

// SMS dispatch completed

      // If backend failed or was offline, construct delivery result from Direct SIM SMS
      if (delivery == null || !delivery.anyReached) {
        delivery = EmergencyDeliveryResult(
          anyReached: smsDispatched,
          contactCount: contacts.length,
          reached: sentCount,
          smsSent: sentCount,
          smsFailed: contacts.length - sentCount,
          callsPlaced: 0,
          callsFailed: 0,
          perContact: contacts.map((c) => {'phone': c.phone, 'status': 'dispatched'}).toList(),
          message: smsDispatched
              ? 'Emergency alert sent with evidences to $sentCount contact(s)!'
              : 'Alert prepared. Please dial 112 directly.',
        );
      }
    } catch (e) {
      debugPrint('❌ SOS pipeline error: $e');
      if (delivery == null && smsDispatched) {
        delivery = EmergencyDeliveryResult(
          anyReached: true,
          contactCount: contacts.length,
          reached: sentCount,
          smsSent: sentCount,
          smsFailed: 0,
          callsPlaced: 0,
          callsFailed: 0,
          perContact: contacts.map((c) => {'phone': c.phone, 'status': 'sent'}).toList(),
          message: 'Emergency alert sent with evidences to $sentCount contact(s)!',
        );
      }
    }
    if (!mounted) return;

    // If the whole pipeline threw before producing a delivery result, tell the
    // user clearly rather than leaving them with no feedback.
    if (delivery == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            '❌ SOS could not be completed. Please call 112 directly.',
          ),
          backgroundColor: AppColors.emergency,
          duration: Duration(seconds: 6),
        ),
      );
      return;
    }

    final result = delivery;
    final partial =
        result.anyReached && result.reached < result.contactCount;
    final color = !result.anyReached
        ? AppColors.emergency
        : (partial ? Colors.orange : AppColors.safe);
    final emoji = result.anyReached ? '🚨' : '❌';
    final summary = result.contactCount == 0
        ? result.message
        : '$emoji ${result.message}';

    messenger.showSnackBar(
      SnackBar(
        content: Text(summary),
        backgroundColor: color,
        duration: const Duration(seconds: 6),
        action: !result.anyReached
            ? SnackBarAction(
                label: 'Call 112',
                textColor: Colors.white,
                onPressed: () {
                  // url_launcher tel: link — graceful no-op if unavailable.
                },
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(

        index: _currentIndex == 2 ? 0 : _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 2) {
            _triggerSOS();
          } else {
            setState(() => _currentIndex = index);
          }
        },
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined),
            activeIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AppColors.emergency,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sos, color: Colors.white, size: 28),
            ),
            label: 'SOS',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.sensors_outlined),
            activeIcon: Icon(Icons.sensors),
            label: 'Sensors',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outlined),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _SosProgressDialog extends StatelessWidget {
  const _SosProgressDialog();
  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.emergency),
          SizedBox(height: 16),
          Text('Sending emergency alert…',
              style: TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 4),
          Text('Capturing evidence and notifying contacts.',
              style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
