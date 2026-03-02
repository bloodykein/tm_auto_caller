// sync_status_chip.dart - v4 sync indicator widget
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/tm_provider.dart';
import '../models/tm_models.dart';

class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TMProvider>(
      builder: (_, provider, __) {
        switch (provider.syncStatus) {
          case SyncStatus.syncing:
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                  ),
                  SizedBox(width: 6),
                  Text('동기화 중', style: TextStyle(fontSize: 12, color: Colors.blue)),
                ],
              ),
            );
          case SyncStatus.synced:
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_done, size: 16, color: Colors.green),
                  SizedBox(width: 4),
                  Text('동기화됨', style: TextStyle(fontSize: 12, color: Colors.green)),
                ],
              ),
            );
          case SyncStatus.error:
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off, size: 16, color: Colors.red),
                  SizedBox(width: 4),
                  Text('오프라인', style: TextStyle(fontSize: 12, color: Colors.red)),
                ],
              ),
            );
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }
}
