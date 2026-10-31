async function testLiveSOS() {
  const token = 'safeher_secret_key_development_jwt_2026';
  // Let's create a test JWT
  const jwt = require('jsonwebtoken');
  const userToken = jwt.sign(
    { sub: 'test-user-123', email: 'test@example.com' },
    token,
    { expiresIn: '1h' }
  );

  console.log('Sending SOS to http://127.0.0.1:5001/api/emergency...');
  try {
    const res = await fetch('http://127.0.0.1:5001/api/emergency', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${userToken}`,
      },
      body: JSON.stringify({
        type: 'panic_button',
        location: {
          latitude: 18.5204,
          longitude: 73.8567,
        },
        evidenceUrls: [],
      }),
    });

    const data = await res.json();
    console.log('SOS Response:', JSON.stringify(data, null, 2));
  } catch (err) {
    console.error('SOS Error:', err.message);
  }
}

testLiveSOS();

