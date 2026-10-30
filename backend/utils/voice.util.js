/**
 * Voice Call Utility (Twilio Voice)
 * Places an outbound call that speaks an emergency message and plays the
 * captured audio evidence so the contact can hear what's happening in
 * near-real-time. Falls back to a console log when Twilio isn't configured
 * or TWILIO_PHONE_NUMBER isn't set (voice calls require a purchased number —
 * a Messaging Service SID is not sufficient).
 */

let twilioClient = null;
if (process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN) {
  const twilio = require('twilio');
  twilioClient = twilio(
    process.env.TWILIO_ACCOUNT_SID,
    process.env.TWILIO_AUTH_TOKEN
  );
}

function toE164(raw) {
  if (!raw) return raw;
  const defaultCc = (process.env.SMS_DEFAULT_COUNTRY_CODE || '+91').trim();
  let s = String(raw).trim();
  if (s.startsWith('+')) return '+' + s.slice(1).replace(/\D/g, '');
  const digits = s.replace(/\D/g, '');
  const stripped = digits.startsWith('0') && digits.length === 11
    ? digits.slice(1)
    : digits;
  if (stripped.length >= 11) return '+' + stripped;
  return defaultCc + stripped;
}

function escapeXml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

/**
 * Build the TwiML the callee hears on answer.
 *  - <Say>: Polly voice reads an opening line with user name + SOS type.
 *  - <Play>: streams the uploaded audio evidence.
 *  - Repeats the play once if audio duration is short.
 */
function buildTwiml({ userName, alertLabel, audioUrl, mapsLink }) {
  const intro =
    `Emergency alert from ${userName}. ${alertLabel}. ` +
    `Live location link was sent to you via SMS. ` +
    `Now playing captured audio.`;
  const playTag = audioUrl
    ? `<Play>${escapeXml(audioUrl)}</Play>`
    : `<Say voice="Polly.Aditi">No audio recording was captured.</Say>`;

  return (
    `<?xml version="1.0" encoding="UTF-8"?>` +
    `<Response>` +
    `<Say voice="Polly.Aditi">${escapeXml(intro)}</Say>` +
    `<Pause length="1"/>` +
    playTag +
    `<Pause length="1"/>` +
    `<Say voice="Polly.Aditi">Please check on them immediately. Repeating audio.</Say>` +
    playTag +
    `</Response>`
  );
}

/**
 * Place an emergency voice call.
 * @param {object} args
 * @param {string} args.to         - E.164 phone number (normalized internally).
 * @param {string} args.userName   - Name of the person in distress.
 * @param {string} args.alertLabel - Human-readable alert type.
 * @param {string} [args.audioUrl] - Public URL of the captured audio.
 * @param {string} [args.mapsLink] - Google Maps link (spoken in intro).
 * @returns {Promise<object>} Twilio call object or { sid: 'mock_...' }.
 */
exports.placeEmergencyCall = async ({
  to, userName, alertLabel, audioUrl, mapsLink,
}) => {
  const normalizedTo = toE164(to);

  if (!twilioClient || !process.env.TWILIO_PHONE_NUMBER) {
    console.log(`📞 [Call Mock] To: ${normalizedTo}  audio=${audioUrl || 'none'}`);
    return { sid: 'mock_call_' + Date.now(), status: 'mock' };
  }

  const twiml = buildTwiml({ userName, alertLabel, audioUrl, mapsLink });

  try {
    const call = await twilioClient.calls.create({
      to: normalizedTo,
      from: process.env.TWILIO_PHONE_NUMBER,
      twiml,
      timeout: 30, // ring for up to 30s
    });
    console.log(`✅ Voice call placed to ${normalizedTo} (SID: ${call.sid})`);
    return call;
  } catch (error) {
    console.error(`❌ Voice call failed to ${normalizedTo}:`, error.message);
    throw error;
  }
};
