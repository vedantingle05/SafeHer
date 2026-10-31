/**
 * SafeHer Unified Database Adapter
 * Seamlessly interfaces with Supabase when configured, or provides a
 * fast, resilient local file-backed database (data/db.json) for development.
 */

const fs = require('fs');
const path = require('path');
const { createClient } = require('@supabase/supabase-js');

const DATA_DIR = path.join(__dirname, '..', 'data');
const DB_FILE = path.join(DATA_DIR, 'db.json');

let supabase = null;
const hasSupabaseConfig = Boolean(
  process.env.SUPABASE_URL &&
  process.env.SUPABASE_SERVICE_ROLE_KEY &&
  !process.env.SUPABASE_URL.includes('your-project') &&
  !process.env.SUPABASE_SERVICE_ROLE_KEY.includes('your_service_role')
);

if (hasSupabaseConfig) {
  try {
    supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });
    console.log('🔗 Connected to Supabase backend database');
  } catch (err) {
    console.warn('⚠️ Could not initialize Supabase client:', err.message);
  }
}

// ──── Local Fallback Database Helper ────
function ensureLocalDb() {
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  }
  if (!fs.existsSync(DB_FILE)) {
    const initial = { users: {}, alerts: [] };
    fs.writeFileSync(DB_FILE, JSON.stringify(initial, null, 2));
  }
}

function readLocalDb() {
  ensureLocalDb();
  try {
    const content = fs.readFileSync(DB_FILE, 'utf-8');
    return JSON.parse(content || '{"users":{}, "alerts":[]}');
  } catch {
    return { users: {}, alerts: [] };
  }
}

function writeLocalDb(data) {
  ensureLocalDb();
  fs.writeFileSync(DB_FILE, JSON.stringify(data, null, 2));
}

// ──── Database Operations ────
const db = {
  isSupabaseAvailable: () => Boolean(supabase),

  getSupabaseClient: () => supabase,

  // User Operations
  async getUser(userId) {
    if (supabase) {
      const { data, error } = await supabase
        .from('users')
        .select('*')
        .eq('id', userId)
        .maybeSingle();
      if (!error && data) return data;
    }
    const local = readLocalDb();
    return local.users[userId] || null;
  },

  async upsertUser(user) {
    if (supabase) {
      const { data, error } = await supabase
        .from('users')
        .upsert(user)
        .select()
        .single();
      if (!error && data) return data;
    }
    const local = readLocalDb();
    const existing = local.users[user.id] || {};
    const updated = {
      ...existing,
      ...user,
      emergency_contacts: user.emergency_contacts || existing.emergency_contacts || [],
      updated_at: new Date().toISOString(),
    };
    local.users[user.id] = updated;
    writeLocalDb(local);
    return updated;
  },

  // Alert Operations
  async createAlert(alert) {
    const newAlert = {
      id: alert.id || 'alt_' + Date.now() + '_' + Math.random().toString(36).substr(2, 6),
      user_id: alert.user_id,
      type: alert.type,
      location: alert.location,
      status: alert.status || 'triggered',
      confidence: alert.confidence,
      evidence_urls: alert.evidence_urls || [],
      created_at: new Date().toISOString(),
    };

    // Always persist to resilient local DB so records are never lost
    const local = readLocalDb();
    local.alerts.unshift(newAlert);
    writeLocalDb(local);

    if (supabase) {
      try {
        const { data, error } = await supabase
          .from('alerts')
          .insert(newAlert)
          .select()
          .single();
        if (!error && data) return data;
      } catch (err) {
        console.warn('⚠️ Supabase createAlert error:', err.message);
      }
    }

    return newAlert;
  },

  async getAlerts(userId, { page = 1, limit = 20 } = {}) {
    const local = readLocalDb();
    const map = new Map();

    // 1. Add local alerts unconditionally
    for (const a of local.alerts || []) {
      map.set(a.id, a);
    }

    // 2. Merge Supabase alerts if available
    if (supabase) {
      try {
        const { data, error } = await supabase
          .from('alerts')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', { ascending: false });
        if (!error && data) {
          for (const sAlert of data) {
            map.set(sAlert.id, sAlert);
          }
        }
      } catch (err) {
        console.warn('⚠️ Supabase getAlerts warning:', err.message);
      }
    }

    const merged = Array.from(map.values());
    merged.sort((a, b) => new Date(b.created_at || 0) - new Date(a.created_at || 0));

    const startIndex = (page - 1) * limit;
    const paginated = merged.slice(startIndex, startIndex + limit);
    return { alerts: paginated, total: merged.length };
  },

  async getAlertById(alertId) {
    if (supabase) {
      try {
        const { data, error } = await supabase
          .from('alerts')
          .select('*')
          .eq('id', alertId)
          .maybeSingle();
        if (!error && data) return data;
      } catch (err) {
        console.warn('⚠️ Supabase getAlertById error:', err.message);
      }
    }

    const local = readLocalDb();
    return local.alerts.find((a) => a.id === alertId) || null;
  },

  async updateAlertStatus(alertId, status) {
    if (supabase) {
      try {
        const { data, error } = await supabase
          .from('alerts')
          .update({ status, resolved_at: new Date().toISOString() })
          .eq('id', alertId)
          .select()
          .single();
        if (!error && data) return data;
      } catch (err) {
        console.warn('⚠️ Supabase updateAlertStatus error:', err.message);
      }
    }

    const local = readLocalDb();
    const alert = local.alerts.find((a) => a.id === alertId);
    if (alert) {
      alert.status = status;
      alert.resolved_at = new Date().toISOString();
      writeLocalDb(local);
    }
    return alert;
  },
};

module.exports = db;

