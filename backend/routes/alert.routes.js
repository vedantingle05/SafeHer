/**
 * Alert Routes (all protected by JWT)
 * POST   /api/alert            - Create alert
 * GET    /api/alert             - List alerts (paginated)
 * GET    /api/alert/:id         - Get single alert
 * PATCH  /api/alert/:id/status  - Update alert status
 */

const router = require('express').Router();
const jwtMiddleware = require('../middleware/jwt.middleware');
const {
  createAlert,
  getAlerts,
  getAlertById,
  updateAlertStatus,
} = require('../controllers/alert.controller');

router.use(jwtMiddleware);

router.post('/', createAlert);
router.get('/', getAlerts);
router.get('/:id', getAlertById);
router.patch('/:id/status', updateAlertStatus);

module.exports = router;
