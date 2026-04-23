import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Discogs API client with OAuth 1.0a authentication and rate limiting.
class DiscogsApi {
  static const String _baseUrl = 'https://api.discogs.com';
  static const String consumerKey = 'RjrMoGGZRWPVYEWRZIMG';
  static const String _consumerKey = consumerKey;
  static const String _consumerSecret = 'cjCYrFzJZXZ0YptcFFQTbEdseUEHxBPW';

  static const String _requestTokenUrl =
      'https://api.discogs.com/oauth/request_token';
  static const String _authorizeUrl =
      'https://www.discogs.com/oauth/authorize';
  static const String _accessTokenUrl =
      'https://api.discogs.com/oauth/access_token';

  static const String _keyAccessToken = 'discogs_access_token';
  static const String _keyAccessSecret = 'discogs_access_secret';
  static const String _keyUsername = 'discogs_username';

  static const Duration _rateLimitInterval = Duration(milliseconds: 1100);

  final Dio _dio;
  final FlutterSecureStorage _storage;

  DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
  final _rateLimitLock = Completer<void>.sync()..complete(null);

  String? _accessToken;
  String? _accessSecret;
  String? _username;

  DiscogsApi({
    Dio? dio,
    FlutterSecureStorage? storage,
  })  : _dio = dio ?? Dio(),
        _storage = storage ?? const FlutterSecureStorage() {
    _dio.options.baseUrl = _baseUrl;
    _dio.options.headers['User-Agent'] = 'SpinnerApp/1.0';
    _dio.options.headers['Accept'] = 'application/json';
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
  }

  // ── Initialization ──

  /// Load stored OAuth tokens. Call once at app startup.
  Future<void> init() async {
    _accessToken = await _storage.read(key: _keyAccessToken);
    _accessSecret = await _storage.read(key: _keyAccessSecret);
    _username = await _storage.read(key: _keyUsername);
  }

  bool get isAuthenticated => _accessToken != null && _accessSecret != null;

  String? get username => _username;

  /// Clear stored credentials and log out.
  Future<void> logout() async {
    _accessToken = null;
    _accessSecret = null;
    _username = null;
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyAccessSecret);
    await _storage.delete(key: _keyUsername);
  }

  // ── OAuth 1.0a Flow ──

  /// Step 1: Get a request token and return the authorization URL.
  /// The caller should open this URL in a browser/webview.
  /// [callbackUrl] is your app's OAuth callback scheme (e.g. 'spinner://oauth-callback').
  Future<OAuthRequestResult> getAuthorizationUrl(String callbackUrl) async {
    final nonce = _generateNonce();
    final timestamp = _timestamp();

    final params = <String, String>{
      'oauth_consumer_key': _consumerKey,
      'oauth_nonce': nonce,
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': timestamp,
      'oauth_version': '1.0',
      'oauth_callback': callbackUrl,
    };

    final signature = _generateSignature(
      'POST',
      _requestTokenUrl,
      params,
      '',
    );
    params['oauth_signature'] = signature;

    final response = await _dio.post(
      _requestTokenUrl,
      options: Options(
        headers: {
          'Authorization': _buildAuthHeader(params),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ),
    );

    final body = Uri.splitQueryString(response.data.toString());
    final requestToken = body['oauth_token']!;
    final requestSecret = body['oauth_token_secret']!;

    final authorizeUrl = '$_authorizeUrl?oauth_token=$requestToken';

    return OAuthRequestResult(
      authorizeUrl: authorizeUrl,
      requestToken: requestToken,
      requestSecret: requestSecret,
    );
  }

  /// Step 2: Exchange the request token + verifier for an access token.
  /// Call this after the user authorizes and you receive the callback with
  /// [oauthToken] and [oauthVerifier].
  Future<void> completeAuthentication({
    required String requestToken,
    required String requestSecret,
    required String oauthVerifier,
  }) async {
    final nonce = _generateNonce();
    final timestamp = _timestamp();

    final params = <String, String>{
      'oauth_consumer_key': _consumerKey,
      'oauth_nonce': nonce,
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': timestamp,
      'oauth_version': '1.0',
      'oauth_token': requestToken,
      'oauth_verifier': oauthVerifier,
    };

    final signature = _generateSignature(
      'POST',
      _accessTokenUrl,
      params,
      requestSecret,
    );
    params['oauth_signature'] = signature;

    final response = await _dio.post(
      _accessTokenUrl,
      options: Options(
        headers: {
          'Authorization': _buildAuthHeader(params),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ),
    );

    final body = Uri.splitQueryString(response.data.toString());
    _accessToken = body['oauth_token']!;
    _accessSecret = body['oauth_token_secret']!;

    await _storage.write(key: _keyAccessToken, value: _accessToken);
    await _storage.write(key: _keyAccessSecret, value: _accessSecret);

    // Fetch and store the username.
    final identity = await _authenticatedGet('/oauth/identity');
    _username = identity['username'] as String?;
    if (_username != null) {
      await _storage.write(key: _keyUsername, value: _username);
    }
  }

  // ── API Methods ──

  /// Search Discogs by barcode. Works without OAuth (uses key/secret).
  Future<DiscogsSearchResult> searchByBarcode(String barcode) async {
    final data = await _get('/database/search', queryParams: {
      'barcode': barcode,
      'type': 'release',
    });
    return DiscogsSearchResult.fromJson(data);
  }

  /// Search Discogs by text query. Works without OAuth (uses key/secret).
  Future<DiscogsSearchResult> searchByText(
    String query, {
    String type = 'release',
    int page = 1,
    int perPage = 20,
  }) async {
    final data = await _get('/database/search', queryParams: {
      'q': query,
      'type': type,
      'page': page.toString(),
      'per_page': perPage.toString(),
    });
    return DiscogsSearchResult.fromJson(data);
  }

  /// Get full release details by release ID. Works without OAuth.
  Future<Map<String, dynamic>> getReleaseDetails(int releaseId) async {
    return _get('/releases/$releaseId');
  }

  /// Get price suggestions for a release. Requires OAuth authentication.
  /// Returns null if not authenticated.
  Future<Map<String, dynamic>?> getPriceSuggestions(int releaseId) async {
    if (!isAuthenticated) return null;
    return _authenticatedGet(
        '/marketplace/price_suggestions/$releaseId');
  }

  /// Get marketplace stats / sold listings history for a release.
  Future<Map<String, dynamic>> getMarketplaceSoldListings(
    int releaseId, {
    int page = 1,
    int perPage = 50,
    String? sort,
    String? sortOrder,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
      'status': 'Sold',
    };
    if (sort != null) params['sort'] = sort;
    if (sortOrder != null) params['sort_order'] = sortOrder;

    return _authenticatedGet(
      '/marketplace/releases/$releaseId/stats',
      queryParams: params,
    );
  }

  /// Get all collection folders for a user.
  Future<List<Map<String, dynamic>>> getUserCollectionFolders(
      {String? user}) async {
    final u = user ?? _username;
    if (u == null) throw DiscogsApiException('Not authenticated');
    final data = await _authenticatedGet('/users/$u/collection/folders');
    final folders = data['folders'] as List<dynamic>;
    return folders.cast<Map<String, dynamic>>();
  }

  /// Get releases in a specific folder (paginated).
  Future<Map<String, dynamic>> getFolderReleases(
    int folderId, {
    String? user,
    int page = 1,
    int perPage = 100,
    String? sort,
    String? sortOrder,
  }) async {
    final u = user ?? _username;
    if (u == null) throw DiscogsApiException('Not authenticated');

    final params = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (sort != null) params['sort'] = sort;
    if (sortOrder != null) params['sort_order'] = sortOrder;

    return _authenticatedGet(
      '/users/$u/collection/folders/$folderId/releases',
      queryParams: params,
    );
  }

  /// Get user's wantlist (paginated).
  Future<Map<String, dynamic>> getUserWantlist({
    String? user,
    int page = 1,
    int perPage = 100,
  }) async {
    final u = user ?? _username;
    if (u == null) throw DiscogsApiException('Not authenticated');

    return _authenticatedGet(
      '/users/$u/wants',
      queryParams: {
        'page': page.toString(),
        'per_page': perPage.toString(),
      },
    );
  }

  // ── Rate-Limited Request (auto-selects authenticated or key/secret) ──

  /// Makes a GET request. Uses OAuth if authenticated, otherwise falls back
  /// to key/secret query params for unauthenticated access.
  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    if (isAuthenticated) {
      return _authenticatedGet(path, queryParams: queryParams);
    }
    return _unauthenticatedGet(path, queryParams: queryParams);
  }

  /// Makes an unauthenticated GET request using consumer key/secret as query
  /// params. Rate limited to ~25 requests/minute by Discogs.
  Future<Map<String, dynamic>> _unauthenticatedGet(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    await _enforceRateLimit();

    final params = <String, String>{
      'key': _consumerKey,
      'secret': _consumerSecret,
      ...?queryParams,
    };

    try {
      final response = await _dio.get(
        path,
        queryParameters: params,
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        final retryAfter = int.tryParse(
                e.response?.headers.value('Retry-After') ?? '') ??
            5;
        await Future.delayed(Duration(seconds: retryAfter));
        return _unauthenticatedGet(path, queryParams: queryParams);
      }
      throw DiscogsApiException(
        'API request failed: ${e.message}',
        statusCode: e.response?.statusCode,
        response: e.response?.data,
      );
    }
  }

  // ── Rate-Limited Authenticated Request ──

  Future<Map<String, dynamic>> _authenticatedGet(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    if (!isAuthenticated) {
      throw DiscogsApiException('Not authenticated. Call init() or authenticate first.');
    }

    await _enforceRateLimit();

    final fullUrl = '$_baseUrl$path';
    final nonce = _generateNonce();
    final timestamp = _timestamp();

    final oauthParams = <String, String>{
      'oauth_consumer_key': _consumerKey,
      'oauth_nonce': nonce,
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': timestamp,
      'oauth_version': '1.0',
      'oauth_token': _accessToken!,
    };

    // Merge query params for signature base string.
    final allParams = <String, String>{...oauthParams};
    if (queryParams != null) allParams.addAll(queryParams);

    final signature = _generateSignature(
      'GET',
      fullUrl,
      allParams,
      _accessSecret!,
    );
    oauthParams['oauth_signature'] = signature;

    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParams,
        options: Options(
          headers: {
            'Authorization': _buildAuthHeader(oauthParams),
          },
        ),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        // Rate limited - wait and retry once.
        final retryAfter = int.tryParse(
                e.response?.headers.value('Retry-After') ?? '') ??
            5;
        await Future.delayed(Duration(seconds: retryAfter));
        return _authenticatedGet(path, queryParams: queryParams);
      }
      throw DiscogsApiException(
        'API request failed: ${e.message}',
        statusCode: e.response?.statusCode,
        response: e.response?.data,
      );
    }
  }

  // ── Rate Limiting ──

  Future<void> _enforceRateLimit() async {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRequestTime);
    if (elapsed < _rateLimitInterval) {
      await Future.delayed(_rateLimitInterval - elapsed);
    }
    _lastRequestTime = DateTime.now();
  }

  // ── OAuth Signature Helpers ──

  String _generateSignature(
    String method,
    String url,
    Map<String, String> params,
    String tokenSecret,
  ) {
    final sortedKeys = params.keys.toList()..sort();
    final paramString = sortedKeys
        .map((k) => '${_percentEncode(k)}=${_percentEncode(params[k]!)}')
        .join('&');

    final baseString =
        '${method.toUpperCase()}&${_percentEncode(url)}&${_percentEncode(paramString)}';

    final signingKey =
        '${_percentEncode(_consumerSecret)}&${_percentEncode(tokenSecret)}';

    final hmac = Hmac(sha1, utf8.encode(signingKey));
    final digest = hmac.convert(utf8.encode(baseString));
    return base64.encode(digest.bytes);
  }

  String _buildAuthHeader(Map<String, String> params) {
    final entries = params.entries
        .map((e) => '${_percentEncode(e.key)}="${_percentEncode(e.value)}"')
        .join(', ');
    return 'OAuth $entries';
  }

  static String _percentEncode(String value) {
    return Uri.encodeComponent(value)
        .replaceAll('+', '%20')
        .replaceAll('*', '%2A')
        .replaceAll('%7E', '~');
  }

  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  }

  String _timestamp() =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
}

// ── Models ──

class OAuthRequestResult {
  final String authorizeUrl;
  final String requestToken;
  final String requestSecret;

  const OAuthRequestResult({
    required this.authorizeUrl,
    required this.requestToken,
    required this.requestSecret,
  });
}

class DiscogsSearchResult {
  final List<Map<String, dynamic>> results;
  final int? pages;
  final int? items;

  const DiscogsSearchResult({
    required this.results,
    this.pages,
    this.items,
  });

  factory DiscogsSearchResult.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'] as Map<String, dynamic>?;
    final results = (json['results'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    return DiscogsSearchResult(
      results: results,
      pages: pagination?['pages'] as int?,
      items: pagination?['items'] as int?,
    );
  }

  bool get isEmpty => results.isEmpty;
  bool get isNotEmpty => results.isNotEmpty;
}

class DiscogsApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic response;

  const DiscogsApiException(this.message, {this.statusCode, this.response});

  @override
  String toString() =>
      'DiscogsApiException($statusCode): $message';
}
