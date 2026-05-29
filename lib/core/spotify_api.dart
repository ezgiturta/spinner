import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// Spotify Web API client (no user login).
///
/// Auth: OAuth client_credentials. Only public catalog endpoints work without
/// a user token (search, recommendations, audio-features, artists, albums).
///
/// Setup:
///   1. https://developer.spotify.com/dashboard → Create app
///   2. Copy Client ID + Client Secret to Codemagic env:
///      SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET
///   3. Pass at build:
///      --dart-define=SPOTIFY_CLIENT_ID=\$SPOTIFY_CLIENT_ID
///      --dart-define=SPOTIFY_CLIENT_SECRET=\$SPOTIFY_CLIENT_SECRET
class SpotifyApi {
  static const String _clientId =
      String.fromEnvironment('SPOTIFY_CLIENT_ID', defaultValue: '');
  static const String _clientSecret =
      String.fromEnvironment('SPOTIFY_CLIENT_SECRET', defaultValue: '');

  static const String _tokenUrl = 'https://accounts.spotify.com/api/token';
  static const String _apiBase = 'https://api.spotify.com/v1';

  static final SpotifyApi _instance = SpotifyApi._();
  factory SpotifyApi() => _instance;
  SpotifyApi._() : _dio = Dio();

  final Dio _dio;
  String? _accessToken;
  DateTime? _tokenExpiresAt;

  static bool get isConfigured =>
      _clientId.isNotEmpty && _clientSecret.isNotEmpty;

  Future<String?> _getToken() async {
    if (!isConfigured) return null;
    final now = DateTime.now();
    if (_accessToken != null &&
        _tokenExpiresAt != null &&
        now.isBefore(_tokenExpiresAt!.subtract(const Duration(minutes: 1)))) {
      return _accessToken;
    }
    final basic = base64Encode(utf8.encode('$_clientId:$_clientSecret'));
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        _tokenUrl,
        data: 'grant_type=client_credentials',
        options: Options(
          headers: {
            'Authorization': 'Basic $basic',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
      );
      final data = resp.data;
      if (data == null) return null;
      _accessToken = data['access_token'] as String?;
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
      _tokenExpiresAt = now.add(Duration(seconds: expiresIn));
      return _accessToken;
    } catch (_) {
      return null;
    }
  }

  /// Look up an artist by name. Returns the top match (id + name + genres).
  Future<Map<String, dynamic>?> findArtist(String name) async {
    if (name.trim().isEmpty) return null;
    final token = await _getToken();
    if (token == null) return null;
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '$_apiBase/search',
        queryParameters: {
          'q': name,
          'type': 'artist',
          'limit': '1',
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final list = (resp.data?['artists']?['items'] as List?) ?? const [];
      if (list.isEmpty) return null;
      return Map<String, dynamic>.from(list.first as Map);
    } catch (_) {
      return null;
    }
  }

  /// Recommendations seeded from a single artist id. Returns up to [limit]
  /// tracks, each with title, artist, album cover and a 30-sec preview URL
  /// when available.
  Future<List<SpotifyRecommendation>> recommendationsForArtist(
    String artistId, {
    int limit = 8,
  }) async {
    final token = await _getToken();
    if (token == null) return const [];
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '$_apiBase/recommendations',
        queryParameters: {
          'seed_artists': artistId,
          'limit': '$limit',
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final tracks = (resp.data?['tracks'] as List?) ?? const [];
      final out = <SpotifyRecommendation>[];
      for (final t in tracks) {
        if (t is! Map) continue;
        final artists = (t['artists'] as List?) ?? const [];
        final artistName = artists.isNotEmpty
            ? (artists.first['name'] ?? '').toString()
            : '';
        final album = t['album'] as Map?;
        final images = (album?['images'] as List?) ?? const [];
        final cover = images.isNotEmpty
            ? (images.first['url'] ?? '').toString()
            : '';
        out.add(SpotifyRecommendation(
          id: (t['id'] ?? '').toString(),
          name: (t['name'] ?? '').toString(),
          artist: artistName,
          coverUrl: cover,
          previewUrl: (t['preview_url'] ?? '').toString(),
          spotifyUrl: (t['external_urls']?['spotify'] ?? '').toString(),
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}

class SpotifyRecommendation {
  final String id;
  final String name;
  final String artist;
  final String coverUrl;
  final String previewUrl;
  final String spotifyUrl;

  const SpotifyRecommendation({
    required this.id,
    required this.name,
    required this.artist,
    required this.coverUrl,
    required this.previewUrl,
    required this.spotifyUrl,
  });
}
