import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/database.dart';
import '../../core/itunes_api.dart';
import '../../core/theme.dart';

class WantlistScreen extends StatefulWidget {
  const WantlistScreen({super.key});

  @override
  State<WantlistScreen> createState() => _WantlistScreenState();
}

class _WantlistScreenState extends State<WantlistScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  List<Map<String, dynamic>>? _items;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWantlist();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
  }

  List<Map<String, dynamic>> get _filteredItems {
    final items = _items;
    if (items == null) return [];
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return items;
    return items.where((item) {
      final title = (item['title'] as String?)?.toLowerCase() ?? '';
      final artist = (item['artist'] as String?)?.toLowerCase() ?? '';
      return title.contains(query) || artist.contains(query);
    }).toList();
  }

  Future<void> _loadWantlist() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await AppDatabase.getWantlist();
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _removeItem(Map<String, dynamic> item) async {
    final items = _items;
    if (items == null) return;
    final removed = items.indexOf(item);
    if (removed < 0) return;

    setState(() {
      items.removeAt(removed);
    });

    try {
      final id = item['id'] as String;
      await AppDatabase.updateRecord(id, {'in_wantlist': 0});
    } catch (e) {
      if (!mounted) return;
      // Revert on failure
      setState(() {
        items.insert(removed, item);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to remove item: $e'),
          backgroundColor: SpinnerTheme.red,
        ),
      );
    }
  }

  void _showPriceAlertDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => _PriceAlertDialog(
        item: item,
        onSave: (price) async {
          try {
            final id = item['id'] as String;
            await AppDatabase.updateRecord(id, {'alert_price': price});
            if (!mounted) return;
            _loadWantlist();
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to set alert: $e'),
                backgroundColor: SpinnerTheme.red,
              ),
            );
          }
        },
      ),
    );
  }

  void _showAddToWantlistDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _AddToWantlistDialog(
        onAdded: () {
          _loadWantlist();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      appBar: AppBar(
        backgroundColor: SpinnerTheme.bg,
        elevation: 0,
        title: Text(
          'Wantlist',
          style: SpinnerTheme.nunito(
            size: 22,
            weight: FontWeight.w700,
            color: SpinnerTheme.white,
          ),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddToWantlistDialog,
        backgroundColor: SpinnerTheme.accent,
        foregroundColor: SpinnerTheme.white,
        icon: const Icon(Icons.add),
        label: Text(
          'Add to Wantlist',
          style: SpinnerTheme.nunito(
            size: 14,
            weight: FontWeight.w600,
            color: SpinnerTheme.white,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.white),
        decoration: InputDecoration(
          hintText: 'Search by title or artist...',
          hintStyle: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.grey),
          prefixIcon: Icon(Icons.search, color: SpinnerTheme.grey, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: SpinnerTheme.grey, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _searchFocusNode.unfocus();
                  },
                )
              : null,
          filled: true,
          fillColor: SpinnerTheme.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
            borderSide: BorderSide(color: SpinnerTheme.accent, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: SpinnerTheme.accent),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    final items = _filteredItems;
    if (_items == null || _items!.isEmpty) {
      return _buildEmptyState();
    }

    if (items.isEmpty) {
      return Center(
        child: Text(
          'No results found',
          style: SpinnerTheme.nunito(
            size: 15,
            weight: FontWeight.w500,
            color: SpinnerTheme.grey,
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: SpinnerTheme.accent,
      backgroundColor: SpinnerTheme.surface,
      onRefresh: _loadWantlist,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return _buildDismissibleItem(item);
        },
      ),
    );
  }

  Widget _buildDismissibleItem(Map<String, dynamic> item) {
    final id = item['id'] as String;
    final title = item['title'] as String? ?? 'Unknown Title';
    final artist = item['artist'] as String? ?? 'Unknown Artist';

    return Dismissible(
      key: ValueKey(id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: SpinnerTheme.red.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: SpinnerTheme.red, size: 24),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: SpinnerTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text(
              'Remove from wantlist?',
              style: SpinnerTheme.nunito(
                size: 16,
                weight: FontWeight.w600,
                color: SpinnerTheme.white,
              ),
            ),
            content: Text(
              'Remove "$title" by $artist?',
              style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.greyLight),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  'Cancel',
                  style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.grey),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  'Remove',
                  style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.red),
                ),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => _removeItem(item),
      child: _buildItemCard(item),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final priceFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    final id = item['id'] as String?;
    final title = item['title'] as String? ?? 'Unknown Title';
    final artist = item['artist'] as String? ?? 'Unknown Artist';
    final coverUrl = item['cover_url'] as String?;
    final medianValue = (item['median_value'] as num?)?.toDouble();
    final alertPrice = (item['alert_price'] as num?)?.toDouble();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: InkWell(
        onTap: () {
          if (id != null) context.push('/record/$id');
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Cover art
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: coverUrl != null && coverUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: coverUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: SpinnerTheme.surface,
                            child: Icon(Icons.album, color: SpinnerTheme.grey, size: 32),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: SpinnerTheme.surface,
                            child: Icon(Icons.album, color: SpinnerTheme.grey, size: 32),
                          ),
                        )
                      : Container(
                          color: SpinnerTheme.surface,
                          child: Icon(Icons.album, color: SpinnerTheme.grey, size: 32),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Title, artist, prices
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: SpinnerTheme.nunito(
                        size: 15,
                        weight: FontWeight.w600,
                        color: SpinnerTheme.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      artist,
                      style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.greyLight),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          medianValue != null
                              ? priceFmt.format(medianValue)
                              : '--',
                          style: SpinnerTheme.nunito(
                            size: 14,
                            weight: FontWeight.w700,
                            color: SpinnerTheme.white,
                          ),
                        ),
                        if (alertPrice != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: SpinnerTheme.amber.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.notifications_active,
                                    size: 12, color: SpinnerTheme.amber),
                                const SizedBox(width: 3),
                                Text(
                                  priceFmt.format(alertPrice),
                                  style: SpinnerTheme.nunito(
                                    size: 11,
                                    weight: FontWeight.w600,
                                    color: SpinnerTheme.amber,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Set Alert button
              SizedBox(
                width: 72,
                child: OutlinedButton(
                  onPressed: () => _showPriceAlertDialog(item),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SpinnerTheme.accent,
                    side: BorderSide(color: SpinnerTheme.accent),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    alertPrice != null ? 'Edit' : 'Set Alert',
                    style: SpinnerTheme.nunito(
                      size: 11,
                      weight: FontWeight.w600,
                      color: SpinnerTheme.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.playlist_add, size: 64, color: SpinnerTheme.grey),
            const SizedBox(height: 16),
            Text(
              'Your wantlist is empty.\nTap the button below to add records!',
              textAlign: TextAlign.center,
              style: SpinnerTheme.nunito(
                size: 16,
                weight: FontWeight.w600,
                color: SpinnerTheme.greyLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: SpinnerTheme.red),
            const SizedBox(height: 12),
            Text(
              'Failed to load wantlist.',
              style: SpinnerTheme.nunito(
                size: 15,
                weight: FontWeight.w600,
                color: SpinnerTheme.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _error ?? 'Unknown error',
              style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadWantlist,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: SpinnerTheme.accent,
                foregroundColor: SpinnerTheme.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add to Wantlist dialog — searches Discogs without auth
// ---------------------------------------------------------------------------

class _AddToWantlistDialog extends StatefulWidget {
  final VoidCallback onAdded;

  const _AddToWantlistDialog({required this.onAdded});

  @override
  State<_AddToWantlistDialog> createState() => _AddToWantlistDialogState();
}

class _AddToWantlistDialogState extends State<_AddToWantlistDialog> {
  final _queryController = TextEditingController();

  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  String? _searchError;
  bool _isAdding = false;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchError = null;
      _results = [];
    });

    try {
      final results = await ItunesApi.searchAlbums(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = 'Search failed. Please try again.';
        _isSearching = false;
      });
    }
  }

  Future<void> _addToWantlist(Map<String, dynamic> result) async {
    if (_isAdding) return;
    setState(() => _isAdding = true);

    try {
      final albumTitle = result['title'] as String? ?? 'Unknown';
      final artist = result['artist'] as String? ?? 'Unknown Artist';
      final coverUrl = result['cover_url'] as String? ?? '';
      final year = int.tryParse(result['year']?.toString() ?? '');

      final id = const Uuid().v4();
      await AppDatabase.insertRecord({
        'id': id,
        'title': albumTitle,
        'artist': artist,
        'year': year,
        'cover_url': coverUrl,
        'in_collection': 0,
        'in_wantlist': 1,
        'synced_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      widget.onAdded();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAdding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add: $e'),
          backgroundColor: SpinnerTheme.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: SpinnerTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text(
              'Add to Wantlist',
              style: SpinnerTheme.nunito(
                size: 18,
                weight: FontWeight.w700,
                color: SpinnerTheme.white,
              ),
            ),
          ),
          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    autofocus: true,
                    style: SpinnerTheme.nunito(
                        size: 14, color: SpinnerTheme.white),
                    decoration: InputDecoration(
                      hintText: 'Search album name...',
                      hintStyle: SpinnerTheme.nunito(
                          size: 14, color: SpinnerTheme.grey),
                      prefixIcon: Icon(Icons.search,
                          color: SpinnerTheme.grey, size: 20),
                      filled: true,
                      fillColor: SpinnerTheme.bg,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
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
                        borderSide: BorderSide(
                            color: SpinnerTheme.accent, width: 1.5),
                      ),
                    ),
                    onSubmitted: (_) => _search(),
                    textInputAction: TextInputAction.search,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isSearching ? null : _search,
                  icon: Icon(Icons.search, color: SpinnerTheme.accent),
                  style: IconButton.styleFrom(
                    backgroundColor: SpinnerTheme.accent.withOpacity(0.15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Results
          Flexible(
            child: _buildResults(),
          ),
          // Close button
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Close',
                style: SpinnerTheme.nunito(
                    size: 14, color: SpinnerTheme.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_isSearching) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: CircularProgressIndicator(color: SpinnerTheme.accent),
      );
    }

    if (_searchError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _searchError!,
          style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.red),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Search for an album to add to your wantlist',
          style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        final title = result['title'] as String? ?? 'Unknown';
        final artist = result['artist'] as String? ?? '';
        final coverUrl = result['cover_url'] as String? ?? '';
        final year = result['year']?.toString() ?? '';
        final genre = result['genre'] as String? ?? '';

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: SpinnerTheme.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: SpinnerTheme.border),
          ),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 48,
                height: 48,
                child: coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: SpinnerTheme.surface,
                          child: Icon(Icons.album,
                              color: SpinnerTheme.grey, size: 24),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: SpinnerTheme.surface,
                          child: Icon(Icons.album,
                              color: SpinnerTheme.grey, size: 24),
                        ),
                      )
                    : Container(
                        color: SpinnerTheme.surface,
                        child: Icon(Icons.album,
                            color: SpinnerTheme.grey, size: 24),
                      ),
              ),
            ),
            title: Text(
              title,
              style: SpinnerTheme.nunito(
                size: 14,
                weight: FontWeight.w600,
                color: SpinnerTheme.white,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [if (artist.isNotEmpty) artist, if (year.isNotEmpty) year, if (genre.isNotEmpty) genre]
                  .join(' \u2022 '),
              style:
                  SpinnerTheme.nunito(size: 12, color: SpinnerTheme.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _isAdding
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: SpinnerTheme.accent,
                    ),
                  )
                : Icon(Icons.add_circle_outline,
                    color: SpinnerTheme.accent, size: 24),
            onTap: _isAdding ? null : () => _addToWantlist(result),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Price alert dialog
// ---------------------------------------------------------------------------

class _PriceAlertDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  final ValueChanged<double> onSave;

  const _PriceAlertDialog({required this.item, required this.onSave});

  @override
  State<_PriceAlertDialog> createState() => _PriceAlertDialogState();
}

class _PriceAlertDialogState extends State<_PriceAlertDialog> {
  late final TextEditingController _priceController;
  late double _sliderValue;
  final _formKey = GlobalKey<FormState>();

  static const double _minPrice = 1.0;
  static const double _maxPrice = 500.0;

  @override
  void initState() {
    super.initState();
    final alertPrice = (widget.item['alert_price'] as num?)?.toDouble();
    final medianValue = (widget.item['median_value'] as num?)?.toDouble();
    final initial = alertPrice ?? medianValue ?? 25.0;
    _sliderValue = initial.clamp(_minPrice, _maxPrice);
    _priceController = TextEditingController(text: _sliderValue.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  void _onSliderChanged(double value) {
    setState(() {
      _sliderValue = value;
      _priceController.text = value.toStringAsFixed(2);
    });
  }

  void _onTextChanged(String text) {
    final parsed = double.tryParse(text);
    if (parsed != null && parsed >= _minPrice && parsed <= _maxPrice) {
      setState(() {
        _sliderValue = parsed;
      });
    }
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;
    final price = double.tryParse(_priceController.text);
    if (price == null) return;
    widget.onSave(price);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final priceFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final title = widget.item['title'] as String? ?? 'Unknown Title';
    final artist = widget.item['artist'] as String? ?? 'Unknown Artist';
    final medianValue = (widget.item['median_value'] as num?)?.toDouble();

    return AlertDialog(
      backgroundColor: SpinnerTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Set Price Alert',
        style: SpinnerTheme.nunito(
          size: 18,
          weight: FontWeight.w700,
          color: SpinnerTheme.white,
        ),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title by $artist',
              style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.greyLight),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (medianValue != null) ...[
              const SizedBox(height: 8),
              Text(
                'Current price: ${priceFmt.format(medianValue)}',
                style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.grey),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Alert me when price drops to:',
              style: SpinnerTheme.nunito(
                size: 14,
                weight: FontWeight.w500,
                color: SpinnerTheme.white,
              ),
            ),
            const SizedBox(height: 12),
            // Slider
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: SpinnerTheme.accent,
                inactiveTrackColor: SpinnerTheme.border,
                thumbColor: SpinnerTheme.accent,
                overlayColor: SpinnerTheme.accent.withOpacity(0.15),
                trackHeight: 4,
              ),
              child: Slider(
                value: _sliderValue,
                min: _minPrice,
                max: _maxPrice,
                divisions: ((_maxPrice - _minPrice) * 2).toInt(),
                onChanged: _onSliderChanged,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  priceFmt.format(_minPrice),
                  style: SpinnerTheme.nunito(size: 11, color: SpinnerTheme.grey),
                ),
                Text(
                  priceFmt.format(_maxPrice),
                  style: SpinnerTheme.nunito(size: 11, color: SpinnerTheme.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Text field
            TextFormField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: SpinnerTheme.nunito(
                size: 18,
                weight: FontWeight.w700,
                color: SpinnerTheme.white,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                prefixText: '\$ ',
                prefixStyle: SpinnerTheme.nunito(
                  size: 18,
                  weight: FontWeight.w700,
                  color: SpinnerTheme.accent,
                ),
                filled: true,
                fillColor: SpinnerTheme.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: SpinnerTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: SpinnerTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: SpinnerTheme.accent, width: 1.5),
                ),
              ),
              onChanged: _onTextChanged,
              validator: (value) {
                if (value == null || value.isEmpty) return 'Enter a price';
                final parsed = double.tryParse(value);
                if (parsed == null) return 'Invalid number';
                if (parsed < _minPrice) return 'Min is ${priceFmt.format(_minPrice)}';
                if (parsed > _maxPrice) return 'Max is ${priceFmt.format(_maxPrice)}';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.grey),
          ),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: SpinnerTheme.accent,
            foregroundColor: SpinnerTheme.white,
          ),
          child: Text(
            'Save Alert',
            style: SpinnerTheme.nunito(
              size: 14,
              weight: FontWeight.w600,
              color: SpinnerTheme.white,
            ),
          ),
        ),
      ],
    );
  }
}
