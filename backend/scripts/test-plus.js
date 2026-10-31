require('dotenv').config({ path: __dirname + '/../.env' });

async function sendBoth() {
  const phoneId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  const token = process.env.WHATSAPP_ACCESS_TOKEN;

  for (const to of ['+919657085702', '919657085702']) {
    console.log(`Sending hello_world to "${to}"...`);
    const res = await fetch(`https://graph.facebook.com/v20.0/${phoneId}/messages`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        to: to,
        type: 'template',
        template: {
          name: 'hello_world',
          language: { code: 'en_US' },
        },
      }),
    });
    const data = await res.json();
    console.log(`Result for ${to}:`, JSON.stringify(data));
  }
}

sendBoth();

