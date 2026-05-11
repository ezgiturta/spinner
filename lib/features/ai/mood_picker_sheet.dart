import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/ai_access.dart';
import '../../core/claude_api.dart';
import '../../core/database.dart';
import '../../core/router.dart';
import '../../core/theme.dart';

/// Modal bottom sheet that asks Claude to pick records from the user's
/// collection that match a freeform mood / vibe / moment.
class MoodPickerSheet extends StatefulWidget {
  const MoodPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const MoodPickerSheet(),
    );
  }

  @override
  State<MoodPickerSheet> createState() => _MoodPickerSheetState();
}

class _MoodPickerSheetState extends State<MoodPickerSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _error;
  List<_PickWithRecord>? _picks;

  static const _suggestions = [
    'rainy evening, slow tempo',
    'sunday morning coffee',
    'late night drive',
    'studying, no vocals',
    'dinner with friends',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask([String? text]) async {
    final query = (text ?? _controller.text).trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();

    final allowed = await AiAccess.canUseMood();
    if (!mounted) return;
    if (!allowed) {
      Navigator.of(context).pop();
      context.push(AppRoutes.paywall);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _picks = null;
    });

    try {
      final collection = await AppDatabase.getCollection();
      if (collection.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Your collection is empty. Scan a few records first.';
        });
        return;
      }
      final lookup = {for (final r in collection) r['id'] as String: r};
      final compact = collection
          .map((r) => {
                'id': r['id'],
                'title': r['title'],
                'artist': r['artist'],
                'year': r['year'],
                'genre': r['genre'],
              })
          .toList();

      final picks = await ClaudeApi.instance.pickForMood(
        query: query,
        collection: compact,
      );
      await AiAccess.recordMoodUse();

      final resolved = picks
          .map((p) {
            final rec = lookup[p.id];
            if (rec == null) return null;
            return _PickWithRecord(record: rec, reason: p.reason);
          })
          .whereType<_PickWithRecord>()
          .toList();

      if (!mounted) return;
      setState(() {
        _picks = resolved;
        _loading = false;
        if (resolved.isEmpty) {
          _error = 'No matches in your collection.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not fetch picks: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: SpinnerTheme.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(bottom: viewInsets),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: SpinnerTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.mood, color: SpinnerTheme.accent, size: 20),
                    const SizedBox(width: 8),
                    Text('Ask Spinner',
                        style: SpinnerTheme.nunito(
                            size: 18,
                            weight: FontWeight.w800,
                            color: SpinnerTheme.white)),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, color: SpinnerTheme.grey),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _ask(),
                  style: SpinnerTheme.nunito(size: 15, color: SpinnerTheme.white),
                  cursorColor: SpinnerTheme.accent,
                  decoration: InputDecoration(
                    hintText: 'e.g. "jazz for a rainy evening"',
                    hintStyle: SpinnerTheme.nunito(
                        size: 14, color: SpinnerTheme.grey.withOpacity(0.7)),
                    filled: true,
                    fillColor: SpinnerTheme.surface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: SpinnerTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: SpinnerTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: SpinnerTheme.accent, width: 1.5),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.send, color: SpinnerTheme.accent),
                      onPressed: _ask,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => InkWell(
                    onTap: () {
                      _controller.text = _suggestions[i];
                      _ask(_suggestions[i]);
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: SpinnerTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: SpinnerTheme.border),
                      ),
                      child: Text(_suggestions[i],
                          style: SpinnerTheme.nunito(
                              size: 12,
                              weight: FontWeight.w500,
                              color: SpinnerTheme.greyLight)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding:
                      const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    if (_loading) _buildLoading(),
                    if (_error != null) _buildError(_error!),
                    if (_picks != null && _picks!.isNotEmpty) ..._picks!
                        .map((p) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _PickCard(pick: p),
                            )),
                    if (!_loading && _picks == null && _error == null)
                      _buildEmptyHint(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: SpinnerTheme.accent),
          ),
          const SizedBox(width: 12),
          Text('Picking from your shelf…',
              style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.grey)),
        ],
      ),
    );
  }

  Widget _buildError(String msg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SpinnerTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: Text(msg,
          style: SpinnerTheme.nunito(
              size: 13, color: SpinnerTheme.greyLight, height: 1.4)),
    );
  }

  Widget _buildEmptyHint() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Center(
        child: Text(
          'Describe a moment, mood, or activity.\nClaude picks from YOUR shelf.',
          textAlign: TextAlign.center,
          style: SpinnerTheme.nunito(
              size: 13, color: SpinnerTheme.grey, height: 1.5),
        ),
      ),
    );
  }
}

class _PickWithRecord {
  final Map<String, dynamic> record;
  final String reason;
  const _PickWithRecord({required this.record, required this.reason});
}

class _PickCard extends StatelessWidget {
  final _PickWithRecord pick;
  const _PickCard({required this.pick});

  @override
  Widget build(BuildContext context) {
    final r = pick.record;
    final cover = r['cover_url'] as String? ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Navigator.of(context).pop();
        context.push(AppRoutes.recordPath(r['id'] as String));
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SpinnerTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SpinnerTheme.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 64,
                height: 64,
                child: cover.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: cover,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: SpinnerTheme.card,
                          child: Icon(Icons.album,
                              color: SpinnerTheme.grey, size: 24),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: SpinnerTheme.card,
                          child: Icon(Icons.album,
                              color: SpinnerTheme.grey, size: 24),
                        ),
                      )
                    : Container(
                        color: SpinnerTheme.card,
                        child: Icon(Icons.album,
                            color: SpinnerTheme.grey, size: 24),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (r['title'] as String?) ?? 'Unknown',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SpinnerTheme.nunito(
                        size: 14,
                        weight: FontWeight.w700,
                        color: SpinnerTheme.white),
                  ),
                  Text(
                    (r['artist'] as String?) ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SpinnerTheme.nunito(
                        size: 12, color: SpinnerTheme.grey),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    pick.reason,
                    maxLines: 4,
                    style: SpinnerTheme.nunito(
                        size: 12,
                        color: SpinnerTheme.greyLight,
                        height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
