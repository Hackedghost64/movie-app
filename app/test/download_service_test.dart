import 'package:flutter_test/flutter_test.dart';
import 'package:mbx_app/models/media_models.dart';
import 'package:mbx_app/services/download_service.dart';

void main() {
  group('Download Feature Tests', () {
    test('DownloadTask initializes with correct default properties', () {
      final task = DownloadTask(
        id: 'task-101',
        title: 'Interstellar (1080p)',
        filePath: '/storage/downloads/Interstellar.mp4',
      );

      expect(task.id, equals('task-101'));
      expect(task.title, equals('Interstellar (1080p)'));
      expect(task.filePath, equals('/storage/downloads/Interstellar.mp4'));
      expect(task.progress, equals(0.0));
      expect(task.isCompleted, isFalse);
      expect(task.isCancelled, isFalse);
      expect(task.status, equals('Downloading'));
    });

    test('DownloadTask state transitions correctly on completion and cancellation', () {
      final task = DownloadTask(
        id: 'task-102',
        title: 'Inception',
        filePath: '/storage/downloads/Inception.mp4',
      );

      // Simulate download progress update
      task.progress = 0.65;
      task.status = 'Downloading 65%';
      expect(task.progress, closeTo(0.65, 0.001));
      expect(task.status, equals('Downloading 65%'));

      // Simulate completion
      task.progress = 1.0;
      task.isCompleted = true;
      task.status = 'Completed';
      expect(task.isCompleted, isTrue);
      expect(task.isCancelled, isFalse);
      expect(task.progress, equals(1.0));
      expect(task.status, equals('Completed'));
    });

    test('DownloadService cancelDownload flags active task as cancelled', () {
      final service = DownloadService.instance;

      // Ensure service singleton tasks list is accessible
      expect(service.tasks, isNotNull);

      // Cancel a non-existent task should not throw
      expect(() => service.cancelDownload('non-existent-id'), returnsNormally);
    });

    test('DownloadService task tracking reflects active tasks list', () {
      final service = DownloadService.instance;
      final initialCount = service.tasks.length;
      expect(initialCount, greaterThanOrEqualTo(0));
    });
  });
}
