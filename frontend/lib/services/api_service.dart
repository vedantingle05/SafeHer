/// ApiService v2.0
/// Production-grade HTTP client with:
/// - Request timeouts (30s)
/// - Response caching for GET requests
/// - Proper error handling
/// - Offline detection

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:supabase_flutter/supabase_flutter.dart';

// Custom exception for API errors
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? responseBody;

  ApiException({
    required this.statusCode,
    required this.message,
    this.responseBody,
  });

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  /// Override at build time: --dart-define=API_BASE_URL=http://YOUR_IP:5000/api
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Cache for GET requests (TTL-based)
  static final Map<String, _CacheEntry> _cache = {};

  /// Request timeout
  static const Duration _timeout = Duration(seconds: 30);

  /// Cache TTL for profile (5 minutes)
  static const Duration _profileCacheTTL = Duration(minutes: 5);

  /// Cache TTL for other data (1 minute)
  static const Duration _dataCacheTTL = Duration(minutes: 1);

  /// Android emulator → 10.0.2.2; iOS simulator / desktop → localhost.
  /// Physical device: set API_BASE_URL to your machine's LAN IP.
  static String get baseUrl {
    final normalized = _normalizeApiBaseUrl(_envBaseUrl);
    if (normalized.isNotEmpty) return normalized;
    if (kIsWeb) return 'http://localhost:5000/api';
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:5000/api';
    }
    return 'http://localhost:5000/api';
  }

  static String _normalizeApiBaseUrl(String value) {
    if (value.isEmpty) return '';
    var url = value.trim();

    // Fix malformed http:/ to http://
    if (url.startsWith('http:/') && !url.startsWith('http://')) {
      url = url.replaceFirst('http:/', 'http://');
    }
    if (url.startsWith('https:/') && !url.startsWith('https://')) {
      url = url.replaceFirst('https:/', 'https://');
    }

    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
      debugPrint('❌ Invalid API_BASE_URL: $value');
      return '';
    }

    debugPrint('✅ API_BASE_URL normalized: $url');
    return url;
  }

  String? get _accessToken =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  /// GET request with caching
  Future<Map<String, dynamic>> get(
    String endpoint, {
    bool useCache = true,
  }) async {
    final cacheKey = 'GET:$endpoint';
    final cachedData = useCache ? _getFromCache(cacheKey) : null;

    if (cachedData != null) {
      debugPrint('💾 GET $endpoint (cached)');
      return cachedData;
    }

    debugPrint('→ GET $baseUrl$endpoint');
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl$endpoint'),
            headers: _headers,
          )
          .timeout(_timeout, onTimeout: () {
            throw ApiException(
              statusCode: 0,
              message: 'Request timeout. Backend may be unavailable.',
            );
          });

      final result = _handle(res);

      // Cache successful GET requests
      if (res.statusCode == 200) {
        _setCache(cacheKey, result);
      }

      return result;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        statusCode: 0,
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  /// POST request (no caching)
  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    debugPrint('→ POST $baseUrl$endpoint');
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(_timeout, onTimeout: () {
            throw ApiException(
              statusCode: 0,
              message: 'Request timeout',
            );
          });

      return _handle(res);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        statusCode: 0,
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  /// PUT request
  Future<Map<String, dynamic>> put(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    debugPrint('→ PUT $baseUrl$endpoint');
    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl$endpoint'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(_timeout, onTimeout: () {
            throw ApiException(
              statusCode: 0,
              message: 'Request timeout',
            );
          });

      return _handle(res);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        statusCode: 0,
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  /// PATCH request
  Future<Map<String, dynamic>> patch(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    debugPrint('→ PATCH $baseUrl$endpoint');
    try {
      final res = await http
          .patch(
            Uri.parse('$baseUrl$endpoint'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(_timeout, onTimeout: () {
            throw ApiException(
              statusCode: 0,
              message: 'Request timeout',
            );
          });

      return _handle(res);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        statusCode: 0,
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  /// DELETE request
  Future<Map<String, dynamic>> delete(String endpoint) async {
    debugPrint('→ DELETE $baseUrl$endpoint');
    try {
      final res = await http
          .delete(
            Uri.parse('$baseUrl$endpoint'),
            headers: _headers,
          )
          .timeout(_timeout, onTimeout: () {
            throw ApiException(
              statusCode: 0,
              message: 'Request timeout',
            );
          });

      return _handle(res);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        statusCode: 0,
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  /// Multipart file upload with retry
  Future<String> uploadFile({
    required String folder,
    required String filePath,
    int maxRetries = 3,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        return await _uploadFileOnce(folder: folder, filePath: filePath);
      } catch (e) {
        if (attempt == maxRetries) rethrow;
        debugPrint(
            '⚠️ Upload attempt $attempt failed, retrying... Error: $e');
        await Future.delayed(Duration(seconds: attempt));
      }
    }
    throw ApiException(
      statusCode: 0,
      message: 'Upload failed after $maxRetries attempts',
    );
  }

  Future<String> _uploadFileOnce({
    required String folder,
    required String filePath,
  }) async {
    final uri = Uri.parse('$baseUrl/upload?folder=$folder');
    final req = http.MultipartRequest('POST', uri);

    if (_accessToken != null) {
      req.headers['Authorization'] = 'Bearer $_accessToken';
    }

    final lower = filePath.toLowerCase();
    final contentType = lower.endsWith('.png')
        ? MediaType('image', 'png')
        : lower.endsWith('.webp')
            ? MediaType('image', 'webp')
            : lower.endsWith('.aac')
                ? MediaType('audio', 'aac')
                : lower.endsWith('.m4a') || lower.endsWith('.mp4')
                    ? MediaType('audio', 'mp4')
                    : lower.endsWith('.mp3')
                        ? MediaType('audio', 'mpeg')
                        : lower.endsWith('.wav')
                            ? MediaType('audio', 'wav')
                            : MediaType('image', 'jpeg');

    req.files.add(await http.MultipartFile.fromPath(
      'file',
      filePath,
      contentType: contentType,
    ));

    debugPrint('→ UPLOAD $uri');

    try {
      final streamed = await req.send().timeout(_timeout);
      final res = await http.Response.fromStream(streamed);
      final body = _handle(res);
      return body['data']['url'] as String;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        statusCode: 0,
        message: 'Upload failed: ${e.toString()}',
      );
    }
  }

  Map<String, dynamic> _handle(http.Response res) {
    debugPrint('← ${res.statusCode}');

    Map<String, dynamic> body;
    try {
      if (res.body.isEmpty) {
        body = {};
      } else {
        final decoded = jsonDecode(res.body);
        body = decoded is Map<String, dynamic> ? decoded : {'data': decoded};
      }
    } catch (e) {
      throw ApiException(
        statusCode: res.statusCode,
        message: 'Invalid server response',
        responseBody: res.body,
      );
    }

    // Success
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }

    // Auth errors
    if (res.statusCode == 401) {
      throw ApiException(
        statusCode: 401,
        message: 'Session expired. Please sign in again.',
        responseBody: res.body,
      );
    }

    // Client errors
    if (res.statusCode >= 400 && res.statusCode < 500) {
      throw ApiException(
        statusCode: res.statusCode,
        message: body['message'] ?? 'Request failed (${res.statusCode})',
        responseBody: res.body,
      );
    }

    // Server errors
    throw ApiException(
      statusCode: res.statusCode,
      message: 'Server error (${res.statusCode})',
      responseBody: res.body,
    );
  }

  /// Cache Management
  void _setCache(String key, Map<String, dynamic> value) {
    final ttl = key.startsWith('GET:/api/user/profile')
        ? _profileCacheTTL
        : _dataCacheTTL;

    _cache[key] = _CacheEntry(
      data: value,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  Map<String, dynamic>? _getFromCache(String key) {
    final entry = _cache[key];
    if (entry == null) return null;

    if (DateTime.now().isAfter(entry.expiresAt)) {
      _cache.remove(key);
      return null;
    }

    return entry.data;
  }

  /// Clear all caches
  static void clearCache() {
    _cache.clear();
    debugPrint('💾 Cache cleared');
  }

  /// Clear specific endpoint cache
  static void clearCacheFor(String endpoint) {
    final key = 'GET:$endpoint';
    _cache.remove(key);
    debugPrint('💾 Cache cleared for $endpoint');
  }
}

class _CacheEntry {
  final Map<String, dynamic> data;
  final DateTime expiresAt;

  _CacheEntry({
    required this.data,
    required this.expiresAt,
  });
}
