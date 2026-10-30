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

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeHer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
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
                        ElevatedButton(
                          onPressed: () => safety.confirmSafe(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.emergency,
                          ),
                          child: const Text('I\'m OK'),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            value,
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                )),
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
