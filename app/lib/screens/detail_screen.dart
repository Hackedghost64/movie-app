import 'package:flutter/material.dart';
import '../models/media_models.dart';
import '../services/moviebox_api.dart';
import '../services/download_service.dart';
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

  @override
  void initState() {
    super.initState();
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

  void _onPlayTapped({int season = 0, int episode = 0, String? episodeTitle}) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
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
      backgroundColor: const Color(0xFF1E1E1E),
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

  @override
  Widget build(BuildContext context) {
    final poster = widget.item.poster;
    final type = _details?['subjectType'] as int? ?? widget.item.type ?? 1;
    final isSeries = type == 2 && _seasons.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 320,
                  pinned: true,
                  backgroundColor: const Color(0xFF1E1E1E),
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(
                      widget.item.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                      ),
                    ),
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (poster != null)
                          Image.network(
                            poster,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(color: Colors.grey[900]),
                          )
                        else
                          Container(color: Colors.grey[900]),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87, Colors.black],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Metadata row
                        Row(
                          children: [
                            if (widget.item.year != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white12,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(widget.item.year!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              ),
                            const SizedBox(width: 8),
                            if (widget.item.rating != null)
                              Row(
                                children: [
                                  const Icon(Icons.star, color: Colors.amber, size: 16),
                                  const SizedBox(width: 4),
                                  Text(widget.item.rating!, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isSeries ? "TV SERIES" : "MOVIE",
                                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Action buttons for movies
                        if (!isSeries)
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amber,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () => _onPlayTapped(),
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text("Watch Movie", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton.filledTonal(
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white12,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.all(14),
                                ),
                                onPressed: () => _onDownloadTapped(),
                                icon: const Icon(Icons.download),
                              ),
                            ],
                          ),

                        const SizedBox(height: 16),
                        // Overview
                        Text(
                          widget.item.description?.isNotEmpty == true
                              ? widget.item.description!
                              : (_details?['desc'] ?? _details?['introduce'] ?? "No synopsis available."),
                          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                        ),
                        const SizedBox(height: 24),

                        // Seasons & Episodes Section
                        if (isSeries) ...[
                          const Text("Episodes", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),

                          // Season selector chips
                          if (_seasons.length > 1)
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: _seasons.map((s) {
                                  final isSelected = s.seasonNumber == _selectedSeason;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: ChoiceChip(
                                      label: Text(s.title),
                                      selected: isSelected,
                                      selectedColor: Colors.amber,
                                      backgroundColor: const Color(0xFF252525),
                                      labelStyle: TextStyle(
                                        color: isSelected ? Colors.black : Colors.white,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                      onSelected: (_) => _loadEpisodes(s.seasonNumber),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          const SizedBox(height: 12),

                          // Episode List
                          if (_isLoadingEpisodes)
                            const Center(child: Padding(padding: EdgeInsets.all(24.0), child: CircularProgressIndicator(color: Colors.amber)))
                          else if (_episodes.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text("No episodes found for this season.", style: TextStyle(color: Colors.white54)),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _episodes.length,
                              itemBuilder: (ctx, i) {
                                final ep = _episodes[i];
                                return Card(
                                  color: const Color(0xFF1E1E1E),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.amber.withOpacity(0.2),
                                      child: Text(
                                        "${ep.episodeNumber}",
                                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(ep.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                                    subtitle: ep.description?.isNotEmpty == true
                                        ? Text(ep.description!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12))
                                        : null,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.download, color: Colors.white70, size: 20),
                                          onPressed: () => _onDownloadTapped(season: ep.seasonNumber, episode: ep.episodeNumber, episodeTitle: ep.title),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.play_circle_fill, color: Colors.amber, size: 28),
                                          onPressed: () => _onPlayTapped(season: ep.seasonNumber, episode: ep.episodeNumber, episodeTitle: ep.title),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

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
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.isDownloadMode ? Icons.download : Icons.play_circle, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.isDownloadMode ? "Download: ${widget.title}" : "Play: ${widget.title}",
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24.0), child: CircularProgressIndicator(color: Colors.amber)))
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text("Error fetching streams: $_error", style: const TextStyle(color: Colors.redAccent)),
            )
          else if (_streams.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("No streams found.", style: TextStyle(color: Colors.white54)),
            )
          else ...[
            const Text("Select Quality:", style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 8),
            ..._streams.map((s) {
              return Card(
                color: const Color(0xFF2A2A2A),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Row(
                    children: [
                      Text(s.resolution, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(s.kind.toUpperCase(), style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      if (s.bypassedDecoy) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.verified, color: Colors.greenAccent, size: 14),
                      ],
                    ],
                  ),
                  subtitle: s.sizeMb != null
                      ? Text("${s.sizeMb} MB", style: const TextStyle(color: Colors.white54, fontSize: 12))
                      : null,
                  trailing: Icon(widget.isDownloadMode ? Icons.file_download : Icons.play_arrow, color: Colors.amber),
                  onTap: () {
                    Navigator.pop(context);
                    if (widget.isDownloadMode) {
                      DownloadService.instance.startDownload(
                        id: "${widget.subjectId}_${widget.season}_${widget.episode}_${s.resolution}",
                        title: widget.title,
                        url: s.url,
                        cookie: s.cookie,
                        ext: s.kind == 'dash' ? 'mpd' : (s.kind == 'hls' ? 'm3u8' : 'mp4'),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Started downloading: ${widget.title} (${s.resolution})")),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NetflixPlayerScreen(
                            subjectId: widget.subjectId,
                            title: widget.title,
                            poster: widget.poster,
                            season: widget.season,
                            episode: widget.episode,
                            stream: s,
                            availableStreams: _streams,
                            isSeries: widget.season > 0,
                          ),
                        ),
                      );
                    }
                  },
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
