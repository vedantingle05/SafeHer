/// Profile Screen
/// User info, emergency contacts CRUD, logout.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/safety_monitoring_service.dart';
import '../models/data_models.dart';
import '../themes/app_theme.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploadingAvatar = false;

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final XFile? picked = await picker.pickImage(
      source: source,
      maxWidth: 800,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    final api = context.read<ApiService>();
    final auth = context.read<AuthService>();
    try {
      await api.uploadFile(folder: 'avatars', filePath: picked.path);
      // Backend already updated profile_image. Clear the cached profile so the
      // refetch returns the NEW image instead of the stale cached copy.
      ApiService.clearCacheFor('/user/profile');
      if (!mounted) return;
      await auth.fetchProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.emergency,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: Consumer<AuthService>(
        builder: (context, auth, _) {
          final user = auth.currentUser;

          // Stale-while-revalidate: if we have a cached user, show it
          // immediately and overlay a small refresh indicator. The full
          // spinner is reserved for the case where we genuinely have no
          // data yet (first ever load with no cache).
          if (auth.isProfileLoading && user == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (user == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off, size: 48, color: AppColors.emergency),
                    const SizedBox(height: 16),
                    Text(
                      auth.error ??
                          'Could not load your profile. Check that the backend is running.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => auth.fetchProfile(allowFallback: true),
                      child: const Text('Retry'),
                    ),
                    if (!auth.isAuthenticated) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _handleLogout,
                        child: const Text('Sign in again'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          // The (rare) revalidation indicator: shown only while we already
          // have a user on screen but a background refresh is in flight.
          final body = SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Avatar (tap to change)
                Stack(
                  alignment: Alignment.center,
                  children: [
                    GestureDetector(
                      onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: AppColors.primary.withOpacity(0.15),
                        backgroundImage: user.profileImage != null &&
                                user.profileImage!.isNotEmpty
                            ? NetworkImage(user.profileImage!)
                            : null,
                        child: user.profileImage == null ||
                                user.profileImage!.isEmpty
                            ? Text(
                                user.name.isNotEmpty
                                    ? user.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary),
                              )
                            : null,
                      ),
                    ),
                    if (_uploadingAvatar)
                      const CircularProgressIndicator(strokeWidth: 2)
                    else
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onTap: _pickAndUploadAvatar,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt,
                                size: 18, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(user.name,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(user.email,
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color)),
                if (user.phone != null) ...[
                  const SizedBox(height: 4),
                  Text(user.phone!,
                      style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color)),
                ],

                const SizedBox(height: 32),

                // Emergency Contacts Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Emergency Contacts',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    if (user.emergencyContacts.length < 5)
                      IconButton(
                        icon: const Icon(Icons.add_circle,
                            color: AppColors.primary),
                        onPressed: () => _addContactDialog(context),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                if (user.emergencyContacts.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.people_outline, size: 48,
                            color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text('No emergency contacts yet'),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => _addContactDialog(context),
                          child: const Text('Add Contact'),
                        ),
                      ],
                    ),
                  )
                else
                  ...user.emergencyContacts.map((contact) =>
                      _ContactCard(contact: contact)),
              ],
            ),
          );

          return Stack(
            children: [
              body,
              if (auth.isProfileLoading)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _addContactDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final relationCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Emergency Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(
                  labelText: 'Phone', hintText: '+91 9876543210'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: relationCtrl,
              decoration: const InputDecoration(
                  labelText: 'Relation (optional)', hintText: 'e.g. Mother'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && phoneCtrl.text.isNotEmpty) {
                context.read<AuthService>().addEmergencyContact(
                  EmergencyContact(
                    name: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    relation: relationCtrl.text.trim().isNotEmpty
                        ? relationCtrl.text.trim()
                        : null,
                  ),
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Logout')),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      context.read<SafetyMonitoringService>().stopMonitoring();
      await context.read<AuthService>().logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }
}

class _ContactCard extends StatelessWidget {
  final EmergencyContact contact;
  const _ContactCard({required this.contact});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.15),
          child: Text(
            contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: AppColors.primary),
          ),
        ),
        title: Text(contact.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${contact.phone}${contact.relation != null ? ' · ${contact.relation}' : ''}',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: AppColors.emergency),
          onPressed: () {
            if (contact.id != null) {
              context.read<AuthService>().removeEmergencyContact(contact.id!);
            }
          },
        ),
      ),
    );
  }
}
