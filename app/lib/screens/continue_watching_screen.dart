import 'package:flutter/material.dart';
import '../models/media_models.dart';
import '../models/storage_models.dart';
import '../services/storage_service.dart';
import 'netflix_player_screen.dart';

class ContinueWatchingScreen extends StatefulWidget {
  const ContinueWatchingScreen({super.key});

  @override
  State<ContinueWatchingScreen> createState() => _ContinueWatchingScreenState();
}

class _ContinueWatchingScreenState extends State<ContinueWatchingScreen> {
  static const _scaffoldBg = Color(0xFF0F0F0F);
  static const _cardBg = Color(0xFF1E1E1E);
  static const _accentRed = Color(0xFFE50914);

  List<WatchProgress> _items = [];

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
      _items = StorageService.instance.getAllWatchProgress();
    });
  }

  Future<void> _refresh() async {
    _loadItems();
  }

  void _removeItem(String id) {
    setState(() {
      _items.removeWhere((e) => e.subjectId == id);
    });
    StorageService.instance.removeWatchProgress(id); // no await
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Text('Clear All?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will remove all continue watching history.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear All', style: TextStyle(color: _accentRed)),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirmed == true) {
      final ids = _items.map((e) => e.subjectId).toList();
      for (final id in ids) {
        await StorageService.instance.removeWatchProgress(id);
      }
      if (!mounted) return;
      setState(() {
        _items = StorageService.instance.getAllWatchProgress();
      });
    }
  }

  void _resumeItem(WatchProgress progress) {
    if (progress.streamUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stream URL unavailable, open detail to reselect quality'),
        ),
      );
      return;
    }

    final url = progress.streamUrl!;
    final stream = StreamOption(
      url: url,
      kind: url.contains('.m3u8')
          ? 'hls'
          : url.contains('.mpd')
              ? 'dash'
              : 'mp4',
      resolution: 'Saved',
      cookie: progress.streamCookie,
      bypassedDecoy: true,
    );

    Navigator.of(context).push(
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
  }

  String _remainingText(WatchProgress p) {
    final remainingMs = p.durationMs - p.positionMs;
    final remainingMin = (remainingMs / 60000).ceil();
    return '${remainingMin}m left';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _scaffoldBg,
      appBar: AppBar(
        backgroundColor: _scaffoldBg,
        title: const Text(
          'Continue Watching',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_items.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: const Text(
                'Clear All',
                style: TextStyle(color: _accentRed, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: _accentRed,
        onRefresh: _refresh,
        child: _items.isEmpty ? _buildEmptyState() : _buildList(),
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
                Icon(Icons.play_circle_outline, size: 64, color: Colors.white30),
                SizedBox(height: 16),
                Text(
                  'Nothing here yet\nStart watching something!',
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

  Widget _buildList() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final progress = _items[index];
            return _buildCard(progress);
          },
        ),
      ),
    );
  }

  Widget _buildCard(WatchProgress progress) {
    return Dismissible(
      key: Key('cw_${progress.subjectId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: _accentRed,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _removeItem(progress.subjectId),
      child: GestureDetector(
        onTap: () => _resumeItem(progress),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poster
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: progress.poster != null
                    ? Image.network(
                        progress.poster!,
                        width: 80,
                        height: 110,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _posterFallback(),
                      )
                    : _posterFallback(),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progress.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (progress.season > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'S${progress.season}:E${progress.episode}'
                        '${progress.episodeTitle != null ? ' — ${progress.episodeTitle}' : ''}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress.progressPercentage.clamp(0.0, 1.0),
                        backgroundColor: Colors.white12,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(_accentRed),
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Remaining time badge
                    if (progress.durationMs > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _remainingText(progress),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              // Resume icon
              const Padding(
                padding: EdgeInsets.only(top: 30),
                child: Icon(Icons.play_arrow, color: Colors.white54, size: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _posterFallback() {
    return Container(
      width: 80,
      height: 110,
      color: Colors.grey[800],
      child: const Icon(Icons.movie, color: Colors.white38),
    );
  }
}
