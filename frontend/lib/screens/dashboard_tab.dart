/// Dashboard Tab
/// Shows safety status, monitoring state, quick stats, and recent alerts.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/sensor_service.dart';
import '../services/safety_monitoring_service.dart';
import '../services/alert_service.dart';
import '../themes/app_theme.dart';
import 'settings_screen.dart';
import 'evidence_screen.dart';
import 'package:camera/camera.dart';

class DashboardTab extends StatelessWidget {
  final VoidCallback? onTriggerSos;
  const DashboardTab({super.key, this.onTriggerSos});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeHer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_special_outlined, size: 26),
            tooltip: 'Evidence Vault',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EvidenceScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 28),
            tooltip: 'Settings',
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
            splashRadius: 28,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Greeting
            Consumer<AuthService>(
              builder: (_, auth, __) {
                return Text(
                  'Hello, ${auth.currentUser?.name.split(' ').first ?? 'there'} 👋',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Safety Status Card
            Consumer2<SafetyMonitoringService, SensorService>(
              builder: (_, safety, sensor, __) {
                final isMonitoring = safety.isMonitoring;
                final isFallDetected = sensor.fallDetected;

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isFallDetected
                          ? [AppColors.emergency, AppColors.emergency.withOpacity(0.8)]
                          : isMonitoring
                              ? [AppColors.safe, AppColors.safe.withOpacity(0.8)]
                              : [Colors.grey, Colors.grey.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: (isFallDetected
                                ? AppColors.emergency
                                : isMonitoring
                                    ? AppColors.safe
                                    : Colors.grey)
                            .withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        isFallDetected
                            ? Icons.warning_amber_rounded
                            : isMonitoring
                                ? Icons.shield
                                : Icons.shield_outlined,
                        size: 56,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isFallDetected
                            ? 'DANGER DETECTED'
                            : isMonitoring
                                ? 'You\'re Protected'
                                : 'Monitoring Off',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isFallDetected
                            ? 'A fall was detected. Are you okay?'
                            : isMonitoring
                                ? 'Sensors & distress detection active'
                                : 'Tap to start monitoring',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      if (isFallDetected) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            ElevatedButton(
                              onPressed: () => safety.confirmSafe(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppColors.emergency,
                              ),
                              child: const Text('I\'m OK'),
                            ),
                            if (onTriggerSos != null)
                              ElevatedButton.icon(
                                onPressed: onTriggerSos,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppColors.emergency,
                                ),
                                icon: const Icon(Icons.send_rounded, size: 18),
                                label: const Text('Send Evidences'),
                              ),
                          ],
                        ),
                      ],
                      if (!isMonitoring) ...[
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => safety.startMonitoring(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.safe,
                          ),
                          child: const Text('Start Monitoring'),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Quick Stats
            Row(
              children: [
                _StatCard(
                  icon: Icons.location_on,
                  label: 'Location',
                  value: Consumer<SensorService>(
                    builder: (_, s, __) => Text(
                      s.currentPosition != null
                          ? '${s.latitude.toStringAsFixed(4)},\n${s.longitude.toStringAsFixed(4)}'
                          : 'Loading...',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  color: AppColors.accent,
                ),
                const SizedBox(width: 12),
                _StatCard(
                  icon: Icons.notifications_active,
                  label: 'Total Alerts',
                  value: Consumer<AlertService>(
                    builder: (_, a, __) => Text(
                      '${a.totalAlerts}',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                    ),
                  ),
                  color: AppColors.warning,
                ),
                const SizedBox(width: 12),
                _StatCard(
                  icon: Icons.people,
                  label: 'Contacts',
                  value: Consumer<AuthService>(
                    builder: (_, a, __) => Text(
                      '${a.currentUser?.emergencyContacts.length ?? 0}',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                    ),
                  ),
                  color: AppColors.primary,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // AI Facial Emotion Monitor & Front Camera Card
            Consumer<SafetyMonitoringService>(
              builder: (ctx, safety, _) {
                final cam = safety.cameraController;
                final isCamReady = cam != null && cam.value.isInitialized;
                final emotion = safety.lastEmotionResult;
                final emotionLabel = emotion?['label']?.toString().toUpperCase() ?? 'DETECTING...';
                final confidence = emotion != null
                    ? ((emotion['confidence'] as double) * 100).toStringAsFixed(0)
                    : '--';
                final isDistress = emotion?['isDistress'] == true;

                return Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Row(
                                children: [
                                  Icon(Icons.face_retouching_natural_rounded, color: AppColors.primary, size: 22),
                                  SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'AI Emotion HUD',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDistress
                                    ? AppColors.emergency.withOpacity(0.15)
                                    : AppColors.safe.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                isDistress ? '⚠️ DISTRESS' : '✅ NORMAL',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDistress ? AppColors.emergency : AppColors.safe,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (isCamReady) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              height: 190,
                              width: double.infinity,
                              color: Colors.black,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: FittedBox(
                                      fit: BoxFit.cover,
                                      clipBehavior: Clip.hardEdge,
                                      child: SizedBox(
                                        width: cam.value.previewSize != null
                                            ? cam.value.previewSize!.height
                                            : 1,
                                        height: cam.value.previewSize != null
                                            ? cam.value.previewSize!.width
                                            : 1,
                                        child: CameraPreview(cam),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 8,
                                    left: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.75),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Emotion: $emotionLabel ($confidence%)',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'Live',
                                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final messenger = ScaffoldMessenger.of(ctx);
                                    final alertService = ctx.read<AlertService>();
                                    final sensor = ctx.read<SensorService>();
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text('Capturing forensic snapshot to Vault...'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                    final photoPath = await safety.captureSilentPhoto();
                                    if (photoPath != null) {
                                      await alertService.recordLocalEvidenceAlert(
                                        type: 'Snapshot Evidence',
                                        latitude: sensor.latitude,
                                        longitude: sensor.longitude,
                                        evidenceUrls: [photoPath],
                                      );
                                    }
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(photoPath != null ? '✅ Snapshot recorded in Evidence Vault!' : 'Camera busy, try again'),
                                        backgroundColor: photoPath != null ? AppColors.safe : AppColors.emergency,
                                        action: photoPath != null
                                            ? SnackBarAction(
                                                label: 'View Vault',
                                                textColor: Colors.white,
                                                onPressed: () => Navigator.push(
                                                  ctx,
                                                  MaterialPageRoute(builder: (_) => const EvidenceScreen()),
                                                ),
                                              )
                                            : null,
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.camera_alt, size: 18),
                                  label: const Text('Capture Snapshot to Vault'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          Container(
                            height: 120,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.videocam_outlined, size: 36, color: Colors.grey),
                                const SizedBox(height: 6),
                                const Text(
                                  'Front Camera is initializing for facial expression AI...',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 6),
                                TextButton.icon(
                                  onPressed: () => safety.initCameraManually(),
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Start AI Camera'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            // Evidence Vault Banner Card
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EvidenceScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.lightCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.folder_special_rounded, color: AppColors.primary, size: 32),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Evidence Vault 📁',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'View captured front-camera photos, audio recordings & maps',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 28),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Recent Alerts
            const Text(
              'Recent Alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            Consumer<AlertService>(
              builder: (_, alertService, __) {
                if (alertService.alerts.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Column(
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 48, color: AppColors.safe),
                          SizedBox(height: 12),
                          Text('No alerts yet. Stay safe!',
                              style: TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: alertService.alerts.take(3).map((alert) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Text(alert.typeEmoji, style: const TextStyle(fontSize: 28)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(alert.typeLabel,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(
                                  _formatDate(alert.createdAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _StatusChip(status: alert.status),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}

// ──── Stat Card Widget ────
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: value,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──── Status Chip Widget ────
class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'resolved':
        color = AppColors.safe;
        break;
      case 'false_alarm':
        color = Colors.grey;
        break;
      case 'notified':
        color = AppColors.warning;
        break;
      default:
        color = AppColors.emergency;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
