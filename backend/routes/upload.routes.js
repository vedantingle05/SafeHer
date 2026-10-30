const router = require('express').Router();
const multer = require('multer');
const auth = require('../middleware/auth.middleware');
const { upload } = require('../controllers/upload.controller');

const memoryUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 20 * 1024 * 1024 }, // 20MB
});

router.use(auth);
router.post('/', memoryUpload.single('file'), upload);

module.exports = router;
