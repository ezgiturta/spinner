import 'package:dio/dio.dart';

/// Last.fm API client for artist discovery features.
class LastFmApi {
  static const String _baseUrl = 'https://ws.audioscrobbler.com/2.0/';
  static const String _apiKey = 'YOUR_LASTFM_API_KEY';

  final Dio _dio;

  LastFmApi({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.baseUrl = _baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);
  }

  /// Get artists similar to the given artist.
  ///
  /// Returns a list of similar artists with match scores.
  /// [limit] controls the maximum number of results (default 30).
  Future<List<SimilarArtist>> getSimilarArtists(
    String artistName, {
    int limit = 30,
  }) async {
    try {
      final response = await _dio.get(
        '',
        queryParameters: {
          'method': 'artist.getSimilar',
          'artist': artistName,
          'api_key': _apiKey,
          'format': 'json',
          'limit': limit,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final similarArtists = data['similarartists'] as Map<String, dynamic>?;
      if (similarArtists == null) return [];

      final artistList = similarArtists['artist'] as List<dynamic>?;
      if (artistList == null) return [];

      return artistList.map((json) {
        final map = json as Map<String, dynamic>;
        return SimilarArtist(
          name: map['name'] as String? ?? '',
          matchScore: double.tryParse(map['match']?.toString() ?? '') ?? 0.0,
          url: map['url'] as String? ?? '',
          imageUrl: _extractImageUrl(map['image']),
        );
      }).toList();
    } on DioException catch (e) {
      throw LastFmApiException(
        'Failed to get similar artists: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Get top tags for an artist.
  ///
  /// Returns genre/style tags ordered by usage count.
  Future<List<ArtistTag>> getTopTags(String artistName) async {
    try {
      final response = await _dio.get(
        '',
        queryParameters: {
          'method': 'artist.getTopTags',
          'artist': artistName,
          'api_key': _apiKey,
          'format': 'json',
        },
      );

      final data = response.data as Map<String, dynamic>;
      final topTags = data['toptags'] as Map<String, dynamic>?;
      if (topTags == null) return [];

      final tagList = topTags['tag'] as List<dynamic>?;
      if (tagList == null) return [];

      return tagList.map((json) {
        final map = json as Map<String, dynamic>;
        return ArtistTag(
          name: map['name'] as String? ?? '',
          count: (map['count'] as num?)?.toInt() ?? 0,
          url: map['url'] as String? ?? '',
        );
      }).toList();
    } on DioException catch (e) {
      throw LastFmApiException(
        'Failed to get top tags: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Extract the best available image URL from Last.fm's image array.
  static String? _extractImageUrl(dynamic images) {
    if (images is! List || images.isEmpty) return null;
    // Prefer 'extralarge', then 'large', then 'medium', then any.
    for (final size in ['extralarge', 'large', 'medium', 'small']) {
      for (final img in images) {
        if (img is Map<String, dynamic> &&
            img['size'] == size &&
            (img['#text'] as String?)?.isNotEmpty == true) {
          return img['#text'] as String;
        }
      }
    }
    // Fallback: return the last image.
    final last = images.last;
    if (last is Map<String, dynamic>) {
      final url = last['#text'] as String?;
      return (url?.isNotEmpty == true) ? url : null;
    }
    return null;
  }
}

// ── Models ──

class SimilarArtist {
  final String name;
  final double matchScore;
  final String url;
  final String? imageUrl;

  const SimilarArtist({
    required this.name,
    required this.matchScore,
    required this.url,
    this.imageUrl,
  });
}

class ArtistTag {
  final String name;
  final int count;
  final String url;

  const ArtistTag({
    required this.name,
    required this.count,
    required this.url,
  });
}

class LastFmApiException implements Exception {
  final String message;
  final int? statusCode;

  const LastFmApiException(this.message, {this.statusCode});

  @override
  String toString() => 'LastFmApiException($statusCode): $message';
}
