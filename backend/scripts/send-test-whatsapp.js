require('dotenv').config({ path: __dirname + '/../.env' });
const { sendWhatsAppEmergency } = require('../utils/whatsapp.util');

const recipient = process.argv[2];

if (!recipient) {
  console.log('Usage: node backend/scripts/send-test-whatsapp.js <phone_number_with_country_code>');
  console.log('Example: node backend/scripts/send-test-whatsapp.js 919876543210');
  process.exit(1);
}

console.log(`🚀 Sending test SOS alert to ${recipient}...`);

sendWhatsAppEmergency({
  to: recipient,
  userName: 'SafeHer User (Test)',
  alertLabel: '🚨 LIVE EMERGENCY SOS TEST',
  location: {
    latitude: 18.5204,
    longitude: 73.8567,
  },
  evidenceUrls: [],
})
  .then((res) => {
    console.log('✅ WhatsApp message dispatched successfully!');
    console.log('API Response:', JSON.stringify(res, null, 2));
  })
  .catch((err) => {
    console.error('❌ Failed to send WhatsApp message:', err.message);
  });

