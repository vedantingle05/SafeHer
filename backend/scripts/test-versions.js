require('dotenv').config({ path: __dirname + '/../.env' });

async function testVersions() {
  const token = process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneId = process.env.WHATSAPP_PHONE_NUMBER_ID;

  for (const ver of ['v25.0', 'v21.0', 'v22.0']) {
    console.log(`Testing version ${ver}...`);
    try {
      const res = await fetch(`https://graph.facebook.com/${ver}/${phoneId}/messages`, {
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
            name: 'hello_world',
            language: { code: 'en_US' },
          },
        }),
      });
      const data = await res.json();
      console.log(`Version ${ver} response:`, JSON.stringify(data));
    } catch (err) {
      console.error(`Version ${ver} error:`, err.message);
    }
  }
}

testVersions();

