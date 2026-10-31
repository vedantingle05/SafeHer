/**
 * Alert Controller
 * Handles CRUD and status updates for safety alerts.
 */

const db = require('../db/db');

function shapeAlert(alert) {
  if (!alert) return null;
  return {
    id: alert.id,
    userId: alert.user_id || alert.userId,
    type: alert.type,
    location: alert.location || {
      latitude: alert.latitude || 0.0,
      longitude: alert.longitude || 0.0,
      address: alert.address || null,
    },
    status: alert.status || 'triggered',
    confidence: alert.confidence !== undefined ? alert.confidence : null,
    evidenceUrls: alert.evidence_urls || alert.evidenceUrls || [],
    createdAt: alert.created_at || new Date().toISOString(),
    resolvedAt: alert.resolved_at || null,
  };
}

/**
 * POST /api/alert
 */
exports.createAlert = async (req, res) => {
  try {
    const { type, location, confidence, evidenceUrls } = req.body;

    const alert = await db.createAlert({
      user_id: req.userId,
      type: type || 'sos',
      location: location || { latitude: 0.0, longitude: 0.0 },
      confidence: confidence,
      evidence_urls: evidenceUrls || [],
      status: 'triggered',
    });

    return res.status(201).json({
      success: true,
      data: shapeAlert(alert),
    });
  } catch (error) {
    console.error('[Alert] createAlert error:', error.message);
    return res.status(500).json({ success: false, message: error.message });
  }
};

/**
 * GET /api/alert
 */
exports.getAlerts = async (req, res) => {
  try {
    const page = parseInt(req.query.page, 10) || 1;
    const limit = parseInt(req.query.limit, 10) || 20;

    const { alerts, total } = await db.getAlerts(req.userId, { page, limit });

    return res.json({
      success: true,
      data: {
        alerts: alerts.map(shapeAlert),
        total,
        page,
        limit,
      },
    });
  } catch (error) {
    console.error('[Alert] getAlerts error:', error.message);
    return res.status(500).json({ success: false, message: error.message });
  }
};

/**
 * GET /api/alert/:id
 */
exports.getAlertById = async (req, res) => {
  try {
    const alert = await db.getAlertById(req.params.id);
    if (!alert) {
      return res.status(404).json({
        success: false,
        message: 'Alert not found',
      });
    }

    return res.json({
      success: true,
      data: shapeAlert(alert),
    });
  } catch (error) {
    console.error('[Alert] getAlertById error:', error.message);
    return res.status(500).json({ success: false, message: error.message });
  }
};

/**
 * PATCH /api/alert/:id/status
 */
exports.updateAlertStatus = async (req, res) => {
  try {
    const { status } = req.body;
    if (!status) {
      return res.status(400).json({
        success: false,
        message: 'Status is required',
      });
    }

    const updated = await db.updateAlertStatus(req.params.id, status);
    if (!updated) {
      return res.status(404).json({
        success: false,
        message: 'Alert not found',
      });
    }

    return res.json({
      success: true,
      data: shapeAlert(updated),
    });
  } catch (error) {
    console.error('[Alert] updateAlertStatus error:', error.message);
    return res.status(500).json({ success: false, message: error.message });
  }
};

