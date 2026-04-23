import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';

/// A reusable dark-themed card displaying a vinyl record's cover art,
/// title, artist, and optional metadata (price, last spun, condition).
class RecordCard extends StatelessWidget {
  final String coverUrl;
  final String title;
  final String artist;
  final double? price;
  final String? lastSpun;
  final String? condition;
  final VoidCallback? onTap;

  const RecordCard({
    super.key,
    required this.coverUrl,
    required this.title,
    required this.artist,
    this.price,
    this.lastSpun,
    this.condition,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: SpinnerTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SpinnerTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover art
            AspectRatio(
              aspectRatio: 1,
              child: _buildCoverArt(),
            ),

            // Metadata
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
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
                    const SizedBox(height: 2),

                    // Artist
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

                    const Spacer(),

                    // Bottom row: price / last spun / condition
                    _buildBottomRow(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverArt() {
    if (coverUrl.isEmpty) {
      return Container(
        color: SpinnerTheme.surface,
        child: Center(
          child: Icon(Icons.album, color: SpinnerTheme.grey, size: 40),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: coverUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: SpinnerTheme.surface,
        child: Center(
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
        child: Center(
          child: Icon(Icons.broken_image, color: SpinnerTheme.grey, size: 32),
        ),
      ),
    );
  }

  Widget _buildBottomRow() {
    final hasPrice = price != null;
    final hasLastSpun = lastSpun != null && lastSpun!.isNotEmpty;
    final hasCondition = condition != null && condition!.isNotEmpty;

    if (!hasPrice && !hasLastSpun && !hasCondition) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        if (hasPrice)
          Text(
            '\$${price!.toStringAsFixed(2)}',
            style: SpinnerTheme.nunito(
              size: 13,
              weight: FontWeight.w700,
              color: SpinnerTheme.green,
            ),
          ),
        if (hasPrice && (hasLastSpun || hasCondition)) const Spacer(),
        if (hasLastSpun && !hasCondition)
          Flexible(
            child: Text(
              lastSpun!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SpinnerTheme.nunito(
                size: 11,
                weight: FontWeight.w500,
                color: SpinnerTheme.grey,
              ),
            ),
          ),
        if (hasCondition) _buildConditionBadge(condition!),
      ],
    );
  }

  Widget _buildConditionBadge(String cond) {
    final badgeColor = _conditionColor(cond);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        cond,
        style: SpinnerTheme.nunito(
          size: 11,
          weight: FontWeight.w700,
          color: badgeColor,
        ),
      ),
    );
  }

  Color _conditionColor(String condition) {
    switch (condition.toUpperCase()) {
      case 'M':
      case 'MINT':
        return SpinnerTheme.green;
      case 'NM':
      case 'NEAR MINT':
        return SpinnerTheme.green;
      case 'VG+':
      case 'VG':
        return SpinnerTheme.amber;
      case 'G+':
      case 'G':
        return SpinnerTheme.amber;
      case 'F':
      case 'FAIR':
      case 'P':
      case 'POOR':
        return SpinnerTheme.red;
      default:
        return SpinnerTheme.grey;
    }
  }
}
