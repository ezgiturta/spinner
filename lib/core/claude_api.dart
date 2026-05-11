import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Thin client for the Spinner AI proxy hosted on Vercel.
///
/// All requests go through `https://kiraapp-nu.vercel.app/api/spinner/*`,
/// which holds the Anthropic API key as a server env var.
class ClaudeApi {
  ClaudeApi._();
  static final ClaudeApi instance = ClaudeApi._();

  static const _baseUrl = 'https://kiraapp-nu.vercel.app/api/spinner';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));

  // ---------------------------------------------------------------------------
  // Condition Grader
  // ---------------------------------------------------------------------------

  Future<ConditionGrade> gradeCondition({
    required File frontImage,
    File? backImage,
    String? albumTitle,
    String? artist,
  }) async {
    final frontBytes = await frontImage.readAsBytes();
    final body = <String, dynamic>{
      'imageBase64': base64Encode(frontBytes),
      'mediaType': _mediaTypeForPath(frontImage.path),
      if (albumTitle != null) 'albumTitle': albumTitle,
      if (artist != null) 'artist': artist,
    };
    if (backImage != null) {
      final backBytes = await backImage.readAsBytes();
      body['secondImageBase64'] = base64Encode(backBytes);
      body['secondMediaType'] = _mediaTypeForPath(backImage.path);
    }

    final res = await _dio.post('$_baseUrl/grade', data: jsonEncode(body));
    final data = _asMap(res.data);
    return ConditionGrade.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // Album Storyteller
  // ---------------------------------------------------------------------------

  Future<AlbumStory> getAlbumStory({
    required String title,
    required String artist,
    int? year,
    String? label,
    String? country,
  }) async {
    final body = {
      'title': title,
      'artist': artist,
      if (year != null) 'year': year,
      if (label != null && label.isNotEmpty) 'label': label,
      if (country != null && country.isNotEmpty) 'country': country,
    };
    final res = await _dio.post('$_baseUrl/story', data: jsonEncode(body));
    final data = _asMap(res.data);
    return AlbumStory.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // Mood Picker
  // ---------------------------------------------------------------------------

  Future<List<MoodPick>> pickForMood({
    required String query,
    required List<Map<String, dynamic>> collection,
  }) async {
    final body = {'query': query, 'collection': collection};
    final res = await _dio.post('$_baseUrl/mood', data: jsonEncode(body));
    final data = _asMap(res.data);
    final picks = data['picks'];
    if (picks is! List) return const [];
    return picks
        .whereType<Map>()
        .map((m) => MoodPick.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) return data.cast<String, dynamic>();
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    }
    if (data is List<int>) {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is Map) return decoded.cast<String, dynamic>();
    }
    if (data is Uint8List) {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is Map) return decoded.cast<String, dynamic>();
    }
    throw const FormatException('Unexpected response shape');
  }

  String _mediaTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class ConditionGrade {
  final String rating;
  final double confidence;
  final String? sleeve;
  final String? vinyl;
  final String? notes;
  final List<String> redFlags;

  const ConditionGrade({
    required this.rating,
    required this.confidence,
    this.sleeve,
    this.vinyl,
    this.notes,
    this.redFlags = const [],
  });

  factory ConditionGrade.fromJson(Map<String, dynamic> j) {
    return ConditionGrade(
      rating: (j['rating'] as String?)?.trim() ?? '?',
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
      sleeve: j['sleeve'] as String?,
      vinyl: j['vinyl'] as String?,
      notes: j['notes'] as String?,
      redFlags: (j['redFlags'] as List?)
              ?.whereType<String>()
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'rating': rating,
        'confidence': confidence,
        if (sleeve != null) 'sleeve': sleeve,
        if (vinyl != null) 'vinyl': vinyl,
        if (notes != null) 'notes': notes,
        'redFlags': redFlags,
      };
}

class AlbumStory {
  final String? recordingContext;
  final String? bandHistory;
  final WhereToStart? whereToStart;
  final List<HiddenTrack> hiddenTracks;
  final List<RarePressing> rarePressings;

  const AlbumStory({
    this.recordingContext,
    this.bandHistory,
    this.whereToStart,
    this.hiddenTracks = const [],
    this.rarePressings = const [],
  });

  factory AlbumStory.fromJson(Map<String, dynamic> j) {
    return AlbumStory(
      recordingContext: j['recordingContext'] as String?,
      bandHistory: j['bandHistory'] as String?,
      whereToStart: j['whereToStart'] is Map
          ? WhereToStart.fromJson(
              (j['whereToStart'] as Map).cast<String, dynamic>())
          : null,
      hiddenTracks: (j['hiddenTracks'] as List?)
              ?.whereType<Map>()
              .map((m) => HiddenTrack.fromJson(m.cast<String, dynamic>()))
              .toList() ??
          const [],
      rarePressings: (j['rarePressings'] as List?)
              ?.whereType<Map>()
              .map((m) => RarePressing.fromJson(m.cast<String, dynamic>()))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        if (recordingContext != null) 'recordingContext': recordingContext,
        if (bandHistory != null) 'bandHistory': bandHistory,
        if (whereToStart != null) 'whereToStart': whereToStart!.toJson(),
        'hiddenTracks': hiddenTracks.map((t) => t.toJson()).toList(),
        'rarePressings': rarePressings.map((p) => p.toJson()).toList(),
      };

  bool get isEmpty =>
      (recordingContext == null || recordingContext!.isEmpty) &&
      (bandHistory == null || bandHistory!.isEmpty) &&
      whereToStart == null &&
      hiddenTracks.isEmpty &&
      rarePressings.isEmpty;
}

class WhereToStart {
  final String track;
  final String why;
  const WhereToStart({required this.track, required this.why});
  factory WhereToStart.fromJson(Map<String, dynamic> j) => WhereToStart(
        track: j['track'] as String? ?? '',
        why: j['why'] as String? ?? '',
      );
  Map<String, dynamic> toJson() => {'track': track, 'why': why};
}

class HiddenTrack {
  final String track;
  final String why;
  const HiddenTrack({required this.track, required this.why});
  factory HiddenTrack.fromJson(Map<String, dynamic> j) => HiddenTrack(
        track: j['track'] as String? ?? '',
        why: j['why'] as String? ?? '',
      );
  Map<String, dynamic> toJson() => {'track': track, 'why': why};
}

class RarePressing {
  final String name;
  final String? marker;
  final String? note;
  const RarePressing({required this.name, this.marker, this.note});
  factory RarePressing.fromJson(Map<String, dynamic> j) => RarePressing(
        name: j['name'] as String? ?? '',
        marker: j['marker'] as String?,
        note: j['note'] as String?,
      );
  Map<String, dynamic> toJson() => {
        'name': name,
        if (marker != null) 'marker': marker,
        if (note != null) 'note': note,
      };
}

class MoodPick {
  final String id;
  final String reason;
  const MoodPick({required this.id, required this.reason});
  factory MoodPick.fromJson(Map<String, dynamic> j) => MoodPick(
        id: j['id'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
      );
}
