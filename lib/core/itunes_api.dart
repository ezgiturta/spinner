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

  /// Best-effort album lookup → list of tracks with 30sec previewUrl.
  /// Searches album by "artist title", then uses lookup with collectionId to pull tracks.
  static Future<List<Map<String, dynamic>>> findAlbumTracks({
    required String artist,
    required String title,
  }) async {
    if (artist.trim().isEmpty && title.trim().isEmpty) return const [];
    try {
      final searchResp = await _dio.get(
        'https://itunes.apple.com/search',
        queryParameters: {
          'term': '$artist $title',
          'media': 'music',
          'entity': 'album',
          'limit': '5',
        },
      );
      final searchData = _parseData(searchResp.data);
      final albums = (searchData['results'] as List?) ?? const [];
      if (albums.isEmpty) return const [];

      Map<String, dynamic>? match;
      final wantTitle = title.toLowerCase();
      final wantArtist = artist.toLowerCase();
      for (final a in albums) {
        final aTitle = (a['collectionName'] ?? '').toString().toLowerCase();
        final aArtist = (a['artistName'] ?? '').toString().toLowerCase();
        if (aTitle.contains(wantTitle) && aArtist.contains(wantArtist)) {
          match = a as Map<String, dynamic>;
          break;
        }
      }
      match ??= albums.first as Map<String, dynamic>;
      final collectionId = match['collectionId'];
      if (collectionId == null) return const [];

      final lookupResp = await _dio.get(
        'https://itunes.apple.com/lookup',
        queryParameters: {
          'id': '$collectionId',
          'entity': 'song',
        },
      );
      final lookupData = _parseData(lookupResp.data);
      final results = (lookupData['results'] as List?) ?? const [];
      final tracks = <Map<String, dynamic>>[];
      for (final r in results) {
        if (r is! Map) continue;
        if (r['wrapperType'] != 'track') continue;
        final preview = (r['previewUrl'] ?? '').toString();
        if (preview.isEmpty) continue;
        tracks.add({
          'track_number': r['trackNumber'] ?? 0,
          'track_name': r['trackName'] ?? '',
          'preview_url': preview,
          'duration_ms': r['trackTimeMillis'] ?? 0,
        });
      }
      tracks.sort((a, b) => (a['track_number'] as int).compareTo(b['track_number'] as int));
      return tracks;
    } catch (_) {
      return const [];
    }
  }
}
