import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  // Screen 1: Welcome + Name
  final _nameController = TextEditingController();

  // Screen 2: Genres
  final Set<String> _selectedGenres = {};

  // Screen 3: Collection size
  String? _collectionSize;

  // Screen 4: Discogs
  bool _connectingDiscogs = false;

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

  static const _collectionSizes = [
    'Just starting',
    '1-50',
    '50-200',
    '200+',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _nextPage() {
    FocusScope.of(context).unfocus();
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    FocusScope.of(context).unfocus();
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
      await prefs.setString('user_name', _nameController.text.trim());
      await prefs.setStringList('genres', _selectedGenres.toList());
      if (_collectionSize != null) {
        await prefs.setString('collection_size', _collectionSize!);
      }
    } catch (_) {
      // Never block app startup -- proceed even if prefs fail.
    }

    if (!mounted) return;
    context.go('/home');
  }

  Future<void> _connectDiscogs() async {
    setState(() => _connectingDiscogs = true);
    try {
      // TODO: Implement Discogs OAuth flow.
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      await _completeOnboarding();
    } catch (_) {
      if (!mounted) return;
      setState(() => _connectingDiscogs = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: SpinnerTheme.surface,
          content: Text(
            'Could not connect to Discogs. Please try again.',
            style: SpinnerTheme.nunito(
              size: 14,
              weight: FontWeight.w500,
              color: SpinnerTheme.white,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openDiscogsSignup() async {
    final uri = Uri.parse('https://www.discogs.com/users/create');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
                  _buildWelcomePage(),
                  _buildGenresPage(),
                  _buildCollectionSizePage(),
                  _buildDiscogsPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDotIndicators() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) {
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

  // ─── Screen 1: Welcome + Name ───────────────────────────────────────

  Widget _buildWelcomePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 48),
            const Icon(Icons.album, color: SpinnerTheme.accent, size: 72),
            const SizedBox(height: 24),
            Text(
              'Welcome to Spinner',
              style: SpinnerTheme.nunito(
                size: 28,
                weight: FontWeight.w800,
                color: SpinnerTheme.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Your vinyl collection deserves to be valued.',
              style: SpinnerTheme.nunito(
                size: 16,
                weight: FontWeight.w400,
                color: SpinnerTheme.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (_nameController.text.trim().isNotEmpty) _nextPage();
              },
              style: SpinnerTheme.nunito(
                size: 16,
                weight: FontWeight.w500,
                color: SpinnerTheme.white,
              ),
              decoration: InputDecoration(
                hintText: "What's your name?",
                hintStyle: SpinnerTheme.nunito(
                  size: 16,
                  weight: FontWeight.w400,
                  color: SpinnerTheme.grey,
                ),
                filled: true,
                fillColor: SpinnerTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: SpinnerTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: SpinnerTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: SpinnerTheme.accent, width: 2),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
            ),
            const SizedBox(height: 48),
            _ContinueButton(
              label: 'Continue',
              onTap:
                  _nameController.text.trim().isNotEmpty ? _nextPage : null,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ─── Screen 2: Genres ───────────────────────────────────────────────

  Widget _buildGenresPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
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
          const SizedBox(height: 40),
          _ContinueButton(
            label: 'Continue',
            onTap: _selectedGenres.isNotEmpty ? _nextPage : null,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ─── Screen 3: Collection Size ──────────────────────────────────────

  Widget _buildCollectionSizePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Text(
            'How many records\ndo you own?',
            style: SpinnerTheme.nunito(
              size: 28,
              weight: FontWeight.w800,
              color: SpinnerTheme.white,
            ),
          ),
          const SizedBox(height: 32),
          ...List.generate(_collectionSizes.length, (index) {
            final size = _collectionSizes[index];
            final isSelected = _collectionSize == size;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => setState(() => _collectionSize = size),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? SpinnerTheme.accent.withOpacity(0.15)
                        : SpinnerTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? SpinnerTheme.accent
                          : SpinnerTheme.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    size,
                    style: SpinnerTheme.nunito(
                      size: 16,
                      weight: FontWeight.w600,
                      color: isSelected
                          ? SpinnerTheme.accent
                          : SpinnerTheme.white,
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 40),
          _ContinueButton(
            label: 'Continue',
            onTap: _collectionSize != null ? _nextPage : null,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ─── Screen 4: Connect Discogs ──────────────────────────────────────

  Widget _buildDiscogsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 48),
            const Icon(Icons.sync_alt, color: SpinnerTheme.accent, size: 64),
            const SizedBox(height: 24),
            Text(
              'Import your collection',
              style: SpinnerTheme.nunito(
                size: 28,
                weight: FontWeight.w800,
                color: SpinnerTheme.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Connect your Discogs account to sync your vinyl collection.',
              style: SpinnerTheme.nunito(
                size: 15,
                weight: FontWeight.w400,
                color: SpinnerTheme.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            _ContinueButton(
              label:
                  _connectingDiscogs ? 'Connecting...' : 'Connect Discogs',
              onTap: _connectingDiscogs ? null : _connectDiscogs,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _connectingDiscogs ? null : _openDiscogsSignup,
              child: Text(
                'Create Discogs Account',
                style: SpinnerTheme.nunito(
                  size: 16,
                  weight: FontWeight.w600,
                  color: SpinnerTheme.accent,
                ),
              ),
            ),
            TextButton(
              onPressed: _connectingDiscogs ? null : _completeOnboarding,
              child: Text(
                'Skip for now',
                style: SpinnerTheme.nunito(
                  size: 16,
                  weight: FontWeight.w600,
                  color: SpinnerTheme.grey,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _ContinueButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Material(
        color: enabled ? SpinnerTheme.accent : SpinnerTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: Text(
              label,
              style: SpinnerTheme.nunito(
                size: 17,
                weight: FontWeight.w700,
                color: enabled ? SpinnerTheme.white : SpinnerTheme.grey,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
