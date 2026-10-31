import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../models/media_models.dart';
import '../services/local_stream_relay.dart';
import '../services/moviebox_api.dart';

class PlayerScreen extends StatefulWidget {
  final String title;
  final StreamOption stream;
  final List<StreamOption> availableStreams;

  const PlayerScreen({
    super.key,
    required this.title,
    required this.stream,
    required this.availableStreams,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late StreamOption _currentStream;
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentStream = widget.stream;
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _chewieController?.dispose();
    await _videoPlayerController?.dispose();

    try {
      final headers = <String, String>{};
      if (_currentStream.cookie != null && _currentStream.cookie!.isNotEmpty) {
        headers['Cookie'] = _currentStream.cookie!;
      }
      headers['User-Agent'] = 'MovieBox/${MovieBoxApi.appVersion} (Android 14; Pixel 8 Pro)';

      await LocalStreamRelay.instance.ensureStarted();
      final playbackUrl = (_currentStream.cookie != null && _currentStream.cookie!.isNotEmpty && LocalStreamRelay.instance.isRunning)
          ? LocalStreamRelay.instance.getRelayUrl(
              url: _currentStream.url,
              cookie: _currentStream.cookie,
              kind: _currentStream.kind,
              title: widget.title,
            )
          : _currentStream.url;

      // Accurate format hint calculation: NEVER force HLS or DASH on an MP4 container!
      VideoFormat? formatHint;
      final lowerUrl = _currentStream.url.toLowerCase();
      final k = _currentStream.kind.toLowerCase();
      if (lowerUrl.contains('.mp4') || lowerUrl.contains('.m4v')) {
        formatHint = null; // Let ExoPlayer sniff MP4 naturally
      } else if (lowerUrl.contains('.m3u8') || (k == 'hls' && !lowerUrl.contains('.mp4') && !lowerUrl.contains('.mpd'))) {
        formatHint = VideoFormat.hls;
      } else if (lowerUrl.contains('.mpd') || (k == 'dash' && !lowerUrl.contains('.mp4') && !lowerUrl.contains('.m3u8'))) {
        formatHint = VideoFormat.dash;
      } else {
        formatHint = null;
      }

      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(playbackUrl),
        formatHint: formatHint,
        httpHeaders: headers,
      );

      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio > 0
            ? _videoPlayerController!.value.aspectRatio
            : 16 / 9,
        allowFullScreen: true,
        allowMuting: true,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                const SizedBox(height: 12),
                Text(
                  "Playback Error: $errorMessage",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _initPlayer(),
                  icon: const Icon(Icons.refresh),
                  label: const Text("Retry Playback"),
                ),
              ],
            ),
          );
        },
      );

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _switchQuality(StreamOption opt) {
    if (opt.url == _currentStream.url) return;
    setState(() {
      _currentStream = opt;
    });
    _initPlayer();
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        actions: [
          if (widget.availableStreams.length > 1)
            PopupMenuButton<StreamOption>(
              icon: const Icon(Icons.high_quality),
              tooltip: "Select Quality",
              onSelected: _switchQuality,
              itemBuilder: (context) {
                return widget.availableStreams.map((opt) {
                  final isSelected = opt.url == _currentStream.url;
                  return PopupMenuItem(
                    value: opt,
                    child: Row(
                      children: [
                        if (isSelected) const Icon(Icons.check, size: 18, color: Colors.amber),
                        const SizedBox(width: 8),
                        Text(
                          "${opt.resolution} (${opt.kind.toUpperCase()}) ${opt.sizeMb != null ? '${opt.sizeMb} MB' : ''}",
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.amber : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList();
              },
            ),
        ],
      ),
      body: Center(
        child: _isLoading
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.amber),
                  SizedBox(height: 16),
                  Text("Loading stream...", style: TextStyle(color: Colors.white70)),
                ],
              )
            : _errorMessage != null
                ? Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 56),
                        const SizedBox(height: 16),
                        Text(
                          "Failed to load player:\n$_errorMessage",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          onPressed: () => _initPlayer(),
                          icon: const Icon(Icons.refresh),
                          label: const Text("Retry Playback", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  )
                : Chewie(controller: _chewieController!),
      ),
    );
  }
}
