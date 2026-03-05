// tm_provider.dart - v4: 모든 수정 통합본
// ① WidgetsBindingObserver (통화 종료 후 앱 복귀)
// ② unawaited 동기화 + 앱 시작 시 오프라인 큐 자동 전송
// ③ syncAllToCloud() 수동 배치 동기화 추가
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_phone_call_state/flutter_phone_call_state.dart';
import '../models/tm_models.dart';
import 'database_service.dart';
import 'cloud_sync_service.dart';
import 'webhook_sync_service.dart';  // ✅ 배치 동기화용

enum SessionPhase { idle, waiting, calling, recording, completed }

class TMProvider extends ChangeNotifier with WidgetsBindingObserver {
  final DatabaseService _db = DatabaseService();
  CloudSyncService? _cloudSync;
  CloudSyncService? get cloudSync => _cloudSync;

  // ─── 세션 목록 ───────────────────────────────
  List<TMSession> sessions = [];
  List<TMSession> get incompleteSessions =>
      sessions.where((s) => !s.isComplete).toList();
  List<TMSession> get completedSessions =>
      sessions.where((s) => s.isComplete).toList();

  // ─── 현재 세션 ───────────────────────────────
  TMSession? currentSession;
  SessionPhase phase = SessionPhase.idle;

  // ─── 통화 큐 ─────────────────────────────────
  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  TMContact? get currentContact {
    final contacts = _pendingContacts;
    if (contacts.isEmpty) return null;
    return contacts.first;
  }

  TMContact? get nextContact {
    final contacts = _pendingContacts;
    if (contacts.length < 2) return null;
    return contacts[1];
  }

  List<TMContact> get _pendingContacts {
    if (currentSession == null) return [];
    return currentSession!.contacts
        .where((c) => !c.isCompleted && !c.isSkipped)
        .toList();
  }

  // ─── 타이머 ───────────────────────────────────
  Timer? _timer;
  int callSeconds = 0;

  // ─── 통화 상태 감지 ────────────────────────────
  StreamSubscription? _callSub;
  bool _callConnected = false;

  // ─── 결과 입력 ────────────────────────────────
  List<String> selectedResults = [];
  String? selectedGrade;
  String memoText = '';

  // ─── 동기화 상태 ──────────────────────────────
  SyncStatus syncStatus = SyncStatus.idle;

  // ═══════════════════════════════════════════════
  // 초기화 & 세션 로드
  // ═══════════════════════════════════════════════

  Future<void> initialize({CloudSyncService? cloudSync}) async {
    _cloudSync = cloudSync;
    WidgetsBinding.instance.addObserver(this); // 앱 생명주기 감지 등록
    await loadAllSessions();

    // ✅ 앱 시작 시 미전송 오프라인 큐 자동 재전송
    if (_cloudSync != null) {
      unawaited(_cloudSync!.flushOfflineQueue());
    }
  }

  Future<void> loadAllSessions() async {
    sessions = await _db.getAllSessions();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════
  // 앱 생명주기 감지 (통화 종료 후 복귀 처리)
  // ═══════════════════════════════════════════════

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        phase == SessionPhase.calling) {
      // 통화 중 상태에서 앱으로 돌아왔다면 → 결과 입력 화면으로 전환
      _timer?.cancel();
      phase = SessionPhase.recording;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════
  // v4: 세션 이어가기 (Session Resume)
  // ═══════════════════════════════════════════════

  Future<void> resumeSession(TMSession session) async {
    currentSession = session;
    _currentIndex = session.currentIndex;
    phase = SessionPhase.waiting;
    _resetResultInput();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════
  // 새 세션 시작
  // ═══════════════════════════════════════════════

  Future<void> startNewSession({
    required String name,
    required List<TMContact> contacts,
  }) async {
    final session = TMSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      createdAt: DateTime.now(),
      contacts: contacts,
      currentIndex: 0,
    );

    await _db.insertSession(session);
    sessions.insert(0, session);
    currentSession = session;
    _currentIndex = 0;
    phase = SessionPhase.waiting;
    _resetResultInput();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════
  // 통화 제어
  // ═══════════════════════════════════════════════

  Future<void> startCall() async {
    if (currentSession == null) return;
    final contact = currentContact;
    if (contact == null) return;

    final phone = contact.phone;
    if (phone.isEmpty) return;

    // 타이머 초기화
    callSeconds = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      callSeconds++;
      notifyListeners();
    });

    phase = SessionPhase.calling;
    notifyListeners();

    // 통화 상태 감지 시작
    _callConnected = false;
    _callSub?.cancel();
    _callSub =
        PhoneCallState.instance.phoneStateChange.listen((event) {
      try {
        if (event.state == CallState.outgoing ||
            event.state == CallState.outgoingAccept) {
          _callConnected = true;
        }
        if (event.state == CallState.end && _callConnected) {
          _callConnected = false;
          _timer?.cancel();
          // 리스너 내부에서 직접 cancel() 금지 → microtask로 지연
          Future.microtask(() => _callSub?.cancel());
          // addPostFrameCallback 제거 → 직접 상태 변경 (백그라운드에서도 동작)
          phase = SessionPhase.recording;
          notifyListeners();
        }
      } catch (e) {
        debugPrint('Call state error: $e');
      }
    }, onError: (e) {
      debugPrint('Phone state stream error: $e');
    });

    // Android 전용: 모니터 서비스 시작
    if (Platform.isAndroid) {
      try {
        PhoneCallState.instance.startMonitorService();
      } catch (e) {
        debugPrint('startMonitorService error: $e');
      }
    }

    // 전화 앱 실행
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // 수동 통화 종료 (폴백 버튼용)
  void endCall() {
    _callSub?.cancel();
    _callSub = null;
    _callConnected = false;
    _timer?.cancel();
    phase = SessionPhase.recording;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════
  // v4: 결과 저장 + 자동 재시도 분류
  // ═══════════════════════════════════════════════

  Future<void> saveResult() async {
    final contact = currentContact;
    if (contact == null || currentSession == null) return;

    final idx = _findContactIndex(contact.id);
    if (idx < 0) return;

    final needsRetry = selectedResults.any(ResultCode.isRetryTrigger);

    final updated = contact.copyWith(
      resultCodes: List<String>.from(selectedResults),
      customerGrade: selectedGrade,
      memo: memoText,
      callDuration: callSeconds,
      isCompleted: !needsRetry,
      retryCount:
          needsRetry ? contact.retryCount + 1 : contact.retryCount,
    );

    currentSession!.contacts[idx] = updated;
    await _db.updateContact(currentSession!.id, updated);

    if (needsRetry) {
      currentSession!.contacts.removeAt(idx);
      currentSession!.contacts.add(updated);
    }

    _currentIndex++;
    await _db.saveSessionProgress(currentSession!.id, _currentIndex);

    // ✅ unawaited: 블로킹 없이 동기화, 에러는 로그+큐에 저장
    unawaited(_syncToCloud(updated));

    _resetResultInput();
    _advanceToNextContact();
  }

  void _advanceToNextContact() {
    final pending = _pendingContacts;
    if (pending.isEmpty) {
      _completeSession();
    } else {
      phase = SessionPhase.waiting;
    }
    notifyListeners();
  }

  Future<void> _completeSession() async {
    if (currentSession == null) return;

    currentSession!.isComplete =
        currentSession!.contacts.every((c) => c.isCompleted || c.isSkipped);

    phase = SessionPhase.completed;

    await _db.updateSession(currentSession!);
    await loadAllSessions();
    notifyListeners();
  }

  Future<void> startRetryRound() async {
    if (currentSession == null) return;

    final retryContacts = currentSession!.retryContacts;
    if (retryContacts.isEmpty) return;

    phase = SessionPhase.waiting;
    _resetResultInput();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════
  // 건너뛰기
  // ═══════════════════════════════════════════════

  Future<void> skipContact() async {
    final contact = currentContact;
    if (contact == null || currentSession == null) return;

    final idx = _findContactIndex(contact.id);
    if (idx < 0) return;

    final updated = contact.copyWith(isSkipped: true);
    currentSession!.contacts[idx] = updated;
    await _db.updateContact(currentSession!.id, updated);

    _currentIndex++;
    await _db.saveSessionProgress(currentSession!.id, _currentIndex);

    _advanceToNextContact();
  }

  // ═══════════════════════════════════════════════
  // 결과 입력 토글
  // ═══════════════════════════════════════════════

  void toggleResult(String code) {
    if (selectedResults.contains(code)) {
      selectedResults.remove(code);
    } else {
      selectedResults.add(code);
    }
    notifyListeners();
  }

  void setGrade(String? grade) {
    selectedGrade = (selectedGrade == grade) ? null : grade;
    notifyListeners();
  }

  void setMemo(String text) {
    memoText = text;
  }

  // ═══════════════════════════════════════════════
  // 클라우드 동기화 (실시간 단건)
  // ═══════════════════════════════════════════════

  Future<void> _syncToCloud(TMContact contact) async {
    if (_cloudSync == null || currentSession == null) return;

    syncStatus = SyncStatus.syncing;
    notifyListeners();

    try {
      await _cloudSync!.syncResult(
        sessionId: currentSession!.id,
        sessionName: currentSession!.name,
        contact: contact,
      );
      syncStatus = SyncStatus.synced;
    } catch (e) {
      debugPrint('Cloud sync error: $e');
      syncStatus = SyncStatus.error;
      // webhook_sync_service에서 오프라인 큐에 저장 완료
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════
  // 수동 배치 동기화 (UI 버튼용)
  // ═══════════════════════════════════════════════

  Future<SyncBatchResult?> syncAllToCloud(TMSession session) async {
    // WebhookSyncService로 캐스팅 (배치 메서드 접근)
    final webhook = _cloudSync as WebhookSyncService?;
    if (webhook == null) {
      debugPrint('syncAllToCloud: _cloudSync is null or not WebhookSyncService');
      return null;
    }

    syncStatus = SyncStatus.syncing;
    notifyListeners();

    try {
      // 완료 또는 스킵된 연락처만 동기화
      final targets = session.contacts
          .where((c) => c.isCompleted || c.isSkipped)
          .toList();

      debugPrint('syncAllToCloud: syncing ${targets.length} contacts');

      final result = await webhook.syncBatch(
        sessionId: session.id,
        sessionName: session.name,
        contacts: targets,
      );

      syncStatus =
          result.failed == 0 ? SyncStatus.synced : SyncStatus.error;
      notifyListeners();
      return result;
    } catch (e) {
      debugPrint('syncAllToCloud error: $e');
      syncStatus = SyncStatus.error;
      notifyListeners();
      return null;
    }
  }

  // ═══════════════════════════════════════════════
  // 헬퍼
  // ═══════════════════════════════════════════════

  int _findContactIndex(int contactId) =>
      currentSession?.contacts.indexWhere((c) => c.id == contactId) ?? -1;

  void _resetResultInput() {
    selectedResults = [];
    selectedGrade = null;
    memoText = '';
    callSeconds = 0;
    _timer?.cancel();
  }

  void exitSession() {
    _callSub?.cancel();
    _timer?.cancel();
    currentSession = null;
    phase = SessionPhase.idle;
    _resetResultInput();
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 생명주기 감지 해제
    _callSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}
