/// Alerts Screen
/// Displays full alert history with filtering and detail view.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/alert_service.dart';
import '../models/data_models.dart';
import '../themes/app_theme.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alert History')),
      body: Consumer<AlertService>(
        builder: (context, alertService, _) {
          if (alertService.isLoading && alertService.alerts.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (alertService.alerts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_user, size: 80,
                      color: AppColors.safe.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  const Text('No alerts yet',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('You\'re safe! Alerts will appear here.',
                      style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color)),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => alertService.fetchAlerts(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: alertService.alerts.length,
              itemBuilder: (context, index) {
                final alert = alertService.alerts[index];
                return _AlertCard(alert: alert);
              },
            ),
          );
        },
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final AlertModel alert;
  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showAlertDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Type emoji
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _typeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(alert.typeEmoji, style: const TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(width: 16),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert.typeLabel,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(
                      _formatDateTime(alert.createdAt),
                      style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).textTheme.bodySmall?.color),
                    ),
                    if (alert.confidence != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Confidence: ${(alert.confidence! * 100).toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 12, color: _typeColor),
                      ),
                    ],
                  ],
                ),
              ),

              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  alert.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _statusColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color get _typeColor {
    switch (alert.type) {
      case 'scream': return Colors.orange;
      case 'fall': return AppColors.warning;
      case 'panic_button': return AppColors.emergency;
      case 'emotion': return AppColors.accent;
      default: return AppColors.primary;
    }
  }

  Color get _statusColor {
    switch (alert.status) {
      case 'resolved': return AppColors.safe;
      case 'false_alarm': return Colors.grey;
      case 'notified': return AppColors.warning;
      default: return AppColors.emergency;
    }
  }

  void _showAlertDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('${alert.typeEmoji} ${alert.typeLabel}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              _detailRow('Time', _formatDateTime(alert.createdAt)),
              _detailRow('Status', alert.status.toUpperCase()),
              if (alert.confidence != null)
                _detailRow('AI Confidence',
                    '${(alert.confidence! * 100).toStringAsFixed(1)}%'),
              _detailRow('Location',
                  '${alert.location.latitude.toStringAsFixed(5)}, ${alert.location.longitude.toStringAsFixed(5)}'),
              const SizedBox(height: 16),

              // Open in Maps
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(alert.location.mapsLink)),
                  icon: const Icon(Icons.map),
                  label: const Text('Open in Google Maps'),
                ),
              ),

              // Resolve / False Alarm buttons
              if (alert.status == 'triggered' || alert.status == 'notified') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          context.read<AlertService>().updateAlertStatus(
                              alert.id, 'resolved');
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.safe),
                        child: const Text('Mark Resolved'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          context.read<AlertService>().updateAlertStatus(
                              alert.id, 'false_alarm');
                          Navigator.pop(ctx);
                        },
                        child: const Text('False Alarm'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}
