require('dotenv').config({ path: __dirname + '/../.env' });

async function testRaw() {
  const token = process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneId = process.env.WHATSAPP_PHONE_NUMBER_ID;

  const res = await fetch(`https://graph.facebook.com/v20.0/${phoneId}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to: '9657085702',
      type: 'template',
      template: {
        name: 'hello_world',
        language: { code: 'en_US' },
      },
    }),
  });
  console.log('Result for raw 10 digits:', await res.json());
}

testRaw();

