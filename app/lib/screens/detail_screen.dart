import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/media_models.dart';
import '../services/moviebox_api.dart';
import '../services/download_service.dart';
import '../services/storage_service.dart';
import '../services/content_filter_service.dart';
import '../coordinators/download_coordinator.dart';
import '../coordinators/playback_coordinator.dart';
import 'netflix_player_screen.dart';

class DetailScreen extends StatefulWidget {
  final MediaItem item;

  const DetailScreen({super.key, required this.item});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _details;
  List<SeasonItem> _seasons = [];
  int _selectedSeason = 1;
  List<EpisodeItem> _episodes = [];
  bool _isLoadingEpisodes = false;
  bool _inWatchlist = false;
  bool _isSynopsisExpanded = false;

  static const _bg = Color(0xFF090A0E);
  static const _surface = Color(0xFF141622);
  static const _cardBorder = Color(0x1FFFFFFF);
  static const _accentRed = Color(0xFFE50914);

  @override
  void initState() {
    super.initState();
    _inWatchlist = StorageService.instance.isInWatchlist(widget.item.id);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final details = await MovieBoxApi.instance.getDetails(widget.item.id);
      _details = details['data'] as Map<String, dynamic>?;

      // Check if it's a TV show (type 2 = series)
      final type = _details?['subjectType'] as int? ?? widget.item.type ?? 1;
      if (type == 2) {
        final seasons = await MovieBoxApi.instance.getSeasons(widget.item.id);
        _seasons = seasons;
        if (_seasons.isNotEmpty) {
          _selectedSeason = _seasons.first.seasonNumber;
          await _loadEpisodes(_selectedSeason);
        }
      } else {
        _seasons = [];
      }
    } catch (e) {
      debugPrint("Error loading details: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadEpisodes(int season) async {
    setState(() {
      _selectedSeason = season;
      _isLoadingEpisodes = true;
    });
    try {
      final eps = await MovieBoxApi.instance.getEpisodes(widget.item.id, season);
      _episodes = eps;
    } catch (e) {
      debugPrint("Error loading episodes: $e");
    } finally {
      if (mounted) setState(() => _isLoadingEpisodes = false);
    }
  }

  /// Instant one-tap play for mobile phones: skips selector dialog and plays top authentic stream immediately
  Future<void> _playDirect({int season = 0, int episode = 0, String? episodeTitle}) async {
    HapticFeedback.lightImpact();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Loading ${episodeTitle != null ? '${widget.item.title} ($episodeTitle)' : widget.item.title}..."),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF1E1E1E),
      ),
    );

    try {
      final streams = await MovieBoxApi.instance.getStreams(
        widget.item.id,
        season: season,
        episode: episode,
      );

      if (streams.isNotEmpty && mounted) {
        final topStream = streams.first;
        PlaybackCoordinator.instance.launchPlayer(
          context,
          subjectId: widget.item.id,
          title: episodeTitle != null ? "${widget.item.title} - $episodeTitle" : widget.item.title,
          poster: widget.item.poster,
          season: season,
          episode: episode,
          episodeTitle: episodeTitle,
          stream: topStream,
          availableStreams: streams,
          isSeries: _seasons.isNotEmpty,
        );
        return;
      }
    } catch (e) {
      debugPrint("Direct play stream error: $e");
    }

    // Fallback: show quality sheet if direct stream fetch failed
    if (mounted) {
      _showQualitySelector(season: season, episode: episode, episodeTitle: episodeTitle);
    }
  }

  void _showQualitySelector({int season = 0, int episode = 0, String? episodeTitle}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161822),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _StreamSelectorSheet(
          subjectId: widget.item.id,
          title: episodeTitle != null ? "${widget.item.title} - $episodeTitle" : widget.item.title,
          poster: widget.item.poster,
          season: season,
          episode: episode,
          isDownloadMode: false,
        );
      },
    );
  }

  void _onDownloadTapped({int season = 0, int episode = 0, String? episodeTitle}) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161822),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _StreamSelectorSheet(
          subjectId: widget.item.id,
          title: episodeTitle != null ? "${widget.item.title} - $episodeTitle" : widget.item.title,
          season: season,
          episode: episode,
          isDownloadMode: true,
        );
      },
    );
  }

  Widget _buildMetadataRow(bool isSeries) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _accentRed,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            isSeries ? "TV SERIES" : "MOVIE",
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.8),
          ),
        ),
        if (widget.item.year != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(widget.item.year!, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        if (widget.item.rating != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                const SizedBox(width: 3),
                Text(widget.item.rating!, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11)),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.white12),
          ),
          child: const Text("4K UHD", style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildActionButtons(bool isSeries) {
    final progress = StorageService.instance.getWatchProgress(widget.item.id);
    final hasProgress = progress != null && (isSeries ? progress.season > 0 : progress.positionMs > 0);
    final targetSeason = hasProgress && isSeries
        ? progress.season
        : (_selectedSeason > 0 ? _selectedSeason : 1);
    final targetEpisode = hasProgress && isSeries ? progress.episode : 1;
    final playLabel = isSeries
        ? (hasProgress ? "Resume S${progress.season} E${progress.episode}" : "Play Series (S1 E1)")
        : (hasProgress ? "Resume Movie" : "Play Movie");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary Prominent Play Button (One-tap play)
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _accentRed,
            foregroundColor: Colors.white,
            elevation: 8,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () {
            if (isSeries) {
              _playDirect(
                season: targetSeason,
                episode: targetEpisode,
                episodeTitle: hasProgress ? progress.episodeTitle : null,
              );
            } else {
              _playDirect();
            }
          },
          icon: const Icon(Icons.play_arrow_rounded, size: 28),
          label: Text(
            playLabel,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.2),
          ),
        ),
        const SizedBox(height: 12),

        // Secondary Action Row: My List, Download, Quality
        Row(
          children: [
            // My List toggle
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: _surface,
                  side: BorderSide(color: _inWatchlist ? const Color(0xFF4CAF50) : _cardBorder),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await StorageService.instance.toggleWatchlist(widget.item);
                  if (mounted) {
                    setState(() => _inWatchlist = !_inWatchlist);
                  }
                },
                icon: Icon(
                  _inWatchlist ? Icons.check_rounded : Icons.add_rounded,
                  color: _inWatchlist ? const Color(0xFF4CAF50) : Colors.white,
                  size: 20,
                ),
                label: Text(
                  _inWatchlist ? "Saved" : "My List",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Download
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: _surface,
                  side: const BorderSide(color: _cardBorder),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _onDownloadTapped(
                  season: isSeries ? targetSeason : 0,
                  episode: isSeries ? targetEpisode : 0,
                ),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text(
                  "Download",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Quality / Streams selector
            IconButton.outlined(
              style: IconButton.styleFrom(
                backgroundColor: _surface,
                side: const BorderSide(color: _cardBorder),
                padding: const EdgeInsets.all(12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 18),
              tooltip: "Select Quality",
              onPressed: () => _showQualitySelector(
                season: isSeries ? targetSeason : 0,
                episode: isSeries ? targetEpisode : 0,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEpisodesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          "Episodes",
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        // Season Chips
        if (_seasons.length > 1)
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _seasons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final s = _seasons[i];
                final isSelected = s.seasonNumber == _selectedSeason;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _loadEpisodes(s.seasonNumber);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected ? _accentRed : _surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSelected ? _accentRed : _cardBorder),
                    ),
                    child: Text(
                      s.title,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 14),

        if (_isLoadingEpisodes)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: CircularProgressIndicator(color: _accentRed),
            ),
          )
        else if (_episodes.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("No episodes found.", style: TextStyle(color: Colors.white54)),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _episodes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final ep = _episodes[i];
              final saved = StorageService.instance.getWatchProgress(widget.item.id);
              final isThisEp = saved != null &&
                  saved.season == ep.seasonNumber &&
                  saved.episode == ep.episodeNumber;
              final isWatched = isThisEp && saved.progressPercentage >= 0.9;
              final progressFraction = isThisEp ? saved.progressPercentage.clamp(0.0, 1.0) : 0.0;

              return Container(
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _cardBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _playDirect(
                    season: ep.seasonNumber,
                    episode: ep.episodeNumber,
                    episodeTitle: ep.title,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Episode badge avatar
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isWatched ? const Color(0x2E4CAF50) : const Color(0x2EE50914),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: isWatched
                                    ? const Icon(Icons.check_rounded, color: Color(0xFF4CAF50), size: 18)
                                    : Text(
                                        "${ep.episodeNumber}",
                                        style: const TextStyle(
                                          color: _accentRed,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Title & Description
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ep.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (ep.description?.isNotEmpty == true)
                                    Text(
                                      ep.description!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Quick download icon
                            IconButton(
                              icon: const Icon(Icons.download_rounded, color: Colors.white38, size: 20),
                              onPressed: () => _onDownloadTapped(
                                season: ep.seasonNumber,
                                episode: ep.episodeNumber,
                                episodeTitle: ep.title,
                              ),
                            ),
                            // Play icon
                            const Icon(Icons.play_circle_fill_rounded, color: _accentRed, size: 30),
                          ],
                        ),
                        if (isThisEp && progressFraction > 0.02 && !isWatched) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progressFraction,
                              minHeight: 3,
                              backgroundColor: Colors.white12,
                              valueColor: const AlwaysStoppedAnimation<Color>(_accentRed),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context, String? poster, bool isSeries) {
    final synopsis = widget.item.description?.isNotEmpty == true
        ? widget.item.description!
        : (_details?['desc'] ?? _details?['introduce'] ?? "No synopsis available.");

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          // Immersive Hero Backdrop Sliver
          SliverAppBar(
            expandedHeight: 380,
            pinned: true,
            backgroundColor: _bg,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: GestureDetector(
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    await StorageService.instance.toggleWatchlist(widget.item);
                    if (mounted) setState(() => _inWatchlist = !_inWatchlist);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _inWatchlist ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
                      color: _inWatchlist ? const Color(0xFF4CAF50) : Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (poster != null)
                    Image.network(
                      poster,
                      fit: BoxFit.cover,
                      cacheWidth: 800,
                      errorBuilder: (_, _, _) => Container(color: _surface),
                    )
                  else
                    Container(color: _surface),
                  // Bottom fade into background
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.4, 0.8, 1.0],
                        colors: [
                          _bg.withValues(alpha: 0.5),
                          Colors.transparent,
                          _bg.withValues(alpha: 0.85),
                          _bg,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Details content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    widget.item.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Metadata Badges Row
                  _buildMetadataRow(isSeries),
                  const SizedBox(height: 16),

                  // Actions (Play / My List / Download / Quality)
                  _buildActionButtons(isSeries),
                  const SizedBox(height: 18),

                  // Synopsis with read more
                  GestureDetector(
                    onTap: () => setState(() => _isSynopsisExpanded = !_isSynopsisExpanded),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          synopsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                          maxLines: _isSynopsisExpanded ? 50 : 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (synopsis.length > 120) ...[
                          const SizedBox(height: 4),
                          Text(
                            _isSynopsisExpanded ? "Show less" : "Read more",
                            style: const TextStyle(color: _accentRed, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Episodes section
                  if (isSeries) _buildEpisodesSection(),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout(BuildContext context, String? poster, bool isSeries) {
    final synopsis = widget.item.description?.isNotEmpty == true
        ? widget.item.description!
        : (_details?['desc'] ?? _details?['introduce'] ?? "No synopsis available.");

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 220,
                      height: 330,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _cardBorder),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: poster != null
                          ? Image.network(poster, fit: BoxFit.cover)
                          : Container(color: _surface),
                    ),
                    const SizedBox(width: 28),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item.title,
                            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          _buildMetadataRow(isSeries),
                          const SizedBox(height: 20),
                          _buildActionButtons(isSeries),
                          const SizedBox(height: 20),
                          Text(synopsis, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (isSeries) ...[
                  const SizedBox(height: 32),
                  _buildEpisodesSection(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBlocked = ContentFilterService.instance.isNsfw(widget.item) ||
        (_details != null && ContentFilterService.instance.isDetailDataNsfw(_details!));
    if (isBlocked) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield, color: _accentRed, size: 54),
                SizedBox(height: 14),
                Text(
                  "Content Restricted",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                SizedBox(height: 6),
                Text(
                  "This title is blocked by Family Safe filter.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final poster = widget.item.poster;
    final type = _details?['subjectType'] as int? ?? widget.item.type ?? 1;
    final isSeries = type == 2 && _seasons.isNotEmpty;
    final isWide = MediaQuery.of(context).size.width >= 720;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _accentRed)),
      );
    }

    return isWide
        ? _buildWideLayout(context, poster, isSeries)
        : _buildMobileLayout(context, poster, isSeries);
  }
}

// ─── Stream Selector Bottom Sheet ─────────────────────────────────────────────

class _StreamSelectorSheet extends StatefulWidget {
  final String subjectId;
  final String title;
  final String? poster;
  final int season;
  final int episode;
  final bool isDownloadMode;

  const _StreamSelectorSheet({
    required this.subjectId,
    required this.title,
    this.poster,
    required this.season,
    required this.episode,
    required this.isDownloadMode,
  });

  @override
  State<_StreamSelectorSheet> createState() => _StreamSelectorSheetState();
}

class _StreamSelectorSheetState extends State<_StreamSelectorSheet> {
  bool _loading = true;
  List<StreamOption> _streams = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchStreams();
  }

  Future<void> _fetchStreams() async {
    try {
      final streams = await MovieBoxApi.instance.getStreams(
        widget.subjectId,
        season: widget.season,
        episode: widget.episode,
      );
      if (mounted) {
        setState(() {
          _streams = streams;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.isDownloadMode ? Icons.download_rounded : Icons.tune_rounded, color: const Color(0xFFE50914)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.isDownloadMode ? "Download: ${widget.title}" : "Quality: ${widget.title}",
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(28.0),
                  child: CircularProgressIndicator(color: Color(0xFFE50914)),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text("Error fetching streams: $_error", style: const TextStyle(color: Colors.redAccent)),
              )
            else if (_streams.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Center(
                  child: Text(
                    "No streams found for this title.",
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ),
              )
            else ...[
              const Text("Available Resolutions:", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ..._streams.map((s) {
                final is1080 = s.resolution.contains("1080");
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E202C),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: is1080 ? const Color(0xFFE50914).withValues(alpha: 0.5) : Colors.white12),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        is1080 ? Icons.hd_rounded : Icons.video_collection_outlined,
                        color: is1080 ? const Color(0xFFE50914) : Colors.white70,
                      ),
                      title: Text(
                        "${s.resolution} (${s.kind.toUpperCase()})",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      subtitle: s.sizeMb != null
                          ? Text("${s.sizeMb} MB", style: const TextStyle(color: Colors.white54, fontSize: 11))
                          : null,
                      trailing: Icon(
                        widget.isDownloadMode ? Icons.download_rounded : Icons.play_arrow_rounded,
                        color: const Color(0xFFE50914),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        if (widget.isDownloadMode) {
                          DownloadCoordinator.instance.requestDownload(
                            subjectId: widget.subjectId,
                            title: widget.title,
                            stream: s,
                            season: widget.season,
                            episode: widget.episode,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Started downloading: ${widget.title} (${s.resolution})")),
                          );
                        } else {
                          PlaybackCoordinator.instance.launchPlayer(
                            context,
                            subjectId: widget.subjectId,
                            title: widget.title,
                            poster: widget.poster,
                            season: widget.season,
                            episode: widget.episode,
                            stream: s,
                            availableStreams: _streams,
                            isSeries: widget.season > 0,
                          );
                        }
                      },
                    ),
                  ),
                );
              }),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
