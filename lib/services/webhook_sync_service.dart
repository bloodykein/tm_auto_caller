import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tm_models.dart';
import 'cloud_sync_service.dart';

const String _kWebhookUrlKey = 'webhook_url';
const String _defaultWebhookUrl =
    'https://script.google.com/macros/s/AKfycbxyPofCnGcj9u0vvpCcxTBvyrha3ymtk3HgVIq4yIBw274kvHlwyMvg7cz5r5If13HWrA/exec';

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
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(Uri.parse(url));
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(payload));
      final response = await request.close();
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
      'resultCode': contact.resultCodes.isNotEmpty ? contact.resultCodes.last : '',
      'grade': contact.customerGrade ?? '',
      'memo': contact.memo ?? '',
      'callDuration': contact.callDuration ?? 0,
      'retryCount': contact.retryCount,
      'isCompleted': contact.isCompleted,
    };
    final success = await _post(payload);
    if (!success) _offlineQueue.add(payload);
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
      if (!success) { _offlineQueue.add(payload); break; }
    }
  }
}
