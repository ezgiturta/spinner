import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/database.dart';
import '../../core/theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  String _userName = '';
  List<String> _genres = [];

  double _totalValue = 0;
  int _totalRecords = 0;
  int _totalSpins = 0;

  List<Map<String, dynamic>> _recentlyScanned = [];
  List<Map<String, dynamic>> _neglected = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final results = await Future.wait([
        AppDatabase.getCollectionValue(),
        AppDatabase.getCollectionCount(),
        AppDatabase.getTotalSpins(),
        AppDatabase.getRecentlyScanned(),
        AppDatabase.getNeglectedRecords(),
      ]);

      if (!mounted) return;

      setState(() {
        _userName = prefs.getString('user_name') ?? '';
        _genres = prefs.getStringList('genres') ?? [];
        _totalValue = (results[0] as num?)?.toDouble() ?? 0;
        _totalRecords = (results[1] as num?)?.toInt() ?? 0;
        _totalSpins = (results[2] as num?)?.toInt() ?? 0;
        _recentlyScanned = results[3] as List<Map<String, dynamic>>;
        _neglected = results[4] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              color: SpinnerTheme.accent,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    if (_totalRecords > 0) _buildQuickStats(),
                    if (_totalRecords == 0) _buildScanCTA(),
                    _buildRecentlyScanned(),
                    _buildExploreGenres(),
                    if (_genres.isNotEmpty) _buildDiscovery(),
                    if (_neglected.isNotEmpty) _buildNeglected(),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Header ──

  Widget _buildHeader() {
    final greeting =
        _userName.isNotEmpty ? 'Hey $_userName' : 'Hey there';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 64, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              greeting,
              style: SpinnerTheme.nunito(
                size: 28,
                weight: FontWeight.w800,
                color: SpinnerTheme.white,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: SpinnerTheme.grey),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }

  // ── Quick Stats ──

  Widget _buildQuickStats() {
    final valueFormatted =
        NumberFormat.compactCurrency(symbol: '\$', decimalDigits: 0)
            .format(_totalValue);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          _StatCard(
            label: 'Records',
            value: _totalRecords.toString(),
            icon: Icons.album,
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'Value',
            value: valueFormatted,
            icon: Icons.trending_up,
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'Spins',
            value: _totalSpins.toString(),
            icon: Icons.play_arrow,
          ),
        ],
      ),
    );
  }

  // ── Empty-state CTA ──

  Widget _buildScanCTA() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: GestureDetector(
        onTap: () => context.push('/scan'),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [SpinnerTheme.accent, Color(0xFF8B7CF7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const Icon(Icons.qr_code_scanner, color: SpinnerTheme.white, size: 48),
              const SizedBox(height: 16),
              Text(
                'Scan Your First Vinyl',
                style: SpinnerTheme.nunito(
                  size: 22,
                  weight: FontWeight.w800,
                  color: SpinnerTheme.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Scan a barcode to see its value and start building your collection.',
                textAlign: TextAlign.center,
                style: SpinnerTheme.nunito(
                  size: 14,
                  weight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Recently Scanned ──

  Widget _buildRecentlyScanned() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Recently Scanned'),
        if (_recentlyScanned.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'No records scanned yet. Tap Scan to get started!',
              style: SpinnerTheme.nunito(
                size: 14,
                weight: FontWeight.w500,
                color: SpinnerTheme.grey,
              ),
            ),
          )
        else
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _recentlyScanned.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _buildRecordTile(_recentlyScanned[i]),
            ),
          ),
      ],
    );
  }

  // ── Explore Genres CTA ──

  Widget _buildExploreGenres() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: GestureDetector(
        onTap: () => context.push('/explore'),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.explore, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Explore Genres',
                      style: SpinnerTheme.nunito(
                        size: 17,
                        weight: FontWeight.w800,
                        color: SpinnerTheme.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Discover 100+ genres and find new vinyl',
                      style: SpinnerTheme.nunito(
                        size: 12,
                        weight: FontWeight.w500,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Discovery ──

  static const _genreRecommendations = <String, List<Map<String, String>>>{
    // Rock subgenres
    'Classic Rock': [
      {'title': 'Dark Side of the Moon', 'artist': 'Pink Floyd', 'year': '1973', 'img': 'https://upload.wikimedia.org/wikipedia/en/3/3b/Dark_Side_of_the_Moon.png'},
      {'title': 'Rumours', 'artist': 'Fleetwood Mac', 'year': '1977', 'img': 'https://upload.wikimedia.org/wikipedia/en/f/fb/FMacRumworsCover.png'},
      {'title': 'Abbey Road', 'artist': 'The Beatles', 'year': '1969', 'img': 'https://upload.wikimedia.org/wikipedia/en/4/42/Beatles_-_Abbey_Road.jpg'},
    ],
    'Alternative Rock': [
      {'title': 'OK Computer', 'artist': 'Radiohead', 'year': '1997', 'img': 'https://upload.wikimedia.org/wikipedia/en/b/ba/Radioheadokcomputer.png'},
      {'title': 'Nevermind', 'artist': 'Nirvana', 'year': '1991', 'img': 'https://upload.wikimedia.org/wikipedia/en/b/b7/NirvanaNevermindalbumcover.jpg'},
    ],
    'Indie Rock': [
      {'title': 'Is This It', 'artist': 'The Strokes', 'year': '2001', 'img': 'https://upload.wikimedia.org/wikipedia/en/a/ad/The_Strokes_-_Is_This_It_cover.png'},
    ],
    'Psychedelic Rock': [
      {'title': 'Dark Side of the Moon', 'artist': 'Pink Floyd', 'year': '1973', 'img': 'https://upload.wikimedia.org/wikipedia/en/3/3b/Dark_Side_of_the_Moon.png'},
    ],
    'Progressive Rock': [
      {'title': 'Dark Side of the Moon', 'artist': 'Pink Floyd', 'year': '1973', 'img': 'https://upload.wikimedia.org/wikipedia/en/3/3b/Dark_Side_of_the_Moon.png'},
    ],
    // Jazz
    'Jazz': [
      {'title': 'Kind of Blue', 'artist': 'Miles Davis', 'year': '1959', 'img': 'https://upload.wikimedia.org/wikipedia/en/9/9c/MilesDavisKindofBlue.jpg'},
      {'title': 'A Love Supreme', 'artist': 'John Coltrane', 'year': '1965', 'img': 'https://upload.wikimedia.org/wikipedia/en/1/1d/A_Love_Supreme.jpg'},
      {'title': 'Blue Train', 'artist': 'John Coltrane', 'year': '1958', 'img': 'https://upload.wikimedia.org/wikipedia/en/6/68/John_Coltrane_-_Blue_Train.jpg'},
    ],
    'Bebop': [
      {'title': 'Kind of Blue', 'artist': 'Miles Davis', 'year': '1959', 'img': 'https://upload.wikimedia.org/wikipedia/en/9/9c/MilesDavisKindofBlue.jpg'},
    ],
    'Free Jazz': [
      {'title': 'A Love Supreme', 'artist': 'John Coltrane', 'year': '1965', 'img': 'https://upload.wikimedia.org/wikipedia/en/1/1d/A_Love_Supreme.jpg'},
    ],
    'Jazz Fusion': [
      {'title': 'Kind of Blue', 'artist': 'Miles Davis', 'year': '1959', 'img': 'https://upload.wikimedia.org/wikipedia/en/9/9c/MilesDavisKindofBlue.jpg'},
    ],
    // Hip-Hop
    'Hip-Hop': [
      {'title': 'Illmatic', 'artist': 'Nas', 'year': '1994', 'img': 'https://upload.wikimedia.org/wikipedia/en/2/23/Illmatic.jpg'},
      {'title': 'To Pimp a Butterfly', 'artist': 'Kendrick Lamar', 'year': '2015', 'img': 'https://upload.wikimedia.org/wikipedia/en/f/f6/Kendrick_Lamar_-_To_Pimp_a_Butterfly.png'},
    ],
    'Boom Bap': [
      {'title': 'Illmatic', 'artist': 'Nas', 'year': '1994', 'img': 'https://upload.wikimedia.org/wikipedia/en/2/23/Illmatic.jpg'},
      {'title': 'To Pimp a Butterfly', 'artist': 'Kendrick Lamar', 'year': '2015', 'img': 'https://upload.wikimedia.org/wikipedia/en/f/f6/Kendrick_Lamar_-_To_Pimp_a_Butterfly.png'},
    ],
    // Electronic
    'House': [
      {'title': 'Homework', 'artist': 'Daft Punk', 'year': '1997', 'img': 'https://upload.wikimedia.org/wikipedia/en/9/9c/Daftpunk-homework.jpg'},
    ],
    'Techno': [
      {'title': 'Drexciya', 'artist': 'Drexciya', 'year': '1997', 'img': 'https://upload.wikimedia.org/wikipedia/en/b/b5/Drexciya_-_Neptune%27s_Lair.jpg'},
    ],
    'Ambient': [
      {'title': 'Selected Ambient Works', 'artist': 'Aphex Twin', 'year': '1992', 'img': 'https://upload.wikimedia.org/wikipedia/en/3/3f/Selected_Ambient_Works_85-92.png'},
    ],
    'Synthwave': [
      {'title': 'Drive OST', 'artist': 'Various', 'year': '2011', 'img': 'https://upload.wikimedia.org/wikipedia/en/1/1f/Drive_soundtrack.jpg'},
    ],
    // Soul/Funk/R&B
    'Soul': [
      {'title': "What's Going On", 'artist': 'Marvin Gaye', 'year': '1971', 'img': 'https://upload.wikimedia.org/wikipedia/en/8/84/MarvinGayeWhat%27sGoingOnalbumcover.jpg'},
      {'title': 'Songs in the Key of Life', 'artist': 'Stevie Wonder', 'year': '1976', 'img': 'https://upload.wikimedia.org/wikipedia/en/e/e2/Stevie_Wonder_-_Songs_in_the_Key_of_Life.png'},
    ],
    'Funk': [
      {'title': 'Maggot Brain', 'artist': 'Funkadelic', 'year': '1971', 'img': 'https://upload.wikimedia.org/wikipedia/en/5/5a/Funkadelic_-_Maggot_Brain.jpg'},
    ],
    // Pop
    'Pop': [
      {'title': 'Thriller', 'artist': 'Michael Jackson', 'year': '1982', 'img': 'https://upload.wikimedia.org/wikipedia/en/5/55/Michael_Jackson_-_Thriller.png'},
      {'title': 'Purple Rain', 'artist': 'Prince', 'year': '1984', 'img': 'https://upload.wikimedia.org/wikipedia/en/9/9c/Princepurplerain.jpg'},
    ],
    // Classical
    'Classical': [
      {'title': 'The Four Seasons', 'artist': 'Vivaldi', 'year': '1725', 'img': 'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d9/Antonio_Vivaldi.jpg/440px-Antonio_Vivaldi.jpg'},
    ],
    // Punk
    'Punk': [
      {'title': 'London Calling', 'artist': 'The Clash', 'year': '1979', 'img': 'https://upload.wikimedia.org/wikipedia/en/0/00/TheClashLondonCallingalbumcover.jpg'},
      {'title': 'Never Mind the Bollocks', 'artist': 'Sex Pistols', 'year': '1977', 'img': 'https://upload.wikimedia.org/wikipedia/en/4/4c/Never_Mind_the_Bollocks%2C_Here%27s_the_Sex_Pistols.png'},
    ],
    'Post-Punk': [
      {'title': 'Unknown Pleasures', 'artist': 'Joy Division', 'year': '1979', 'img': 'https://upload.wikimedia.org/wikipedia/en/7/71/Unknown_Pleasures_Joy_Division.png'},
    ],
    'Hardcore': [
      {'title': 'London Calling', 'artist': 'The Clash', 'year': '1979', 'img': 'https://upload.wikimedia.org/wikipedia/en/0/00/TheClashLondonCallingalbumcover.jpg'},
    ],
    // Metal
    'Heavy Metal': [
      {'title': 'Master of Puppets', 'artist': 'Metallica', 'year': '1986', 'img': 'https://upload.wikimedia.org/wikipedia/en/b/b2/Metallica_-_Master_of_Puppets_cover.jpg'},
      {'title': 'Paranoid', 'artist': 'Black Sabbath', 'year': '1970', 'img': 'https://upload.wikimedia.org/wikipedia/en/6/64/Black_Sabbath_-_Paranoid.jpg'},
    ],
    'Thrash Metal': [
      {'title': 'Master of Puppets', 'artist': 'Metallica', 'year': '1986', 'img': 'https://upload.wikimedia.org/wikipedia/en/b/b2/Metallica_-_Master_of_Puppets_cover.jpg'},
    ],
    'Death Metal': [
      {'title': 'Master of Puppets', 'artist': 'Metallica', 'year': '1986', 'img': 'https://upload.wikimedia.org/wikipedia/en/b/b2/Metallica_-_Master_of_Puppets_cover.jpg'},
    ],
    'Black Metal': [
      {'title': 'Paranoid', 'artist': 'Black Sabbath', 'year': '1970', 'img': 'https://upload.wikimedia.org/wikipedia/en/6/64/Black_Sabbath_-_Paranoid.jpg'},
    ],
    'Doom Metal': [
      {'title': 'Paranoid', 'artist': 'Black Sabbath', 'year': '1970', 'img': 'https://upload.wikimedia.org/wikipedia/en/6/64/Black_Sabbath_-_Paranoid.jpg'},
    ],
    // Reggae
    'Reggae': [
      {'title': 'Legend', 'artist': 'Bob Marley', 'year': '1984', 'img': 'https://upload.wikimedia.org/wikipedia/en/1/1e/BobMarley-Legend.jpg'},
    ],
    // Blues
    'Blues': [
      {'title': 'King of the Delta Blues', 'artist': 'Robert Johnson', 'year': '1961', 'img': 'https://upload.wikimedia.org/wikipedia/en/3/32/Robert_Johnson_-_King_of_the_Delta_Blues_Singers.jpg'},
    ],
    // Shoegaze
    'Shoegaze': [
      {'title': 'Loveless', 'artist': 'My Bloody Valentine', 'year': '1991', 'img': 'https://upload.wikimedia.org/wikipedia/en/4/4b/My_Bloody_Valentine_-_Loveless.png'},
    ],
    // New Wave
    'New Wave': [
      {'title': 'Closer', 'artist': 'Joy Division', 'year': '1980', 'img': 'https://upload.wikimedia.org/wikipedia/en/2/2a/Joy_Division_-_Closer.png'},
    ],
  };

  List<Map<String, String>> get _recommendations {
    final recs = <Map<String, String>>[];
    for (final genre in _genres) {
      final items = _genreRecommendations[genre];
      if (items != null) recs.addAll(items);
    }
    return recs;
  }

  Widget _buildDiscovery() {
    final recs = _recommendations;
    if (recs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Recommended For You'),
        if (recs.isNotEmpty)
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: recs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final rec = recs[i];
                return GestureDetector(
                  onTap: () {
                    // Future: navigate to record detail
                  },
                  child: SizedBox(
                    width: 140,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: rec['img'] ?? '',
                            width: 140,
                            height: 140,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              width: 140, height: 140,
                              color: SpinnerTheme.card,
                              child: const Icon(Icons.album, color: SpinnerTheme.grey, size: 40),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              width: 140, height: 140,
                              color: SpinnerTheme.card,
                              child: const Icon(Icons.album, color: SpinnerTheme.grey, size: 40),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          rec['title'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SpinnerTheme.nunito(size: 13, weight: FontWeight.w600, color: SpinnerTheme.white),
                        ),
                        Text(
                          rec['artist'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SpinnerTheme.nunito(size: 11, color: SpinnerTheme.grey),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          )
      ],
    );
  }

  // ── Neglected Records ──

  Widget _buildNeglected() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle("Haven't Played in a While"),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _neglected.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _buildRecordTile(_neglected[i]),
          ),
        ),
      ],
    );
  }

  // ── Shared helpers ──

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      child: Text(
        title,
        style: SpinnerTheme.nunito(
          size: 20,
          weight: FontWeight.w700,
          color: SpinnerTheme.white,
        ),
      ),
    );
  }

  Widget _buildRecordTile(Map<String, dynamic> record) {
    final coverUrl = record['cover_url'] as String? ?? '';
    final title = record['title'] as String? ?? 'Unknown';
    final artist = record['artist'] as String? ?? 'Unknown';
    final id = record['id'];

    return GestureDetector(
      onTap: () {
        if (id != null) context.push('/record/$id');
      },
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover art
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 140,
                height: 140,
                child: coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: SpinnerTheme.surface,
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: SpinnerTheme.grey,
                              ),
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: SpinnerTheme.surface,
                          child: const Icon(Icons.album,
                              color: SpinnerTheme.grey, size: 40),
                        ),
                      )
                    : Container(
                        color: SpinnerTheme.surface,
                        child: const Center(
                          child: Icon(Icons.album,
                              color: SpinnerTheme.grey, size: 40),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SpinnerTheme.nunito(
                size: 14,
                weight: FontWeight.w700,
                color: SpinnerTheme.white,
              ),
            ),
            Text(
              artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SpinnerTheme.nunito(
                size: 12,
                weight: FontWeight.w500,
                color: SpinnerTheme.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stat Card ──

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SpinnerTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SpinnerTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: SpinnerTheme.accent, size: 18),
            const SizedBox(height: 8),
            Text(
              value,
              style: SpinnerTheme.nunito(
                size: 20,
                weight: FontWeight.w800,
                color: SpinnerTheme.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: SpinnerTheme.nunito(
                size: 12,
                weight: FontWeight.w500,
                color: SpinnerTheme.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
