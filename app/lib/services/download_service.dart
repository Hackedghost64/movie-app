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

  void cancelDownload(String id) {
    for (var task in _tasks) {
      if (task.id == id && !task.isCompleted) {
        task.isCancelled = true;
        task.status = 'Cancelled';
        notifyListeners();
        break;
      }
    }
  }

  Future<void> deleteDownload(String id) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx != -1) {
      final task = _tasks[idx];
      task.isCancelled = true;
      try {
        final f = File(task.filePath);
        if (await f.exists()) {
          await f.delete();
        }
        // If it was a DASH folder, delete parent dir if named after title
        final parent = f.parent;
        if (await parent.exists() && parent.path.endsWith(task.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_'))) {
          await parent.delete(recursive: true);
        }
      } catch (_) {}
      _tasks.removeAt(idx);
      notifyListeners();
    }
  }

  Future<void> startDownload({
    required String id,
    required String title,
    required String url,
    String? cookie,
    String ext = "mp4",
  }) async {
    // Avoid duplicate download tasks
    final existing = _tasks.where((t) => t.id == id).toList();
    if (existing.isNotEmpty && !existing.first.isCancelled && !existing.first.status.contains('Failed')) {
      return;
    }

    final sanitizedTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final dirPath = await _getDownloadDir();
    final defaultFilePath = '$dirPath/$sanitizedTitle.$ext';

    final task = DownloadTask(
      id: id,
      title: title,
      filePath: defaultFilePath,
    );
    _tasks.insert(0, task);
    notifyListeners();

    if (url.contains('.mpd')) {
      await _downloadDashStream(task, sanitizedTitle, dirPath, url, cookie);
    } else if (url.contains('.m3u8') || ext == 'm3u8') {
      await _downloadHlsStream(task, sanitizedTitle, dirPath, url, cookie);
    } else {
      await _downloadDirectStream(task, defaultFilePath, url, cookie);
    }
  }

  Future<void> _downloadDashStream(
    DownloadTask task,
    String sanitizedTitle,
    String baseDirPath,
    String mpdUrl,
    String? cookie,
  ) async {
    try {
      final client = http.Client();
      final headers = <String, String>{
        'User-Agent': 'Mozilla/5.0 (Android; Mobile; rv:109.0) Gecko/109.0 Firefox/118.0',
      };
      if (cookie != null && cookie.isNotEmpty) {
        headers['Cookie'] = cookie;
      }

      // Fetch MPD
      final mpdUri = Uri.parse(mpdUrl);
      final mpdResp = await client.get(mpdUri, headers: headers);
      if (mpdResp.statusCode < 200 || mpdResp.statusCode >= 300) {
        throw Exception('Failed to fetch DASH manifest: HTTP ${mpdResp.statusCode}');
      }

      final mpdText = mpdResp.body;
      final folderPath = '$baseDirPath/$sanitizedTitle';
      final folder = Directory(folderPath);
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      // Write local index_web.mpd
      final localMpdFile = File('$folderPath/index_web.mpd');
      await localMpdFile.writeAsString(mpdText);
      task.filePath = localMpdFile.path;

      // Base URL for chunks
      final lastSlash = mpdUrl.lastIndexOf('/');
      final baseUrl = lastSlash != -1 ? mpdUrl.substring(0, lastSlash + 1) : mpdUrl;

      // Parse duration and chunk count
      final durMatch = RegExp(r'mediaPresentationDuration="([^"]+)"').firstMatch(mpdText);
      double totalSeconds = 3000.0;
      if (durMatch != null) {
        totalSeconds = _parseIsoDuration(durMatch.group(1)!);
      }

      final timescaleMatch = RegExp(r'timescale="(\d+)"').firstMatch(mpdText);
      final durationMatch = RegExp(r'duration="(\d+)"').firstMatch(mpdText);
      double chunkSeconds = 5.0;
      if (timescaleMatch != null && durationMatch != null) {
        final ts = double.tryParse(timescaleMatch.group(1)!) ?? 1000000;
        final d = double.tryParse(durationMatch.group(1)!) ?? 5000000;
        chunkSeconds = d / ts;
      }

      final totalChunks = (totalSeconds / chunkSeconds).ceil();
      int totalBytesDownloaded = mpdResp.bodyBytes.length;

      // Download init segments
      final initVideo = File('$folderPath/init-stream0.m4s');
      if (!await initVideo.exists()) {
        final vInitResp = await client.get(Uri.parse('${baseUrl}init-stream0.m4s'), headers: headers);
        if (vInitResp.statusCode == 200) {
          await initVideo.writeAsBytes(vInitResp.bodyBytes);
          totalBytesDownloaded += vInitResp.bodyBytes.length;
        }
      }

      final initAudio = File('$folderPath/init-stream2.m4s');
      if (!await initAudio.exists()) {
        final aInitResp = await client.get(Uri.parse('${baseUrl}init-stream2.m4s'), headers: headers);
        if (aInitResp.statusCode == 200) {
          await initAudio.writeAsBytes(aInitResp.bodyBytes);
          totalBytesDownloaded += aInitResp.bodyBytes.length;
        }
      }

      int lastNotificationMs = 0;

      for (int i = 1; i <= totalChunks; i++) {
        if (task.isCancelled) {
          client.close();
          return;
        }

        final numStr = i.toString().padLeft(5, '0');
        final vChunkFile = File('$folderPath/chunk-stream0-$numStr.m4s');
        if (!await vChunkFile.exists()) {
          final vChunkResp = await client.get(Uri.parse('${baseUrl}chunk-stream0-$numStr.m4s'), headers: headers);
          if (vChunkResp.statusCode == 200) {
            await vChunkFile.writeAsBytes(vChunkResp.bodyBytes);
            totalBytesDownloaded += vChunkResp.bodyBytes.length;
          }
        }

        final aChunkFile = File('$folderPath/chunk-stream2-$numStr.m4s');
        if (!await aChunkFile.exists()) {
          final aChunkResp = await client.get(Uri.parse('${baseUrl}chunk-stream2-$numStr.m4s'), headers: headers);
          if (aChunkResp.statusCode == 200) {
            await aChunkFile.writeAsBytes(aChunkResp.bodyBytes);
            totalBytesDownloaded += aChunkResp.bodyBytes.length;
          }
        }

        task.progress = (i / totalChunks).clamp(0.0, 1.0);
        final mb = (totalBytesDownloaded / 1048576).toStringAsFixed(1);
        final pct = (task.progress * 100).toStringAsFixed(1);
        task.status = '$pct% ($mb MB) • Chunk $i/$totalChunks';

        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastNotificationMs > 250 || i == totalChunks) {
          lastNotificationMs = now;
          notifyListeners();
        }
      }

      client.close();
      task.isCompleted = true;
      task.progress = 1.0;
      final finalMb = (totalBytesDownloaded / 1048576).toStringAsFixed(1);
      task.status = 'Completed ($finalMb MB)';
      notifyListeners();
    } catch (e) {
      if (!task.isCancelled) {
        task.status = 'Failed: $e';
        notifyListeners();
      }
    }
  }

  Future<void> _downloadHlsStream(
    DownloadTask task,
    String sanitizedTitle,
    String baseDirPath,
    String m3u8Url,
    String? cookie,
  ) async {
    try {
      final client = http.Client();
      final headers = <String, String>{
        'User-Agent': 'Mozilla/5.0 (Android; Mobile; rv:109.0) Gecko/109.0 Firefox/118.0',
      };
      if (cookie != null && cookie.isNotEmpty) {
        headers['Cookie'] = cookie;
      }

      // Fetch M3U8 manifest
      var m3u8Uri = Uri.parse(m3u8Url);
      var m3u8Resp = await client.get(m3u8Uri, headers: headers);
      if (m3u8Resp.statusCode < 200 || m3u8Resp.statusCode >= 300) {
        throw Exception('Failed to fetch HLS playlist: HTTP ${m3u8Resp.statusCode}');
      }

      var playlistText = m3u8Resp.body;

      // Handle Master Playlist (multi-variant)
      if (playlistText.contains('#EXT-X-STREAM-INF')) {
        final lines = playlistText.split('\n');
        String? variantUrl;
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('#EXT-X-STREAM-INF') && i + 1 < lines.length) {
            final nextLine = lines[i + 1].trim();
            if (nextLine.isNotEmpty && !nextLine.startsWith('#')) {
              variantUrl = nextLine;
              break;
            }
          }
        }
        if (variantUrl != null) {
          m3u8Uri = m3u8Uri.resolve(variantUrl);
          m3u8Resp = await client.get(m3u8Uri, headers: headers);
          if (m3u8Resp.statusCode == 200) {
            playlistText = m3u8Resp.body;
          }
        }
      }

      final folderPath = '$baseDirPath/$sanitizedTitle';
      final folder = Directory(folderPath);
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      // Parse segments
      final lines = playlistText.split('\n');
      final segmentUris = <Uri>[];
      final rewrittenLines = <String>[];
      int segIndex = 0;

      for (var rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;

        if (line.startsWith('#')) {
          if (line.startsWith('#EXT-X-KEY:')) {
            final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
            if (uriMatch != null) {
              final keyUrl = uriMatch.group(1)!;
              final keyUri = m3u8Uri.resolve(keyUrl);
              try {
                final keyResp = await client.get(keyUri, headers: headers);
                if (keyResp.statusCode == 200) {
                  final keyFile = File('$folderPath/enc.key');
                  await keyFile.writeAsBytes(keyResp.bodyBytes);
                  rewrittenLines.add(line.replaceFirst(keyUrl, 'enc.key'));
                  continue;
                }
              } catch (_) {}
            }
          }
          rewrittenLines.add(line);
        } else {
          segIndex++;
          final segUri = m3u8Uri.resolve(line);
          segmentUris.add(segUri);
          final segName = 'segment_${segIndex.toString().padLeft(5, '0')}.ts';
          rewrittenLines.add(segName);
        }
      }

      if (segmentUris.isEmpty) {
        throw Exception('No playable segments discovered in HLS playlist');
      }

      // Save local playlist pointing to downloaded segments
      final localM3u8File = File('$folderPath/local.m3u8');
      await localM3u8File.writeAsString(rewrittenLines.join('\n'));
      task.filePath = localM3u8File.path;

      final totalSegments = segmentUris.length;
      int totalBytesDownloaded = 0;
      int lastNotificationMs = 0;

      for (int i = 0; i < totalSegments; i++) {
        if (task.isCancelled) {
          client.close();
          return;
        }

        final segName = 'segment_${(i + 1).toString().padLeft(5, '0')}.ts';
        final segFile = File('$folderPath/$segName');

        if (!await segFile.exists() || await segFile.length() == 0) {
          final segResp = await client.get(segmentUris[i], headers: headers);
          if (segResp.statusCode == 200) {
            await segFile.writeAsBytes(segResp.bodyBytes);
            totalBytesDownloaded += segResp.bodyBytes.length;
          } else {
            throw Exception('Segment ${i + 1} download failed: HTTP ${segResp.statusCode}');
          }
        } else {
          totalBytesDownloaded += await segFile.length();
        }

        task.progress = ((i + 1) / totalSegments).clamp(0.0, 1.0);
        final mb = (totalBytesDownloaded / 1048576).toStringAsFixed(1);
        final pct = (task.progress * 100).toStringAsFixed(1);
        task.status = '$pct% ($mb MB) • Segment ${i + 1}/$totalSegments';

        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastNotificationMs > 250 || i == totalSegments - 1) {
          lastNotificationMs = now;
          notifyListeners();
        }
      }

      client.close();
      task.isCompleted = true;
      task.progress = 1.0;
      final finalMb = (totalBytesDownloaded / 1048576).toStringAsFixed(1);
      task.status = 'Completed ($finalMb MB)';
      notifyListeners();
    } catch (e) {
      if (!task.isCancelled) {
        task.status = 'Failed: $e';
        notifyListeners();
      }
    }
  }

  Future<void> _downloadDirectStream(
    DownloadTask task,
    String filePath,
    String url,
    String? cookie,
  ) async {
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
      int lastNotificationMs = 0;

      await for (var chunk in response.stream) {
        if (task.isCancelled) {
          await sink.close();
          client.close();
          if (await file.exists()) await file.delete();
          return;
        }

        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          task.progress = receivedBytes / totalBytes;
          task.status = '${(task.progress * 100).toStringAsFixed(1)}% (${(receivedBytes / 1048576).toStringAsFixed(1)} MB / ${(totalBytes / 1048576).toStringAsFixed(1)} MB)';
        } else {
          task.status = '${(receivedBytes / 1048576).toStringAsFixed(1)} MB downloaded';
        }

        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastNotificationMs > 250) {
          lastNotificationMs = now;
          notifyListeners();
        }
      }

      await sink.close();
      client.close();

      if (receivedBytes < 50000 && (url.contains('.m3u8') || url.contains('.mpd'))) {
        throw Exception("Manifest payload received in direct file stream without video chunks.");
      }

      task.isCompleted = true;
      task.progress = 1.0;
      task.status = 'Completed';
      notifyListeners();
    } catch (e) {
      if (!task.isCancelled) {
        task.status = 'Failed: $e';
        notifyListeners();
      }
    }
  }

  double _parseIsoDuration(String pt) {
    final reg = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?');
    final match = reg.firstMatch(pt);
    if (match == null) return 0.0;
    final h = double.tryParse(match.group(1) ?? '') ?? 0.0;
    final m = double.tryParse(match.group(2) ?? '') ?? 0.0;
    final s = double.tryParse(match.group(3) ?? '') ?? 0.0;
    return h * 3600 + m * 60 + s;
  }

  Future<void> openFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await OpenFilex.open(filePath);
    }
  }
}
