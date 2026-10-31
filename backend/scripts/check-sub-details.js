require('dotenv').config({ path: __dirname + '/../.env' });

async function checkSubscribedDetails() {
  const token = process.env.WHATSAPP_ACCESS_TOKEN;
  const wabaId = '2248389402403444';

  const res = await fetch(`https://graph.facebook.com/v20.0/${wabaId}/subscribed_apps`, {
    headers: { Authorization: `Bearer ${token}` }
  });
  const data = await res.json();
  console.log('Subscribed apps detail:', JSON.stringify(data, null, 2));
}

checkSubscribedDetails();

