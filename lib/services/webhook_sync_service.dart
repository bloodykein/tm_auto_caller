// webhook_sync_service.dart - 시간대 수정 + 배치 동기화 추가
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tm_models.dart';
import 'cloud_sync_service.dart';

class SyncBatchResult {
  final int success;
  final int failed;
  const SyncBatchResult({required this.success, required this.failed});
}

class WebhookSyncService implements CloudSyncService {
  static const _defaultUrl =
      'https://script.google.com/macros/s/AKfycbzcajzOHW54cfvuOx7W6cNnHi1RKGugxHR7kT2RezUzLX_mtflYZg5yh6VtZtr-TvudYQ/exec';
  static const _prefKey = 'webhook_url';
  static const _queueKey = 'offline_sync_queue';

  // ─── URL 관리 ─────────────────────────────
  Future<String> getWebhookUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey) ?? _defaultUrl;
  }

  Future<void> saveWebhookUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, url);
  }

  // ─── 시간 유틸: KST 포맷 문자열 반환 ────────
  // DateTime.now()는 기기 로컬 시간(KST)을 반환
  // ISO 8601 대신 "yyyy-MM-dd HH:mm:ss" 형식으로 전송 → Apps Script 재변환 없음
  String _nowKst() {
    final t = DateTime.now();
    return '${t.year}-${_p(t.month)}-${_p(t.day)} '
        '${_p(t.hour)}:${_p(t.minute)}:${_p(t.second)}';
  }

  String _p(int v) => v.toString().padLeft(2, '0');

  // ─── HTTP POST (302 리다이렉트 처리) ─────────
  Future<bool> _post(String url, Map<String, dynamic> payload) async {
    try {
      final resp = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 302) {
        final location = resp.headers['location'];
        if (location != null) {
          final r2 = await http
              .post(
                Uri.parse(location),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 15));
          final body = r2.body.toLowerCase();
          return r2.statusCode == 200 ||
              body.contains('ok') ||
              body.contains('success');
        }
      }

      final body = resp.body.toLowerCase();
      return resp.statusCode == 200 ||
          body.contains('ok') ||
          body.contains('success');
    } catch (e) {
      debugPrint('WebhookSyncService._post error: $e');
      return false;
    }
  }

  // ─── 단건 결과 동기화 ─────────────────────
  @override
  Future<void> syncResult({
    required String sessionId,
    required String sessionName,
    required TMContact contact,
  }) async {
    final url = await getWebhookUrl();
    final payload = {
      'type': 'result',
      'timestamp': _nowKst(),           // ✅ KST 로컬 시간 직접 전송
      'sessionId': sessionId,
      'sessionName': sessionName,
      'name': contact.name,
      'phone': contact.phone,
      'resultCodes': contact.resultCodes.join(', '),
      'customerGrade': contact.customerGrade ?? '',
      'memo': contact.memo ?? '',
      'callDuration': contact.callDuration,
    };

    final ok = await _post(url, payload);
    if (!ok) {
      await _enqueue(payload);
      throw Exception('Webhook POST failed – queued for retry');
    }
  }

  // ─── 세션 동기화 ──────────────────────────
  @override
  Future<void> syncSession(TMSession session) async {
    final url = await getWebhookUrl();
    final payload = {
      'type': 'session',
      'timestamp': _nowKst(),
      'sessionId': session.id,
      'sessionName': session.name,
      'totalContacts': session.contacts.length,
      'completedContacts':
          session.contacts.where((c) => c.isCompleted).length,
    };

    final ok = await _post(url, payload);
    if (!ok) {
      await _enqueue(payload);
      throw Exception('Webhook POST failed – queued for retry');
    }
  }

  // ─── 배치 동기화 (수동 동기화 버튼용) ────────
  Future<SyncBatchResult> syncBatch({
    required String sessionId,
    required String sessionName,
    required List<TMContact> contacts,
  }) async {
    final url = await getWebhookUrl();
    int success = 0;
    int failed = 0;

    for (final contact in contacts) {
      final payload = {
        'type': 'result',
        'timestamp': _nowKst(),
        'sessionId': sessionId,
        'sessionName': sessionName,
        'name': contact.name,
        'phone': contact.phone,
        'resultCodes': contact.resultCodes.join(', '),
        'customerGrade': contact.customerGrade ?? '',
        'memo': contact.memo ?? '',
        'callDuration': contact.callDuration,
      };

      final ok = await _post(url, payload);
      if (ok) {
        success++;
      } else {
        failed++;
        await _enqueue(payload);
      }
    }

    return SyncBatchResult(success: success, failed: failed);
  }

  // ─── 오프라인 큐 ──────────────────────────
  Future<void> _enqueue(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_queueKey) ?? [];
    list.add(jsonEncode(payload));
    await prefs.setStringList(_queueKey, list);
    debugPrint('Queued offline payload. Queue size: ${list.length}');
  }

  @override
  Future<void> flushOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_queueKey) ?? [];
    if (list.isEmpty) return;

    debugPrint('Flushing offline queue: ${list.length} items');
    final url = await getWebhookUrl();
    final remaining = <String>[];

    for (final raw in list) {
      try {
        final payload = jsonDecode(raw) as Map<String, dynamic>;
        final ok = await _post(url, payload);
        if (!ok) remaining.add(raw);
      } catch (e) {
        remaining.add(raw);
      }
    }

    await prefs.setStringList(_queueKey, remaining);
    debugPrint('Queue flush done. Remaining: ${remaining.length}');
  }

  // 큐 사이즈 조회
  Future<int> getQueueSize() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_queueKey) ?? []).length;
  }
}
