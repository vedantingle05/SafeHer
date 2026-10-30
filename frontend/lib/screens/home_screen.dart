/// Home Screen
/// Main navigation shell with bottom bar, SOS panic button, and dashboard tabs.

import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/sensor_service.dart';
import '../services/safety_monitoring_service.dart';
import '../services/alert_service.dart';
import '../services/evidence_service.dart';
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

  final List<Widget> _tabs = const [
    DashboardTab(),
    AlertsScreen(),
    SizedBox(), // Placeholder for SOS button
    SensorScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Observe app lifecycle so we can release the camera when backgrounded.
    // Without this, the camera SurfaceView holds its buffers across a
    // background/resume cycle and the renderer deadlocks (BLASTBufferQueue
    // "can't acquire next buffer"), freezing all touch input on reopen.
    WidgetsBinding.instance.addObserver(this);

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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Trigger SOS emergency: capture photo + live location + send to contacts.
  Future<void> _triggerSOS() async {
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

    // Capture references BEFORE any await to survive widget teardown.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final api = context.read<ApiService>();
    final sensor = context.read<SensorService>();
    final alert = context.read<AlertService>();
    final evidence = context.read<EvidenceCaptureService>();

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
    EmergencyDeliveryResult? delivery;
    try {
      // 2. Capture an evidence photo (opens camera UI briefly).
      final photoUrl = await evidence.captureAndUploadPhoto(apiService: api);

      // 3. Get the freshest location possible.
      double lat = sensor.latitude;
      double lng = sensor.longitude;
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 5),
        ).timeout(const Duration(seconds: 6));
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (e) {
        debugPrint('⚠️ Live location fetch failed, using last known: $e');
      }

      // 4. Let audio continue a few seconds so there is useful content.
      await Future.delayed(const Duration(seconds: 4));
      final audioPath = await evidence.stopVoiceRecording();
      String? audioUrl;
      if (audioPath != null) {
        audioUrl = await evidence.uploadLocalFile(
          apiService: api,
          filePath: audioPath,
        );
      }

      // 5. Trigger emergency on the backend (alerts + SMS to contacts).
      final evidenceUrls = <String>[
        if (photoUrl != null) photoUrl,
        if (audioUrl != null) audioUrl,
      ];
      delivery = await alert.triggerEmergency(
        type: 'panic_button',
        latitude: lat,
        longitude: lng,
        evidenceUrls: evidenceUrls.isNotEmpty ? evidenceUrls : null,
      );
    } catch (e) {
      debugPrint('❌ SOS pipeline error: $e');
    } finally {
      if (dialogOpen) {
        try {
          navigator.pop();
        } catch (_) {}
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
