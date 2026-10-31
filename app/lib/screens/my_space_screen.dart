import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/media_models.dart';
import '../models/storage_models.dart';
import '../services/storage_service.dart';
import '../services/moviebox_api.dart';
import 'detail_screen.dart';
import 'netflix_player_screen.dart';

class MySpaceScreen extends StatefulWidget {
  final int initialTab;
  const MySpaceScreen({super.key, this.initialTab = 0});

  @override
  State<MySpaceScreen> createState() => _MySpaceScreenState();
}

class _MySpaceScreenState extends State<MySpaceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<WatchProgress> _continueWatching = [];
  List<WatchlistItem> _myList = [];

  static const _bg = Color(0xFF090A0E);
  static const _surface = Color(0xFF141622);
  static const _cardBorder = Color(0x1FFFFFFF);
  static const _accentRed = Color(0xFFE50914);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _loadData();
    StorageService.instance.addListener(_onStorageChanged);
  }

  @override
  void dispose() {
    StorageService.instance.removeListener(_onStorageChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onStorageChanged() {
    if (mounted) _loadData();
  }

  void _loadData() {
    setState(() {
      _continueWatching = StorageService.instance.getAllWatchProgress();
      _myList = StorageService.instance.getWatchlist();
    });
  }

  void _resumeItem(WatchProgress progress) async {
    HapticFeedback.lightImpact();

    // If stream URL is missing or looks like an unbypassed decoy honeypot, fetch fresh stream
    if (progress.streamUrl == null || MovieBoxApi.isDecoyUrl(progress.streamUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Fetching authentic stream..."),
          duration: Duration(seconds: 1),
          backgroundColor: Color(0xFF1E1E1E),
        ),
      );
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
      // Fallback: open detail screen so user can pick
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

  void _removeContinueWatching(String id) {
    HapticFeedback.mediumImpact();
    setState(() {
      _continueWatching.removeWhere((e) => e.subjectId == id);
    });
    StorageService.instance.removeWatchProgress(id);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Removed from continue watching"),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _removeWatchlist(String id) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _myList.removeWhere((e) => e.id == id);
    });
    await StorageService.instance.removeWatchlist(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Removed from My List"),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text(
          "My Library",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: -0.5,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _cardBorder),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: _accentRed,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: _accentRed.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_circle_outline_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text("Continue (${_continueWatching.length})"),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.bookmark_outline_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text("My List (${_myList.length})"),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildContinueWatchingTab(),
          _buildWatchlistTab(),
        ],
      ),
    );
  }

  Widget _buildContinueWatchingTab() {
    if (_continueWatching.isEmpty) {
      return _buildEmptyState(
        icon: Icons.history_rounded,
        title: "No Watching History",
        subtitle: "Movies and episodes you start watching will automatically appear here.",
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _continueWatching.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final item = _continueWatching[i];
        final fraction = item.durationMs > 0
            ? (item.positionMs / item.durationMs).clamp(0.0, 1.0)
            : 0.0;
        final minutesLeft = item.durationMs > item.positionMs
            ? ((item.durationMs - item.positionMs) / 60000).ceil()
            : 0;

        return Dismissible(
          key: Key("cw_${item.subjectId}"),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFD32F2F),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
          ),
          onDismissed: (_) => _removeContinueWatching(item.subjectId),
          child: Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cardBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _resumeItem(item),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // Thumbnail
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 100,
                              height: 64,
                              child: item.poster != null
                                  ? Image.network(
                                      item.poster!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        color: Colors.black26,
                                        child: const Icon(Icons.movie, color: Colors.white24),
                                      ),
                                    )
                                  : Container(
                                      color: Colors.black26,
                                      child: const Icon(Icons.movie, color: Colors.white24),
                                    ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.season > 0
                                  ? "S${item.season} E${item.episode}${item.episodeTitle != null ? ' • ${item.episodeTitle}' : ''}"
                                  : (minutesLeft > 0 ? "$minutesLeft min left" : "Watched"),
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            // Progress bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: fraction,
                                minHeight: 4,
                                backgroundColor: Colors.white12,
                                valueColor: const AlwaysStoppedAnimation<Color>(_accentRed),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert, color: Colors.white38),
                        onPressed: () {
                          _showItemActions(item);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showItemActions(WatchProgress item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161822),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded, color: Colors.white),
                title: const Text("View Details", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DetailScreen(
                        item: MediaItem(
                          id: item.subjectId,
                          title: item.title,
                          poster: item.poster,
                          type: item.season > 0 ? 2 : 1,
                        ),
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE50914)),
                title: const Text("Remove from History", style: TextStyle(color: Color(0xFFE50914))),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeContinueWatching(item.subjectId);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWatchlistTab() {
    if (_myList.isEmpty) {
      return _buildEmptyState(
        icon: Icons.bookmark_border_rounded,
        title: "Your Watchlist is Empty",
        subtitle: "Tap '+ My List' on any movie or TV series to save it for later.",
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 600;
    final crossAxisCount = isWide ? 4 : 2;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _myList.length,
      itemBuilder: (ctx, i) {
        final item = _myList[i];
        final mediaItem = item.toMediaItem();

        return Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _cardBorder),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DetailScreen(item: mediaItem)),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: item.poster != null
                          ? Image.network(
                              item.poster!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: Colors.black26,
                                child: const Center(child: Icon(Icons.movie, color: Colors.white24)),
                              ),
                            )
                          : Container(
                              color: Colors.black26,
                              child: const Center(child: Icon(Icons.movie, color: Colors.white24)),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () => _removeWatchlist(item.id),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _surface,
                shape: BoxShape.circle,
                border: Border.all(color: _cardBorder),
              ),
              child: Icon(icon, color: Colors.white30, size: 48),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
