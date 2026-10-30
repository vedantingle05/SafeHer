/// AuthService
/// Wraps Supabase Auth and exposes a small API for screens.
/// Profile data is loaded from GET /api/user/profile after every sign-in.

import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/data_models.dart';
import 'api_service.dart';

const bool _useDevAuth = bool.fromEnvironment('USE_DEV_AUTH', defaultValue: false);

/// Deep link Supabase should redirect to after the user clicks the email
/// confirmation link. This must also be registered in
/// Supabase Dashboard → Authentication → URL Configuration → Redirect URLs.
const String _authRedirectUrl = 'io.supabase.safeher://login-callback/';

class AuthService extends ChangeNotifier {
  final ApiService apiService;
  final SupabaseClient _sb = Supabase.instance.client;

  UserModel? _currentUser;
  bool _isLoading = false;
  bool _isProfileLoading = false;
  String? _error;
  bool _emailNotConfirmed = false;
  String? _lastAuthEmail;
  StreamSubscription<AuthState>? _authSub;

  static const String _profileCacheKey = 'cached_profile_v1';

  AuthService({required this.apiService}) {
    // Restore cached profile so the home/profile screens have something to
    // render immediately on cold start, before the network call completes.
    _restoreCachedProfile();

    _authSub = _sb.auth.onAuthStateChange.listen((state) {
      final event = state.event;
      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.tokenRefreshed ||
          event == AuthChangeEvent.userUpdated) {
        fetchProfile().catchError((e) {
          debugPrint('⚠️ Profile refresh after auth event failed: $e');
        });
      } else if (event == AuthChangeEvent.signedOut) {
        _currentUser = null;
        _clearCachedProfile();
        notifyListeners();
      }
    });

    if (_sb.auth.currentSession != null) {
      fetchProfile().catchError((e) {
        debugPrint('⚠️ Cold-start profile load failed: $e');
      });
    }
  }

  Future<void> _restoreCachedProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_profileCacheKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      // Only restore if we actually still have a session; otherwise cached
      // data could leak between accounts.
      if (_sb.auth.currentSession == null) return;
      _currentUser = UserModel.fromJson(data);
      debugPrint('📦 Restored cached profile for ${_currentUser!.email}');
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ Profile cache restore failed: $e');
    }
  }

  Future<void> _persistCachedProfile() async {
    if (_currentUser == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = _currentUser!;
      await prefs.setString(
        _profileCacheKey,
        jsonEncode({
          'id': user.id,
          'name': user.name,
          'email': user.email,
          'phone': user.phone,
          'profileImage': user.profileImage,
          'emergencyContacts':
              user.emergencyContacts.map((c) => c.toJson()..['id'] = c.id).toList(),
        }),
      );
    } catch (e) {
      debugPrint('⚠️ Profile cache write failed: $e');
    }
  }

  Future<void> _clearCachedProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_profileCacheKey);
    } catch (_) {}
  }

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _sb.auth.currentSession != null;
  bool get isProfileLoaded => _currentUser != null;
  bool get isProfileLoading => _isProfileLoading;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// True if the most recent login attempt failed because the user has not
  /// clicked the confirmation link yet. UI uses this to show a "Resend
  /// confirmation email" button.
  bool get emailNotConfirmed => _emailNotConfirmed;

  /// The email used in the last register/login/resend call — used so the UI
  /// can offer "Resend confirmation email" without re-prompting.
  String? get lastAuthEmail => _lastAuthEmail;

  /// Wait until profile is loaded (or fails). Used by splash / OAuth navigation.
  Future<bool> ensureProfileLoaded() async {
    if (_currentUser != null) return true;
    if (!isAuthenticated) return false;
    await fetchProfile();
    return _currentUser != null;
  }

  UserModel _userFromSupabaseUser(User user) {
    final email = user.email ?? '';
    final meta = user.userMetadata ?? {};
    final name = (meta['name'] as String?) ??
        (meta['full_name'] as String?) ??
        (email.contains('@') ? email.split('@').first : 'SafeHer User');
    final phone = meta['phone'] as String?;
    return UserModel(
      id: user.id,
      name: name,
      email: email,
      phone: phone,
      emergencyContacts: const [],
    );
  }

  /// Registration outcome.
  ///
  /// - [signedIn]: Account created successfully (already confirmed — the
  ///   backend creates it via the Admin API with email_confirm=true, so NO
  ///   confirmation email is sent). The user can sign in immediately.
  /// - [needsEmailConfirmation]: Retained for compatibility but no longer
  ///   produced by this flow.
  /// - [failed]: Network error, invalid input, or email already exists.
  ///
  /// Registration uses `supabase.auth.signUp` directly (works with the anon
  /// key). To create accounts WITHOUT a confirmation email, turn OFF
  /// "Confirm email" in Supabase → Authentication → Providers → Email; then
  /// signUp returns a session immediately and sends no email.
  Future<RegisterResult> register({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async {
    final trimmedEmail = email.trim();
    _setLoading(true);
    _error = null;
    _emailNotConfirmed = false;
    _lastAuthEmail = trimmedEmail;
    try {
      if (_useDevAuth) {
        final prefs = await SharedPreferences.getInstance();
        final user = {
          'name': name,
          'email': trimmedEmail,
          'phone': phone ?? '',
        };
        await prefs.setString('dev_user', jsonEncode(user));
        _currentUser = UserModel.fromJson(user);
        notifyListeners();
        return RegisterResult.signedIn;
      }

      final res = await _sb.auth.signUp(
        email: trimmedEmail,
        password: password,
        emailRedirectTo: _authRedirectUrl,
        data: {
          'name': name.trim(),
          if (phone != null && phone.isNotEmpty) 'phone': phone.trim(),
        },
      );

      // With "Confirm email" turned OFF in Supabase, signUp returns a session
      // immediately and sends no email → account is created and ready to use.
      if (res.session != null) {
        debugPrint('✅ Account created and auto-confirmed for $trimmedEmail');
        return RegisterResult.signedIn;
      }
      // If "Confirm email" is still ON, no session is issued and Supabase
      // tries to send a confirmation email.
      if (res.user != null) {
        debugPrint('📧 Account created, awaiting email confirmation for $trimmedEmail');
        return RegisterResult.needsEmailConfirmation;
      }
      _error = 'Registration failed. Please try again.';
      notifyListeners();
      return RegisterResult.failed;
    } on AuthException catch (e) {
      debugPrint('❌ Register AuthException: code=${e.statusCode} msg=${e.message}');
      _error = _mapAuthError(e);
      notifyListeners();
      return RegisterResult.failed;
    } on SocketException catch (e) {
      _error = 'Network error. Could not reach Supabase. (${e.message})';
      debugPrint('❌ Register SocketException: $e');
      notifyListeners();
      return RegisterResult.failed;
    } catch (e) {
      _error = 'Registration failed. Please try again.';
      debugPrint('❌ Register unexpected: $e');
      notifyListeners();
      return RegisterResult.failed;
    } finally {
      _setLoading(false);
    }
  }

  /// Re-send the confirmation email for an unverified account. Supabase
  /// rate-limits this to ~once per 60 seconds per email.
  Future<bool> resendConfirmationEmail(String email) async {
    final trimmedEmail = email.trim();
    _lastAuthEmail = trimmedEmail;
    try {
      await _sb.auth.resend(
        type: OtpType.signup,
        email: trimmedEmail,
        emailRedirectTo: _authRedirectUrl,
      );
      _error = null;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _error = _mapAuthError(e);
      debugPrint('❌ Resend AuthException: code=${e.statusCode} msg=${e.message}');
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Could not resend confirmation email. Please try again shortly.';
      debugPrint('❌ Resend unexpected: $e');
      notifyListeners();
      return false;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    final trimmedEmail = email.trim();
    _setLoading(true);
    _error = null;
    _emailNotConfirmed = false;
    _lastAuthEmail = trimmedEmail;
    try {
      if (_useDevAuth) {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('dev_user');
        if (raw != null) {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          _currentUser = UserModel.fromJson(data);
          notifyListeners();
          return true;
        }
        _error = 'No local dev user found. Register first.';
        notifyListeners();
        return false;
      }

      final res = await _sb.auth.signInWithPassword(
        email: trimmedEmail,
        password: password,
      );
      debugPrint('🔐 login response: session=${res.session != null}, user=${res.user?.email}');

      // Check if email is verified (Supabase sets email_confirmed_at)
      if (res.user?.emailConfirmedAt == null) {
        _error = 'Please verify your email before logging in. Check your inbox for a confirmation link.';
        notifyListeners();
        return false;
      }

      // Defensive: signInWithPassword should throw on failure, but if a
      // session somehow isn't issued, treat that as a failure too.
      if (res.session == null) {
        _error = 'Login failed. Please try again.';
        notifyListeners();
        return false;
      }

      await fetchProfile(allowFallback: true);
      if (_currentUser == null) {
        _error ??= 'Signed in but could not load your profile. Check your connection and try again.';
        notifyListeners();
        return false;
      }
      return true;
    } on AuthException catch (e) {
      debugPrint('❌ Login AuthException: code=${e.statusCode} msg=${e.message}');
      _error = _mapAuthError(e);
      notifyListeners();
      return false;
    } on SocketException catch (e) {
      _error = 'Network error. Could not reach Supabase servers. (${e.message})';
      debugPrint('❌ AuthService.login SocketException: $e');
      notifyListeners();
      return false;
    } catch (e) {
      _error = _mapAuthError(e is AuthException ? e : AuthException(e.toString()));
      debugPrint('❌ AuthService.login error: $e');
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }



  /// Translate Supabase auth errors into user-facing messages and set
  /// [_emailNotConfirmed] when applicable so the UI can show a Resend button.
  ///
  /// Supabase error codes worth distinguishing:
  ///   email_not_confirmed   → user must click confirmation link first
  ///   invalid_credentials   → wrong email/password
  ///   user_already_exists   → registering an existing account
  ///   over_email_send_rate_limit → SMTP rate limit hit
  ///   weak_password         → password too short / weak
  String _mapAuthError(AuthException e) {
    final code = e.code?.toLowerCase() ?? '';
    final msg = e.message.toLowerCase();

    final isEmailNotConfirmed = code == 'email_not_confirmed' ||
        msg.contains('email not confirmed') ||
        msg.contains('not confirmed');
    if (isEmailNotConfirmed) {
      _emailNotConfirmed = true;
      return 'Please confirm your email first. Check your inbox (and spam) for the confirmation link, or tap "Resend" below.';
    }
    if (code == 'invalid_credentials' || msg.contains('invalid login credentials')) {
      return 'Wrong email or password.';
    }
    if (code == 'user_already_exists' || msg.contains('already registered') || msg.contains('already exists')) {
      return 'An account with this email already exists. Try signing in instead.';
    }
    // Supabase returns this when its SMTP layer fails (default sender rate
    // limit, or custom SMTP misconfigured). The user can't act on the raw
    // server message — explain in plain language.
    if (msg.contains('error sending confirmation email') ||
        msg.contains('error sending recovery email') ||
        (code == 'unexpected_failure' && msg.contains('email'))) {
      return 'We couldn\'t send the confirmation email right now. '
          'Supabase\'s default mail sender is rate-limited; please try '
          'again in about an hour, or ask the project admin to configure '
          'a custom SMTP provider.';
    }
    if (code.contains('rate_limit') || msg.contains('rate limit') ||
        msg.contains('over_email_send_rate_limit')) {
      return 'Too many email attempts. Please wait a few minutes and try again.';
    }
    if (code == 'weak_password' || msg.contains('weak password') || msg.contains('password should be')) {
      return e.message; // Supabase's own message is most informative here.
    }
    return e.message;
  }

  Future<bool> signInWithGoogle() async {
    _setLoading(true);
    _error = null;
    _emailNotConfirmed = false;
    try {
      // `inAppBrowserView` keeps the Flutter activity in the foreground while
      // the Custom Tab is shown. With `externalApplication` Android often
      // background-kills the app on low-RAM devices while the user is on
      // the Google sign-in page — which produced the symptom of "app
      // returns to account-selection screen". Custom Tab survives that.
      final ok = await _sb.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _authRedirectUrl,
        authScreenLaunchMode: LaunchMode.inAppBrowserView,
      );
      return ok;
    } on AuthException catch (e) {
      _error = _mapAuthError(e);
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Google sign-in failed. Please try again.';
      debugPrint('❌ Google sign-in error: $e');
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> fetchProfile({bool allowFallback = false}) async {
    if (_sb.auth.currentSession == null) {
      try {
        debugPrint('🔄 No session found; attempting Supabase refresh');
        await _sb.auth.refreshSession();
      } catch (e) {
        debugPrint('⚠️ Supabase session refresh failed: $e');
      }
    }

    if (_sb.auth.currentSession == null) {
      _currentUser = null;
      notifyListeners();
      return;
    }

    _isProfileLoading = true;
    notifyListeners();

    try {
      debugPrint('🔄 Fetching profile from ${ApiService.baseUrl}/user/profile');
      final res = await apiService.get('/user/profile');
      final data = res['data'];
      if (data == null || data is! Map<String, dynamic>) {
        throw Exception('Profile response missing data field');
      }
      _currentUser = UserModel.fromJson(data);
      _error = null;
      debugPrint('✅ Profile loaded: ${_currentUser!.name} (${_currentUser!.email})');
      unawaited(_persistCachedProfile());
      await _registerFcmTokenIfPossible();
    } on ApiException catch (e) {
      debugPrint('❌ fetchProfile ApiException: $e');
      _error = e.statusCode == 401
          ? 'Session expired. Please sign in again.'
          : 'Could not load profile: ${e.message}';
      if (e.statusCode == 401) {
        await _sb.auth.signOut();
        _currentUser = null;
      } else if (allowFallback && _sb.auth.currentSession?.user != null) {
        _currentUser = _userFromSupabaseUser(_sb.auth.currentSession!.user);
        _error = null;
      }
    } catch (e) {
      debugPrint('❌ fetchProfile error: $e');
      _error =
          'Could not reach server at ${ApiService.baseUrl}. Start the backend or set API_BASE_URL.';
      if (allowFallback && _sb.auth.currentSession?.user != null) {
        _currentUser = _userFromSupabaseUser(_sb.auth.currentSession!.user);
        _error = null;
      }
    } finally {
      _isProfileLoading = false;
      notifyListeners();
    }
  }

  Future<void> _registerFcmTokenIfPossible() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await apiService.put('/user/fcm-token', {'fcmToken': token});
      debugPrint('✅ FCM token registered with backend');
    } catch (e) {
      debugPrint('ℹ️ FCM token not registered (Firebase may be unconfigured): $e');
    }
  }

  Future<void> logout() async {
    await _sb.auth.signOut();
    _currentUser = null;
    ApiService.clearCache();
    await _clearCachedProfile();
    notifyListeners();
  }

  Future<bool> addEmergencyContact(EmergencyContact contact) async {
    try {
      await apiService.post('/user/contacts', contact.toJson());
      // Invalidate the cached profile so the refetch below actually hits the
      // server and reflects the new contact (otherwise the 1-min ApiService
      // cache serves the old profile with the contact missing).
      ApiService.clearCacheFor('/user/profile');
      await fetchProfile();
      return true;
    } catch (e) {
      _error = 'Failed to add contact.';
      debugPrint('❌ addEmergencyContact failed: $e');
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeEmergencyContact(String contactId) async {
    try {
      await apiService.delete('/user/contacts/$contactId');
      ApiService.clearCacheFor('/user/profile');
      await fetchProfile();
      return true;
    } catch (e) {
      _error = 'Failed to remove contact.';
      debugPrint('❌ removeEmergencyContact failed: $e');
      notifyListeners();
      return false;
    }
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

enum RegisterResult { signedIn, needsEmailConfirmation, failed }
