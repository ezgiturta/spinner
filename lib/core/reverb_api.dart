import 'dart:async';

import 'package:dio/dio.dart';

/// Reverb Marketplace API client.
///
/// Auth: Personal Access Token (one bearer token, no OAuth dance).
/// Docs: https://www.reverb-api.com/docs/listings (or check current docs)
///
/// Setup:
/// 1. Create a Reverb account at https://reverb.com (US-based marketplace,
///    but ships globally).
/// 2. Go to https://reverb.com/my/api_settings and generate a Personal API
///    Token.
/// 3. Add it to Codemagic env as REVERB_TOKEN and pass at build time:
///    --dart-define=REVERB_TOKEN=$REVERB_TOKEN
///
/// When the token is unset, [isConfigured] returns false and search short
/// circuits with an empty result so the UI can fall back to a deep link.
class ReverbApi {
  static const String _token =
      String.fromEnvironment('REVERB_TOKEN', defaultValue: '');

  static const String _baseUrl = 'https://api.reverb.com/api';

  static final ReverbApi _instance = ReverbApi._();
  factory ReverbApi() => _instance;
  ReverbApi._() : _dio = Dio();

  final Dio _dio;

  static bool get isConfigured => _token.isNotEmpty;

  /// Search Reverb vinyl listings, cheapest first.
  /// Returns at most [limit] items. Empty list on failure or missing token.
  Future<List<ReverbListing>> searchVinyl(String query, {int limit = 3}) async {
    if (!isConfigured) return const [];
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '$_baseUrl/listings',
        queryParameters: {
          'query': query,
          'per_page': limit.toString(),
          // Reverb categorizes vinyl under accessories. Sort by price.
          'product_type': 'accessories',
          'sort_by': 'price',
          'sort_order': 'asc',
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $_token',
            'Accept': 'application/hal+json',
            'Accept-Version': '3.0',
          },
        ),
      );
      final listings = (resp.data?['listings'] as List?) ?? const [];
      return listings
          .cast<Map<String, dynamic>>()
          .map(ReverbListing.fromJson)
          .where((l) => l.price != null)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}

class ReverbListing {
  final String title;
  final double? price;
  final String currency;
  final String? condition;
  final String? imageUrl;
  final String? webUrl;

  const ReverbListing({
    required this.title,
    required this.price,
    required this.currency,
    required this.condition,
    required this.imageUrl,
    required this.webUrl,
  });

  factory ReverbListing.fromJson(Map<String, dynamic> json) {
    final price = json['price'] as Map<String, dynamic>?;
    final condition = json['condition'] as Map<String, dynamic>?;
    final photos = json['photos'] as List?;
    final links = json['_links'] as Map<String, dynamic>?;
    final web = links?['web'] as Map<String, dynamic>?;
    return ReverbListing(
      title: (json['title'] as String?) ?? '',
      price: price == null
          ? null
          : double.tryParse((price['amount'] as String?) ?? ''),
      currency: (price?['currency'] as String?) ?? 'USD',
      condition: condition?['display_name'] as String?,
      imageUrl: (photos?.isNotEmpty ?? false)
          ? ((photos!.first as Map<String, dynamic>?)?['_links']
                  as Map<String, dynamic>?)?['large_crop']
              ?['href'] as String?
          : null,
      webUrl: web?['href'] as String?,
    );
  }
}
