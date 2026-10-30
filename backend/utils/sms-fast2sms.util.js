/**
 * Fast2SMS wrapper — India-native SMS delivery, bypasses Twilio's A2P
 * routing restrictions. Uses the "Quick" transactional route (no DLT
 * template registration required), which is suitable for free-tier use.
 *
 * Docs: https://docs.fast2sms.com/
 * Free tier: ~20 SMS/day on route=q.
 */

const FAST2SMS_URL = 'https://www.fast2sms.com/dev/bulkV2';

/**
 * Strip +91/0 prefixes — Fast2SMS Quick route expects 10 local digits.
 */
function toIndianLocal(raw) {
  const digits = String(raw || '').replace(/\D/g, '');
  if (digits.length === 12 && digits.startsWith('91')) return digits.slice(2);
  if (digits.length === 11 && digits.startsWith('0')) return digits.slice(1);
  return digits;
}

/**
 * Send SMS via Fast2SMS. Returns { request_id, ... } on success.
 * Throws on HTTP or API error.
 */
exports.sendSMSViaFast2SMS = async (rawTo, body) => {
  const apiKey = process.env.FAST2SMS_API_KEY;
  if (!apiKey) throw new Error('FAST2SMS_API_KEY not set');

  const local = toIndianLocal(rawTo);
  if (local.length !== 10) {
    throw new Error(`Fast2SMS requires a 10-digit Indian number, got: ${rawTo}`);
  }

  const res = await fetch(FAST2SMS_URL, {
    method: 'POST',
    headers: {
      authorization: apiKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      route: 'q',          // Quick transactional, no DLT needed
      message: body,
      numbers: local,
      flash: 0,
    }),
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.return !== true) {
    const msg = data.message
      || (data.errors && JSON.stringify(data.errors))
      || `HTTP ${res.status}`;
    throw new Error(`Fast2SMS: ${msg}`);
  }
  return data;
};
