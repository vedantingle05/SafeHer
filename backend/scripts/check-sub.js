require('dotenv').config({ path: __dirname + '/../.env' });

async function checkSubscribedApps() {
  const token = process.env.WHATSAPP_ACCESS_TOKEN;
  const wabaId = '2248389402403444';
  const phoneId = process.env.WHATSAPP_PHONE_NUMBER_ID;

  try {
    const res = await fetch(`https://graph.facebook.com/v20.0/${wabaId}/subscribed_apps`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    console.log('Subscribed apps:', await res.json());
  } catch (e) {
    console.error('Error:', e.message);
  }

  try {
    const res2 = await fetch(`https://graph.facebook.com/v20.0/${phoneId}?fields=name_status,status,quality_score`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    console.log('Phone status:', await res2.json());
  } catch (e) {
    console.error('Error 2:', e.message);
  }
}

checkSubscribedApps();

