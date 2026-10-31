require('dotenv').config({ path: __dirname + '/../.env' });

async function testJasper() {
  const token = process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneId = process.env.WHATSAPP_PHONE_NUMBER_ID;

  const res = await fetch(`https://graph.facebook.com/v21.0/${phoneId}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to: '919657085702',
      type: 'template',
      template: {
        name: 'jaspers_market_plain_text_v1',
        language: { code: 'en_US' },
      },
    }),
  });
  console.log('Jasper template response:', await res.json());
}

testJasper();

