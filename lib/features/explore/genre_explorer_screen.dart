import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:uuid/uuid.dart';

import '../../core/database.dart';
import '../../core/itunes_api.dart';
import '../../core/theme.dart';

// ── Genre data model ──

class _Genre {
  final String name;
  final String category;
  final Color color;
  final double popularity; // 0.0 - 1.0, affects text size

  const _Genre({
    required this.name,
    required this.category,
    required this.color,
    required this.popularity,
  });
}

// ── Color mappings by category ──

Color _categoryColor(String category, int index) {
  switch (category) {
    case 'Rock':
      const shades = [
        Color(0xFFE74C3C),
        Color(0xFFFF6B6B),
        Color(0xFFEE5A24),
        Color(0xFFC0392B),
        Color(0xFFE55039),
        Color(0xFFFC5C65),
        Color(0xFFEB3B5A),
        Color(0xFFFF4757),
        Color(0xFFD63031),
        Color(0xFFE66767),
        Color(0xFFF19066),
        Color(0xFFFF6348),
        Color(0xFFEA8685),
      ];
      return shades[index % shades.length];
    case 'Metal':
      const shades = [
        Color(0xFF8B0000),
        Color(0xFFA93226),
        Color(0xFF922B21),
        Color(0xFF7B241C),
        Color(0xFF641E16),
        Color(0xFF943126),
        Color(0xFFB03A2E),
        Color(0xFF78281F),
        Color(0xFF6E2C00),
      ];
      return shades[index % shades.length];
    case 'Punk':
      const shades = [
        Color(0xFFE74C3C),
        Color(0xFFFF4757),
        Color(0xFFC0392B),
        Color(0xFFEB3B5A),
        Color(0xFFFC5C65),
        Color(0xFFFF6348),
        Color(0xFFD63031),
      ];
      return shades[index % shades.length];
    case 'Electronic':
      const shades = [
        Color(0xFF0984E3),
        Color(0xFF00CEC9),
        Color(0xFF6C5CE7),
        Color(0xFF74B9FF),
        Color(0xFF81ECEC),
        Color(0xFF55E6C1),
        Color(0xFF3DC1D3),
        Color(0xFF0ABDE3),
        Color(0xFF48DBFB),
        Color(0xFF00D2D3),
        Color(0xFF01A3A4),
        Color(0xFF54A0FF),
        Color(0xFF5F27CD),
        Color(0xFF2E86DE),
        Color(0xFF0984E3),
        Color(0xFF00B894),
        Color(0xFF6C5CE7),
        Color(0xFF00CEC9),
        Color(0xFF74B9FF),
        Color(0xFF81ECEC),
      ];
      return shades[index % shades.length];
    case 'Hip-Hop':
      const shades = [
        Color(0xFF6C5CE7),
        Color(0xFFA29BFE),
        Color(0xFF9B59B6),
        Color(0xFF8E44AD),
        Color(0xFFA55EEA),
        Color(0xFF5F27CD),
        Color(0xFF7C4DFF),
        Color(0xFFD6A2E8),
        Color(0xFFB33771),
        Color(0xFFCD84F1),
      ];
      return shades[index % shades.length];
    case 'Jazz':
      const shades = [
        Color(0xFFFDCB6E),
        Color(0xFFF6B93B),
        Color(0xFFD4AC0D),
        Color(0xFFF0B27A),
        Color(0xFFE2B04A),
        Color(0xFFD4A017),
        Color(0xFFCDA200),
        Color(0xFFF5CD79),
        Color(0xFFEAB543),
      ];
      return shades[index % shades.length];
    case 'Soul/Funk/R&B':
      const shades = [
        Color(0xFFE17055),
        Color(0xFFF39C12),
        Color(0xFFE67E22),
        Color(0xFFD35400),
        Color(0xFFF7B731),
        Color(0xFFFA8231),
        Color(0xFFFF9F43),
        Color(0xFFFD9644),
        Color(0xFFEE5A24),
      ];
      return shades[index % shades.length];
    case 'Pop':
      const shades = [
        Color(0xFFFF6B81),
        Color(0xFFE84393),
        Color(0xFFFD79A8),
        Color(0xFFF368E0),
        Color(0xFFFF9FF3),
        Color(0xFFE056AF),
        Color(0xFFFF6B6B),
        Color(0xFFF78FB3),
      ];
      return shades[index % shades.length];
    default: // Other
      const shades = [
        Color(0xFFDFE6E9),
        Color(0xFFB2BEC3),
        Color(0xFF95A5A6),
        Color(0xFFBDC3C7),
        Color(0xFFDCDADA),
        Color(0xFFA4B0BD),
        Color(0xFF636E72),
        Color(0xFF808E9B),
        Color(0xFF84817A),
        Color(0xFFD1D8E0),
      ];
      return shades[index % shades.length];
  }
}

// ── Full genre list ──

final List<_Genre> _allGenres = _buildGenreList();

List<_Genre> _buildGenreList() {
  final rng = Random(42); // deterministic for consistent layout
  final categories = <String, List<String>>{
    'Rock': [
      'Classic Rock', 'Alternative Rock', 'Indie Rock', 'Psychedelic Rock',
      'Progressive Rock', 'Garage Rock', 'Grunge', 'Brit-pop', 'Art Rock',
      'Stoner Rock', 'Southern Rock', 'Surf Rock', 'Krautrock',
    ],
    'Metal': [
      'Heavy Metal', 'Thrash Metal', 'Death Metal', 'Black Metal',
      'Doom Metal', 'Power Metal', 'Sludge Metal', 'Metalcore', 'Nu Metal',
    ],
    'Punk': [
      'Punk Rock', 'Post-Punk', 'Hardcore', 'Pop Punk', 'Oi!',
      'Crust Punk', 'Skate Punk',
    ],
    'Electronic': [
      'House', 'Deep House', 'Tech House', 'Techno', 'Minimal Techno',
      'Ambient', 'Drum & Bass', 'Jungle', 'Synthwave', 'Retrowave',
      'IDM', 'Trance', 'Psytrance', 'Dubstep', 'UK Garage', 'Breakbeat',
      'Downtempo', 'Chillwave', 'Vaporwave', 'Industrial',
    ],
    'Hip-Hop': [
      'Boom Bap', 'Trap', 'Lo-Fi Hip-Hop', 'Conscious Hip-Hop',
      'Gangsta Rap', 'G-Funk', 'Cloud Rap', 'Drill', 'Grime', 'Trip-Hop',
    ],
    'Jazz': [
      'Bebop', 'Free Jazz', 'Jazz Fusion', 'Smooth Jazz', 'Acid Jazz',
      'Modal Jazz', 'Cool Jazz', 'Hard Bop', 'Latin Jazz',
    ],
    'Soul/Funk/R&B': [
      'Soul', 'Neo-Soul', 'Northern Soul', 'Funk', 'P-Funk', 'R&B',
      'Motown', 'Gospel', 'Doo-Wop',
    ],
    'Pop': [
      'Synth-Pop', 'Dream Pop', 'Electropop', 'K-Pop', 'J-Pop',
      'Chamber Pop', 'Indie Pop', 'Twee Pop', 'City Pop',
    ],
    'Other': [
      'Blues', 'Delta Blues', 'Chicago Blues', 'Country', 'Alt-Country',
      'Americana', 'Folk', 'Indie Folk', 'Bluegrass', 'Reggae', 'Ska',
      'Dub', 'Dancehall', 'Classical', 'Baroque', 'Romantic', 'Latin',
      'Bossa Nova', 'Salsa', 'Cumbia', 'Afrobeat', 'Highlife', 'World',
      'Soundtrack', 'Musical', 'Experimental', 'Noise', 'Shoegaze',
      'New Wave', 'Post-Rock', 'Math Rock', 'Emo', 'Screamo',
    ],
  };

  // Well-known genres get higher popularity
  const popularGenres = {
    'Classic Rock', 'Alternative Rock', 'Indie Rock', 'Heavy Metal',
    'Punk Rock', 'House', 'Techno', 'Hip-Hop', 'Boom Bap', 'Trap',
    'Jazz Fusion', 'Soul', 'Funk', 'R&B', 'Blues', 'Reggae', 'Country',
    'Folk', 'Classical', 'Synth-Pop', 'Dream Pop', 'Grunge', 'Shoegaze',
    'Ambient', 'Drum & Bass', 'Post-Punk', 'New Wave', 'K-Pop',
    'Afrobeat', 'Bossa Nova', 'Lo-Fi Hip-Hop', 'Synthwave',
  };

  final list = <_Genre>[];
  for (final entry in categories.entries) {
    for (var i = 0; i < entry.value.length; i++) {
      final name = entry.value[i];
      final pop = popularGenres.contains(name)
          ? 0.6 + rng.nextDouble() * 0.4
          : 0.2 + rng.nextDouble() * 0.4;
      list.add(_Genre(
        name: name,
        category: entry.key,
        color: _categoryColor(entry.key, i),
        popularity: pop,
      ));
    }
  }
  // Shuffle for visual variety
  list.shuffle(Random(7));
  return list;
}

// ══════════════════════════════════════════════════════════════════════
// GenreExplorerScreen
// ══════════════════════════════════════════════════════════════════════

class GenreExplorerScreen extends StatefulWidget {
  const GenreExplorerScreen({super.key});

  @override
  State<GenreExplorerScreen> createState() => _GenreExplorerScreenState();
}

class _GenreExplorerScreenState extends State<GenreExplorerScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _Genre? _selectedGenre;

  bool _loadingAlbums = false;
  List<Map<String, dynamic>> _albums = [];
  String? _albumError;

  // Audio preview
  final _audioPlayer = AudioPlayer();
  String? _nowPlayingTrack;
  String? _nowPlayingArtist;
  String? _nowPlayingCover;
  bool _isPlaying = false;

  final _uuid = const Uuid();

  @override
  void dispose() {
    _searchController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  List<_Genre> get _filteredGenres {
    if (_searchQuery.isEmpty) return _allGenres;
    final q = _searchQuery.toLowerCase();
    return _allGenres
        .where((g) => g.name.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _onGenreTap(_Genre genre) async {
    setState(() {
      _selectedGenre = genre;
      _loadingAlbums = true;
      _albums = [];
      _albumError = null;
    });

    // Play a random preview from this genre
    _playRandomPreview(genre.name);

    try {
      final results = await ItunesApi.searchAlbums(genre.name);
      if (!mounted) return;
      setState(() {
        _albums = results;
        _loadingAlbums = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _albumError = 'Could not load albums. Check your connection.';
        _loadingAlbums = false;
      });
    }
  }

  Future<void> _playRandomPreview(String genre) async {
    try {
      final songs = await ItunesApi.searchSongs(genre, limit: 25);
      final withPreview = songs.where((s) => (s['preview_url'] as String).isNotEmpty).toList();
      if (withPreview.isEmpty) {
        debugPrint('No songs with preview for genre: $genre');
        return;
      }

      final random = withPreview[Random().nextInt(withPreview.length)];
      final url = random['preview_url'] as String;
      debugPrint('Playing preview: $url');

      await _audioPlayer.setVolume(1.0);
      final duration = await _audioPlayer.setUrl(url);
      debugPrint('Audio duration: $duration');

      if (duration == null) {
        debugPrint('Failed to load audio');
        return;
      }

      await _audioPlayer.play();

      if (!mounted) return;
      setState(() {
        _isPlaying = true;
        _nowPlayingTrack = random['track_name'] as String;
        _nowPlayingArtist = random['artist'] as String;
        _nowPlayingCover = random['cover_url'] as String;
      });

      _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) setState(() => _isPlaying = false);
        }
      });
    } catch (e) {
      debugPrint('Audio error: $e');
    }
  }

  void _stopPreview() {
    _audioPlayer.stop();
    setState(() => _isPlaying = false);
  }

  Future<void> _addToWantlist(Map<String, dynamic> album) async {
    final id = _uuid.v4();
    await AppDatabase.insertRecord({
      'id': id,
      'title': album['title'] ?? '',
      'artist': album['artist'] ?? '',
      'year': int.tryParse(album['year']?.toString() ?? ''),
      'cover_url': album['cover_url'] ?? '',
      'in_wantlist': 1,
      'in_collection': 0,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added "${album['title']}" to Wantlist',
          style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.white),
        ),
        backgroundColor: SpinnerTheme.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Build ──

  Widget _buildNowPlaying() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SpinnerTheme.accent.withAlpha(40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpinnerTheme.accent.withAlpha(80)),
      ),
      child: Row(
        children: [
          if (_nowPlayingCover != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: _nowPlayingCover!,
                width: 36, height: 36, fit: BoxFit.cover,
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _nowPlayingTrack ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: SpinnerTheme.nunito(size: 12, weight: FontWeight.w700, color: SpinnerTheme.white),
                ),
                Text(
                  _nowPlayingArtist ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: SpinnerTheme.nunito(size: 11, color: SpinnerTheme.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle, color: SpinnerTheme.accent, size: 28),
            onPressed: _stopPreview,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            _buildSearchBar(),
            if (_isPlaying && _nowPlayingTrack != null) _buildNowPlaying(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  _buildGenreCloud(),
                  if (_selectedGenre != null) _buildAlbumSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: SpinnerTheme.white, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              'Explore Genres',
              style: SpinnerTheme.nunito(
                size: 20,
                weight: FontWeight.w800,
                color: SpinnerTheme.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.white),
        decoration: InputDecoration(
          hintText: 'Search genres...',
          hintStyle: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.grey),
          prefixIcon: const Icon(Icons.search, color: SpinnerTheme.grey, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: SpinnerTheme.grey, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: SpinnerTheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  // ── Genre cloud ──

  Widget _buildGenreCloud() {
    final genres = _filteredGenres;
    if (genres.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            'No genres match your search.',
            style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.grey),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 4,
        runSpacing: 2,
        children: genres.map((g) {
          final isSelected = _selectedGenre?.name == g.name;
          final fontSize = 11.0 + g.popularity * 16.0; // 11-27
          final hPad = 4.0 + g.popularity * 8.0;
          final vPad = 2.0 + g.popularity * 4.0;

          return GestureDetector(
            onTap: () => _onGenreTap(g),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.symmetric(
                horizontal: hPad * 0.3,
                vertical: vPad * 0.3,
              ),
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
              decoration: BoxDecoration(
                color: isSelected
                    ? SpinnerTheme.accent.withOpacity(0.25)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: isSelected
                    ? Border.all(color: SpinnerTheme.accent, width: 1.5)
                    : null,
              ),
              child: Text(
                g.name,
                style: SpinnerTheme.nunito(
                  size: fontSize,
                  weight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? SpinnerTheme.accent : g.color,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Album results section ──

  Widget _buildAlbumSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: SpinnerTheme.border, height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: _selectedGenre!.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Top Albums in ${_selectedGenre!.name}',
                  style: SpinnerTheme.nunito(
                    size: 18,
                    weight: FontWeight.w700,
                    color: SpinnerTheme.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_loadingAlbums)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(color: SpinnerTheme.accent),
            ),
          )
        else if (_albumError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.cloud_off, color: SpinnerTheme.grey, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    _albumError!,
                    textAlign: TextAlign.center,
                    style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.grey),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => _onGenreTap(_selectedGenre!),
                    child: Text(
                      'Retry',
                      style: SpinnerTheme.nunito(
                        size: 13,
                        weight: FontWeight.w700,
                        color: SpinnerTheme.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (_albums.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Center(
              child: Text(
                'No albums found for this genre.',
                style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.grey),
              ),
            ),
          )
        else
          _buildAlbumGrid(),
      ],
    );
  }

  Widget _buildAlbumGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
          childAspectRatio: 0.58,
        ),
        itemCount: _albums.length,
        itemBuilder: (_, i) => _buildAlbumCard(_albums[i]),
      ),
    );
  }

  Widget _buildAlbumCard(Map<String, dynamic> album) {
    final coverUrl = album['cover_url'] as String? ?? '';
    final title = album['title'] as String? ?? 'Unknown';
    final artist = album['artist'] as String? ?? 'Unknown';
    final year = album['year'] as String? ?? '';

    return Container(
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover art
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: AspectRatio(
              aspectRatio: 1,
              child: coverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: SpinnerTheme.surface,
                        child: const Center(
                          child: Icon(Icons.album, color: SpinnerTheme.grey, size: 40),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: SpinnerTheme.surface,
                        child: const Center(
                          child: Icon(Icons.album, color: SpinnerTheme.grey, size: 40),
                        ),
                      ),
                    )
                  : Container(
                      color: SpinnerTheme.surface,
                      child: const Center(
                        child: Icon(Icons.album, color: SpinnerTheme.grey, size: 40),
                      ),
                    ),
            ),
          ),
          // Info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SpinnerTheme.nunito(
                      size: 13,
                      weight: FontWeight.w700,
                      color: SpinnerTheme.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    year.isNotEmpty ? '$artist  $year' : artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SpinnerTheme.nunito(
                      size: 11,
                      color: SpinnerTheme.grey,
                    ),
                  ),
                  const Spacer(),
                  // Add to wantlist button
                  SizedBox(
                    width: double.infinity,
                    height: 30,
                    child: TextButton.icon(
                      onPressed: () => _addToWantlist(album),
                      icon: const Icon(Icons.favorite_outline, size: 14),
                      label: Text(
                        'Wantlist',
                        style: SpinnerTheme.nunito(size: 11, weight: FontWeight.w600),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: SpinnerTheme.accent,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: SpinnerTheme.accent, width: 1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
