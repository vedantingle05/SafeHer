/// Sensor Data Screen
/// Live display of all sensor readings: accelerometer, gyroscope, GPS.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sensor_service.dart';
import '../services/safety_monitoring_service.dart';
import '../themes/app_theme.dart';

class SensorScreen extends StatelessWidget {
  const SensorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sensor Data')),
      body: Consumer2<SafetyMonitoringService, SensorService>(
        builder: (context, safety, sensor, _) {
          final isMonitoring = safety.isMonitoring;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Monitoring status
                _MonitoringBanner(isMonitoring: isMonitoring),
                const SizedBox(height: 20),

                // Accelerometer
                _SensorCard(
                  title: 'Accelerometer',
                  icon: Icons.speed,
                  color: AppColors.primary,
                  readings: [
                    _Reading('X', sensor.accelX),
                    _Reading('Y', sensor.accelY),
                    _Reading('Z', sensor.accelZ),
                    _Reading('Magnitude', sensor.accelMagnitude),
                  ],
                ),
                const SizedBox(height: 16),

                // Gyroscope
                _SensorCard(
                  title: 'Gyroscope',
                  icon: Icons.rotate_right,
                  color: AppColors.accent,
                  readings: [
                    _Reading('X', sensor.gyroX),
                    _Reading('Y', sensor.gyroY),
                    _Reading('Z', sensor.gyroZ),
                  ],
                ),
                const SizedBox(height: 16),

                // Location
                _SensorCard(
                  title: 'GPS Location',
                  icon: Icons.location_on,
                  color: AppColors.safe,
                  readings: [
                    _Reading('Latitude', sensor.latitude),
                    _Reading('Longitude', sensor.longitude),
                  ],
                ),
                const SizedBox(height: 16),

                // Fall detection status
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: sensor.fallDetected
                        ? AppColors.emergency.withOpacity(0.15)
                        : AppColors.safe.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: sensor.fallDetected
                          ? AppColors.emergency
                          : AppColors.safe,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        sensor.fallDetected
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle,
                        color: sensor.fallDetected
                            ? AppColors.emergency
                            : AppColors.safe,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        sensor.fallDetected
                            ? 'Fall Detected!'
                            : 'No fall detected',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: sensor.fallDetected
                              ? AppColors.emergency
                              : AppColors.safe,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Toggle monitoring
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (isMonitoring) {
                        safety.stopMonitoring();
                      } else {
                        safety.startMonitoring();
                      }
                    },
                    icon: Icon(isMonitoring ? Icons.stop : Icons.play_arrow),
                    label: Text(isMonitoring ? 'Stop Monitoring' : 'Start Monitoring'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isMonitoring ? AppColors.emergency : AppColors.safe,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MonitoringBanner extends StatelessWidget {
  final bool isMonitoring;
  const _MonitoringBanner({required this.isMonitoring});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isMonitoring
            ? AppColors.safe.withOpacity(0.15)
            : Colors.grey.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isMonitoring ? AppColors.safe : Colors.grey,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isMonitoring ? 'Sensors Active' : 'Sensors Inactive',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isMonitoring ? AppColors.safe : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

class _SensorCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<_Reading> readings;

  const _SensorCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.readings,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            ...readings.map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(r.label,
                      style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color)),
                  Text(
                    r.value.toStringAsFixed(4),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: color,
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _Reading {
  final String label;
  final double value;
  _Reading(this.label, this.value);
}
