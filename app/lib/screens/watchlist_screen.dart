import 'package:flutter/material.dart';
import '../models/media_models.dart';
import '../models/storage_models.dart';
import '../services/storage_service.dart';
import 'detail_screen.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  static const _scaffoldBg = Color(0xFF0F0F0F);
  static const _cardBg = Color(0xFF1E1E1E);
  static const _accentRed = Color(0xFFE50914);

  List<WatchlistItem> _items = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
    StorageService.instance.addListener(_onStorageChanged);
  }

  void _onStorageChanged() {
    if (mounted) _loadItems();
  }

  @override
  void dispose() {
    StorageService.instance.removeListener(_onStorageChanged);
    super.dispose();
  }

  void _loadItems() {
    setState(() {
      _items = StorageService.instance.getWatchlist();
    });
  }

  Future<void> _refresh() async {
    _loadItems();
  }

  void _removeItem(String id) {
    setState(() {
      _items.removeWhere((e) => e.id == id);
    });
    StorageService.instance.removeWatchlist(id); // no await
  }

  void _openDetail(WatchlistItem item) {
    final mediaItem = MediaItem(
      id: item.id,
      title: item.title,
      poster: item.poster,
      year: item.year,
      rating: item.rating,
      type: item.type,
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailScreen(item: mediaItem)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _scaffoldBg,
      appBar: AppBar(
        backgroundColor: _scaffoldBg,
        title: const Text(
          'My List',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        color: _accentRed,
        onRefresh: _refresh,
        child: _items.isEmpty ? _buildEmptyState() : _buildGrid(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bookmark_border, size: 64, color: Colors.white30),
                SizedBox(height: 16),
                Text(
                  'Your list is empty\nAdd movies and shows to watch later!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  int _getResponsiveColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 480) return 2;
    if (width < 720) return 3;
    if (width < 1000) return 4;
    if (width < 1300) return 5;
    if (width < 1600) return 6;
    return 7;
  }

  Widget _buildGrid() {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildGridCard(_items[index]),
              childCount: _items.length,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _getResponsiveColumns(context),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.65,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGridCard(WatchlistItem item) {
    return Dismissible(
      key: Key('wl_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: _accentRed,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.bookmark_remove, color: Colors.white),
      ),
      onDismissed: (_) => _removeItem(item.id),
      child: GestureDetector(
        onTap: () => _openDetail(item),
        child: Container(
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Poster image
              item.poster != null
                  ? Image.network(
                      item.poster!,
                      fit: BoxFit.cover,
                      cacheWidth: 400,
                      errorBuilder: (context, error, stackTrace) => _posterFallback(),
                    )
                  : _posterFallback(),
              // Gradient overlay at the bottom
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.year != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.year!,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Type badge (top-left)
              if (item.type != null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: _accentRed,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.type == 1 ? 'MOVIE' : 'SERIES',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
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

  Widget _posterFallback() {
    return Container(
      color: Colors.grey[800],
      child: const Center(
        child: Icon(Icons.movie, color: Colors.white38, size: 40),
      ),
    );
  }
}
