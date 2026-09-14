import 'package:flutter/material.dart';
import '../widgets/tv_focusable.dart';
import '../models/media_models.dart';
import '../models/storage_models.dart';
import '../services/moviebox_api.dart';
import '../services/storage_service.dart';
import '../services/content_filter_service.dart';
import 'continue_watching_screen.dart';
import 'detail_screen.dart';
import 'downloads_screen.dart';
import 'netflix_player_screen.dart';
import 'watchlist_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<MediaItem> _trending = [];
  List<MediaItem> _searchResults = [];
  bool _isLoadingTrending = true;
  bool _isSearching = false;

  List<WatchProgress> _continueWatching = [];
  List<WatchlistItem> _myList = [];

  String _selectedCategory = "All";
  final Map<String, List<MediaItem>> _categoryCache = {};
  static const List<String> _categories = [
    "All",
    "Movies",
    "TV Series",
    "Action",
    "Comedy",
    "Animation",
    "Sci-Fi",
    "Horror",
    "Drama",
    "Thriller",
    "Romance",
    "Crime",
    "Documentary",
  ];

  @override
  void initState() {
    super.initState();
    _loadTrending();
    StorageService.instance.addListener(_onStorageChanged);
    _onStorageChanged();
  }

  @override
  void dispose() {
    StorageService.instance.removeListener(_onStorageChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onStorageChanged() {
    if (!mounted) return;
    setState(() {
      _continueWatching = StorageService.instance.getAllWatchProgress();
      _myList = StorageService.instance.getWatchlist();
    });
  }

  Future<void> _loadTrending() async {
    setState(() => _isLoadingTrending = true);
    try {
      final items = await MovieBoxApi.instance.getTopRank();
      if (items.isEmpty) {
        // Fallback search to populate trending
        final fallback = await MovieBoxApi.instance.search("Avatar");
        _trending = fallback;
      } else {
        _trending = items;
      }
      _categoryCache["All"] = _trending;
    } catch (e) {
      debugPrint("Error loading trending: $e");
    } finally {
      if (mounted) setState(() => _isLoadingTrending = false);
    }
  }

  Future<void> _selectCategory(String category) async {
    if (_selectedCategory == category && !_isLoadingTrending) return;
    setState(() {
      _selectedCategory = category;
      _isLoadingTrending = true;
    });

    if (_categoryCache.containsKey(category)) {
      if (mounted) {
        setState(() {
          _trending = _categoryCache[category]!;
          _isLoadingTrending = false;
        });
      }
      return;
    }

    try {
      final items = await MovieBoxApi.instance.getByCategory(category);
      _categoryCache[category] = items;
      if (mounted) {
        setState(() {
          _trending = items;
        });
      }
    } catch (e) {
      debugPrint("Error loading category $category: $e");
    } finally {
      if (mounted) setState(() => _isLoadingTrending = false);
    }
  }

  Future<void> _performSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    if (ContentFilterService.instance.isQueryNsfw(q)) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await MovieBoxApi.instance.search(q);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Search failed: $e")),
        );
      }
    }
  }

  void _showSettingsDialog() {
    final api = MovieBoxApi.instance;
    bool gateway = api.useGateway;
    final urlController = TextEditingController(text: api.gatewayUrl);
    final keyController = TextEditingController(text: api.gatewayApiKey ?? "");

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.settings, color: Colors.amber),
                  SizedBox(width: 8),
                  Text("Connection Mode", style: TextStyle(color: Colors.white, fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Choose how this app communicates with MovieBox:",
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    // ignore: deprecated_member_use
                    RadioListTile<bool>(
                      value: false,
                      // ignore: deprecated_member_use
                      groupValue: gateway,
                      activeColor: const Color(0xFFE50914),
                      title: const Text("Direct Mode (Standalone)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text("Connects directly using embedded signatures. No computer or server needed.", style: TextStyle(color: Colors.white54, fontSize: 12)),
                      // ignore: deprecated_member_use
                      onChanged: (v) => setDialogState(() => gateway = v!),
                    ),
                    // ignore: deprecated_member_use
                    RadioListTile<bool>(
                      value: true,
                      // ignore: deprecated_member_use
                      groupValue: gateway,
                      activeColor: const Color(0xFFE50914),
                      title: const Text("Gateway Mode (Custom Server)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text("Routes calls through your local or remote MBX wrapper server.", style: TextStyle(color: Colors.white54, fontSize: 12)),
                      // ignore: deprecated_member_use
                      onChanged: (v) => setDialogState(() => gateway = v!),
                    ),
                    if (gateway) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: urlController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: "Gateway URL",
                          labelStyle: TextStyle(color: Colors.amber),
                          hintText: "http://10.0.2.2:8399",
                          hintStyle: TextStyle(color: Colors.white24),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: keyController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: "API Key (optional)",
                          labelStyle: TextStyle(color: Colors.amber),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: ContentFilterService.instance.isFilterEnabled,
                      // ignore: deprecated_member_use
                      activeColor: const Color(0xFFE50914),
                      title: const Row(
                        children: [
                          Icon(Icons.shield, color: Color(0xFFE50914), size: 18),
                          SizedBox(width: 8),
                          Text(
                            "Family Safe (NSFW Filter)",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      subtitle: const Text(
                        "Strictly blocks adult, 18+, and explicit titles across the app. Always ON by default for family safety.",
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      onChanged: (val) async {
                        await ContentFilterService.instance.setFilterEnabled(val);
                        setDialogState(() {});
                        _categoryCache.clear();
                        _loadTrending();
                      },
                    ),
                    // Credits section
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          const Divider(color: Colors.white24),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A0000),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE50914), width: 1),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.code, color: Color(0xFFE50914), size: 28),
                                SizedBox(height: 6),
                                Text(
                                  'Made by Hackedghost64',
                                  style: TextStyle(
                                    color: Color(0xFFE50914),
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'MBX Stream v1.0',
                                  style: TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                  onPressed: () async {
                    await api.saveSettings(
                      gateway: gateway,
                      url: urlController.text.trim(),
                      apiKey: keyController.text.trim().isNotEmpty ? keyController.text.trim() : null,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Switched to ${gateway ? 'Gateway' : 'Direct Standalone'} Mode")),
                    );
                    _loadTrending();
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text("MBX", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 14)),
            ),
            const SizedBox(width: 8),
            const Text("STREAM", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            tooltip: "Downloads",
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            tooltip: "Settings",
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Input
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              onChanged: (_) => setState(() {}),
              onSubmitted: _performSearch,
              decoration: InputDecoration(
                hintText: "Search movies, series, shows...",
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                prefixIcon: const Icon(Icons.search, color: Colors.amber),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white38),
                        onPressed: () {
                          _searchController.clear();
                          _performSearch("");
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
            ),
          ),

          // Content Area
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
                : ContentFilterService.instance.isQueryNsfw(_searchController.text.trim())
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield, color: Color(0xFFE50914), size: 54),
                              SizedBox(height: 14),
                              Text(
                                "Search Restricted",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                              SizedBox(height: 6),
                              Text(
                                "Adult and explicit searches are blocked by Family Safe filter.",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                : _searchResults.isNotEmpty
                    ? _buildSearchResults()
                    : _searchController.text.isNotEmpty
                        ? const Center(child: Text("No titles found.", style: TextStyle(color: Colors.white54)))
                        : _buildHomeFeed(),
          ),
        ],
      ),
    );
  }

  int _getResponsiveColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) return 3;
    if (width < 840) return 4;
    if (width < 1100) return 5;
    if (width < 1400) return 6;
    if (width < 1800) return 7;
    return 8;
  }

  Widget _buildSearchResults() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _getResponsiveColumns(context),
        childAspectRatio: 0.65,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (ctx, i) {
        final item = _searchResults[i];
        return _MediaCard(item: item);
      },
    );
  }

  Widget _buildHomeFeed() {
    return CustomScrollView(
      cacheExtent: 600,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Continue Watching carousel
                if (_continueWatching.isNotEmpty) ...[
                  _buildSectionHeader(
                    title: "Continue Watching",
                    onSeeAll: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ContinueWatchingScreen()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _continueWatching.length,
                      itemBuilder: (ctx, i) {
                        final progress = _continueWatching[i];
                        return _ContinueWatchingCard(
                          progress: progress,
                          autofocus: i == 0,
                          onTap: () {
                            if (progress.streamUrl != null) {
                              final stream = StreamOption(
                                url: progress.streamUrl!,
                                kind: progress.streamUrl!.contains('.m3u8')
                                    ? 'hls'
                                    : progress.streamUrl!.contains('.mpd')
                                        ? 'dash'
                                        : 'mp4',
                                resolution: 'Saved',
                                cookie: progress.streamCookie,
                                bypassedDecoy: true,
                              );
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => NetflixPlayerScreen(
                                    subjectId: progress.subjectId,
                                    title: progress.title,
                                    poster: progress.poster,
                                    season: progress.season,
                                    episode: progress.episode,
                                    episodeTitle: progress.episodeTitle,
                                    stream: stream,
                                    availableStreams: [stream],
                                    isSeries: progress.season > 0,
                                    initialPosition: Duration(milliseconds: progress.positionMs),
                                  ),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ContinueWatchingScreen()),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // My List carousel
                if (_myList.isNotEmpty) ...[
                  _buildSectionHeader(
                    title: "My List",
                    onSeeAll: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WatchlistScreen()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 185,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _myList.length,
                      itemBuilder: (ctx, i) {
                        final item = _myList[i];
                        return _WatchlistCard(
                          item: item,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => DetailScreen(item: item.toMediaItem())),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Categories Selector Bar
                const Text(
                  "Categories",
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final cat = _categories[i];
                      return _CategoryChip(
                        label: cat,
                        isSelected: _selectedCategory == cat,
                        autofocus: _continueWatching.isEmpty && i == 0,
                        onTap: () => _selectCategory(cat),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),

                // Feed Section Header
                Row(
                  children: [
                    Icon(
                      _selectedCategory == "All" ? Icons.local_fire_department : Icons.movie_filter,
                      color: const Color(0xFFE50914),
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _selectedCategory == "All" ? "Trending & Popular" : _selectedCategory,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),

        if (_isLoadingTrending)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),
            ),
          )
        else if (_trending.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.movie_filter_outlined, color: Colors.white24, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      "No trending titles found",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE50914),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _loadTrending,
                      icon: const Icon(Icons.refresh),
                      label: const Text("Retry"),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _getResponsiveColumns(context),
                childAspectRatio: 0.65,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _MediaCard(
                item: _trending[i],
                autofocus: i == 0 && _continueWatching.isEmpty,
              ),
                childCount: _trending.length,
              ),
            ),
          ),

        // Home footer Credits badge
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 20),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0000),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE50914)),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.code, color: Color(0xFFE50914), size: 20),
                    SizedBox(height: 4),
                    Text(
                      'Made by Hackedghost64',
                      style: TextStyle(
                        color: Color(0xFFE50914),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader({required String title, required VoidCallback onSeeAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        TextButton(
          onPressed: onSeeAll,
          child: const Text("See all", style: TextStyle(color: Color(0xFFE50914))),
        ),
      ],
    );
  }
}

// ─── TV Remote Focusable Wrapper ─────────────────────────────────────────────

class _TvFocusableCard extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final double borderRadius;
  final bool autofocus;

  const _TvFocusableCard({
    required this.child,
    required this.onTap,
    this.borderRadius = 8,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: onTap,
      borderRadius: borderRadius,
      autofocus: autofocus,
      scaleFactor: 1.08,
      child: child,
    );
  }
}

// ─── Category Chip with TV Focus ─────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool autofocus;

  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: onTap,
      borderRadius: 20,
      scaleFactor: 1.1,
      autofocus: autofocus,
      focusedBackgroundColor: const Color(0xFFE50914),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE50914) : const Color(0xFF222222),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFE50914) : Colors.white24,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ─── Continue Watching card ────────────────────────────────────────────────────

class _ContinueWatchingCard extends StatelessWidget {
  final WatchProgress progress;
  final VoidCallback onTap;
  final bool autofocus;

  const _ContinueWatchingCard({
    required this.progress,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return _TvFocusableCard(
      autofocus: autofocus,
      onTap: onTap,
      borderRadius: 8,
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  SizedBox(
                    width: 94,
                    height: 110,
                    child: progress.poster != null
                        ? Image.network(
                            progress.poster!,
                            fit: BoxFit.cover,
                            cacheWidth: 200,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: const Color(0xFF1E1E1E),
                              child: const Center(child: Icon(Icons.movie, color: Colors.white24, size: 30)),
                            ),
                          )
                        : Container(
                            color: const Color(0xFF1E1E1E),
                            child: const Center(child: Icon(Icons.movie, color: Colors.white24, size: 30)),
                          ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: progress.progressPercentage.clamp(0.0, 1.0),
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                      minHeight: 3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              progress.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── My List card ─────────────────────────────────────────────────────────────

class _WatchlistCard extends StatelessWidget {
  final WatchlistItem item;
  final VoidCallback onTap;

  const _WatchlistCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _TvFocusableCard(
      onTap: onTap,
      borderRadius: 8,
      child: Container(
        width: 110,
        margin: const EdgeInsets.only(right: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 104,
                height: 145,
                child: item.poster != null
                    ? Image.network(
                        item.poster!,
                        fit: BoxFit.cover,
                        cacheWidth: 220,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: const Color(0xFF1E1E1E),
                          child: const Center(child: Icon(Icons.movie, color: Colors.white24, size: 36)),
                        ),
                      )
                    : Container(
                        color: const Color(0xFF1E1E1E),
                        child: const Center(child: Icon(Icons.movie, color: Colors.white24, size: 36)),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Trending media card ───────────────────────────────────────────────────────

class _MediaCard extends StatelessWidget {
  final MediaItem item;
  final bool autofocus;

  const _MediaCard({
    required this.item,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return _TvFocusableCard(
      autofocus: autofocus,
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(item: item)));
      },
      borderRadius: 8,
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
                        errorBuilder: (context, error, stackTrace) => const Center(
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
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87, Colors.black],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      if (item.rating != null || item.year != null)
                        Row(
                          children: [
                            if (item.rating != null) ...[
                              const Icon(Icons.star, color: Colors.amber, size: 10),
                              const SizedBox(width: 2),
                              Text(item.rating!, style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 4),
                            ],
                            if (item.year != null)
                              Text(item.year!, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
