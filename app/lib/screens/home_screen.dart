import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/media_models.dart';
import '../models/storage_models.dart';
import '../services/moviebox_api.dart';
import '../services/storage_service.dart';
import '../services/content_filter_service.dart';
import '../services/tv_mode_service.dart';
import 'detail_screen.dart';
import 'netflix_player_screen.dart';
import 'my_space_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MediaItem> _trending = [];
  bool _isLoadingTrending = true;

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

  static const _bg = Color(0xFF090A0E);
  static const _surface = Color(0xFF141622);
  static const _cardBorder = Color(0x1FFFFFFF);
  static const _accentRed = Color(0xFFE50914);

  @override
  void initState() {
    super.initState();
    _loadTrending();
    StorageService.instance.addListener(_onStorageChanged);
    TvModeService.instance.addListener(_onTvModeChanged);
    _onStorageChanged();
  }

  @override
  void dispose() {
    StorageService.instance.removeListener(_onStorageChanged);
    TvModeService.instance.removeListener(_onTvModeChanged);
    super.dispose();
  }

  void _onTvModeChanged() {
    if (mounted) setState(() {});
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
    HapticFeedback.selectionClick();
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

  void _playMediaItem(MediaItem item) async {
    HapticFeedback.lightImpact();
    // Quick progress indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Loading ${item.title}..."),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF1E1E1E),
      ),
    );

    try {
      final streams = await MovieBoxApi.instance.getStreams(item.id);
      if (streams.isNotEmpty && mounted) {
        final topStream = streams.first;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NetflixPlayerScreen(
              subjectId: item.id,
              title: item.title,
              poster: item.poster,
              season: 0,
              episode: 0,
              stream: topStream,
              availableStreams: streams,
              isSeries: item.type == 2,
            ),
          ),
        );
        return;
      }
    } catch (_) {}

    // Fallback: navigate to details screen if direct play fails
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DetailScreen(item: item)),
      );
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
              backgroundColor: const Color(0xFF181A26),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: const Row(
                children: [
                  Icon(Icons.tune_rounded, color: Color(0xFFE50914)),
                  SizedBox(width: 10),
                  Text("Preferences", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Connection Mode:",
                      style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    RadioGroup<bool>(
                      groupValue: gateway,
                      onChanged: (v) => setDialogState(() => gateway = v ?? false),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<bool>(
                            contentPadding: EdgeInsets.zero,
                            value: false,
                            activeColor: _accentRed,
                            title: const Text("Direct Standalone (Recommended)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: const Text("Zero server setup required. Direct fast CDN access.", style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ),
                          RadioListTile<bool>(
                            contentPadding: EdgeInsets.zero,
                            value: true,
                            activeColor: _accentRed,
                            title: const Text("Gateway Server Mode", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: const Text("Route through custom proxy/wrapper server.", style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                    if (gateway) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: urlController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: "Gateway URL",
                          labelStyle: const TextStyle(color: _accentRed),
                          hintText: "http://10.0.2.2:8399",
                          hintStyle: const TextStyle(color: Colors.white24),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: keyController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: "API Key (optional)",
                          labelStyle: const TextStyle(color: _accentRed),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          isDense: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: ContentFilterService.instance.isFilterEnabled,
                      activeThumbColor: _accentRed,
                      title: const Row(
                        children: [
                          Icon(Icons.shield_rounded, color: Color(0xFF4CAF50), size: 18),
                          SizedBox(width: 8),
                          Text(
                            "Family Safe Filter",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      subtitle: const Text(
                        "Strictly hides explicit 18+ content.",
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      onChanged: (val) async {
                        await ContentFilterService.instance.setFilterEnabled(val);
                        setDialogState(() {});
                        _categoryCache.clear();
                        _loadTrending();
                      },
                    ),
                    const SizedBox(height: 8),
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 8),
                    // TV Mode Settings
                    Row(
                      children: [
                        const Icon(Icons.tv_rounded, color: Colors.white70, size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          "Display Mode",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: TvModeService.instance.isTvHardware
                                ? Colors.green.withValues(alpha: 0.2)
                                : Colors.white10,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            TvModeService.instance.isTvHardware ? "Android TV" : "Mobile Phone",
                            style: TextStyle(
                              color: TvModeService.instance.isTvHardware ? Colors.greenAccent : Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    RadioGroup<TvModePreference>(
                      groupValue: TvModeService.instance.preference,
                      onChanged: (pref) async {
                        if (pref != null) {
                          await TvModeService.instance.setPreference(pref);
                          setDialogState(() {});
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<TvModePreference>(
                            contentPadding: EdgeInsets.zero,
                            value: TvModePreference.auto,
                            activeColor: _accentRed,
                            title: const Text("Auto Detect", style: TextStyle(color: Colors.white, fontSize: 13)),
                            subtitle: const Text("Adapts layout automatically for touch vs remote", style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ),
                          RadioListTile<TvModePreference>(
                            contentPadding: EdgeInsets.zero,
                            value: TvModePreference.mobile,
                            activeColor: _accentRed,
                            title: const Text("Force Mobile Mode", style: TextStyle(color: Colors.white, fontSize: 13)),
                            subtitle: const Text("Always use touch layout and bottom navigation", style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ),
                          RadioListTile<TvModePreference>(
                            contentPadding: EdgeInsets.zero,
                            value: TvModePreference.tv,
                            activeColor: _accentRed,
                            title: const Text("Force TV Mode", style: TextStyle(color: Colors.white, fontSize: 13)),
                            subtitle: const Text("Always use left rail and D-pad remote focus", style: TextStyle(color: Colors.white54, fontSize: 11)),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
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

  int _getResponsiveColumns(BuildContext context) {
    final isTv = TvModeService.instance.isTvMode(context);
    final width = MediaQuery.of(context).size.width;
    if (isTv) {
      if (width < 900) return 4;
      if (width < 1300) return 5;
      if (width < 1700) return 6;
      return 7;
    }
    // Mobile phones: strictly 2 columns for optimal readable size & thumb ergonomics
    if (width < 600) return 2;
    if (width < 840) return 3;
    if (width < 1100) return 4;
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.85),
                Colors.black.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_accentRed, Color(0xFFFF2A36)],
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: _accentRed.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Text(
                "MBX",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              "STREAM",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 17,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          // Filter indicator badge
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Icon(
                    ContentFilterService.instance.isFilterEnabled
                        ? Icons.shield_rounded
                        : Icons.shield_outlined,
                    color: ContentFilterService.instance.isFilterEnabled
                        ? const Color(0xFF4CAF50)
                        : Colors.white38,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    ContentFilterService.instance.isFilterEnabled ? "Safe" : "All",
                    style: TextStyle(
                      color: ContentFilterService.instance.isFilterEnabled
                          ? const Color(0xFF4CAF50)
                          : Colors.white60,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 22),
            onPressed: _showSettingsDialog,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTrending,
        color: _accentRed,
        backgroundColor: _surface,
        edgeOffset: 80,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoadingTrending && _trending.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: _accentRed),
      );
    }

    if (_trending.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.movie_filter_outlined, color: Colors.white24, size: 54),
              const SizedBox(height: 14),
              const Text(
                "Unable to load media catalog",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Check your internet connection or connection mode.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _loadTrending,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }

    final heroItem = _trending.first;
    final isSpecificCategory = _selectedCategory != "All";

    return CustomScrollView(
      cacheExtent: 800,
      slivers: [
        // ── 1. Hero Featured Billboard ──────────────────────────────────────
        if (!isSpecificCategory)
          SliverToBoxAdapter(
            child: _buildHeroBillboard(heroItem),
          ),

        // ── 2. Category Filter Pills ─────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(
              top: isSpecificCategory ? 100 : 8,
              bottom: 12,
              left: 14,
              right: 14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final cat = _categories[i];
                      final isSelected = _selectedCategory == cat;
                      return _buildCategoryChip(cat, isSelected);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── 3. Continue Watching Row (if active) ─────────────────────────────
        if (!isSpecificCategory && _continueWatching.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: _buildSectionHeader(
                title: "Continue Watching",
                badge: "${_continueWatching.length}",
                onSeeAll: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MySpaceScreen(initialTab: 0)),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 154,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                scrollDirection: Axis.horizontal,
                itemCount: _continueWatching.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) => _ContinueWatchingCard(
                  progress: _continueWatching[i],
                  onTap: () => _resumeContinueWatching(_continueWatching[i]),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],

        // ── 4. My List Quick Carousel (if active) ───────────────────────────
        if (!isSpecificCategory && _myList.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: _buildSectionHeader(
                title: "My List",
                badge: "${_myList.length}",
                onSeeAll: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MySpaceScreen(initialTab: 1)),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 200,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                scrollDirection: Axis.horizontal,
                itemCount: _myList.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) {
                  final it = _myList[i].toMediaItem();
                  return _PosterCard(
                    item: it,
                    width: 120,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DetailScreen(item: it)),
                    ),
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],

        // ── 5. Trending Horizontal Carousel (on All feed) ────────────────────
        if (!isSpecificCategory && _trending.length > 5) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: _buildSectionHeader(
                title: "🔥 Trending Now",
                onSeeAll: () => _selectCategory("Movies"),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 220,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                scrollDirection: Axis.horizontal,
                itemCount: _trending.take(10).length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) {
                  final item = _trending[i];
                  return _PosterCard(
                    item: item,
                    width: 130,
                    rank: i + 1,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DetailScreen(item: item)),
                    ),
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],

        // ── 6. Feed Section Header & Responsive 2-Column Grid ─────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(
                  isSpecificCategory ? Icons.filter_alt_rounded : Icons.explore_rounded,
                  color: _accentRed,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isSpecificCategory ? _selectedCategory : "Explore Catalog",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  "${_trending.length} titles",
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ),

        // Responsive 2-column poster grid
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _getResponsiveColumns(context),
              childAspectRatio: 0.65,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _PosterCard(
                item: _trending[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DetailScreen(item: _trending[i])),
                ),
              ),
              childCount: _trending.length,
            ),
          ),
        ),

        // Footer branding
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 32, bottom: 40),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _cardBorder),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.movie_rounded, color: _accentRed, size: 16),
                        SizedBox(width: 6),
                        Text(
                          "MBX Stream • v1.0 Mobile",
                          style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Hero Featured Billboard Widget ──────────────────────────────────────────
  Widget _buildHeroBillboard(MediaItem item) {
    final poster = item.poster;
    final isSeries = item.type == 2;
    final inWatchlist = StorageService.instance.isInWatchlist(item.id);

    return Stack(
      children: [
        // Background poster with smooth gradient overlays
        SizedBox(
          height: 440,
          width: double.infinity,
          child: poster != null
              ? Image.network(
                  poster,
                  fit: BoxFit.cover,
                  cacheWidth: 800,
                  errorBuilder: (_, _, _) => Container(color: const Color(0xFF161822)),
                )
              : Container(color: const Color(0xFF161822)),
        ),
        // Vignette gradient
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.35, 0.7, 1.0],
                colors: [
                  _bg.withValues(alpha: 0.4),
                  Colors.transparent,
                  _bg.withValues(alpha: 0.85),
                  _bg,
                ],
              ),
            ),
          ),
        ),
        // Content overlay
        Positioned(
          left: 16,
          right: 16,
          bottom: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badge row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _accentRed,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isSeries ? "TV SERIES" : "FEATURED MOVIE",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (item.rating != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                          const SizedBox(width: 3),
                          Text(
                            item.rating!,
                            style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (item.year != null)
                    Text(
                      item.year!,
                      style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Big Title
              Text(
                item.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  letterSpacing: -0.5,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 10),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              // Action Buttons Row
              Row(
                children: [
                  // Play button
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentRed,
                        foregroundColor: Colors.white,
                        elevation: 6,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _playMediaItem(item),
                      icon: const Icon(Icons.play_arrow_rounded, size: 24),
                      label: const Text(
                        "Play Now",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // My List toggle button
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        HapticFeedback.lightImpact();
                        await StorageService.instance.toggleWatchlist(item);
                        if (mounted) setState(() {});
                      },
                      icon: Icon(
                        inWatchlist ? Icons.check_rounded : Icons.add_rounded,
                        size: 20,
                        color: inWatchlist ? const Color(0xFF4CAF50) : Colors.white,
                      ),
                      label: Text(
                        inWatchlist ? "Saved" : "My List",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Details info button
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.info_outline_rounded, size: 20),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DetailScreen(item: item)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChip(String cat, bool isSelected) {
    return GestureDetector(
      onTap: () => _selectCategory(cat),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _accentRed : _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? _accentRed : _cardBorder,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _accentRed.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            cat,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    String? badge,
    required VoidCallback onSeeAll,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _cardBorder),
            ),
            child: Text(
              badge,
              style: const TextStyle(color: _accentRed, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
        const Spacer(),
        GestureDetector(
          onTap: onSeeAll,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                Text(
                  "See all",
                  style: TextStyle(color: _accentRed, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Icon(Icons.chevron_right_rounded, color: _accentRed, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _resumeContinueWatching(WatchProgress progress) async {
    HapticFeedback.lightImpact();
    // Safety check against decoy URLs
    if (progress.streamUrl == null || MovieBoxApi.isDecoyUrl(progress.streamUrl)) {
      try {
        final streams = await MovieBoxApi.instance.getStreams(
          progress.subjectId,
          season: progress.season,
          episode: progress.episode,
        );
        if (streams.isNotEmpty && mounted) {
          final topStream = streams.first;
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
                stream: topStream,
                availableStreams: streams,
                isSeries: progress.season > 0,
                initialPosition: Duration(milliseconds: progress.positionMs),
              ),
            ),
          );
          return;
        }
      } catch (_) {}
    }

    if (progress.streamUrl != null && !MovieBoxApi.isDecoyUrl(progress.streamUrl)) {
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
      if (!mounted) return;
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
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DetailScreen(
            item: MediaItem(
              id: progress.subjectId,
              title: progress.title,
              poster: progress.poster,
              type: progress.season > 0 ? 2 : 1,
            ),
          ),
        ),
      );
    }
  }
}

// ─── Continue Watching Card ──────────────────────────────────────────────────

class _ContinueWatchingCard extends StatelessWidget {
  final WatchProgress progress;
  final VoidCallback onTap;

  const _ContinueWatchingCard({required this.progress, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fraction = progress.durationMs > 0
        ? (progress.positionMs / progress.durationMs).clamp(0.0, 1.0)
        : 0.0;
    final minutesLeft = progress.durationMs > progress.positionMs
        ? ((progress.durationMs - progress.positionMs) / 60000).ceil()
        : 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          color: const Color(0xFF141622),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x1FFFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail with Play button & progress gauge
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 96,
                  width: 200,
                  child: progress.poster != null
                      ? Image.network(
                          progress.poster!,
                          fit: BoxFit.cover,
                          cacheWidth: 400,
                          errorBuilder: (_, _, _) => Container(color: Colors.black38),
                        )
                      : Container(color: Colors.black38),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: fraction,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                    minHeight: 3.5,
                  ),
                ),
              ],
            ),
            // Title & info
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    progress.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    progress.season > 0
                        ? "S${progress.season} E${progress.episode}${progress.episodeTitle != null ? ' • ${progress.episodeTitle}' : ''}"
                        : (minutesLeft > 0 ? "$minutesLeft min left" : "Watched"),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

// ─── Reusable Poster Card ────────────────────────────────────────────────────

class _PosterCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;
  final double? width;
  final int? rank;

  const _PosterCard({
    required this.item,
    required this.onTap,
    this.width,
    this.rank,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: const Color(0xFF141622),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x1FFFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Poster Image
            item.poster != null
                ? Image.network(
                    item.poster!,
                    fit: BoxFit.cover,
                    cacheWidth: 400,
                    errorBuilder: (_, _, _) => Container(
                      color: const Color(0xFF161822),
                      child: const Center(child: Icon(Icons.movie, color: Colors.white24, size: 36)),
                    ),
                  )
                : Container(
                    color: const Color(0xFF161822),
                    child: const Center(child: Icon(Icons.movie, color: Colors.white24, size: 36)),
                  ),
            // Gradient overlay
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (item.rating != null) ...[
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                          const SizedBox(width: 2),
                          Text(
                            item.rating!,
                            style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                        ],
                        if (item.year != null)
                          Text(
                            item.year!,
                            style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Optional Top Rank Badge
            if (rank != null)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE50914),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 4),
                    ],
                  ),
                  child: Text(
                    "#$rank",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
