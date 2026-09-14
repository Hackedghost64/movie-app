import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/media_models.dart';
import '../models/storage_models.dart';
import '../services/storage_service.dart';
import '../services/moviebox_api.dart';
import '../widgets/tv_focusable.dart';

/// Netflix-style video player with custom overlay controls.
class NetflixPlayerScreen extends StatefulWidget {
  final String subjectId;
  final String title;
  final String? poster;
  final int season; // 0 for movies
  final int episode; // 0 for movies
  final String? episodeTitle;
  final StreamOption stream;
  final List<StreamOption> availableStreams;
  final bool isSeries;
  final Duration? initialPosition;

  const NetflixPlayerScreen({
    super.key,
    required this.subjectId,
    required this.title,
    this.poster,
    required this.season,
    required this.episode,
    this.episodeTitle,
    required this.stream,
    required this.availableStreams,
    required this.isSeries,
    this.initialPosition,
  });

  @override
  State<NetflixPlayerScreen> createState() => _NetflixPlayerScreenState();
}

class _NetflixPlayerScreenState extends State<NetflixPlayerScreen> {
  // ── Video controller ──────────────────────────────────────────────────────
  VideoPlayerController? _controller;
  bool _isInitializing = true;
  bool _hasError = false;
  String _errorMessage = '';

  late StreamOption _currentStream;

  // ── Overlay state ─────────────────────────────────────────────────────────
  bool _showControls = true;
  bool _isLocked = false;
  Timer? _hideTimer;

  // ── Resume banner ─────────────────────────────────────────────────────────
  String? _resumeBannerText;
  Timer? _resumeBannerTimer;

  // ── TV Remote Focus ───────────────────────────────────────────────────────
  final FocusNode _playPauseFocusNode = FocusNode();

  // ── Playback speed ────────────────────────────────────────────────────────
  double _playbackSpeed = 1.0;
  static const List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // ── Aspect ratio ─────────────────────────────────────────────────────────
  BoxFit _boxFit = BoxFit.contain;
  static const List<BoxFit> _fits = [BoxFit.contain, BoxFit.fill, BoxFit.cover];

  String get _fitLabel {
    switch (_boxFit) {
      case BoxFit.contain:
        return 'Fit';
      case BoxFit.fill:
        return 'Fill';
      case BoxFit.cover:
        return 'Crop';
      default:
        return 'Fit';
    }
  }

  // ── Double-tap ripple ─────────────────────────────────────────────────────
  bool _showRewindRipple = false;
  bool _showForwardRipple = false;
  Timer? _rippleTimer;

  // ── Auto-save timer ───────────────────────────────────────────────────────
  Timer? _saveTimer;
  bool _saveTimerStarted = false;
  int _lastTick = 0;

  // ── Slider drag state ─────────────────────────────────────────────────────
  double? _dragValue;


  // ── Constants ─────────────────────────────────────────────────────────────
  static const _accentRed = Color(0xFFE50914);
  static const _seekAmount = Duration(seconds: 10);
  static const _hideAfter = Duration(seconds: 4);

  // ── Derived helpers ───────────────────────────────────────────────────────
  bool get _isPlaying => _controller?.value.isPlaying ?? false;
  Duration get _position => _controller?.value.position ?? Duration.zero;
  Duration get _duration => _controller?.value.duration ?? Duration.zero;
  bool get _isBuffering => _controller?.value.isBuffering ?? false;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _currentStream = widget.stream;
    _enterImmersive();

    // Determine initial playback point
    Duration? seekTarget = widget.initialPosition;
    if (seekTarget == null) {
      final saved = StorageService.instance.getWatchProgress(widget.subjectId);
      if (saved != null &&
          saved.season == widget.season &&
          saved.episode == widget.episode &&
          saved.positionMs > 2000) {
        if (saved.durationMs == 0 || saved.positionMs < (saved.durationMs - 15000)) {
          seekTarget = Duration(milliseconds: saved.positionMs);
        }
      }
    }

    if (seekTarget != null && seekTarget > Duration.zero) {
      final m = seekTarget.inMinutes;
      final s = seekTarget.inSeconds.remainder(60).toString().padLeft(2, '0');
      _resumeBannerText = 'Resumed from $m:$s';
      _resumeBannerTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _resumeBannerText = null);
      });
    }

    _initPlayer(seekTo: seekTarget);
  }

  @override
  void dispose() {
    _saveProgress();
    _hideTimer?.cancel();
    _rippleTimer?.cancel();
    _saveTimer?.cancel();
    _resumeBannerTimer?.cancel();
    _playPauseFocusNode.dispose();
    _controller?.removeListener(_onVideoEvent);
    _controller?.dispose();
    _exitImmersive();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Immersive mode & orientation
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _enterImmersive() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _exitImmersive() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Player initialisation
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initPlayer({Duration? seekTo}) async {
    setState(() {
      _isInitializing = true;
      _hasError = false;
      _errorMessage = '';
    });

    _saveTimer?.cancel();
    _saveTimerStarted = false;

    await _controller?.dispose();
    _controller = null;

    try {
      final headers = <String, String>{};
      if (_currentStream.cookie != null && _currentStream.cookie!.isNotEmpty) {
        headers['Cookie'] = _currentStream.cookie!;
      }

      final VideoPlayerController ctrl;
      if (_currentStream.url.startsWith('http://') || _currentStream.url.startsWith('https://')) {
        ctrl = VideoPlayerController.networkUrl(
          Uri.parse(_currentStream.url),
          httpHeaders: headers,
        );
      } else {
        ctrl = VideoPlayerController.file(
          File(_currentStream.url),
        );
      }
      _controller = ctrl;
      ctrl.addListener(_onVideoEvent);

      await ctrl.initialize();

      // IMPORTANT 4 — bail out if widget was disposed during init
      if (!mounted) {
        ctrl.dispose();
        return;
      }

      await ctrl.setPlaybackSpeed(_playbackSpeed);
      if (seekTo != null && seekTo > Duration.zero) {
        await ctrl.seekTo(seekTo);
      }
      await ctrl.play();
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _isInitializing = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isInitializing = false);
    }
  }

  void _onVideoEvent() {
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Only rebuild UI if controls are visible and throttled to at most once per 200ms
    if (_showControls && now - _lastTick > 200) {
      _lastTick = now;
      setState(() {});
    }

    // Start auto-save timer on first play
    if (_isPlaying && !_saveTimerStarted) {
      _saveTimerStarted = true;
      _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _saveProgress();
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Progress saving
  // ─────────────────────────────────────────────────────────────────────────

  void _saveProgress() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final pos = ctrl.value.position.inMilliseconds;
    final dur = ctrl.value.duration.inMilliseconds;
    StorageService.instance.saveWatchProgress(
      WatchProgress(
        subjectId: widget.subjectId,
        title: widget.title,
        poster: widget.poster,
        season: widget.season,
        episode: widget.episode,
        episodeTitle: widget.episodeTitle,
        positionMs: pos,
        durationMs: dur,
        lastWatchedMs: DateTime.now().millisecondsSinceEpoch,
        streamUrl: _currentStream.url,
        streamCookie: _currentStream.cookie,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Controls visibility
  // ─────────────────────────────────────────────────────────────────────────

  void _showControlsOverlay() {
    setState(() => _showControls = true);
    _resetHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showControls && _playPauseFocusNode.canRequestFocus) {
        _playPauseFocusNode.requestFocus();
      }
    });
  }

  void _toggleControls() {
    if (_showControls) {
      setState(() => _showControls = false);
      _hideTimer?.cancel();
    } else {
      _showControlsOverlay();
    }
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onUserInteraction() {
    if (!_showControls) {
      _showControlsOverlay();
    } else {
      _resetHideTimer();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Playback helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _togglePlayPause() {
    _onUserInteraction();
    final ctrl = _controller;
    if (ctrl == null) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
    } else {
      ctrl.play();
    }
  }

  void _seekRelative(Duration delta) {
    final ctrl = _controller;
    if (ctrl == null) return;
    final target = ctrl.value.position + delta;
    final clamped = target.isNegative
        ? Duration.zero
        : (target > ctrl.value.duration ? ctrl.value.duration : target);
    ctrl.seekTo(clamped);
  }


  void _setSpeed(double speed) {
    _playbackSpeed = speed;
    _controller?.setPlaybackSpeed(speed);
    setState(() {});
  }

  void _cycleAspectRatio() {
    final idx = _fits.indexOf(_boxFit);
    setState(() => _boxFit = _fits[(idx + 1) % _fits.length]);
    _onUserInteraction();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Double-tap seek
  // ─────────────────────────────────────────────────────────────────────────

  void _doubleTapSeek({required bool forward}) {
    // Do NOT call _onUserInteraction() — keep controls hidden during seek
    _seekRelative(forward ? _seekAmount : -_seekAmount);


    _rippleTimer?.cancel();
    setState(() {
      if (forward) {
        _showForwardRipple = true;
      } else {
        _showRewindRipple = true;
      }
    });
    _rippleTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _showRewindRipple = false;
          _showForwardRipple = false;
        });
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // External player
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _openExternal() async {
    final uri = Uri.parse(_currentStream.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch external player')),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Speed dialog
  // ─────────────────────────────────────────────────────────────────────────

  void _showSpeedDialog() {
    _onUserInteraction();
    showDialog<double>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Playback Speed', style: TextStyle(color: Colors.white)),
        children: _speeds
            .asMap()
            .entries
            .map(
              (entry) {
                final s = entry.value;
                final isCurrent = (s - _playbackSpeed).abs() < 0.01;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: TvFocusable(
                    autofocus: isCurrent,
                    borderRadius: 8,
                    scaleFactor: 1.04,
                    onTap: () => Navigator.pop(ctx, s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isCurrent ? const Color(0x33E50914) : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isCurrent ? Icons.check : Icons.speed,
                            color: isCurrent ? _accentRed : Colors.white70,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${s}x',
                            style: TextStyle(
                              color: isCurrent ? _accentRed : Colors.white,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            )
            .toList(),
      ),
    ).then((val) {
      if (val != null) _setSpeed(val);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Resolution bottom sheet
  // ─────────────────────────────────────────────────────────────────────────

  void _showResolutionSheet() {
    _onUserInteraction();
    showModalBottomSheet<StreamOption>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Select Quality',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...widget.availableStreams.asMap().entries.map(
              (entry) {
                final i = entry.key;
                final s = entry.value;
                final isSelected = s.url == _currentStream.url;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TvFocusable(
                    autofocus: isSelected || (i == 0 && !widget.availableStreams.any((x) => x.url == _currentStream.url)),
                    borderRadius: 8,
                    scaleFactor: 1.03,
                    onTap: () => Navigator.pop(ctx, s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0x33E50914) : const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Text(
                            s.resolution,
                            style: TextStyle(
                              color: isSelected ? _accentRed : Colors.white,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              s.kind.toUpperCase(),
                              style: const TextStyle(color: Colors.white70, fontSize: 10),
                            ),
                          ),
                          const Spacer(),
                          if (s.sizeMb != null)
                            Text('${s.sizeMb} MB', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.check, color: _accentRed, size: 18),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ).then((selected) {
      if (selected != null && selected.url != _currentStream.url) {
        final savedPos = _controller?.value.position;
        setState(() => _currentStream = selected);
        _initPlayer(seekTo: savedPos);
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Format helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Audio & Language bottom sheet
  // ─────────────────────────────────────────────────────────────────────────

  void _showLanguageSheet() {
    _onUserInteraction();
    final baseTitle = widget.title.replaceAll(RegExp(r'\[.*?\]'), '').trim();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return FutureBuilder<List<MediaItem>>(
          future: MovieBoxApi.instance.search(baseTitle),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(40.0),
                child: Center(
                  child: CircularProgressIndicator(color: _accentRed),
                ),
              );
            }
            final allResults = snapshot.data ?? [];
            final langItems = allResults.where((item) {
              final t = item.title.toLowerCase();
              final b = baseTitle.toLowerCase();
              return t.contains(b) || b.contains(t);
            }).toList();

            if (langItems.isEmpty) {
              langItems.add(MediaItem(id: widget.subjectId, title: widget.title));
            }

            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.translate, color: _accentRed, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Audio & Language',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Select audio / dub edition:',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: langItems.length,
                      itemBuilder: (context, index) {
                        final item = langItems[index];
                        final isCurrent = item.id == widget.subjectId;
                        String langLabel = 'Original / English';
                        final lowerTitle = item.title.toLowerCase();
                        if (lowerTitle.contains('hindi')) {
                          langLabel = 'Hindi Dub';
                        } else if (lowerTitle.contains('tamil')) {
                          langLabel = 'Tamil Dub';
                        } else if (lowerTitle.contains('telugu')) {
                          langLabel = 'Telugu Dub';
                        } else if (lowerTitle.contains('spanish')) {
                          langLabel = 'Spanish Dub';
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6.0),
                          child: TvFocusable(
                            autofocus: isCurrent || index == 0,
                            borderRadius: 8,
                            scaleFactor: 1.03,
                            onTap: () {
                              Navigator.pop(ctx);
                              if (!isCurrent) {
                                _switchLanguage(item);
                              }
                            },
                            child: Card(
                              color: isCurrent
                                  ? const Color(0xFF2E1A1A)
                                  : const Color(0xFF2A2A2A),
                              margin: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isCurrent ? _accentRed : Colors.transparent,
                                ),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  isCurrent ? Icons.check_circle : Icons.audiotrack,
                                  color: isCurrent ? _accentRed : Colors.white54,
                                ),
                                title: Text(
                                  langLabel,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: isCurrent
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Text(
                                  item.title,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _switchLanguage(MediaItem item) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Switching audio to ${item.title}...')),
    );
    try {
      final savedPos = _controller?.value.position;
      final newStreams = await MovieBoxApi.instance.getStreams(
        item.id,
        season: widget.season,
        episode: widget.episode,
      );
      if (newStreams.isNotEmpty && mounted) {
        setState(() {
          _currentStream = newStreams.first;
        });
        await _initPlayer(seekTo: savedPos);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Playing in ${item.title}')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No streams found for this language edition.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to switch audio: $e')),
        );
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // Dedicated hardware media playback keys always handle directly:
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      _togglePlayPause();
      _onUserInteraction();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.mediaRewind) {
      _doubleTapSeek(forward: false);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.mediaFastForward) {
      _doubleTapSeek(forward: true);
      return KeyEventResult.handled;
    }

    // When controls are hidden: direct D-pad playback actions
    if (!_showControls) {
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.gameButtonA) {
        _showControlsOverlay();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.arrowLeft) {
        _doubleTapSeek(forward: false);
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.arrowRight) {
        _doubleTapSeek(forward: true);
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
        _showControlsOverlay();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
        _saveProgress();
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }

      return KeyEventResult.ignored;
    }

    // When controls ARE visible:
    _resetHideTimer();

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      setState(() => _showControls = false);
      return KeyEventResult.handled;
    }

    // Allow D-pad arrows, select, enter to navigate and click focusable overlay buttons
    return KeyEventResult.ignored;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_showControls) {
            setState(() => _showControls = false);
          } else {
            _saveProgress();
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Video ────────────────────────────────────────────────────
                _buildVideoSurface(),

                // ── Double-tap zones ─────────────────────────────────────────
                _buildDoubleTapZones(),

                // ── Ripple icons ─────────────────────────────────────────────
                _buildRippleOverlays(),

                // ── Buffering indicator ──────────────────────────────────────
                if (_isBuffering && !_isInitializing)
                  const Center(
                    child: CircularProgressIndicator(color: _accentRed),
                  ),

                // ── Error view ───────────────────────────────────────────────
                if (_hasError) _buildErrorView(),

                // ── Overlay controls ─────────────────────────────────────────
                if (!_hasError) _buildOverlay(),

                // ── Resume badge overlay ─────────────────────────────────────
                if (_resumeBannerText != null)
                  Positioned(
                    top: 24,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xE6E50914),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.history, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              _resumeBannerText!,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Video surface ──────────────────────────────────────────────────────

  Widget _buildVideoSurface() {
    if (_isInitializing) {
      return const Center(
        child: CircularProgressIndicator(color: _accentRed),
      );
    }
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return FittedBox(
      fit: _boxFit,
      child: SizedBox(
        width: ctrl.value.size.width,
        height: ctrl.value.size.height,
        child: RepaintBoundary(child: VideoPlayer(ctrl)),
      ),
    );
  }

  // ── Double-tap zones ───────────────────────────────────────────────────

  Widget _buildDoubleTapZones() {
    // CRITICAL 1 — screen lock must block seek gestures
    if (_isLocked) return const SizedBox.shrink();
    return Row(

      children: [
        // Left third — rewind
        Expanded(
          flex: 1,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleControls,
            onDoubleTap: () => _doubleTapSeek(forward: false),
          ),
        ),
        // Center third — toggle
        Expanded(
          flex: 1,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleControls,
          ),
        ),
        // Right third — forward
        Expanded(
          flex: 1,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleControls,
            onDoubleTap: () => _doubleTapSeek(forward: true),
          ),
        ),
      ],
    );
  }

  // ── Ripple overlays ────────────────────────────────────────────────────

  Widget _buildRippleOverlays() {
    // IMPORTANT 2 — ripple must not absorb touch events during animation
    return IgnorePointer(
      child: Row(
        children: [
          // Left ripple
          Expanded(
            flex: 1,
            child: AnimatedOpacity(
              opacity: _showRewindRipple ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                color: Colors.white10,
                child: const Center(
                  child: Icon(Icons.replay_10, color: Colors.white, size: 56),
                ),
              ),
            ),
          ),
          const Spacer(),
          // Right ripple
          Expanded(
            flex: 1,
            child: AnimatedOpacity(
              opacity: _showForwardRipple ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                color: Colors.white10,
                child: const Center(
                  child: Icon(Icons.forward_10, color: Colors.white, size: 56),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Error view ─────────────────────────────────────────────────────────

  Widget _buildErrorView() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: _accentRed, size: 56),
          const SizedBox(height: 16),
          Text(
            'Playback Error\n$_errorMessage',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentRed,
              foregroundColor: Colors.white,
            ),
            onPressed: _openExternal,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open in External Player'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Go Back', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  // ── Overlay wrapper ────────────────────────────────────────────────────

  Widget _buildOverlay() {
    if (_isLocked) return _buildLockedOverlay();
    if (!_showControls) return const SizedBox.shrink();
    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleControls,
            child: const SizedBox.expand(),
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  // ── Locked overlay ─────────────────────────────────────────────────────

  Widget _buildLockedOverlay() {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: GestureDetector(
          onTap: () {
            setState(() => _isLocked = false);
            _resetHideTimer();
          },
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, color: Colors.white, size: 24),
                SizedBox(height: 4),
                Text('Unlock', style: TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final epLabel = widget.isSeries && widget.season > 0
        ? 'S${widget.season} E${widget.episode}'
            '${widget.episodeTitle != null ? ' · ${widget.episodeTitle}' : ''}'
        : null;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          TvFocusable(
            borderRadius: 20,
            scaleFactor: 1.1,
            onTap: () {
              _saveProgress();
              Navigator.pop(context);
            },
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (epLabel != null)
                  Text(
                    epLabel,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
          // External player
          TvFocusable(
            borderRadius: 20,
            scaleFactor: 1.1,
            onTap: _openExternal,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.open_in_new, color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          // Screen lock
          TvFocusable(
            borderRadius: 20,
            scaleFactor: 1.1,
            onTap: () {
              setState(() => _isLocked = true);
              _hideTimer?.cancel();
            },
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.lock_open, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    final pos = _position;
    final dur = _duration;
    final fraction =
        dur.inMilliseconds > 0 ? pos.inMilliseconds / dur.inMilliseconds : 0.0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black, Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Scrubber row
          Row(
            children: [
              Text(
                _fmt(pos),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: _accentRed,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: _accentRed,
                    overlayColor: _accentRed.withValues(alpha: 0.2),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: (_dragValue ?? fraction).clamp(0.0, 1.0),
                    onChangeStart: (_) {
                      _onUserInteraction();
                      setState(() => _dragValue = fraction.clamp(0.0, 1.0));
                    },
                    onChanged: (val) {
                      setState(() => _dragValue = val);
                    },
                    onChangeEnd: (val) {
                      setState(() => _dragValue = null);
                      _controller?.seekTo(
                        Duration(milliseconds: (val * _duration.inMilliseconds).round()),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _fmt(dur),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 2: Control buttons row
          Row(
            children: [
              // Rewind 10s
              TvFocusable(
                borderRadius: 20,
                scaleFactor: 1.08,
                onTap: () {
                  _onUserInteraction();
                  _seekRelative(-_seekAmount);
                },
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: const BoxDecoration(
                    color: Colors.white12,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.replay_10, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 10),
              // Play/Pause (Primary focus node)
              TvFocusable(
                focusNode: _playPauseFocusNode,
                autofocus: true,
                borderRadius: 24,
                scaleFactor: 1.1,
                onTap: _togglePlayPause,
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: const BoxDecoration(
                    color: _accentRed,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x66E50914),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Fast-forward 10s
              TvFocusable(
                borderRadius: 20,
                scaleFactor: 1.08,
                onTap: () {
                  _onUserInteraction();
                  _seekRelative(_seekAmount);
                },
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: const BoxDecoration(
                    color: Colors.white12,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.forward_10, color: Colors.white, size: 20),
                ),
              ),
              const Spacer(),
              // Audio & Language button
              TvFocusable(
                borderRadius: 4,
                scaleFactor: 1.06,
                onTap: _showLanguageSheet,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.translate, color: Colors.white70, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Audio/Lang',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Quality badge
              TvFocusable(
                borderRadius: 4,
                scaleFactor: 1.06,
                onTap: _showResolutionSheet,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _currentStream.resolution,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Speed button
              TvFocusable(
                borderRadius: 4,
                scaleFactor: 1.06,
                onTap: _showSpeedDialog,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_playbackSpeed}x',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Aspect ratio button
              TvFocusable(
                borderRadius: 4,
                scaleFactor: 1.06,
                onTap: _cycleAspectRatio,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _fitLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
              // Next episode button (series only)
              if (widget.isSeries) ...[
                const SizedBox(width: 8),
                TvFocusable(
                  borderRadius: 4,
                  scaleFactor: 1.06,
                  onTap: () {
                    _saveProgress();
                    Navigator.pop(context, 'next');
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: _accentRed.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Next',
                            style:
                                TextStyle(color: Colors.white, fontSize: 11)),
                        SizedBox(width: 4),
                        Icon(Icons.skip_next, color: Colors.white, size: 14),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}
