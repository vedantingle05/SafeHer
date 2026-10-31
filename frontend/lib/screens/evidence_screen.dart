/// Evidence Vault Screen
/// Secure repository of all forensic evidences captured by SafeHer:
/// - Front/Rear camera photos
/// - Distress audio recordings
/// - GPS incident snapshots with Google Maps links
/// - Cloud backup and sync status

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/alert_service.dart';
import '../services/safety_monitoring_service.dart';
import '../services/evidence_service.dart';
import '../services/api_service.dart';
import '../models/data_models.dart';
import '../themes/app_theme.dart';

class EvidenceScreen extends StatefulWidget {
  const EvidenceScreen({super.key});

  @override
  State<EvidenceScreen> createState() => _EvidenceScreenState();
}

class _EvidenceScreenState extends State<EvidenceScreen> {
  bool _isCapturing = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AlertService>().fetchAlerts();
      }
    });
  }

  Future<void> _captureQuickEvidence() async {
    setState(() {
      _isCapturing = true;
      _statusMessage = 'Recording audio & capturing front camera...';
    });

    try {
      final safety = context.read<SafetyMonitoringService>();
      final evidence = context.read<EvidenceCaptureService>();
      final alert = context.read<AlertService>();

      // 1. Start audio recording
      await evidence.startVoiceRecording();

      // 2. Capture front-camera photo (permanently saved to SafeHerVault)
      final photoPath = await safety.captureSilentPhoto();

      // 3. Stop audio after 3 seconds (permanently saved to SafeHerVault)
      await Future.delayed(const Duration(seconds: 3));
      final audioPath = await evidence.stopVoiceRecording();

      final evidenceUrls = <String>[
        if (photoPath != null) photoPath,
        if (audioPath != null) audioPath,
      ];

      // 4. Record in local vault immediately (<100ms) with background cloud sync
      if (evidenceUrls.isNotEmpty) {
        await alert.recordLocalEvidenceAlert(
          type: 'Manual Evidence Capture',
          latitude: safety.sensorService.latitude,
          longitude: safety.sensorService.longitude,
          evidenceUrls: evidenceUrls,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Forensic evidence saved: ${evidenceUrls.length} file(s)'),
            backgroundColor: AppColors.safe,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Capture error: $e'),
            backgroundColor: AppColors.emergency,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _statusMessage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Evidence Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Vault',
            onPressed: () => context.read<AlertService>().fetchAlerts(),
          ),
        ],
      ),
      body: Consumer<AlertService>(
        builder: (context, alertService, _) {
          if (alertService.isLoading && alertService.alerts.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading Evidence Vault...'),
                ],
              ),
            );
          }

          final alertsWithEvidence = alertService.alerts
              .where((a) => a.evidenceUrls.isNotEmpty)
              .toList();

          int totalPhotos = 0;
          int totalAudios = 0;
          for (final a in alertsWithEvidence) {
            for (final u in a.evidenceUrls) {
              if (u.contains('.jpg') || u.contains('.png') || u.contains('.jpeg')) {
                totalPhotos++;
              } else if (u.contains('.aac') || u.contains('.m4a') || u.contains('.wav') || u.contains('.mp3')) {
                totalAudios++;
              }
            }
          }

          return RefreshIndicator(
            onRefresh: () => alertService.fetchAlerts(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Top Vault Stat Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Row(
                              children: [
                                Icon(Icons.lock_clock_rounded, color: Colors.white, size: 22),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Evidence Vault',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cloud_done_rounded, color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Synced',
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'All photos and audio recordings captured during emergencies are cryptographically logged and stored as forensic evidence.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Expanded(
                            child: _VaultStatItem(
                              icon: Icons.photo_camera_rounded,
                              label: 'Photos',
                              value: '$totalPhotos',
                            ),
                          ),
                          Expanded(
                            child: _VaultStatItem(
                              icon: Icons.mic_rounded,
                              label: 'Audio Clips',
                              value: '$totalAudios',
                            ),
                          ),
                          Expanded(
                            child: _VaultStatItem(
                              icon: Icons.warning_rounded,
                              label: 'Incidents',
                              value: '${alertsWithEvidence.length}',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Quick Capture Button
                ElevatedButton.icon(
                  onPressed: _isCapturing ? null : _captureQuickEvidence,
                  icon: _isCapturing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.camera_alt_rounded),
                  label: Flexible(
                    child: Text(
                      _isCapturing ? (_statusMessage ?? 'Capturing Evidence...') : 'Capture Test Evidence (Cam + Mic)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'Captured Incident Records',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                if (alertsWithEvidence.isEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Icon(Icons.shield_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text(
                          'No evidence files recorded yet',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'When a fall, scream, or SOS panic is triggered, photos and audio recordings will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  ...alertsWithEvidence.map((alert) => _EvidenceIncidentCard(alert: alert)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _VaultStatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _VaultStatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
      ],
    );
  }
}

class _EvidenceIncidentCard extends StatelessWidget {
  final AlertModel alert;
  const _EvidenceIncidentCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final photoUrls = alert.evidenceUrls
        .where((u) => u.contains('.jpg') || u.contains('.png') || u.contains('.jpeg'))
        .toList();

    final audioUrls = alert.evidenceUrls
        .where((u) => u.contains('.aac') || u.contains('.m4a') || u.contains('.wav') || u.contains('.mp3'))
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Incident Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.emergency.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.warning_amber_rounded, color: AppColors.emergency, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alert.typeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              _formatDate(alert.createdAt),
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(alert.location.mapsLink), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.map_rounded, size: 16),
                  label: const Text('Map'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Captured Photos
            if (photoUrls.isNotEmpty) ...[
              const Text(
                '📸 Camera Evidence Photos:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photoUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (ctx, idx) {
                    final url = photoUrls[idx];
                    return GestureDetector(
                      onTap: () => _showFullImage(ctx, url),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          children: [
                            _SmartEvidenceImage(
                              url: url,
                              width: 120,
                              height: 120,
                            ),
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.fullscreen, color: Colors.white, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Captured Audios
            if (audioUrls.isNotEmpty) ...[
              const Text(
                '🎙️ Audio Evidence Recordings:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              ...audioUrls.map((url) => _AudioEvidenceTile(url: url)),
            ],
          ],
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context, String url) {
    final isLocal = !url.startsWith('http://') && !url.startsWith('https://');
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: _SmartEvidenceImage(
                  url: url,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!isLocal)
                    TextButton.icon(
                      onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open Cloud Link'),
                    )
                  else
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_rounded, size: 14, color: Colors.green),
                        SizedBox(width: 4),
                        Text('Vault Local Copy', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _SmartEvidenceImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  const _SmartEvidenceImage({
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final isLocal = !url.startsWith('http://') && !url.startsWith('https://');
    if (isLocal || File(url).existsSync()) {
      final cleanPath = url.replaceFirst('file://', '');
      final file = File(cleanPath);
      return Image.file(
        file,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }

    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (ctx, child, progress) {
        if (progress == null) return child;
        return Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => _fallback(),
    );
  }

  Widget _fallback() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade300,
      child: const Center(
        child: Icon(Icons.photo_library_outlined, color: Colors.grey, size: 28),
      ),
    );
  }
}

class _AudioEvidenceTile extends StatelessWidget {
  final String url;
  const _AudioEvidenceTile({required this.url});

  @override
  Widget build(BuildContext context) {
    final fileName = url.split('/').last;
    final isLocal = !url.startsWith('http://') && !url.startsWith('https://');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.audiotrack_rounded, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  isLocal ? '🔒 Local Vault Audio Recording' : '☁️ Cloud Synced Audio',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              if (url.startsWith('http')) {
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Forensic audio record: $fileName'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Play'),
            style: ElevatedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

