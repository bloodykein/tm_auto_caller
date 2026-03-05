import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tm_models.dart';
import 'cloud_sync_service.dart';

const String _kWebhookUrlKey = 'webhook_url';
const String _defaultWebhookUrl =
    'https://script.google.com/macros/s/AKfycbwKc9CSfUrz5IDfCJctxeBa1inX0AtQXUbVd9yXJv7_ugVoenn17JY-EdsRXWiUYWikJA/exec';

class WebhookSyncService implements CloudSyncService {
  String? _webhookUrl;
  final List<Map<String, dynamic>> _offlineQueue = [];

  Future<String> getWebhookUrl() async {
    if (_webhookUrl != null) return _webhookUrl!;
    final prefs = await SharedPreferences.getInstance();
    _webhookUrl = prefs.getString(_kWebhookUrlKey) ?? _defaultWebhookUrl;
    return _webhookUrl!;
  }

  Future<void> saveWebhookUrl(String url) async {
    _webhookUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWebhookUrlKey, url);
  }

  Future<bool> _post(Map<String, dynamic> payload) async {
    try {
      final url = await getWebhookUrl();
      if (url.isEmpty) return false;

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);

      final request = await client.postUrl(Uri.parse(url));
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(payload));

      final response = await request.close()
          .timeout(const Duration(seconds: 15));

      // 302 리다이렉트를 직접 따라가서 최종 응답 확인
      if (response.statusCode == 302) {
        final location = response.headers.value('location');
        await response.drain();
        client.close();

        if (location != null) {
          final redirectClient = HttpClient();
          redirectClient.connectionTimeout = const Duration(seconds: 15);
          final redirectReq = await redirectClient.getUrl(Uri.parse(location));
          final redirectRes = await redirectReq.close()
              .timeout(const Duration(seconds: 15));
          final body = await redirectRes.transform(utf8.decoder).join();
          redirectClient.close();
          // {"status":"ok"} 이면 성공
          return body.contains('"ok"') || redirectRes.statusCode == 200;
        }
        return true; // location 헤더 없어도 302 자체로 성공 처리
      }

      await response.drain();
      client.close();
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> syncResult({
    required String sessionId,
    required String sessionName,
    required TMContact contact,
  }) async {
    final payload = {
      'type': 'syncResult',
      'sessionId': sessionId,
      'sessionName': sessionName,
      'name': contact.name,
      'phone': contact.phone,
      'resultCode': contact.resultCodes.isNotEmpty
          ? contact.resultCodes.join(', ')
          : '',
      'grade': contact.customerGrade ?? '',
      'memo': contact.memo ?? '',
      'callDuration': contact.callDuration ?? 0,
      'retryCount': contact.retryCount,
      'isCompleted': contact.isCompleted,
    };

    final success = await _post(payload);
    if (!success) {
      _offlineQueue.add(payload);
      throw Exception('Webhook POST failed – queued for retry');
    }
  }

  @override
  Future<void> syncSession(TMSession session) async {
    final payload = {
      'type': 'syncSession',
      'sessionId': session.id,
      'sessionName': session.name,
      'totalContacts': session.totalContacts,
      'completedCount': session.completedCount,
      'isComplete': session.isComplete,
    };
    await _post(payload);
  }

  @override
  Future<void> flushOfflineQueue() async {
    if (_offlineQueue.isEmpty) return;

    final toSend = List<Map<String, dynamic>>.from(_offlineQueue);
    _offlineQueue.clear();

    for (final payload in toSend) {
      final success = await _post(payload);
      if (!success) {
        _offlineQueue.add(payload); // 재실패 시 다시 큐에
        break; // 네트워크 불안정 시 중단
      }
    }
  }

  int get offlineQueueCount => _offlineQueue.length;
}
