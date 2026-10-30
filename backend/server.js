/**
 * SafeHer Backend Server
 * Production-ready with:
 * - Local JWT verification (fast)
 * - Proper error handling
 * - Service health checks
 * - Process cleanup on signals
 */

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const http = require('http');

const userRoutes = require('./routes/user.routes');
const alertRoutes = require('./routes/alert.routes');
const emergencyRoutes = require('./routes/emergency.routes');
const uploadRoutes = require('./routes/upload.routes');
const { ensureBucket } = require('./db/storage');

const app = express();
const PORT = process.env.PORT || 5000;
const HOST = process.env.HOST || '0.0.0.0';
let server = null;

// ──── Middleware ────
app.use(helmet());
app.use(cors({
  origin: '*',
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));
app.use(morgan('dev'));
app.use(express.json({ limit: '100mb' }));
app.use(express.urlencoded({ extended: true, limit: '100mb' }));

// ──── Health Check & Status ────
app.get('/', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'SafeHer API',
    version: '2.0.0',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  });
});

app.get('/health', (_req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
  });
});

// ──── API Routes (protected by JWT) ────
app.use('/api/user', userRoutes);
app.use('/api/alert', alertRoutes);
app.use('/api/emergency', emergencyRoutes);
app.use('/api/upload', uploadRoutes);

// ──── Global Error Handler ────
app.use((err, _req, res, _next) => {
  console.error('❌ Unhandled error:', {
    message: err.message,
    statusCode: err.statusCode || 500,
    stack: process.env.NODE_ENV === 'development' ? err.stack : undefined,
  });
  res.status(err.statusCode || 500).json({
    success: false,
    message: err.message || 'Internal Server Error',
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack }),
  });
});

// ──── 404 Handler ────
app.use((_req, res) => {
  res.status(404).json({
    success: false,
    message: 'Route not found',
  });
});

// ──── Startup & Validation ────
const startServer = async () => {
  // Validate required environment variables
  const missing = [];
  if (!process.env.SUPABASE_URL) missing.push('SUPABASE_URL');
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) missing.push('SUPABASE_SERVICE_ROLE_KEY');
  if (!process.env.SUPABASE_JWT_SECRET) {
    console.warn('⚠️ SUPABASE_JWT_SECRET not set — using slow Supabase verification');
  }

  if (missing.length > 0) {
    console.error(`❌ Missing environment variables: ${missing.join(', ')}`);
    process.exit(1);
  }

  try {
    // Test storage bucket
    await ensureBucket();
    console.log('✅ Supabase storage ready');
  } catch (e) {
    console.error('⚠️ Storage initialization failed —', e.message);
  }

  return new Promise((resolve, reject) => {
    server = http.createServer(app);

    server.listen(PORT, HOST, () => {
      console.log(`\n${'='.repeat(50)}`);
      console.log(`🚀 SafeHer API v2.0.0`);
      console.log(`   Server: http://${HOST}:${PORT}`);
      console.log(`   Supabase: ${process.env.SUPABASE_URL}`);
      console.log(`   Mode: ${process.env.NODE_ENV || 'production'}`);
      console.log(`${'='.repeat(50)}\n`);
      resolve(server);
    });

    server.on('error', (err) => {
      if (err.code === 'EADDRINUSE') {
        console.error(`❌ Port ${PORT} is already in use`);
        console.error('   Try: lsof -i :5000  OR  netstat -ano | findstr :5000');
        console.error('   Kill with: kill -9 <PID>  OR  taskkill /PID <PID> /F');
      } else {
        console.error('❌ Server error:', err.message);
      }
      reject(err);
    });

    // Graceful shutdown
    const shutdown = (signal) => {
      console.log(`\n[${signal}] Shutting down gracefully...`);
      server.close(() => {
        console.log('✅ Server closed');
        process.exit(0);
      });
      setTimeout(() => {
        console.error('❌ Forced shutdown after timeout');
        process.exit(1);
      }, 10000);
    };

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));
  });
};

// Start server if not in test mode
if (require.main === module) {
  startServer().catch((err) => {
    console.error('Failed to start server:', err);
    process.exit(1);
  });
}

module.exports = { app, startServer };
