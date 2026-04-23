import 'dart:convert';
import 'package:dio/dio.dart';

class ItunesApi {
  static final _dio = Dio();

  static dynamic _parseData(dynamic data) {
    if (data is String) return jsonDecode(data);
    return data;
  }

  /// Search for albums. No API key needed.
  static Future<List<Map<String, dynamic>>> searchAlbums(String query) async {
    final response = await _dio.get(
      'https://itunes.apple.com/search',
      queryParameters: {
        'term': query,
        'media': 'music',
        'entity': 'album',
        'limit': '20',
      },
    );
    final parsed = _parseData(response.data);
    final results = parsed['results'] as List;
    return results.map((r) => {
      'id': r['collectionId'].toString(),
      'title': r['collectionName'] ?? '',
      'artist': r['artistName'] ?? '',
      'year': ((r['releaseDate'] ?? '') as String).length >= 4 ? (r['releaseDate'] as String).substring(0, 4) : '',
      'cover_url': (r['artworkUrl100'] ?? '').replaceAll('100x100', '600x600'),
      'genre': r['primaryGenreName'] ?? '',
      'track_count': r['trackCount'] ?? 0,
      'collection_price': r['collectionPrice']?.toString() ?? '',
    }).toList().cast<Map<String, dynamic>>();
  }

  /// Search for songs (with preview URLs). No API key needed.
  static Future<List<Map<String, dynamic>>> searchSongs(String query, {int limit = 10}) async {
    final response = await _dio.get(
      'https://itunes.apple.com/search',
      queryParameters: {
        'term': query,
        'media': 'music',
        'entity': 'song',
        'limit': '$limit',
      },
    );
    final parsed = _parseData(response.data);
    final results = parsed['results'] as List;
    return results.map((r) => {
      'track_name': r['trackName'] ?? '',
      'artist': r['artistName'] ?? '',
      'album': r['collectionName'] ?? '',
      'preview_url': r['previewUrl'] ?? '',
      'cover_url': (r['artworkUrl100'] ?? '').replaceAll('100x100', '600x600'),
      'genre': r['primaryGenreName'] ?? '',
    }).toList().cast<Map<String, dynamic>>();
  }
}
