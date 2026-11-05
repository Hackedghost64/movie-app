import 'package:flutter/material.dart';
import '../models/media_models.dart';
import '../models/storage_models.dart';
import '../services/storage_service.dart';
import '../services/local_stream_relay.dart';
import '../screens/netflix_player_screen.dart';

/// Middleman Coordinator bridging UI playback buttons/screens with the player and persistence services.
class PlaybackCoordinator {
  static final PlaybackCoordinator instance = PlaybackCoordinator._();
  PlaybackCoordinator._();

  final StorageService _storage = StorageService();

  Future<void> init() async {
    await _storage.init();
  }

  StreamOption prepareStreamForPlayback(StreamOption option) {
    if (option.kind == 'dash' &&
        !option.url.startsWith('http://127.0.0.1') &&
        !option.url.startsWith('/')) {
      final relayed = LocalStreamRelay.instance.getRelayUrl(
        url: option.url,
        cookie: option.cookie,
        kind: 'dash',
      );
      return StreamOption(
        url: relayed,
        kind: 'dash',
        resolution: option.resolution,
        sizeMb: option.sizeMb,
        durationSeconds: option.durationSeconds,
        cookie: option.cookie,
        bypassedDecoy: option.bypassedDecoy,
      );
    }
    return option;
  }

  Future<void> recordProgress({
    required String subjectId,
    required String title,
    String? poster,
    int season = 0,
    int episode = 0,
    String? episodeTitle,
    required int positionMs,
    required int durationMs,
  }) async {
    if (durationMs <= 0) return;
    final item = WatchProgress(
      subjectId: subjectId,
      title: title,
      poster: poster,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
      positionMs: positionMs,
      durationMs: durationMs,
      lastWatchedMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _storage.saveWatchProgress(item);
  }

  WatchProgress? getResumeProgress(String subjectId) {
    return _storage.getWatchProgress(subjectId);
  }

  void launchPlayer(
    BuildContext context, {
    required String subjectId,
    required String title,
    String? poster,
    int season = 0,
    int episode = 0,
    String? episodeTitle,
    required StreamOption stream,
    List<StreamOption> availableStreams = const [],
    bool isSeries = false,
    Duration? initialPosition,
  }) {
    final preparedStream = prepareStreamForPlayback(stream);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NetflixPlayerScreen(
          subjectId: subjectId,
          title: title,
          poster: poster,
          season: season,
          episode: episode,
          episodeTitle: episodeTitle,
          stream: preparedStream,
          availableStreams: availableStreams,
          isSeries: isSeries,
          initialPosition: initialPosition,
        ),
      ),
    );
  }

  void launchOfflinePlayer(
    BuildContext context, {
    required DownloadTask task,
  }) {
    final kind = task.filePath.endsWith('.mpd')
        ? 'dash'
        : (task.filePath.endsWith('.m3u8') ? 'hls' : 'mp4');

    launchPlayer(
      context,
      subjectId: task.id,
      title: task.title,
      season: 0,
      episode: 0,
      stream: StreamOption(
        url: task.filePath,
        kind: kind,
        resolution: 'Offline',
        bypassedDecoy: true,
      ),
      availableStreams: const [],
      isSeries: false,
    );
  }
}
