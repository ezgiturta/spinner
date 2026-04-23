import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A bottom sheet that displays multiple Discogs search results for the user
/// to pick from. Returns the selected result map via [Navigator.pop].
class SearchResultsSheet extends StatelessWidget {
  final List<Map<String, dynamic>> results;

  const SearchResultsSheet({super.key, required this.results});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.75),
      decoration: BoxDecoration(
        color: SpinnerTheme.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: SpinnerTheme.border),
          left: BorderSide(color: SpinnerTheme.border),
          right: BorderSide(color: SpinnerTheme.border),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHandle(),
          _buildHeader(),
          const Divider(height: 1),
          Flexible(child: _buildResultsList(context)),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: SpinnerTheme.grey.withOpacity(0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Text(
            'Select a release',
            style: SpinnerTheme.nunito(
              size: 18,
              weight: FontWeight.w700,
              color: SpinnerTheme.white,
            ),
          ),
          const Spacer(),
          Text(
            '${results.length} results',
            style: SpinnerTheme.nunito(
              size: 13,
              weight: FontWeight.w400,
              color: SpinnerTheme.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: results.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: 80,
        color: SpinnerTheme.border.withOpacity(0.5),
      ),
      itemBuilder: (context, index) {
        final result = results[index];
        return _ResultTile(
          result: result,
          onTap: () => Navigator.of(context).pop(result),
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  final Map<String, dynamic> result;
  final VoidCallback onTap;

  const _ResultTile({required this.result, required this.onTap});

  String get _title => result['title'] as String? ?? 'Unknown Title';
  String get _artist => result['artist'] as String? ?? 'Unknown Artist';
  String get _year {
    final y = result['year'];
    return y != null ? y.toString() : '';
  }

  String get _format => result['format'] as String? ?? '';
  String get _thumbUrl =>
      result['thumb'] as String? ?? result['cover_image'] as String? ?? '';

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: SpinnerTheme.accent.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 56,
                height: 56,
                child: _thumbUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: _thumbUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _placeholderBox(),
                        errorWidget: (_, __, ___) => _placeholderBox(),
                      )
                    : _placeholderBox(),
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: SpinnerTheme.nunito(
                      size: 15,
                      weight: FontWeight.w600,
                      color: SpinnerTheme.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _artist,
                    style: SpinnerTheme.nunito(
                      size: 13,
                      weight: FontWeight.w400,
                      color: SpinnerTheme.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_year.isNotEmpty || _format.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (_year.isNotEmpty)
                          _metadataBadge(_year),
                        if (_year.isNotEmpty && _format.isNotEmpty)
                          const SizedBox(width: 6),
                        if (_format.isNotEmpty)
                          Flexible(child: _metadataBadge(_format)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: SpinnerTheme.grey.withOpacity(0.5),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderBox() {
    return Container(
      color: SpinnerTheme.surface,
      child: Center(
        child: Icon(Icons.album, size: 24, color: SpinnerTheme.grey),
      ),
    );
  }

  Widget _metadataBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: SpinnerTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: SpinnerTheme.border.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: SpinnerTheme.nunito(
          size: 11,
          weight: FontWeight.w500,
          color: SpinnerTheme.grey,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
