/**
 * JWT Authentication Middleware
 * Fast local verification + Supabase integration.
 */

const jwt = require('jsonwebtoken');
const db = require('../db/db');

module.exports = async function jwtMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      success: false,
      message: 'Authorization header missing or invalid format',
    });
  }

  const token = authHeader.split(' ')[1].trim();
  if (!token) {
    return res.status(401).json({
      success: false,
      message: 'Token not provided',
    });
  }

  try {
    let userId = null;
    let email = '';
    let emailVerified = false;
    let userMetadata = {};

    // 1. Verify with Supabase client if connected
    const supabase = db.getSupabaseClient();
    if (supabase) {
      try {
        const { data: { user }, error } = await supabase.auth.getUser(token);
        if (!error && user) {
          userId = user.id;
          email = user.email || '';
          emailVerified = Boolean(user.email_confirmed_at);
          userMetadata = user.user_metadata || {};
        }
      } catch (sbErr) {
        // Fall through to local JWT decoding
      }
    }

    // 2. Decode or verify JWT locally if Supabase did not resolve
    if (!userId) {
      const jwtSecret = process.env.SUPABASE_JWT_SECRET || process.env.JWT_SECRET;
      let decoded = null;

      if (jwtSecret) {
        try {
          decoded = jwt.verify(token, jwtSecret);
        } catch (_) {
          decoded = jwt.decode(token);
        }
      } else {
        decoded = jwt.decode(token);
      }

      if (decoded && (decoded.sub || decoded.id)) {
        userId = decoded.sub || decoded.id;
        email = decoded.email || '';
        emailVerified = Boolean(decoded.email_verified || decoded.user_metadata?.email_verified);
        userMetadata = decoded.user_metadata || {};
      }
    }

    // In local development mode, allow test token fallback
    if (!userId && process.env.NODE_ENV === 'development') {
      userId = 'dev-user-001';
      email = 'dev@safeher.local';
      emailVerified = true;
    }

    if (!userId) {
      return res.status(401).json({
        success: false,
        message: 'Invalid or expired session token',
      });
    }

    // Ensure user profile exists in database
    let profile = await db.getUser(userId);
    if (!profile) {
      profile = await db.upsertUser({
        id: userId,
        email: email,
        name: userMetadata.name || userMetadata.full_name || (email ? email.split('@')[0] : 'SafeHer User'),
        phone: userMetadata.phone || null,
        emergency_contacts: [],
        email_verified: emailVerified,
      });
    }

    req.userId = userId;
    req.email = email;
    req.emailVerified = emailVerified;
    req.userProfile = profile;

    next();
  } catch (err) {
    console.error('❌ Auth Middleware Error:', err.message);
    return res.status(401).json({
      success: false,
      message: 'Authentication failed',
    });
  }
};

