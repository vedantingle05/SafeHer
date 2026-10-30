/// Settings Screen
/// Theme toggle, permissions management, about, and app info.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../themes/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<Permission, PermissionStatus> _permissions = {};

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final permissions = {
      Permission.camera: await Permission.camera.status,
      Permission.microphone: await Permission.microphone.status,
      Permission.location: await Permission.location.status,
      Permission.notification: await Permission.notification.status,
      Permission.sensors: await Permission.sensors.status,
    };
    setState(() => _permissions = permissions);
  }

  Future<void> _requestPermission(Permission permission) async {
    final status = await permission.request();
    setState(() => _permissions[permission] = status);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Appearance ──
          _SectionHeader(title: 'Appearance'),
          Card(
            child: Consumer<ThemeProvider>(
              builder: (_, theme, __) => SwitchListTile(
                secondary: Icon(
                  theme.isDark ? Icons.dark_mode : Icons.light_mode,
                  color: AppColors.accent,
                ),
                title: const Text('Dark Mode'),
                subtitle: Text(theme.isDark ? 'Dark theme active' : 'Light theme active'),
                value: theme.isDark,
                onChanged: (_) => theme.toggleTheme(),
                activeColor: AppColors.primary,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Permissions ──
          _SectionHeader(title: 'Permissions'),
          Card(
            child: Column(
              children: [
                _PermissionTile(
                  icon: Icons.camera_alt,
                  title: 'Camera',
                  subtitle: 'For evidence capture',
                  status: _permissions[Permission.camera],
                  onRequest: () => _requestPermission(Permission.camera),
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.mic,
                  title: 'Microphone',
                  subtitle: 'For scream detection & audio recording',
                  status: _permissions[Permission.microphone],
                  onRequest: () => _requestPermission(Permission.microphone),
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.location_on,
                  title: 'Location',
                  subtitle: 'For live location sharing',
                  status: _permissions[Permission.location],
                  onRequest: () => _requestPermission(Permission.location),
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.notifications,
                  title: 'Notifications',
                  subtitle: 'For emergency push alerts',
                  status: _permissions[Permission.notification],
                  onRequest: () => _requestPermission(Permission.notification),
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.sensors,
                  title: 'Motion Sensors',
                  subtitle: 'For fall detection',
                  status: _permissions[Permission.sensors],
                  onRequest: () => _requestPermission(Permission.sensors),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── About ──
          _SectionHeader(title: 'About'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline, color: AppColors.primary),
                  title: const Text('SafeHer'),
                  subtitle: const Text('Version 1.0.0'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.shield, color: AppColors.primary),
                  title: const Text('About SafeHer'),
                  subtitle: const Text(
                    'AI-powered personal safety monitoring system that '
                    'detects dangerous situations and alerts your trusted contacts.',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).textTheme.bodySmall?.color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final PermissionStatus? status;
  final VoidCallback onRequest;

  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    final isGranted = status?.isGranted ?? false;

    return ListTile(
      leading: Icon(icon, color: isGranted ? AppColors.safe : Colors.grey),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: isGranted
          ? const Icon(Icons.check_circle, color: AppColors.safe)
          : TextButton(
              onPressed: onRequest,
              child: const Text('Grant'),
            ),
    );
  }
}
