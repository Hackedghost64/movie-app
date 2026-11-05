import 'package:flutter/material.dart';
import '../models/media_models.dart';
import '../coordinators/download_coordinator.dart';
import '../coordinators/playback_coordinator.dart';
import '../widgets/tv_focusable.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final downloadCoordinator = DownloadCoordinator.instance;
    const accentRed = Color(0xFFE50914);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        title: const Text(
          "Downloads",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
        ),
      ),
      body: ListenableBuilder(
        listenable: downloadCoordinator.service,
        builder: (context, _) {
          final tasks = downloadCoordinator.tasks;
          if (tasks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_for_offline_outlined, color: Colors.white24, size: 72),
                  SizedBox(height: 16),
                  Text("No downloads yet", style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text("Downloaded movies and episodes appear here for offline viewing",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: tasks.length,
            itemBuilder: (ctx, i) {
              final task = tasks[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: TvFocusable(
                  autofocus: i == 0,
                  borderRadius: 12,
                  scaleFactor: 1.03,
                  onTap: () {
                    if (task.isCompleted) {
                      _playOffline(context, task);
                    }
                  },
                  child: Card(
                    color: const Color(0xFF1E1E1E),
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                task.isCompleted
                                    ? Icons.check_circle
                                    : (task.isCancelled ? Icons.cancel : Icons.downloading),
                                color: task.isCompleted
                                    ? Colors.greenAccent
                                    : (task.isCancelled ? Colors.redAccent : accentRed),
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      task.status,
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              if (task.isCompleted) ...[
                                IconButton(
                                  icon: const Icon(Icons.play_circle_fill, color: accentRed, size: 32),
                                  tooltip: "Watch Offline",
                                  onPressed: () => _playOffline(context, task),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.white54, size: 22),
                                  tooltip: "Delete Download",
                                  onPressed: () => downloadCoordinator.deleteDownload(task.id),
                                ),
                              ] else if (!task.isCancelled) ...[
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white54, size: 22),
                                  tooltip: "Cancel Download",
                                  onPressed: () => downloadCoordinator.cancelDownload(task.id),
                                ),
                              ] else ...[
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.white54, size: 22),
                                  tooltip: "Remove",
                                  onPressed: () => downloadCoordinator.deleteDownload(task.id),
                                ),
                              ],
                            ],
                          ),
                          if (!task.isCompleted && !task.isCancelled) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: task.progress > 0 ? task.progress : null,
                                backgroundColor: Colors.white12,
                                valueColor: const AlwaysStoppedAnimation<Color>(accentRed),
                                minHeight: 4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _playOffline(BuildContext context, DownloadTask task) {
    PlaybackCoordinator.instance.launchOfflinePlayer(context, task: task);
  }
}
