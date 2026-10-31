import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// Direct SIM SMS Service (Native Telephony)
/// Dispatches emergency SMS messages directly through the device's cellular SIM card.
/// Completely free of cost, works offline, and requires zero cloud SMS gateways.
class DirectSmsService {
  static const _channel = MethodChannel('com.safeher.app/sms');

  /// Clean phone number to national cellular format
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
    String? area,
    String? city,
    String? country,
    String? alertType,
    List<String>? evidenceUrls,
  }) async {
    final targetPhone = formatPhone(phone);
    final mapsUrl = 'https://maps.google.com/?q=$latitude,$longitude';
    final typeLabel = alertType ?? 'Emergency SOS';

    String evidenceText = '';
    if (evidenceUrls != null && evidenceUrls.isNotEmpty) {
      evidenceText = '\nEvidence:\n' + evidenceUrls.map((u) => u).join('\n');
    }

    String locationLine = '';
    if (area != null && city != null) {
      locationLine = 'Location: $area, $city, ${country ?? "India"}\n';
    }

    // Clean GSM 7-bit ASCII format (NO UNICODE EMOJIS like 🚨 or 📸)
    // This keeps the message in standard 160-char SMS segments, preventing
    // the restrictive 70-char UCS-2 limit that causes telecom carrier drops.
    final message =
        '[SAFEHER SOS ALERT]\n'
        '$userName needs urgent assistance!\n'
        'Incident: $typeLabel\n'
        '$locationLine'
        'Live GPS: $mapsUrl$evidenceText\n'
        'Please check immediately or contact authorities.';

    bool sentDirectly = false;

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
          debugPrint('✅ Direct SIM SMS dispatched to baseband for $targetPhone');
          sentDirectly = true;
        }
      } else {
        debugPrint('⚠️ SMS permission denied by user; falling back to native composer');
      }
    } catch (e) {
      debugPrint('⚠️ Direct SIM SMS channel exception: $e');
    }

    // 2. Immediate Native Composer Fallback:
    // If carrier blocks background A2P or user did not grant background SMS permission,
    // open the device's native SMS app with pre-filled contact and alert body.
    try {
      debugPrint('📱 Launching native SMS composer fallback for $targetPhone...');
      final dynamic res = await _channel.invokeMethod('openSmsApp', {
        'phone': targetPhone,
        'message': message,
      });
      if (res == true) return true;
    } catch (e) {
      debugPrint('⚠️ MethodChannel openSmsApp fallback error: $e');
    }

    if (sentDirectly) return true;

    // 3. Secondary url_launcher fallback
    try {
      final uri = Uri(
        scheme: 'smsto',
        path: targetPhone,
        queryParameters: {'body': message},
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (e) {
      debugPrint('❌ url_launcher SMS fallback failed: $e');
    }

    return sentDirectly;
  }
}
