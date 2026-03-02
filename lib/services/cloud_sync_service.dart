// cloud_sync_service.dart - abstract interface
import '../models/tm_models.dart';

abstract class CloudSyncService {
  Future<void> syncResult({
    required String sessionId,
    required String sessionName,
    required TMContact contact,
  });

  Future<void> syncSession(TMSession session);
  Future<void> flushOfflineQueue();
}
