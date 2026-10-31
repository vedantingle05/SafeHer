/// Login Screen
/// Email/password login with Google Sign-In option.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../themes/app_theme.dart';
import 'signup_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  double _progressValue = 0.0;
  Timer? _progressTimer;
  AuthService? _authService;

  // Reentry guard for the auth listener — Supabase fires onAuthStateChange
  // multiple times during OAuth (signedIn, tokenRefreshed, etc.).
  bool _handlingAuthChange = false;
  bool _hasNavigatedAfterAuth = false;

  @override
  void initState() {
    super.initState();
    // After Google OAuth deep-link returns, the session flips on; navigate then.
    _authService = context.read<AuthService>();
    _authService?.addListener(_onAuthChanged);
  }

  Future<void> _onAuthChanged() async {
    if (_handlingAuthChange || _hasNavigatedAfterAuth) return;
    _handlingAuthChange = true;
    try {
      final auth = context.read<AuthService>();
      if (!auth.isAuthenticated || !mounted) return;

      // Bound the post-OAuth profile fetch. If the backend is unreachable we
      // still want to navigate to Home (which has its own retry UI) — leaving
      // the user stuck on the login screen with no feedback is the bug we hit
      // before.
      if (!auth.isProfileLoaded) {
        await auth.ensureProfileLoaded().timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            debugPrint('⚠️ Post-OAuth profile load timed out — navigating anyway');
            return false;
          },
        );
      }
      if (!mounted) return;

      if (auth.isAuthenticated) {
        _hasNavigatedAfterAuth = true;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      } else if (auth.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(auth.error!),
            backgroundColor: AppColors.emergency,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ _onAuthChanged error: $e');
    } finally {
      _handlingAuthChange = false;
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthService>();
    _startProgress();
    final success = await auth.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    _stopProgress();

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
      return;
    }

    if (auth.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error!),
          backgroundColor: auth.emailNotConfirmed
              ? AppColors.safe
              : AppColors.emergency,
          duration: const Duration(seconds: 5),
        ),
      );
    }
    // Trigger rebuild so the Resend button shows up when relevant.
    setState(() {});
  }

  Future<void> _handleResendConfirmation() async {
    final auth = context.read<AuthService>();
    final email = auth.lastAuthEmail ?? _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email first.')),
      );
      return;
    }

    final ok = await auth.resendConfirmationEmail(email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Confirmation email resent to $email. Check your inbox (and spam).'
              : (auth.error ?? 'Could not resend. Try again shortly.'),
        ),
        backgroundColor: ok ? AppColors.safe : AppColors.emergency,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    final auth = context.read<AuthService>();
    
    try {
      _startProgress();
      
      // Add timeout to OAuth
      final launched = await Future.any([
        auth.signInWithGoogle(),
        Future.delayed(const Duration(seconds: 60), () => false),
      ]);
      
      _stopProgress();
      
      if (!launched && mounted && auth.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google sign-in failed: ${auth.error}'),
            backgroundColor: AppColors.emergency,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      _stopProgress();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.emergency,
          ),
        );
      }
    }
  }

  void _startProgress() {
    _progressTimer?.cancel();
    _progressValue = 0.05;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 120), (timer) {
      if (!mounted) return;
      setState(() {
        _progressValue = (_progressValue + 0.06).clamp(0.0, 0.95);
      });
    });
  }

  void _stopProgress() {
    _progressTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _progressValue = 1.0;
    });
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {
        _progressValue = 0.0;
      });
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _authService?.removeListener(_onAuthChanged);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),

                // Logo
                Icon(Icons.shield, size: 64, color: AppColors.primary),
                const SizedBox(height: 16),
                const Text(
                  'Welcome Back',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to continue',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 48),

                // Email field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Email is required';
                    if (!value.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Password field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Password is required';
                    if (value.length < 6) return 'Minimum 6 characters';
                    return null;
                  },
                ),

                const SizedBox(height: 32),

                if (_progressValue > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LinearProgressIndicator(value: _progressValue),
                      const SizedBox(height: 10),
                      Text(
                        'Signing in... ${(_progressValue * 100).round()}%',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),

                // Login button + conditional Resend confirmation button.
                Consumer<AuthService>(
                  builder: (context, auth, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton(
                          onPressed: auth.isLoading ? null : _handleLogin,
                          child: auth.isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Sign In'),
                        ),
                        if (auth.emailNotConfirmed) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: auth.isLoading
                                ? null
                                : _handleResendConfirmation,
                            icon: const Icon(Icons.mail_outline),
                            label: const Text('Resend confirmation email'),
                          ),
                        ],
                      ],
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Divider
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'OR',
                        style: TextStyle(
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withOpacity(0.5),
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),

                const SizedBox(height: 24),

                // Google sign-in button
                OutlinedButton.icon(
                  onPressed: _handleGoogleSignIn,
                  icon: const Icon(Icons.g_mobiledata, size: 28),
                  label: const Text('Continue with Google'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                const SizedBox(height: 32),



                // Sign up link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: TextStyle(
                        color: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color
                            ?.withOpacity(0.6),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SignupScreen()),
                      ),
                      child: const Text(
                        'Sign Up',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
