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
}
