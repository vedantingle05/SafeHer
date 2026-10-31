/**
 * Storage Utility
 * Manages evidence files (audio, image, sensor snapshots).
 * Uses Supabase Storage if configured, or saves to local backend/uploads/ folder.
 */

const fs = require('fs');
const path = require('path');
const db = require('./db');

const UPLOADS_DIR = path.join(__dirname, '..', 'uploads');
const BUCKET_NAME = process.env.SUPABASE_STORAGE_BUCKET || 'evidence';

function ensureLocalUploadsDir() {
  if (!fs.existsSync(UPLOADS_DIR)) {
    fs.mkdirSync(UPLOADS_DIR, { recursive: true });
  }
}

async function ensureBucket() {
  ensureLocalUploadsDir();
  const supabase = db.getSupabaseClient();
  if (!supabase) return;

  try {
    const { data: buckets, error } = await supabase.storage.listBuckets();
    if (error) {
      console.warn('⚠️ Could not list Supabase storage buckets:', error.message);
      return;
    }
    const exists = buckets.some((b) => b.name === BUCKET_NAME);
    if (!exists) {
      await supabase.storage.createBucket(BUCKET_NAME, { public: true });
      console.log(`📦 Created Supabase bucket '${BUCKET_NAME}'`);
    }
  } catch (err) {
    console.warn('⚠️ ensureBucket warning:', err.message);
  }
}

async function uploadFile(fileBuffer, originalname, folder = 'evidence', mimeType = 'application/octet-stream', req = null) {
  ensureLocalUploadsDir();
  const ext = path.extname(originalname) || '.dat';
  const fileName = `${folder}_${Date.now()}_${Math.random().toString(36).substring(2, 8)}${ext}`;
  const supabase = db.getSupabaseClient();

  if (supabase) {
    try {
      const storagePath = `${folder}/${fileName}`;
      const { error } = await supabase.storage
        .from(BUCKET_NAME)
        .upload(storagePath, fileBuffer, { contentType: mimeType, upsert: true });

      if (!error) {
        const { data: publicData } = supabase.storage.from(BUCKET_NAME).getPublicUrl(storagePath);
        if (publicData?.publicUrl) {
          return publicData.publicUrl;
        }
      }
    } catch (err) {
      console.warn('⚠️ Supabase storage upload failed, saving locally:', err.message);
    }
  }

  // Local storage fallback
  const filePath = path.join(UPLOADS_DIR, fileName);
  fs.writeFileSync(filePath, fileBuffer);

  const host = req ? req.get('host') : `localhost:${process.env.PORT || 5000}`;
  const protocol = req ? req.protocol : 'http';
  return `${protocol}://${host}/uploads/${fileName}`;
}

module.exports = {
  ensureBucket,
  uploadFile,
  UPLOADS_DIR,
};

