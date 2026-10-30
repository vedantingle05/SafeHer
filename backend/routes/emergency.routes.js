/**
 * Emergency Routes (protected by JWT)
 * POST /api/emergency  - Trigger full emergency SOS
 */

const router = require('express').Router();
const jwtMiddleware = require('../middleware/jwt.middleware');
const { triggerEmergency } = require('../controllers/emergency.controller');

router.use(jwtMiddleware);

router.post('/', triggerEmergency);

module.exports = router;
