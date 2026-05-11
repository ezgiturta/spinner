import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai_access.dart';
import '../../../core/claude_api.dart';
import '../../../core/database.dart';
import '../../../core/router.dart';
import '../../../core/theme.dart';

/// Expandable, lazy-loaded card that fetches and renders an AI-generated
/// "story" for the album (recording context, band history, hidden tracks,
/// rare pressings).
///
/// First load goes through the proxy and counts toward the free quota; the
/// result is cached in `ai_stories` so subsequent opens are free and instant.
class AlbumStoryCard extends StatefulWidget {
  final String recordId;
  final String title;
  final String artist;
  final int? year;
  final String? label;
  final String? country;

  const AlbumStoryCard({
    super.key,
    required this.recordId,
    required this.title,
    required this.artist,
    this.year,
    this.label,
    this.country,
  });

  @override
  State<AlbumStoryCard> createState() => _AlbumStoryCardState();
}

class _AlbumStoryCardState extends State<AlbumStoryCard> {
  bool _expanded = false;
  bool _loading = false;
  AlbumStory? _story;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCached();
  }

  Future<void> _loadCached() async {
    final cached = await AppDatabase.getAiStory(widget.recordId);
    if (cached == null) return;
    try {
      final parsed =
          jsonDecode(cached['story_json'] as String) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _story = AlbumStory.fromJson(parsed));
    } catch (_) {
      // Ignore stale/corrupt cache.
    }
  }

  Future<void> _toggle() async {
    setState(() => _expanded = !_expanded);
    if (_expanded && _story == null && !_loading) {
      await _generate();
    }
  }

  Future<void> _generate() async {
    final allowed = await AiAccess.canUseStory();
    if (!allowed) {
      if (!mounted) return;
      _showPaywall();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final story = await ClaudeApi.instance.getAlbumStory(
        title: widget.title,
        artist: widget.artist,
        year: widget.year,
        label: widget.label,
        country: widget.country,
      );
      await AiAccess.recordStoryUse();
      await AppDatabase.saveAiStory(
          widget.recordId, jsonEncode(story.toJson()));
      if (!mounted) return;
      setState(() {
        _story = story;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load story: $e';
      });
    }
  }

  void _showPaywall() {
    context.push(AppRoutes.paywall);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.auto_stories,
                      color: SpinnerTheme.accent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Story',
                          style: SpinnerTheme.nunito(
                              size: 14,
                              weight: FontWeight.w700,
                              color: SpinnerTheme.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _story != null
                              ? 'Tap to ${_expanded ? "collapse" : "read"}'
                              : 'AI-generated context, deep cuts, and rare pressings',
                          style: SpinnerTheme.nunito(
                              size: 12, color: SpinnerTheme.grey),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: SpinnerTheme.grey,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildBody(),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: SpinnerTheme.accent),
            ),
            const SizedBox(width: 10),
            Text('Writing the story…',
                style:
                    SpinnerTheme.nunito(size: 13, color: SpinnerTheme.grey)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_error!,
              style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.red)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.refresh, size: 16),
            label: Text('Retry',
                style: SpinnerTheme.nunito(
                    size: 13, weight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: SpinnerTheme.accent,
              side: BorderSide(color: SpinnerTheme.accent.withOpacity(0.5)),
            ),
          ),
        ],
      );
    }

    final story = _story;
    if (story == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Tap to generate.',
          style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.grey),
        ),
      );
    }

    if (story.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No notable info found for this pressing.',
          style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.grey),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (story.recordingContext != null && story.recordingContext!.isNotEmpty)
          _section('Recording', story.recordingContext!),
        if (story.bandHistory != null && story.bandHistory!.isNotEmpty)
          _section('At the time', story.bandHistory!),
        if (story.whereToStart != null) _whereToStart(story.whereToStart!),
        if (story.hiddenTracks.isNotEmpty) _hiddenTracks(story.hiddenTracks),
        if (story.rarePressings.isNotEmpty)
          _rarePressings(story.rarePressings),
      ],
    );
  }

  Widget _section(String label, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: SpinnerTheme.nunito(
                  size: 11,
                  weight: FontWeight.w700,
                  color: SpinnerTheme.grey,
                  height: 1.0)),
          const SizedBox(height: 6),
          Text(body,
              style: SpinnerTheme.nunito(
                  size: 14,
                  color: SpinnerTheme.greyLight,
                  height: 1.5)),
        ],
      ),
    );
  }

  Widget _whereToStart(WhereToStart w) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SpinnerTheme.accent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SpinnerTheme.accent.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.play_circle, color: SpinnerTheme.accent, size: 16),
                const SizedBox(width: 6),
                Text('START HERE',
                    style: SpinnerTheme.nunito(
                        size: 11,
                        weight: FontWeight.w700,
                        color: SpinnerTheme.accent)),
              ],
            ),
            const SizedBox(height: 6),
            Text(w.track,
                style: SpinnerTheme.nunito(
                    size: 15,
                    weight: FontWeight.w700,
                    color: SpinnerTheme.white)),
            const SizedBox(height: 4),
            Text(w.why,
                style: SpinnerTheme.nunito(
                    size: 13,
                    color: SpinnerTheme.greyLight,
                    height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _hiddenTracks(List<HiddenTrack> tracks) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DEEP CUTS',
              style: SpinnerTheme.nunito(
                  size: 11,
                  weight: FontWeight.w700,
                  color: SpinnerTheme.grey)),
          const SizedBox(height: 8),
          ...tracks.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•',
                        style: SpinnerTheme.nunito(
                            size: 14, color: SpinnerTheme.accent)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: t.track,
                              style: SpinnerTheme.nunito(
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: SpinnerTheme.white),
                            ),
                            TextSpan(
                              text: '  —  ${t.why}',
                              style: SpinnerTheme.nunito(
                                  size: 13,
                                  color: SpinnerTheme.greyLight,
                                  height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _rarePressings(List<RarePressing> pressings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PRESSINGS COLLECTORS WANT',
            style: SpinnerTheme.nunito(
                size: 11,
                weight: FontWeight.w700,
                color: SpinnerTheme.grey)),
        const SizedBox(height: 8),
        ...pressings.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: SpinnerTheme.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SpinnerTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        style: SpinnerTheme.nunito(
                            size: 13,
                            weight: FontWeight.w700,
                            color: SpinnerTheme.white)),
                    if (p.marker != null && p.marker!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('Marker: ${p.marker!}',
                          style: SpinnerTheme.nunito(
                              size: 12,
                              color: SpinnerTheme.amber,
                              weight: FontWeight.w500)),
                    ],
                    if (p.note != null && p.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(p.note!,
                          style: SpinnerTheme.nunito(
                              size: 12,
                              color: SpinnerTheme.greyLight,
                              height: 1.4)),
                    ],
                  ],
                ),
              ),
            )),
      ],
    );
  }
}
