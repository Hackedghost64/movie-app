import 'package:flutter/material.dart';
import '../models/media_models.dart';
import '../services/moviebox_api.dart';
import '../services/content_filter_service.dart';
import '../widgets/tv_focusable.dart';
import 'detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isSearching = false;
  List<MediaItem> _results = [];
  String _lastQuery = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _lastQuery = '';
      });
      return;
    }

    if (ContentFilterService.instance.isQueryNsfw(q)) {
      setState(() {
        _results = [];
        _isSearching = false;
        _lastQuery = q;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _lastQuery = q;
    });

    try {
      final res = await MovieBoxApi.instance.search(q);
      if (mounted) {
        setState(() {
          _results = res;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    }
  }

  int _getResponsiveColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) return 2;
    if (width < 840) return 3;
    if (width < 1100) return 4;
    if (width < 1400) return 5;
    if (width < 1800) return 6;
    return 7;
  }

  @override
  Widget build(BuildContext context) {
    final isNsfw = ContentFilterService.instance.isQueryNsfw(_lastQuery);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search Input Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: TextField(
                        controller: _controller,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        textInputAction: TextInputAction.search,
                        onSubmitted: _search,
                        decoration: InputDecoration(
                          hintText: 'Search movies, series, shows...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(Icons.search, color: Color(0xFFE50914)),
                          suffixIcon: _controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.white38),
                                  onPressed: () {
                                    _controller.clear();
                                    _search('');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TvFocusable(
                    borderRadius: 8,
                    scaleFactor: 1.05,
                    onTap: () => _search(_controller.text),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Search',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content Area
            Expanded(
              child: _isSearching
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFFE50914)),
                    )
                  : isNsfw
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.shield, color: Color(0xFFE50914), size: 54),
                                SizedBox(height: 14),
                                Text(
                                  'Search Restricted',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Adult and explicit searches are blocked by Family Safe filter.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white54, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _results.isNotEmpty
                          ? GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _getResponsiveColumns(context),
                                childAspectRatio: 0.65,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: _results.length,
                              itemBuilder: (ctx, i) {
                                final item = _results[i];
                                return TvFocusable(
                                  autofocus: i == 0,
                                  borderRadius: 8,
                                  scaleFactor: 1.07,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => DetailScreen(item: item)),
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      color: const Color(0xFF1E1E1E),
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: item.poster != null
                                                ? Image.network(
                                                    item.poster!,
                                                    fit: BoxFit.cover,
                                                    cacheWidth: 400,
                                                    errorBuilder: (_, _, _) => const Center(
                                                      child: Icon(Icons.movie, color: Colors.white24, size: 36),
                                                    ),
                                                  )
                                                : const Center(
                                                    child: Icon(Icons.movie, color: Colors.white24, size: 36),
                                                  ),
                                          ),
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
                                                  colors: [Colors.transparent, Colors.black87, Colors.black],
                                                ),
                                              ),
                                              child: Text(
                                                item.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search, size: 64, color: Colors.white.withValues(alpha: 0.2)),
                                  const SizedBox(height: 12),
                                  Text(
                                    _lastQuery.isNotEmpty
                                        ? 'No results found for "$_lastQuery"'
                                        : 'Search for movies, TV series, or shows',
                                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
