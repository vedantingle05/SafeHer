/// SafeHer - AI-Based Personal Safety Monitoring System

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/sensor_service.dart';
import 'services/alert_service.dart';
import 'services/ai_inference_service.dart';
import 'services/evidence_service.dart';
import 'services/safety_monitoring_service.dart';
import 'themes/app_theme.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Critical-path boot ────────────────────────────────────────────────
  // Only initialize what the *first* frame depends on. Heavy services
  // (Firebase, AI models, sensors) are deferred to background isolates
  // or lazy provider creation.
  unawaited(SystemChrome.setPreferredOrientations(
    [DeviceOrientation.portraitUp],
  ));

  const _defaultSupabaseUrl = 'https://ocurfsnqwgwuazsatbqu.supabase.co';
  const _defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9jdXJmc25xd2d3dWF6c2F0YnF1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY5NTY2OTksImV4cCI6MjA5MjUzMjY5OX0.vj-MOUSP61XqrWca0Jcy60jUuhwNCE8LPVia8UravcE';

  final supabaseUrl = const String.fromEnvironment('SUPABASE_URL',
      defaultValue: _defaultSupabaseUrl);
  final supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY',
      defaultValue: _defaultSupabaseAnonKey);

  debugPrint('Using Supabase URL: $supabaseUrl');

  // Supabase MUST be initialized before any provider that uses Supabase.instance.
  // SharedPreferences MUST be ready before runApp so ThemeProvider can load.
  // These two are the only blocking awaits in main.
  final results = await Future.wait([
    Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey),
    SharedPreferences.getInstance(),
  ]);
  final prefs = results[1] as SharedPreferences;

  // Firebase is needed only for FCM (push notifications). Defer it so the
  // first frame is not blocked by Firebase's plugin channel handshake.
  // FirebaseMessaging calls inside AuthService are already null-safe.
  unawaited(_initFirebaseInBackground());

  runApp(SafeHerApp(prefs: prefs));
}

Future<void> _initFirebaseInBackground() async {
  try {
    await Firebase.initializeApp();
    debugPrint('✅ Firebase initialized (background)');
  } catch (e) {
    debugPrint('ℹ️ Firebase not configured — push disabled. ($e)');
  }
}

class SafeHerApp extends StatelessWidget {
  final SharedPreferences prefs;
  const SafeHerApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Critical path — needed for first frame and routing.
        Provider<ApiService>(create: (_) => ApiService()),
        ChangeNotifierProvider<AuthService>(
          create: (ctx) => AuthService(apiService: ctx.read<ApiService>()),
        ),
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(prefs: prefs),
        ),

        // Heavy services — `lazy: true` defers construction until the first
        // `Provider.of`/`context.read`/`context.watch`. The home/monitoring
        // screens read these; splash and onboarding do not, so they no
        // longer pay this cost on cold start.
        ChangeNotifierProvider<SensorService>(
          create: (_) => SensorService()..startMonitoring(),
          lazy: false,
        ),
        ChangeNotifierProvider<AlertService>(
          create: (ctx) => AlertService(apiService: ctx.read<ApiService>()),
          lazy: true,
        ),
        Provider<AIInferenceService>(
          create: (_) => AIInferenceService(),
          lazy: true,
        ),
        Provider<EvidenceCaptureService>(
          create: (_) => EvidenceCaptureService(),
          lazy: true,
        ),
        ChangeNotifierProvider<SafetyMonitoringService>(
          create: (ctx) => SafetyMonitoringService(
            sensorService: ctx.read<SensorService>(),
            aiService: ctx.read<AIInferenceService>(),
            alertService: ctx.read<AlertService>(),
            evidenceService: ctx.read<EvidenceCaptureService>(),
            apiService: ctx.read<ApiService>(),
          ),
          lazy: true,
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'SafeHer',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
