import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// eBay Browse API client.
///
/// Auth: OAuth 2.0 client credentials flow (app-level, no user login).
/// Docs: https://developer.ebay.com/api-docs/buy/browse/overview.html
///
/// Setup:
/// 1. Register an application at https://developer.ebay.com
/// 2. Switch to Production keyset, copy the App ID (Client ID) and Cert ID
///    (Client Secret) into Codemagic env vars EBAY_CLIENT_ID and
///    EBAY_CLIENT_SECRET.
/// 3. Pass them at build time:
///    --dart-define=EBAY_CLIENT_ID=$EBAY_CLIENT_ID
///    --dart-define=EBAY_CLIENT_SECRET=$EBAY_CLIENT_SECRET
///
/// When the keys are unset, [isConfigured] returns false and search short
/// circuits with an empty result so the UI can fall back to a deep link.
class EbayApi {
  static const String _clientId =
      String.fromEnvironment('EBAY_CLIENT_ID', defaultValue: '');
  static const String _clientSecret =
      String.fromEnvironment('EBAY_CLIENT_SECRET', defaultValue: '');

  static const String _tokenUrl =
      'https://api.ebay.com/identity/v1/oauth2/token';
  static const String _searchUrl =
      'https://api.ebay.com/buy/browse/v1/item_summary/search';
  static const String _scope = 'https://api.ebay.com/oauth/api_scope';

  static final EbayApi _instance = EbayApi._();
  factory EbayApi() => _instance;
  EbayApi._() : _dio = Dio();

  final Dio _dio;
  String? _accessToken;
  DateTime? _tokenExpiresAt;

  static bool get isConfigured =>
      _clientId.isNotEmpty && _clientSecret.isNotEmpty;

  Future<String?> _getToken() async {
    if (!isConfigured) return null;
    final now = DateTime.now();
    if (_accessToken != null &&
        _tokenExpiresAt != null &&
        now.isBefore(_tokenExpiresAt!.subtract(const Duration(minutes: 1)))) {
      return _accessToken;
    }
    final basic = base64Encode(utf8.encode('$_clientId:$_clientSecret'));
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        _tokenUrl,
        data: 'grant_type=client_credentials&scope=$_scope',
        options: Options(
          headers: {
            'Authorization': 'Basic $basic',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
      );
      final data = resp.data;
      if (data == null) return null;
      _accessToken = data['access_token'] as String?;
      final ttl = (data['expires_in'] as num?)?.toInt() ?? 7200;
      _tokenExpiresAt = now.add(Duration(seconds: ttl));
      return _accessToken;
    } catch (_) {
      return null;
    }
  }

  /// Search eBay listings, cheapest first (price + shipping ascending).
  /// Returns at most [limit] items. Empty list on failure or missing keys.
  Future<List<EbayListing>> searchVinyl(String query, {int limit = 3}) async {
    final token = await _getToken();
    if (token == null) return const [];
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        _searchUrl,
        queryParameters: {
          'q': query,
          'limit': limit.toString(),
          'sort': 'price',
          'filter': 'conditions:{USED|NEW},buyingOptions:{FIXED_PRICE}',
          'category_ids': '176985', // Music > Records
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'X-EBAY-C-MARKETPLACE-ID': 'EBAY_US',
          },
        ),
      );
      final summaries = (resp.data?['itemSummaries'] as List?) ?? const [];
      return summaries
          .cast<Map<String, dynamic>>()
          .map(EbayListing.fromJson)
          .where((l) => l.price != null)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}

class EbayListing {
  final String title;
  final double? price;
  final String currency;
  final String? condition;
  final String? imageUrl;
  final String? itemWebUrl;

  const EbayListing({
    required this.title,
    required this.price,
    required this.currency,
    required this.condition,
    required this.imageUrl,
    required this.itemWebUrl,
  });

  factory EbayListing.fromJson(Map<String, dynamic> json) {
    final price = json['price'] as Map<String, dynamic>?;
    return EbayListing(
      title: (json['title'] as String?) ?? '',
      price: price == null
          ? null
          : double.tryParse((price['value'] as String?) ?? ''),
      currency: (price?['currency'] as String?) ?? 'USD',
      condition: json['condition'] as String?,
      imageUrl: (json['image'] as Map<String, dynamic>?)?['imageUrl'] as String?,
      itemWebUrl: json['itemWebUrl'] as String?,
    );
  }
}
