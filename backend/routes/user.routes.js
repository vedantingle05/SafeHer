/**
 * User Routes (all protected by JWT)
 * GET    /api/user/profile         - Get profile
 * PUT    /api/user/profile         - Update profile
 * POST   /api/user/contacts        - Add emergency contact
 * DELETE /api/user/contacts/:id    - Remove emergency contact
 * PUT    /api/user/fcm-token       - Update FCM token
 */

const router = require('express').Router();
const jwtMiddleware = require('../middleware/jwt.middleware');
const {
  getProfile,
  updateProfile,
  addContact,
  removeContact,
  updateFcmToken,
} = require('../controllers/user.controller');

router.use(jwtMiddleware); // All routes require JWT authentication

router.get('/profile', getProfile);
router.put('/profile', updateProfile);
router.post('/contacts', addContact);
router.delete('/contacts/:contactId', removeContact);
router.put('/fcm-token', updateFcmToken);

module.exports = router;
