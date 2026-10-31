require('dotenv').config({ path: __dirname + '/../.env' });

async function test() {
  const phoneId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  const token = process.env.WHATSAPP_ACCESS_TOKEN;

  console.log('Phone ID:', phoneId);
  console.log('Token starts with:', token ? token.substring(0, 15) + '...' : 'EMPTY');

  // Let's check the test phone number status
  try {
    const res = await fetch(`https://graph.facebook.com/v20.0/${phoneId}?fields=verified_name,display_phone_number`, {
      headers: {
        Authorization: `Bearer ${token}`
      }
    });
    const data = await res.json();
    console.log('Phone number details from Meta:', JSON.stringify(data, null, 2));
  } catch (err) {
    console.error('Fetch error:', err.message);
  }
}

test();

