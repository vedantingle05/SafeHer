require('dotenv').config({ path: __dirname + '/../.env' });

async function checkMessage() {
  const token = process.env.WHATSAPP_ACCESS_TOKEN;
  // Let's check the message ID from send-template.js
  const msgId = 'wamid.HBgMOTE5NjU3MDg1NzAyFQIAERgSMjAyRTg4MDc4MTRCQTg3M0IxAA==';

  try {
    const res = await fetch(`https://graph.facebook.com/v20.0/${msgId}`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    const data = await res.json();
    console.log('Message query result:', JSON.stringify(data, null, 2));
  } catch (e) {
    console.error('Error:', e.message);
  }
}

checkMessage();

