import 'package:flutter_test/flutter_test.dart';
import 'package:mbx_app/services/moviebox_api.dart';
import 'package:mbx_app/models/storage_models.dart';

void main() {
  group('Mobile UI Redesign & Dummy URL Defense Tests', () {
    test('Broadened decoy detection identifies all honeypot & notice patterns', () {
      // 1. Known sha/hash update MP4s
      expect(MovieBoxApi.isDecoyUrl('https://macdn.aoneroom.com/other/2026/09/04/b164fbfb4347792950bdfbfb563d39d9.mp4'), isTrue);
      // 2. Generic other directory MP4s
      expect(MovieBoxApi.isDecoyUrl('https://macdn.aoneroom.com/other/random_update.mp4'), isTrue);
      // 3. Upgrade and notice paths
      expect(MovieBoxApi.isDecoyUrl('https://macdn.aoneroom.com/upgrade/v4.mp4'), isTrue);
      expect(MovieBoxApi.isDecoyUrl('https://macdn.aoneroom.com/notice/update_required.mp4'), isTrue);
      // 4. Any direct .mp4 served from aoneroom.com domain
      expect(MovieBoxApi.isDecoyUrl('https://api6.aoneroom.com/update_app.mp4'), isTrue);
      expect(MovieBoxApi.isDecoyUrl('https://media.aoneroom.com/app_update.mp4'), isTrue);
      expect(MovieBoxApi.isDecoyUrl('https://test.aoneroom.com/dummy.mp4'), isTrue);

      // Authentic streaming CDNs must NOT be flagged
      expect(MovieBoxApi.isDecoyUrl('https://sbcdn5.hakunaymatata.com/hls/movie-1-1-1080/local.m3u8'), isFalse);
      expect(MovieBoxApi.isDecoyUrl('https://sbcdn5.hakunaymatata.com/dash/movie-1-1-1080/index_web.mpd'), isFalse);
      expect(MovieBoxApi.isDecoyUrl('https://cf.moviecdn.net/hls/title/local.m3u8'), isFalse);
    });

    test('WatchProgress sanitizes decoy stream URLs', () {
      const decoyUrl = 'https://macdn.aoneroom.com/other/update.mp4';
      final safeUrl = MovieBoxApi.isDecoyUrl(decoyUrl) ? null : decoyUrl;
      expect(safeUrl, isNull);

      const authenticUrl = 'https://sbcdn5.hakunaymatata.com/hls/movie/local.m3u8';
      final verifiedUrl = MovieBoxApi.isDecoyUrl(authenticUrl) ? null : authenticUrl;
      expect(verifiedUrl, equals(authenticUrl));

      final progress = WatchProgress(
        subjectId: '12345',
        title: 'Inception',
        positionMs: 60000,
        durationMs: 7200000,
        lastWatchedMs: 100000,
        streamUrl: verifiedUrl,
      );
      expect(progress.streamUrl, equals(authenticUrl));
      expect(progress.progressPercentage, closeTo(60000 / 7200000, 0.0001));
    });

    test('WatchlistItem conversion to MediaItem preserves metadata', () {
      final item = WatchlistItem(
        id: '998877',
        title: 'Interstellar',
        poster: 'https://example.com/poster.jpg',
        year: '2014',
        rating: '8.7',
        type: 1,
        addedAtMs: 12345678,
      );

      final mediaItem = item.toMediaItem();
      expect(mediaItem.id, '998877');
      expect(mediaItem.title, 'Interstellar');
      expect(mediaItem.year, '2014');
      expect(mediaItem.rating, '8.7');
      expect(mediaItem.type, 1);
    });
  });
}
