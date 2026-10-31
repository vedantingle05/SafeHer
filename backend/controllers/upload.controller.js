/**
 * Upload Controller
 * Handles multimedia evidence uploads (audio recordings, pictures, sensor data).
 */

const { uploadFile } = require('../db/storage');

exports.upload = async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: 'No file provided in multipart payload',
      });
    }

    const folder = req.query.folder || 'evidence';
    const publicUrl = await uploadFile(
      req.file.buffer,
      req.file.originalname,
      folder,
      req.file.mimetype,
      req
    );

    return res.status(201).json({
      success: true,
      data: {
        url: publicUrl,
        size: req.file.size,
        mimetype: req.file.mimetype,
      },
    });
  } catch (error) {
    console.error('[Upload] Error uploading file:', error.message);
    return res.status(500).json({
      success: false,
      message: 'Failed to process evidence upload',
    });
  }
};

