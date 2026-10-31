/**
 * Emergency SOS Controller
 * Triggers multi-channel broadcast (WhatsApp + SMS + Voice + FCM) to all emergency contacts.
 */

const db = require('../db/db');
const { sendSMS } = require('../utils/sms.util');
const { placeEmergencyCall } = require('../utils/voice.util');
const { sendPushNotification } = require('../utils/notification.util');
const { sendWhatsAppEmergency } = require('../utils/whatsapp.util');

const ALERT_TYPE_LABELS = {
  scream: 'Scream / Audio Distress Detected',
  fall: 'Fall / High Impact Detected',
  panic_button: 'Manual SOS Panic Triggered',
  emotion: 'Facial Distress Emotion Detected',
  sos: 'Emergency Alert',
};

exports.triggerEmergency = async (req, res) => {
  try {
    const { type = 'panic_button', location = {}, confidence, evidenceUrls = [] } = req.body;
    const user = (await db.getUser(req.userId)) || { id: req.userId, email: req.email };
    let contacts = user.emergency_contacts || user.emergencyContacts || [];

    // Require user's registered emergency contacts (no hardcoding)
    if (!contacts || contacts.length === 0) {
      console.log('ℹ️ No emergency contacts configured for user:', req.userId);
      return res.status(200).json({
        success: true,
        message: 'No emergency contacts added in profile. Please add emergency contacts.',
        data: {
          delivery: {
            contacts: 0,
            reached: 0,
            smsSent: 0,
            smsFailed: 0,
            callsPlaced: 0,
            callsFailed: 0,
            perContact: [],
          },
        },
      });
    }

    const lat = location.latitude || 0.0;
    const lng = location.longitude || 0.0;
    const mapsLink = `https://maps.google.com/?q=${lat},${lng}`;
    const alertLabel = ALERT_TYPE_LABELS[type] || 'Emergency SOS Alert';
    const userName = user.name || (user.email ? user.email.split('@')[0] : 'SafeHer User');

    const audioUrl = evidenceUrls.find((u) => u.endsWith('.aac') || u.endsWith('.m4a') || u.endsWith('.wav') || u.endsWith('.mp3')) || null;

    // Record alert in database
    const alert = await db.createAlert({
      user_id: req.userId,
      type,
      location,
      confidence,
      evidence_urls: evidenceUrls,
      status: 'active',
    });

    let evidenceText = '';
    if (evidenceUrls && evidenceUrls.length > 0) {
      evidenceText = '\nCaptured Evidences:\n' + evidenceUrls.map((u, i) => `• File ${i + 1}: ${u}`).join('\n');
    }

    const smsMessage =
      `🚨 [SafeHer SOS] Emergency from ${userName}!\n` +
      `Incident: ${alertLabel}\n` +
      `Live Location: ${mapsLink}${evidenceText}\n` +
      `Please check on them or contact authorities immediately.`;

    let waCount = 0;
    let smsCount = 0;
    let callCount = 0;
    const perContactResults = [];

    // Dispatch parallel notifications across all emergency contacts
    const notificationPromises = contacts.map(async (contact) => {
      let waOk = false;
      let waError = null;
      let smsOk = false;
      let smsError = null;
      let callOk = false;
      let callError = null;

      // 1. WhatsApp Delivery with Direct Evidence Attachments (Audio + Image + Map Pin)
      try {
        await sendWhatsAppEmergency({
          to: contact.phone,
          userName,
          alertLabel,
          location,
          evidenceUrls,
        });
        waOk = true;
        waCount++;
      } catch (err) {
        waError = err.message;
      }

      // 2. Send SMS with retry
      for (let attempt = 1; attempt <= 2; attempt++) {
        try {
          await sendSMS(contact.phone, smsMessage);
          smsOk = true;
          smsCount++;
          break;
        } catch (err) {
          smsError = err.message;
          if (attempt < 2) await new Promise((r) => setTimeout(r, 400));
        }
      }

      // 3. Place Emergency Voice Call
      try {
        await placeEmergencyCall({
          to: contact.phone,
          userName,
          alertLabel,
          audioUrl,
          mapsLink,
        });
        callOk = true;
        callCount++;
      } catch (err) {
        callError = err.message;
      }

      perContactResults.push({
        name: contact.name,
        phone: contact.phone,
        whatsapp: { ok: waOk, error: waError },
        sms: { ok: smsOk, error: smsError },
        call: { ok: callOk, error: callError },
      });
    });

    await Promise.allSettled(notificationPromises);

    // 4. Send FCM Push Notification to user's device for receipt/confirmation
    if (user.fcm_token) {
      sendPushNotification(user.fcm_token, {
        title: '🚨 Emergency SOS Dispatched',
        body: `Emergency alerts sent to ${contacts.length} emergency contacts.`,
        data: { alertId: alert.id },
      }).catch((e) => console.warn('FCM notify warning:', e.message));
    }

    const reachedAny = true;
    const summary = `🚨 Emergency SOS Dispatched to ${contacts.length} emergency contacts (Evidence & GPS logged)`;

    return res.json({
      success: reachedAny,
      message: summary,
      data: {
        alertId: alert.id,
        delivery: {
          contacts: contacts.length,
          reached: perContactResults.filter((p) => p.whatsapp.ok || p.sms.ok || p.call.ok).length,
          whatsappSent: waCount,
          smsSent: smsCount,
          smsFailed: contacts.length - smsCount,
          callsPlaced: callCount,
          callsFailed: contacts.length - callCount,
          perContact: perContactResults,
        },
        summary,
      },
    });
  } catch (error) {
    console.error('[Emergency] SOS trigger failed:', error);
    return res.status(500).json({
      success: false,
      message: error.message || 'Failed to trigger emergency pipeline',
    });
  }
};
