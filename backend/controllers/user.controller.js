/**
 * User Controller
 * Handles user profile, emergency contacts, and FCM tokens.
 */

const db = require('../db/db');

function shapeUser(user) {
  if (!user) return null;
  const contacts = user.emergency_contacts || user.emergencyContacts || [];
  return {
    id: user.id || user._id,
    name: user.name || (user.email ? user.email.split('@')[0] : 'SafeHer User'),
    email: user.email || '',
    phone: user.phone || null,
    profileImage: user.profile_image || user.profileImage || null,
    emergencyContacts: contacts.map((c, idx) => ({
      id: c.id || `c_${idx + 1}`,
      name: c.name || '',
      phone: c.phone || '',
      relation: c.relation || c.relationship || null,
    })),
  };
}

/**
 * GET /api/user/profile
 */
exports.getProfile = async (req, res) => {
  try {
    const user = await db.getUser(req.userId);
    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User profile not found',
      });
    }

    return res.json({
      success: true,
      data: shapeUser(user),
    });
  } catch (error) {
    console.error(`[User] getProfile failed id=${req.userId}:`, error.message);
    return res.status(500).json({ success: false, message: error.message });
  }
};

/**
 * PUT /api/user/profile
 */
exports.updateProfile = async (req, res) => {
  try {
    const { name, phone, profileImage } = req.body;
    const current = (await db.getUser(req.userId)) || { id: req.userId, email: req.email };

    const updated = await db.upsertUser({
      ...current,
      id: req.userId,
      name: name !== undefined ? name : current.name,
      phone: phone !== undefined ? phone : current.phone,
      profile_image: profileImage !== undefined ? profileImage : current.profile_image,
    });

    return res.json({
      success: true,
      data: shapeUser(updated),
    });
  } catch (error) {
    console.error(`[User] updateProfile failed:`, error.message);
    return res.status(500).json({ success: false, message: error.message });
  }
};

/**
 * POST /api/user/contacts
 */
exports.addContact = async (req, res) => {
  try {
    const { name, phone, relation, relationship } = req.body;
    if (!name || !phone) {
      return res.status(400).json({
        success: false,
        message: 'Name and phone are required for emergency contact',
      });
    }

    const current = (await db.getUser(req.userId)) || { id: req.userId, email: req.email, emergency_contacts: [] };
    const contacts = current.emergency_contacts || [];

    const newContact = {
      id: 'contact_' + Date.now() + '_' + Math.random().toString(36).substr(2, 4),
      name: name.trim(),
      phone: phone.trim(),
      relation: (relation || relationship || '').trim(),
    };

    contacts.push(newContact);

    const updated = await db.upsertUser({
      ...current,
      emergency_contacts: contacts,
    });

    return res.json({
      success: true,
      data: shapeUser(updated),
    });
  } catch (error) {
    console.error(`[User] addContact failed:`, error.message);
    return res.status(500).json({ success: false, message: error.message });
  }
};

/**
 * DELETE /api/user/contacts/:contactId
 */
exports.removeContact = async (req, res) => {
  try {
    const { contactId } = req.params;
    const current = (await db.getUser(req.userId)) || { id: req.userId, emergency_contacts: [] };
    const contacts = (current.emergency_contacts || []).filter(
      (c) => c.id !== contactId && c._id !== contactId
    );

    const updated = await db.upsertUser({
      ...current,
      emergency_contacts: contacts,
    });

    return res.json({
      success: true,
      data: shapeUser(updated),
    });
  } catch (error) {
    console.error(`[User] removeContact failed:`, error.message);
    return res.status(500).json({ success: false, message: error.message });
  }
};

/**
 * PUT /api/user/fcm-token
 */
exports.updateFcmToken = async (req, res) => {
  try {
    const { fcmToken } = req.body;
    const current = (await db.getUser(req.userId)) || { id: req.userId };

    await db.upsertUser({
      ...current,
      fcm_token: fcmToken,
    });

    return res.json({
      success: true,
      message: 'FCM token registered successfully',
    });
  } catch (error) {
    console.error(`[User] updateFcmToken failed:`, error.message);
    return res.status(500).json({ success: false, message: error.message });
  }
};

