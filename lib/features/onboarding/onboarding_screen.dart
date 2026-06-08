import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scatesdk_flutter/scatesdk_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';

/// Onboarding = a short feature showcase, then the paywall. No name/size
/// questions — the goal is to show what Spinner does and move into the
/// paywall as one continuous flow. Every step shares the SAME pinned bottom
/// button position so onboarding + paywall feel like a single funnel.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _pageCount = 4;

  // Final step: genre selection (drives Explore recommendations).
  final Set<String> _selectedGenres = {};

  static const _genres = [
    // Rock
    'Classic Rock', 'Alternative Rock', 'Indie Rock', 'Psychedelic Rock', 'Progressive Rock', 'Garage Rock',
    // Metal
    'Heavy Metal', 'Thrash Metal', 'Death Metal', 'Black Metal', 'Doom Metal',
    // Punk
    'Punk', 'Post-Punk', 'Hardcore',
    // Electronic
    'House', 'Techno', 'Ambient', 'Drum & Bass', 'Synthwave', 'IDM', 'Trance',
    // Hip-Hop
    'Hip-Hop', 'Boom Bap', 'Trap', 'Lo-Fi Hip-Hop',
    // Jazz
    'Jazz', 'Bebop', 'Free Jazz', 'Jazz Fusion', 'Smooth Jazz',
    // Soul/Funk/R&B
    'Soul', 'Funk', 'R&B', 'Neo-Soul', 'Motown',
    // Pop
    'Pop', 'Synth-Pop', 'Dream Pop', 'K-Pop', 'J-Pop',
    // Other
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

  /// Whether the pinned button is enabled on the current page. The showcase
  /// slides are always advanceable; the genre step needs at least one pick.
  bool get _canAdvance {
    if (_currentPage == _pageCount - 1) return _selectedGenres.isNotEmpty;
    return true;
  }

  void _onPrimary() {
    FocusScope.of(context).unfocus();
    if (_currentPage < _pageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _completeOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_complete', true);
      await prefs.setStringList('genres', _selectedGenres.toList());
    } catch (_) {
      // Never block app startup — proceed even if prefs fail.
    }
    // The paywall is the final step of the onboarding funnel.
    if (!mounted) return;
    context.go('/onboarding-paywall');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Back button + progress dots
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    GestureDetector(
                      onTap: _previousPage,
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        color: SpinnerTheme.white,
                        size: 20,
                      ),
                    )
                  else
                    const SizedBox(width: 20),
                  const Spacer(),
                  _buildDotIndicators(),
                  const Spacer(),
                  const SizedBox(width: 20),
                ],
              ),
            ),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildShowcasePage(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Scan any record',
                    body:
                        'Point at the barcode — or just snap the cover. '
                        'Spinner identifies the exact pressing and pulls its '
                        'market value in seconds.',
                  ),
                  _buildShowcasePage(
                    icon: Icons.album_rounded,
                    title: 'Build your collection',
                    body:
                        'Every record you scan lands in your collection with '
                        'its value, condition grade, and history — your whole '
                        'shelf, organized.',
                  ),
                  _buildShowcasePage(
                    icon: Icons.trending_down_rounded,
                    title: 'Never overpay again',
                    body:
                        'Add records to your wishlist and get notified the '
                        'moment a copy drops in price. Spinner finds the '
                        'cheapest one for you.',
                  ),
                  _buildGenresPage(),
                ],
              ),
            ),

            // Pinned, always-aligned bottom button
            _buildPinnedButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildDotIndicators() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_pageCount, (index) {
        final isActive = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? SpinnerTheme.accent : SpinnerTheme.grey,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ─── Showcase slide (scan / collection / wishlist) ──────────────────

  Widget _buildShowcasePage({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 24),
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: SpinnerTheme.accent.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: SpinnerTheme.accent, size: 52),
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
      ),
    );
  }

  // ─── Genre selection ────────────────────────────────────────────────

  Widget _buildGenresPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick your favorite genres',
            style: SpinnerTheme.nunito(
              size: 28,
              weight: FontWeight.w800,
              color: SpinnerTheme.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "We'll recommend records you'll love",
            style: SpinnerTheme.nunito(
              size: 14,
              weight: FontWeight.w400,
              color: SpinnerTheme.grey,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _genres.map((genre) {
              final isSelected = _selectedGenres.contains(genre);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedGenres.remove(genre);
                    } else {
                      _selectedGenres.add(genre);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? SpinnerTheme.accent.withOpacity(0.15)
                        : SpinnerTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? SpinnerTheme.accent
                          : SpinnerTheme.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    genre,
                    style: SpinnerTheme.nunito(
                      size: 14,
                      weight: FontWeight.w600,
                      color: isSelected
                          ? SpinnerTheme.accent
                          : SpinnerTheme.white,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─── Pinned bottom button (same position on every step) ─────────────

  Widget _buildPinnedButton() {
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
          color: _canAdvance ? SpinnerTheme.accent : SpinnerTheme.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: _canAdvance ? _onPrimary : null,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: Text(
                'Continue',
                style: SpinnerTheme.nunito(
                  size: 17,
                  weight: FontWeight.w700,
                  color: _canAdvance ? SpinnerTheme.white : SpinnerTheme.grey,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
