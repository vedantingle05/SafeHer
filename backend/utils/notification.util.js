/**
 * Push Notification Utility
 * Sends push notifications via Firebase Cloud Messaging (FCM).
 * Falls back to console logging if Firebase is not configured.
 */

let firebaseAdmin = null;

// Initialize Firebase Admin only if credentials exist
if (process.env.FIREBASE_PROJECT_ID && process.env.FIREBASE_CLIENT_EMAIL) {
  const admin = require('firebase-admin');

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      }),
      storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
    });
  }

  firebaseAdmin = admin;
}

/**
 * Send a push notification to a device.
 * @param {string} fcmToken - Device FCM token
 * @param {object} payload  - { title, body, data? }
 */
exports.sendPushNotification = async (fcmToken, payload) => {
  if (!firebaseAdmin) {
    console.log(`🔔 [Push Mock] Token: ${fcmToken.substring(0, 20)}...`);
    console.log(`   Title: ${payload.title}`);
    console.log(`   Body: ${payload.body}`);
    return { messageId: 'mock_' + Date.now() };
  }

  try {
    const message = {
      token: fcmToken,
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: payload.data || {},
      android: {
        priority: 'high',
        notification: {
          channelId: 'safeher_emergency',
          priority: 'max',
          sound: 'emergency_alarm',
        },
      },
      apns: {
        payload: {
          aps: {
            alert: { title: payload.title, body: payload.body },
            sound: 'emergency_alarm.caf',
            'content-available': 1,
          },
        },
      },
    };

    const response = await firebaseAdmin.messaging().send(message);
    console.log(`✅ Push sent (ID: ${response})`);
    return { messageId: response };
  } catch (error) {
    console.error('❌ Push notification failed:', error.message);
    throw error;
  }
};

/**
 * Get Firebase Admin instance (for Storage access, etc.)
 */
exports.getFirebaseAdmin = () => firebaseAdmin;
