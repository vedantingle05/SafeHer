require('dotenv').config({ path: __dirname + '/../.env' });

async function inspectWaba() {
  const token = process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  const wabaId = '2248389402403444'; // from the dashboard screenshot

  console.log('Inspecting WABA:', wabaId);

  // 1. Check Phone Number details
  try {
    const res = await fetch(`https://graph.facebook.com/v20.0/${phoneId}?fields=display_phone_number,name_status,quality_rating,code_verification_status,messaging_limit_tier`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    const data = await res.json();
    console.log('Phone details:', JSON.stringify(data, null, 2));
  } catch (e) {
    console.error('Phone error:', e.message);
  }

  // 2. Check WABA phone numbers
  try {
    const res = await fetch(`https://graph.facebook.com/v20.0/${wabaId}/phone_numbers`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    const data = await res.json();
    console.log('WABA phone numbers:', JSON.stringify(data, null, 2));
  } catch (e) {
    console.error('WABA error:', e.message);
  }

  // 3. Check registered test phone numbers if accessible
  try {
    const res = await fetch(`https://graph.facebook.com/v20.0/${wabaId}?fields=id,name,currency,timezone_id,message_templates`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    const data = await res.json();
    console.log('WABA details:', JSON.stringify(data, null, 2));
  } catch (e) {
    console.error('WABA details error:', e.message);
  }
}

inspectWaba();

