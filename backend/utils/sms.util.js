/**
 * SMS Utility
 * Routes each SMS to the best provider:
 *   1. Indian numbers (+91) with FAST2SMS_API_KEY set → Fast2SMS (bypasses
 *      Twilio's A2P 10DLC restrictions; actually delivers on free tier).
 *   2. Everything else → Twilio (via MessagingServiceSid or direct from number).
 *   3. No credentials → console log (dev fallback).
 */

const { sendSMSViaFast2SMS } = require('./sms-fast2sms.util');

let twilioClient = null;

if (process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN) {
  const twilio = require('twilio');
  twilioClient = twilio(
    process.env.TWILIO_ACCOUNT_SID,
    process.env.TWILIO_AUTH_TOKEN
  );
}

/**
 * Best-effort E.164 normalization. Assumes India (+91) when no country code
 * is present, which matches the app's primary market. Override via
 * SMS_DEFAULT_COUNTRY_CODE env var for other regions.
 */
function toE164(raw) {
  if (!raw) return raw;
  const defaultCc = (process.env.SMS_DEFAULT_COUNTRY_CODE || '+91').trim();
  let s = String(raw).trim();
  if (s.startsWith('+')) return '+' + s.slice(1).replace(/\D/g, '');
  const digits = s.replace(/\D/g, '');
  // Common Indian formats: "09657085702" (11 leading 0) → drop the 0.
  const stripped = digits.startsWith('0') && digits.length === 11
    ? digits.slice(1)
    : digits;
  // If already 11+ digits and starts with a country code, keep as-is.
  if (stripped.length >= 11) return '+' + stripped;
  return defaultCc + stripped;
}

exports.sendSMS = async (rawTo, body) => {
  const to = toE164(rawTo);

  // 1. Prefer Fast2SMS for Indian numbers (Twilio A2P blocks India delivery).
  if (process.env.FAST2SMS_API_KEY && to.startsWith('+91')) {
    try {
      const result = await sendSMSViaFast2SMS(to, body);
      console.log(`✅ SMS sent via Fast2SMS to ${to} (req_id: ${result.request_id})`);
      return { sid: 'fast2sms_' + result.request_id, status: 'sent' };
    } catch (e) {
      console.error(`❌ Fast2SMS failed for ${to}: ${e.message} — falling back to Twilio`);
      // Fall through to Twilio as a backup.
    }
  }

  // 2. Twilio (or mock if not configured).
  if (!twilioClient) {
    console.log(`📱 [SMS Mock] To: ${to}  (raw: ${rawTo})`);
    console.log(`   Message: ${body.substring(0, 80)}...`);
    return { sid: 'mock_' + Date.now(), status: 'mock_sent' };
  }

  const payload = { to, body };
  if (process.env.TWILIO_MESSAGING_SERVICE_SID) {
    payload.messagingServiceSid = process.env.TWILIO_MESSAGING_SERVICE_SID;
  } else if (process.env.TWILIO_PHONE_NUMBER) {
    payload.from = process.env.TWILIO_PHONE_NUMBER;
  } else {
    console.error('❌ Twilio configured but no sender: set TWILIO_MESSAGING_SERVICE_SID or TWILIO_PHONE_NUMBER');
    throw new Error('Twilio sender not configured');
  }

  // 2. Real Twilio SMS Delivery
  try {
    const message = await twilioClient.messages.create(payload);
    console.log(`✅ [Twilio] Real SMS dispatched to ${to} (SID: ${message.sid}, status: ${message.status})`);
    return message;
  } catch (error) {
    console.error(`❌ [Twilio] SMS dispatch failed to ${to}:`, error.message);
    throw error;
  }
};


