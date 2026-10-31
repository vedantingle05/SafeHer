/**
 * Voice Call Utility (Twilio Voice)
 * Places an outbound emergency phone call from an international Twilio number
 * to emergency contacts.
 * Speaks:
 *   "<userName> is in emergency. <userName> has added your number in their emergency list.
 *    Please note their last location: coordinates <lat>, <lng>, in <area>, <city>, <country>."
 * Runs in a continuous loop, speaking the live location coordinates and address.
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
  return String(s || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

/**
 * Builds the exact TwiML XML speech required by user.
 */
function buildEmergencyTwiml({
  userName = 'SafeHer User',
  lat = 0.0,
  lng = 0.0,
  area = 'Current Location',
  city = 'City',
  country = 'India',
  audioUrl = null,
  loopCount = 4,
}) {
  const spokenLat = Number(lat).toFixed(4);
  const spokenLng = Number(lng).toFixed(4);
  const locationPhrase = `coordinates latitude ${spokenLat}, longitude ${spokenLng}, in ${area}, ${city}, ${country}`;

  const messageText =
    `${userName} is in emergency. ${userName} has added your number in their emergency list. ` +
    `Please note their last location: ${locationPhrase}. ` +
    `Please check on ${userName} immediately or contact the authorities.`;

  let body = '';
  for (let i = 1; i <= loopCount; i++) {
    const loopPrefix = i > 1 ? `Repeating emergency alert. ` : '';
    body += `<Say voice="Polly.Aditi" language="en-IN">${escapeXml(loopPrefix + messageText)}</Say>`;
    body += `<Pause length="2"/>`;
    if (audioUrl && i === 1) {
      body += `<Say voice="Polly.Aditi" language="en-IN">Now streaming audio evidence captured from the device.</Say>`;
      body += `<Play>${escapeXml(audioUrl)}</Play>`;
      body += `<Pause length="2"/>`;
    }
  }

  return (
    `<?xml version="1.0" encoding="UTF-8"?>` +
    `<Response>` +
    body +
    `</Response>`
  );
}

exports.buildEmergencyTwiml = buildEmergencyTwiml;

exports.placeEmergencyCall = async ({
  to,
  userName = 'SafeHer User',
  alertLabel = 'Emergency SOS Alert',
  location = {},
  audioUrl = null,
  mapsLink = null,
}) => {
  const normalizedTo = toE164(to);
  const lat = location.latitude || 0.0;
  const lng = location.longitude || 0.0;
  const address = location.address || {};
  const area = address.area || (address.formatted ? address.formatted.split(',')[0] : 'Current Area');
  const city = address.city || 'City';
  const country = address.country || 'India';

  if (!twilioClient || !process.env.TWILIO_PHONE_NUMBER) {
    console.log(`📞 [Call Mock] Outbound call to ${normalizedTo} for ${userName} at [${lat}, ${lng}] (${area}, ${city})`);
    return { sid: 'mock_call_' + Date.now(), status: 'mock' };
  }

  const twiml = buildEmergencyTwiml({
    userName,
    lat,
    lng,
    area,
    city,
    country,
    audioUrl,
    loopCount: 4,
  });

  try {
    const call = await twilioClient.calls.create({
      to: normalizedTo,
      from: process.env.TWILIO_PHONE_NUMBER,
      twiml,
      timeout: 35, // ring for up to 35 seconds
    });
    console.log(`✅ Voice call placed to ${normalizedTo} (SID: ${call.sid})`);
    return call;
  } catch (error) {
    console.error(`❌ Voice call failed to ${normalizedTo}:`, error.message);
    if (error.message && error.message.includes('unverified')) {
      console.warn(
        `⚠️ [Twilio Trial Notice] To receive live emergency calls on ${normalizedTo}, ` +
        `please verify this number in Twilio Console at: https://console.twilio.com/us1/develop/phone-numbers/manage/verified-caller-ids`
      );
    }
    throw error;
  }
};
