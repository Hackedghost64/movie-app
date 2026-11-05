import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbx_app/models/media_models.dart';
import 'package:mbx_app/coordinators/download_coordinator.dart';
import 'package:mbx_app/coordinators/playback_coordinator.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DownloadCoordinator Tests (Middleman)', () {
    final coordinator = DownloadCoordinator.instance;

    test('generateTaskId produces predictable composite identifier', () {
      final id = coordinator.generateTaskId(
        subjectId: 'sub-404',
        season: 2,
        episode: 5,
        resolution: '1080p',
      );
      expect(id, equals('sub-404_2_5_1080p'));
    });

    test('formatDownloadTitle handles series and standalone movie titles', () {
      final movieTitle = coordinator.formatDownloadTitle(title: 'Interstellar');
      expect(movieTitle, equals('Interstellar'));

      final seriesTitle = coordinator.formatDownloadTitle(
        title: 'Breaking Bad',
        season: 1,
        episode: 2,
      );
      expect(seriesTitle, equals('Breaking Bad - S01E02'));

      final customEpTitle = coordinator.formatDownloadTitle(
        title: 'Severance',
        episodeTitle: 'Defiant Jazz',
        season: 1,
        episode: 7,
      );
      expect(customEpTitle, equals('Severance - Defiant Jazz'));
    });

    test('determineExtension routes stream kinds accurately', () {
      final dashOpt = StreamOption(
        url: 'https://cdn.example.com/stream/manifest.mpd',
        kind: 'dash',
        resolution: '1080p',
      );
      expect(coordinator.determineExtension(dashOpt), equals('mpd'));

      final hlsOpt = StreamOption(
        url: 'https://cdn.example.com/stream/playlist.m3u8',
        kind: 'hls',
        resolution: '720p',
      );
      expect(coordinator.determineExtension(hlsOpt), equals('m3u8'));

      final mp4Opt = StreamOption(
        url: 'https://cdn.example.com/stream/feature.mp4',
        kind: 'mp4',
        resolution: '1080p',
      );
      expect(coordinator.determineExtension(mp4Opt), equals('mp4'));
    });
  });

  group('PlaybackCoordinator Tests (Middleman)', () {
    final coordinator = PlaybackCoordinator.instance;

    test('prepareStreamForPlayback preserves standard MP4 and HLS streams', () {
      final mp4 = StreamOption(
        url: 'https://cdn.example.com/movie.mp4',
        kind: 'mp4',
        resolution: '1080p',
      );
      final preparedMp4 = coordinator.prepareStreamForPlayback(mp4);
      expect(preparedMp4.url, equals('https://cdn.example.com/movie.mp4'));
      expect(preparedMp4.kind, equals('mp4'));

      final hls = StreamOption(
        url: 'https://cdn.example.com/playlist.m3u8',
        kind: 'hls',
        resolution: '720p',
      );
      final preparedHls = coordinator.prepareStreamForPlayback(hls);
      expect(preparedHls.url, equals('https://cdn.example.com/playlist.m3u8'));
    });

    test('recordProgress and getResumeProgress roundtrip through storage', () async {
      await coordinator.init();

      await coordinator.recordProgress(
        subjectId: 'sub-789',
        title: 'The Dark Knight',
        poster: 'https://cdn.example.com/poster.jpg',
        positionMs: 45000,
        durationMs: 90000,
      );

      final progress = coordinator.getResumeProgress('sub-789');
      expect(progress, isNotNull);
      expect(progress!.title, equals('The Dark Knight'));
      expect(progress.positionMs, equals(45000));
      expect(progress.durationMs, equals(90000));
      expect(progress.progressPercentage, closeTo(0.5, 0.01));
    });
  });
}
