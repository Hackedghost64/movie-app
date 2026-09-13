// app/test/storage_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbx_app/models/storage_models.dart';
import 'package:mbx_app/models/media_models.dart';
import 'package:mbx_app/services/storage_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Save and retrieve watch progress', () async {
    final storage = StorageService();
    await storage.init();

    final item = WatchProgress(
      subjectId: '12345',
      title: 'Spider-Man',
      poster: 'https://image.url',
      season: 0,
      episode: 0,
      positionMs: 60000,
      durationMs: 120000,
      lastWatchedMs: DateTime.now().millisecondsSinceEpoch,
    );

    await storage.saveWatchProgress(item);
    final retrieved = storage.getWatchProgress('12345');
    expect(retrieved, isNotNull);
    expect(retrieved!.title, 'Spider-Man');
    expect(retrieved.progressPercentage, closeTo(0.5, 0.01));
  });

  test('Toggle and retrieve watchlist item', () async {
    final storage = StorageService();
    await storage.init();

    final media = MediaItem(
      id: '999',
      title: 'Batman',
      poster: 'https://poster.url',
      year: '2022',
      type: 1,
    );

    expect(storage.isInWatchlist('999'), isFalse);
    final added = await storage.toggleWatchlist(media);
    expect(added, isTrue);
    expect(storage.isInWatchlist('999'), isTrue);

    final list = storage.getWatchlist();
    expect(list.length, 1);
    expect(list.first.title, 'Batman');

    final removed = await storage.toggleWatchlist(media);
    expect(removed, isFalse);
    expect(storage.isInWatchlist('999'), isFalse);
  });

  test('WatchProgress.progressPercentage returns 0.0 when durationMs is 0', () {
    final progress = WatchProgress(
      subjectId: '1',
      title: 'Zero Duration',
      durationMs: 0,
      positionMs: 100,
      lastWatchedMs: 1000,
    );
    expect(progress.progressPercentage, 0.0);
  });

  test('removeWatchProgress removes saved item and returns null on get', () async {
    final storage = StorageService();
    await storage.init();

    final item = WatchProgress(
      subjectId: '123',
      title: 'Test Movie',
      lastWatchedMs: 1000,
    );
    await storage.saveWatchProgress(item);
    expect(storage.getWatchProgress('123'), isNotNull);

    await storage.removeWatchProgress('123');
    expect(storage.getWatchProgress('123'), isNull);
  });

  test('removeWatchlist removes item from watchlist', () async {
    final storage = StorageService();
    await storage.init();

    final media = MediaItem(
      id: '888',
      title: 'Inception',
      poster: 'https://poster.url',
      year: '2010',
      type: 1,
    );

    await storage.toggleWatchlist(media);
    expect(storage.isInWatchlist('888'), isTrue);

    await storage.removeWatchlist('888');
    expect(storage.isInWatchlist('888'), isFalse);
    expect(storage.getWatchlist(), isEmpty);
  });

  test('getAllWatchProgress sorts items descending by lastWatchedMs', () async {
    final storage = StorageService();
    await storage.init();

    final older = WatchProgress(
      subjectId: 'older_id',
      title: 'Older Movie',
      lastWatchedMs: 1000,
    );
    final newer = WatchProgress(
      subjectId: 'newer_id',
      title: 'Newer Movie',
      lastWatchedMs: 2000,
    );

    await storage.saveWatchProgress(older);
    await storage.saveWatchProgress(newer);

    final all = storage.getAllWatchProgress();
    expect(all.length, 2);
    expect(all[0].subjectId, 'newer_id');
    expect(all[1].subjectId, 'older_id');
  });

  test('Persistence across instances', () async {
    final storage1 = StorageService();
    await storage1.init();

    final progress = WatchProgress(
      subjectId: 'persist_1',
      title: 'Persisted Movie',
      lastWatchedMs: 5000,
    );
    final media = MediaItem(
      id: 'persist_2',
      title: 'Persisted Series',
      type: 2,
    );

    await storage1.saveWatchProgress(progress);
    await storage1.toggleWatchlist(media);

    final storage2 = StorageService();
    await storage2.init();

    final retrievedProgress = storage2.getWatchProgress('persist_1');
    expect(retrievedProgress, isNotNull);
    expect(retrievedProgress!.title, 'Persisted Movie');
    expect(storage2.isInWatchlist('persist_2'), isTrue);
  });

  test('Defensive Map deserialization handles dynamic decoded JSON maps', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mbx_watch_progress_v1',
        '{"123": {"subjectId": "123", "title": "Raw JSON Movie", "lastWatchedMs": 100}}');
    await prefs.setString('mbx_watchlist_v1',
        '{"456": {"id": "456", "title": "Raw JSON Item", "addedAtMs": 200}}');

    final storage = StorageService();
    await storage.init(prefs);

    expect(storage.getWatchProgress('123'), isNotNull);
    expect(storage.getWatchProgress('123')!.title, 'Raw JSON Movie');
    expect(storage.isInWatchlist('456'), isTrue);
  });
}
