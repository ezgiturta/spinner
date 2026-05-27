import 'package:shared_preferences/shared_preferences.dart';

/// Local persistence for liked genres. The set drives:
///   - genre tile sizing on the Explore page (liked = bigger + heart)
///   - the "matches your taste" suitability score on record_detail
///
/// Backed by SharedPreferences so it survives reinstalls if the OS
/// preserves them; lives across screens via a singleton in-memory cache.
class GenreLikes {
  GenreLikes._();
  static final GenreLikes instance = GenreLikes._();

  static const _key = 'liked_genres_v1';
  final Set<String> _cache = <String>{};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _cache
      ..clear()
      ..addAll(prefs.getStringList(_key) ?? const <String>[]);
    _loaded = true;
  }

  Future<Set<String>> getAll() async {
    await _ensureLoaded();
    return Set.unmodifiable(_cache);
  }

  /// Synchronous read for already-loaded callers (returns empty if never
  /// touched yet — call [getAll] once on screen mount to warm the cache).
  Set<String> getAllSync() => Set.unmodifiable(_cache);

  Future<bool> toggle(String genre) async {
    await _ensureLoaded();
    final isLiked = _cache.contains(genre);
    if (isLiked) {
      _cache.remove(genre);
    } else {
      _cache.add(genre);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _cache.toList());
    return !isLiked;
  }

  bool isLiked(String genre) => _cache.contains(genre);
}
