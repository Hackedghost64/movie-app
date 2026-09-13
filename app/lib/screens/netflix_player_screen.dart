import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/media_models.dart';
import '../models/storage_models.dart';
import '../services/storage_service.dart';

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

  const NetflixPlayerScreen({
    super.key,
    required this.subjectId,
    required this.title,
    required this.poster,
    required this.season,
    required this.episode,
    this.episodeTitle,
    required this.stream,
    required this.availableStreams,
    required this.isSeries,
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

  // ── Playback speed ────────────────────────────────────────────────────────
  double _playbackSpeed = 1.0;
  static const List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // ── Aspect ratio ─────────────────────────────────────────────────────────
  BoxFit _boxFit = BoxFit.contain;
  static const List<BoxFit> _fits = [BoxFit.contain, BoxFit.fill, BoxFit.cover];

  // ── Double-tap ripple ─────────────────────────────────────────────────────
  bool _showRewindRipple = false;
  bool _showForwardRipple = false;
  Timer? _rippleTimer;

  // ── Auto-save timer ───────────────────────────────────────────────────────
  Timer? _saveTimer;
  bool _saveTimerStarted = false;

  // ── Constants ─────────────────────────────────────────────────────────────
  static const _accentRed = Color(0xFFE50914);
  static const _overlayBg = Colors.black54;
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
    // Force landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initPlayer();
    _resetHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _rippleTimer?.cancel();
    _saveTimer?.cancel();
    _controller?.removeListener(_onVideoEvent);
    _controller?.dispose();
    // Restore UI
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Player initialisation
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initPlayer() async {
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

      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(_currentStream.url),
        httpHeaders: headers,
      );
      _controller = ctrl;
      ctrl.addListener(_onVideoEvent);

      await ctrl.initialize();
      await ctrl.setPlaybackSpeed(_playbackSpeed);
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
    setState(() {});

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

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _resetHideTimer();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onUserInteraction() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _resetHideTimer();
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

  void _seekTo(double fraction) {
    final ctrl = _controller;
    if (ctrl == null) return;
    final ms = (ctrl.value.duration.inMilliseconds * fraction).toInt();
    ctrl.seekTo(Duration(milliseconds: ms));
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
    _onUserInteraction();
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
            .map(
              (s) => SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(ctx, s);
                },
                child: Row(
                  children: [
                    if (s == _playbackSpeed)
                      const Icon(Icons.check, color: _accentRed, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text(
                      '${s}x',
                      style: TextStyle(
                        color: s == _playbackSpeed ? _accentRed : Colors.white,
                        fontWeight: s == _playbackSpeed
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
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
            ...widget.availableStreams.map(
              (s) => ListTile(
                title: Row(
                  children: [
                    Text(
                      s.resolution,
                      style: TextStyle(
                        color: s.url == _currentStream.url
                            ? _accentRed
                            : Colors.white,
                        fontWeight: s.url == _currentStream.url
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        s.kind.toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 10),
                      ),
                    ),
                  ],
                ),
                subtitle: s.sizeMb != null
                    ? Text('${s.sizeMb} MB',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12))
                    : null,
                trailing: s.url == _currentStream.url
                    ? const Icon(Icons.check, color: _accentRed)
                    : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
            ),
          ],
        ),
      ),
    ).then((selected) {
      if (selected != null && selected.url != _currentStream.url) {
        setState(() => _currentStream = selected);
        _initPlayer();
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

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          ],
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
        child: VideoPlayer(ctrl),
      ),
    );
  }

  // ── Double-tap zones ───────────────────────────────────────────────────

  Widget _buildDoubleTapZones() {
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
    return Row(
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
    return Container(
      color: _overlayBg,
      child: Column(
        children: [
          _buildTopBar(),
          const Spacer(),
          _buildCenterRow(),
          const Spacer(),
          _buildBottomBar(),
        ],
      ),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              _saveProgress();
              Navigator.pop(context);
            },
          ),
          const SizedBox(width: 4),
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
          IconButton(
            tooltip: 'Open in external player',
            icon: const Icon(Icons.open_in_new, color: Colors.white),
            onPressed: _openExternal,
          ),
          // Screen lock
          IconButton(
            tooltip: 'Lock screen',
            icon: const Icon(Icons.lock_open, color: Colors.white),
            onPressed: () {
              setState(() => _isLocked = true);
              _hideTimer?.cancel();
            },
          ),
        ],
      ),
    );
  }

  // ── Center row ─────────────────────────────────────────────────────────

  Widget _buildCenterRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // -10s
        IconButton(
          icon: const Icon(Icons.replay_10, color: Colors.white, size: 40),
          onPressed: () {
            _onUserInteraction();
            _seekRelative(-_seekAmount);
          },
        ),
        const SizedBox(width: 24),
        // Play / Pause
        GestureDetector(
          onTap: _togglePlayPause,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(12),
            child: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 56,
            ),
          ),
        ),
        const SizedBox(width: 24),
        // +10s
        IconButton(
          icon: const Icon(Icons.forward_10, color: Colors.white, size: 40),
          onPressed: () {
            _onUserInteraction();
            _seekRelative(_seekAmount);
          },
        ),
      ],
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    final pos = _position;
    final dur = _duration;
    final fraction =
        dur.inMilliseconds > 0 ? pos.inMilliseconds / dur.inMilliseconds : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _accentRed,
              inactiveTrackColor: Colors.white30,
              thumbColor: _accentRed,
              overlayColor: _accentRed.withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              trackHeight: 3,
            ),
            child: Slider(
              value: fraction.clamp(0.0, 1.0),
              onChanged: (val) {
                _onUserInteraction();
                _seekTo(val);
              },
            ),
          ),
          // Time + controls row
          Row(
            children: [
              // Elapsed
              Text(
                _fmt(pos),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 4),
              const Text('|', style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(width: 4),
              // Total
              Text(
                _fmt(dur),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const Spacer(),
              // Quality badge
              GestureDetector(
                onTap: _showResolutionSheet,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              GestureDetector(
                onTap: _showSpeedDialog,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              GestureDetector(
                onTap: _cycleAspectRatio,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                GestureDetector(
                  onTap: () {
                    _saveProgress();
                    Navigator.pop(context, 'next');
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
