import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:scatesdk_flutter/scatesdk_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';

/// Cardly-style onboarding funnel:
///   showcase x3 -> experience -> genre -> goals -> notifications ->
///   "personalizing" loader -> rating -> paywall.
/// Every step shares the same pinned bottom button position so onboarding and
/// the paywall feel like one continuous flow.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _totalPages = 9;
  static const _experiencePage = 3;
  static const _genrePage = 4;
  static const _goalsPage = 5;
  static const _notifPage = 6;
  static const _loadingPage = 7;
  static const _ratingPage = 8;

  String? _experience;
  final Set<String> _selectedGenres = {};
  final Set<String> _selectedGoals = {};
  bool _busy = false;

  static const _experiences = [
    ['Beginner', 'New to collecting'],
    ['Intermediate', 'Collecting for a few years'],
    ['Advanced', 'Seasoned crate digger'],
  ];

  static const _goals = [
    ['Identify records & check value', Icons.search],
    ['AI condition grading', Icons.auto_awesome],
    ['Track my collection\'s worth', Icons.trending_up],
    ['Get price drop alerts', Icons.notifications_active],
  ];

  static const _genres = [
    'Classic Rock', 'Alternative Rock', 'Indie Rock', 'Psychedelic Rock', 'Progressive Rock', 'Garage Rock',
    'Heavy Metal', 'Thrash Metal', 'Death Metal', 'Black Metal', 'Doom Metal',
    'Punk', 'Post-Punk', 'Hardcore',
    'House', 'Techno', 'Ambient', 'Drum & Bass', 'Synthwave', 'IDM', 'Trance',
    'Hip-Hop', 'Boom Bap', 'Trap', 'Lo-Fi Hip-Hop',
    'Jazz', 'Bebop', 'Free Jazz', 'Jazz Fusion', 'Smooth Jazz',
    'Soul', 'Funk', 'R&B', 'Neo-Soul', 'Motown',
    'Pop', 'Synth-Pop', 'Dream Pop', 'K-Pop', 'J-Pop',
    'Blues', 'Country', 'Folk', 'Reggae', 'Ska', 'Dub',
    'Classical', 'Latin', 'Bossa Nova', 'Afrobeat', 'World',
    'Soundtracks', 'Experimental', 'Noise', 'Shoegaze', 'New Wave',
  ];

  @override
  void initState() {
    super.initState();
    try {
      ScateSDK.OnboardingStart();
    } catch (_) {}
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _canAdvance {
    switch (_currentPage) {
      case _experiencePage:
        return _experience != null;
      case _genrePage:
        return _selectedGenres.isNotEmpty;
      case _goalsPage:
        return _selectedGoals.isNotEmpty;
      default:
        return true;
    }
  }

  String get _primaryLabel {
    if (_currentPage == _notifPage) return 'Allow Notifications';
    return 'Continue';
  }

  Future<void> _onPrimary() async {
    if (_currentPage == _notifPage) {
      await _requestNotifications();
    }
    if (_currentPage == _ratingPage) {
      await _completeOnboarding();
      return;
    }
    if (_currentPage < _totalPages - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0 && _currentPage != _loadingPage) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _requestNotifications() async {
    try {
      final ios = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {
      // Permission denial / unsupported platform must never block onboarding.
    }
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    if (page == _loadingPage) {
      // "Personalizing" interstitial — auto-advance to the rating step.
      Future<void>.delayed(const Duration(milliseconds: 2600), () {
        if (mounted && _currentPage == _loadingPage) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  Future<void> _completeOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_complete', true);
      await prefs.setStringList('genres', _selectedGenres.toList());
      if (_experience != null) {
        await prefs.setString('experience', _experience!);
      }
      await prefs.setStringList('goals', _selectedGoals.toList());
    } catch (_) {
      // Never block startup.
    }
    if (!mounted) return;
    context.go('/onboarding-paywall');
  }

  @override
  Widget build(BuildContext context) {
    final showButton = _currentPage != _loadingPage;
    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: _onPageChanged,
                children: [
                  _buildShowcase(
                    icon: Icons.photo_camera_rounded,
                    title: 'Scan any record',
                    body:
                        'Snap a photo of the cover and Spinner IDs the exact '
                        'pressing, then pulls its market value in seconds.',
                  ),
                  _buildShowcase(
                    icon: Icons.album_rounded,
                    title: 'Build your collection',
                    body:
                        'Every record you scan lands in your collection with '
                        'its value, condition grade, and history.',
                  ),
                  _buildShowcase(
                    icon: Icons.trending_down_rounded,
                    title: 'Never overpay again',
                    body:
                        'Add records to your wishlist and get pinged the moment '
                        'a copy drops in price.',
                  ),
                  _buildExperience(),
                  _buildGenres(),
                  _buildGoals(),
                  _buildNotif(),
                  _buildLoading(),
                  _buildRating(),
                ],
              ),
            ),
            if (showButton) _buildPinnedButton(),
          ],
        ),
      ),
    );
  }

  // ── Top bar: back + progress ────────────────────────────────────────

  Widget _buildTopBar() {
    final progress = (_currentPage + 1) / _totalPages;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: (_currentPage > 0 && _currentPage != _loadingPage)
                ? GestureDetector(
                    onTap: _previousPage,
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: SpinnerTheme.white, size: 20),
                  )
                : null,
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: SpinnerTheme.surface,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(SpinnerTheme.accent),
              ),
            ),
          ),
          const SizedBox(width: 28),
        ],
      ),
    );
  }

  // ── Showcase ────────────────────────────────────────────────────────

  Widget _buildShowcase({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      // Fixed top offset + start alignment so the icon and title sit at the
      // SAME vertical position on every showcase page, regardless of how many
      // lines the body text wraps to. (Center alignment made each title land at
      // a different height.)
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 64),
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              color: SpinnerTheme.accent.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: SpinnerTheme.accent, size: 54),
          ),
          const SizedBox(height: 36),
          Text(
            title,
            textAlign: TextAlign.center,
            style: SpinnerTheme.nunito(
              size: 28,
              weight: FontWeight.w800,
              color: SpinnerTheme.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            body,
            textAlign: TextAlign.center,
            style: SpinnerTheme.nunito(
              size: 16,
              weight: FontWeight.w400,
              color: SpinnerTheme.grey,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Experience ──────────────────────────────────────────────────────

  Widget _buildExperience() {
    return _QuestionLayout(
      title: 'How would you describe\nyour collecting experience?',
      subtitle: "We'll personalize the experience for you",
      child: Column(
        children: [
          for (final e in _experiences)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SelectTile(
                title: e[0],
                subtitle: e[1],
                selected: _experience == e[0],
                onTap: () => setState(() => _experience = e[0]),
              ),
            ),
        ],
      ),
    );
  }

  // ── Genre ───────────────────────────────────────────────────────────

  Widget _buildGenres() {
    return _QuestionLayout(
      title: 'Pick your favorite genres',
      subtitle: "We'll recommend records you'll love",
      scrollable: true,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _genres.map((genre) {
          final isSelected = _selectedGenres.contains(genre);
          return GestureDetector(
            onTap: () => setState(() {
              if (isSelected) {
                _selectedGenres.remove(genre);
              } else {
                _selectedGenres.add(genre);
              }
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? SpinnerTheme.accent.withOpacity(0.15)
                    : SpinnerTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color:
                      isSelected ? SpinnerTheme.accent : SpinnerTheme.border,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Text(
                genre,
                style: SpinnerTheme.nunito(
                  size: 14,
                  weight: FontWeight.w600,
                  color:
                      isSelected ? SpinnerTheme.accent : SpinnerTheme.white,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Goals ───────────────────────────────────────────────────────────

  Widget _buildGoals() {
    return _QuestionLayout(
      title: 'What do you want\nhelp with?',
      subtitle: 'So we can focus on what matters to you',
      child: Column(
        children: [
          for (final g in _goals)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SelectTile(
                title: g[0] as String,
                icon: g[1] as IconData,
                selected: _selectedGoals.contains(g[0]),
                onTap: () => setState(() {
                  final key = g[0] as String;
                  if (_selectedGoals.contains(key)) {
                    _selectedGoals.remove(key);
                  } else {
                    _selectedGoals.add(key);
                  }
                }),
              ),
            ),
        ],
      ),
    );
  }

  // ── Notifications ───────────────────────────────────────────────────

  Widget _buildNotif() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              color: SpinnerTheme.accent.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.notifications_active_rounded,
                color: SpinnerTheme.accent, size: 54),
          ),
          const SizedBox(height: 36),
          Text(
            'Stay ahead of the market',
            textAlign: TextAlign.center,
            style: SpinnerTheme.nunito(
              size: 26,
              weight: FontWeight.w800,
              color: SpinnerTheme.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Get notified when a record on your wishlist drops in price or a '
            'rare pressing shows up.',
            textAlign: TextAlign.center,
            style: SpinnerTheme.nunito(
              size: 16,
              weight: FontWeight.w400,
              color: SpinnerTheme.grey,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── "Personalizing" loader ──────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 2400),
              builder: (context, value, _) {
                return SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: value,
                          strokeWidth: 6,
                          backgroundColor: SpinnerTheme.surface,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              SpinnerTheme.accent),
                        ),
                      ),
                      Text(
                        '${(value * 100).round()}%',
                        style: SpinnerTheme.nunito(
                          size: 26,
                          weight: FontWeight.w800,
                          color: SpinnerTheme.white,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              'Personalizing your\nSpinner experience',
              textAlign: TextAlign.center,
              style: SpinnerTheme.nunito(
                size: 22,
                weight: FontWeight.w800,
                color: SpinnerTheme.white,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Rating ──────────────────────────────────────────────────────────

  Widget _buildRating() {
    // Fill the full page height and distribute the blocks evenly so the screen
    // never leaves a dead empty gap at the bottom.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    5,
                    (_) => const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 3),
                      child: Icon(Icons.star_rounded,
                          color: SpinnerTheme.amber, size: 36),
                    ),
                  ),
                ),
                Column(
                  children: [
                    Text(
                      'Loved by vinyl collectors',
                      textAlign: TextAlign.center,
                      style: SpinnerTheme.nunito(
                        size: 24,
                        weight: FontWeight.w800,
                        color: SpinnerTheme.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Column(
                          children: [
                            Text('4.8',
                                style: SpinnerTheme.nunito(
                                    size: 30,
                                    weight: FontWeight.w800,
                                    color: SpinnerTheme.white)),
                            Text('average rating',
                                style: SpinnerTheme.nunito(
                                    size: 13, color: SpinnerTheme.grey)),
                          ],
                        ),
                        Container(
                          width: 1,
                          height: 44,
                          margin: const EdgeInsets.symmetric(horizontal: 28),
                          color: SpinnerTheme.border,
                        ),
                        Column(
                          children: [
                            Text('thousands',
                                style: SpinnerTheme.nunito(
                                    size: 30,
                                    weight: FontWeight.w800,
                                    color: SpinnerTheme.white)),
                            Text('of collectors',
                                style: SpinnerTheme.nunito(
                                    size: 13, color: SpinnerTheme.grey)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  children: [
                    _testimonial(
                      'Scanned my whole shelf in an afternoon and finally know '
                      'what it\'s worth. The price alerts already saved me money.',
                      'Dave R.',
                    ),
                    const SizedBox(height: 12),
                    _testimonial(
                      'The AI condition grading is scary accurate. Best vinyl '
                      'app I\'ve tried, hands down.',
                      'Mara K.',
                    ),
                    const SizedBox(height: 12),
                    _testimonial(
                      'Finally a clean way to catalog my collection and see what '
                      'it\'s actually worth. Worth every penny.',
                      'Theo S.',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _testimonial(String quote, String author) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpinnerTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(
              5,
              (_) => const Icon(Icons.star_rounded,
                  color: SpinnerTheme.amber, size: 15),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            quote,
            style: SpinnerTheme.nunito(
              size: 14,
              weight: FontWeight.w500,
              color: SpinnerTheme.white,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            author,
            style: SpinnerTheme.nunito(size: 12, color: SpinnerTheme.grey),
          ),
        ],
      ),
    );
  }

  // ── Pinned button ───────────────────────────────────────────────────

  Widget _buildPinnedButton() {
    final enabled = _canAdvance && !_busy;
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        MediaQuery.of(context).padding.bottom + 14,
      ),
      decoration: BoxDecoration(
        color: SpinnerTheme.bg,
        border: Border(top: BorderSide(color: SpinnerTheme.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: Material(
          color: enabled ? SpinnerTheme.accent : SpinnerTheme.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: enabled ? _onPrimary : null,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: Text(
                _primaryLabel,
                style: SpinnerTheme.nunito(
                  size: 17,
                  weight: FontWeight.w700,
                  color: enabled ? SpinnerTheme.white : SpinnerTheme.grey,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared question layout ────────────────────────────────────────────

class _QuestionLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final bool scrollable;

  const _QuestionLayout({
    required this.title,
    required this.subtitle,
    required this.child,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          title,
          style: SpinnerTheme.nunito(
            size: 26,
            weight: FontWeight.w800,
            color: SpinnerTheme.white,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: SpinnerTheme.nunito(
            size: 14,
            weight: FontWeight.w400,
            color: SpinnerTheme.grey,
          ),
        ),
        const SizedBox(height: 28),
        child,
        const SizedBox(height: 16),
      ],
    );

    final padded = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: header,
    );

    if (scrollable) return SingleChildScrollView(child: padded);
    return padded;
  }
}

// ── Shared select tile ────────────────────────────────────────────────

class _SelectTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _SelectTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected
              ? SpinnerTheme.accent.withOpacity(0.12)
              : SpinnerTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? SpinnerTheme.accent : SpinnerTheme.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon,
                  color: selected ? SpinnerTheme.accent : SpinnerTheme.grey,
                  size: 22),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: SpinnerTheme.nunito(
                      size: 16,
                      weight: FontWeight.w700,
                      color: selected
                          ? SpinnerTheme.accent
                          : SpinnerTheme.white,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: SpinnerTheme.nunito(
                        size: 13,
                        weight: FontWeight.w400,
                        color: SpinnerTheme.grey,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? SpinnerTheme.accent : Colors.transparent,
                border: Border.all(
                  color: selected ? SpinnerTheme.accent : SpinnerTheme.grey,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
