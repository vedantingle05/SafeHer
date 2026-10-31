import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// Direct SIM SMS Service (Native Telephony)
/// Dispatches emergency SMS messages directly through the device's cellular SIM card.
/// Completely free of cost, works offline, and requires zero cloud SMS gateways.
class DirectSmsService {
  static const _channel = MethodChannel('com.safeher.app/sms');

  /// Clean phone number to national/international cellular format
  static String formatPhone(String rawPhone) {
    var digits = rawPhone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) {
      // 10 digits Indian cellular number
      return '+91$digits';
    } else if (digits.length > 10 && !rawPhone.startsWith('+')) {
      return '+$digits';
    }
    return rawPhone.trim();
  }

  /// Sends a real cellular SMS directly from the device's SIM card
  static Future<bool> sendEmergencySms({
    required String phone,
    required String userName,
    required double latitude,
    required double longitude,
    String? alertType,
    List<String>? evidenceUrls,
  }) async {
    final targetPhone = formatPhone(phone);
    final mapsUrl = 'https://maps.google.com/?q=$latitude,$longitude';
    final typeLabel = alertType ?? 'Emergency SOS';

    String evidenceText = '';
    if (evidenceUrls != null && evidenceUrls.isNotEmpty) {
      evidenceText = '\n\n📸 Evidences:\n' +
          evidenceUrls.map((u) => '• $u').join('\n');
    }

    final message =
        '🚨 [SafeHer SOS Alert] 🚨\n'
        '$userName needs urgent assistance!\n'
        'Incident: $typeLabel\n'
        'Live Location: $mapsUrl$evidenceText\n'
        'Please send help or contact authorities immediately.';

    try {
      // 1. Request SMS permission at runtime
      var status = await Permission.sms.status;
      if (!status.isGranted) {
        status = await Permission.sms.request();
      }

      if (status.isGranted) {
        debugPrint('📱 Dispatching direct SIM SMS to $targetPhone...');
        final dynamic res = await _channel.invokeMethod('sendDirectSms', {
          'phone': targetPhone,
          'message': message,
        });

        if (res == true) {
          debugPrint('✅ Direct SIM SMS sent successfully via native telephony');
          return true;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Direct SIM SMS channel exception: $e');
    }

    // 2. Fallback: If device lacks active SIM / telephony (e.g. Wi-Fi tablet),
    // launch the native SMS app composer with pre-filled target and evidence text.
    try {
      debugPrint('📱 Launching native SMS composer fallback to $targetPhone...');
      final smsUri = Uri.parse('sms:$targetPhone?body=${Uri.encodeComponent(message)}');
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (e) {
      debugPrint('❌ SMS composer fallback failed: $e');
    }

    return false;
  }
}

