import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/media_models.dart';

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
      headers['User-Agent'] = 'MovieBox/4.0.02.0831.03 (Android 14; Pixel 8 Pro)';

      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(_currentStream.url),
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
                  onPressed: _openExternalPlayer,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text("Open in External Player (VLC/MPV)"),
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

  Future<void> _openExternalPlayer() async {
    final uri = Uri.parse(_currentStream.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not launch external player")),
        );
      }
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
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: "Open External Player",
            onPressed: _openExternalPlayer,
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
                          "Failed to load built-in player:\n$_errorMessage",
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
                          onPressed: _openExternalPlayer,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text("Play in VLC / MX Player / MPV", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  )
                : Chewie(controller: _chewieController!),
      ),
    );
  }
}
