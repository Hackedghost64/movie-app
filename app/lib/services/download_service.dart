import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../models/media_models.dart';

class DownloadService extends ChangeNotifier {
  static final DownloadService instance = DownloadService._();
  DownloadService._();

  final List<DownloadTask> _tasks = [];
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  Future<String> _getDownloadDir() async {
    Directory? dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download/MBX');
      if (!await dir.exists()) {
        try {
          await dir.create(recursive: true);
        } catch (_) {
          dir = await getExternalStorageDirectory();
        }
      }
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
    return dir?.path ?? (await getApplicationDocumentsDirectory()).path;
  }

  Future<void> startDownload({
    required String id,
    required String title,
    required String url,
    String? cookie,
    String ext = "mp4",
  }) async {
    final sanitizedTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final dirPath = await _getDownloadDir();
    final filePath = '$dirPath/$sanitizedTitle.$ext';

    final task = DownloadTask(
      id: id,
      title: title,
      filePath: filePath,
    );
    _tasks.insert(0, task);
    notifyListeners();

    try {
      final request = http.Request('GET', Uri.parse(url));
      if (cookie != null && cookie.isNotEmpty) {
        request.headers['Cookie'] = cookie;
      }
      request.headers['User-Agent'] = 'Mozilla/5.0 (Android; Mobile; rv:109.0) Gecko/109.0 Firefox/118.0';

      final client = http.Client();
      final response = await client.send(request);

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;

      final file = File(filePath);
      final sink = file.openWrite();

      await for (var chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          task.progress = receivedBytes / totalBytes;
          task.status = '${(task.progress * 100).toStringAsFixed(1)}% (${(receivedBytes / 1048576).toStringAsFixed(1)} MB / ${(totalBytes / 1048576).toStringAsFixed(1)} MB)';
        } else {
          task.status = '${(receivedBytes / 1048576).toStringAsFixed(1)} MB downloaded';
        }
        notifyListeners();
      }

      await sink.close();
      client.close();

      task.isCompleted = true;
      task.progress = 1.0;
      task.status = 'Completed';
      notifyListeners();
    } catch (e) {
      task.status = 'Failed: $e';
      notifyListeners();
    }
  }

  Future<void> openFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await OpenFilex.open(filePath);
    }
  }
}
