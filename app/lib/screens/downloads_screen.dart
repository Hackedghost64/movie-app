import 'package:flutter/material.dart';
import '../services/download_service.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final downloadService = DownloadService.instance;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Downloads", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: ListenableBuilder(
        listenable: downloadService,
        builder: (context, _) {
          final tasks = downloadService.tasks;
          if (tasks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_for_offline_outlined, color: Colors.white24, size: 64),
                  SizedBox(height: 16),
                  Text("No downloads yet", style: TextStyle(color: Colors.white54, fontSize: 16)),
                  SizedBox(height: 8),
                  Text("Search a movie or show and tap download", style: TextStyle(color: Colors.white30, fontSize: 13)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: tasks.length,
            itemBuilder: (ctx, i) {
              final task = tasks[i];
              return Card(
                color: const Color(0xFF1E1E1E),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            task.isCompleted ? Icons.check_circle : Icons.downloading,
                            color: task.isCompleted ? Colors.greenAccent : Colors.amber,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              task.title,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (task.isCompleted)
                            IconButton(
                              icon: const Icon(Icons.play_circle_fill, color: Colors.amber, size: 28),
                              onPressed: () => downloadService.openFile(task.filePath),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (!task.isCompleted)
                        LinearProgressIndicator(
                          value: task.progress > 0 ? task.progress : null,
                          backgroundColor: Colors.white12,
                          color: Colors.amber,
                          minHeight: 4,
                        ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(task.status, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          if (task.isCompleted)
                            TextButton(
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                              onPressed: () => downloadService.openFile(task.filePath),
                              child: const Text("Open File", style: TextStyle(color: Colors.amber, fontSize: 12)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
