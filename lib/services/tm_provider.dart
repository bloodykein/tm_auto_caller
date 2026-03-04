// tm_provider.dart - v4: session resume + auto-retry core logic
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/tm_models.dart';
import 'database_service.dart';
import 'cloud_sync_service.dart';
import 'package:flutter_phone_call_state/flutter_phone_call_state.dart';

enum SessionPhase { idle, waiting, calling, recording, completed }

class TMProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  CloudSyncService? _cloudSync;

  // ─── 세션 목록 ───────────────────────────────
  List<TMSession> sessions = [];
  List<TMSession> get incompleteSessions => sessions.where((s) => !s.isComplete).toList();
  List<TMSession> get completedSessions => sessions.where((s) => s.isComplete).toList();

  // ─── 현재 세션 ───────────────────────────────
  TMSession? currentSession;
  SessionPhase phase = SessionPhase.idle;

  // ─── 통화 큐 ─────────────────────────────────
  /// 현재 차례 인덱스 (contacts 리스트 기준)
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

  /// 아직 완료/건너뛰기 안 된 연락처 (재시도 포함)
  List<TMContact> get _pendingContacts {
    if (currentSession == null) return [];
    return currentSession!.contacts
        .where((c) => !c.isCompleted && !c.isSkipped)
        .toList();
  }

  // ─── 타이머 ───────────────────────────────────
  Timer? _timer;
  int callSeconds = 0;

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
    await loadAllSessions();
  }

  Future<void> loadAllSessions() async {
    sessions = await _db.getAllSessions();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════
  // v4: 세션 이어가기 (Session Resume)
  // ═══════════════════════════════════════════════

  /// 미완료 세션을 불러와 현재 세션으로 설정
  Future<void> resumeSession(TMSession session) async {
    currentSession = session;
    _currentIndex = session.currentIndex;

    // pending 연락처 중 첫 번째로 이동
    // (재시도 연락처는 needsRetry == true → 아직 isCompleted = false)
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
  if (_session == null || isCompleted) return;
  final contact = currentContact;
  if (contact == null) return;

  final phone = contact.phones.isNotEmpty ? contact.phones.first.number : null;
  if (phone == null || phone.isEmpty) return;

  _callDuration = 0;
  _callTimer?.cancel();
  _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
    _callDuration++;
    notifyListeners();
  });

  _callStartTime = DateTime.now();
  _phase = SessionPhase.calling;
  notifyListeners();

  // ✅ 올바른 API: PhoneCallState.instance 사용
  bool _callConnected = false;
  StreamSubscription? _callSub;

  _callSub = PhoneCallState.instance.phoneStateChange.listen((event) {
    if (event.state == CallState.outgoing ||
        event.state == CallState.outgoingAccept) {
      _callConnected = true;
    }
    if (event.state == CallState.end && _callConnected) {
      _callConnected = false;
      _callSub?.cancel();
      _callTimer?.cancel();
      // 🎯 통화 종료 자동 감지 → 결과 입력 화면
      _phase = SessionPhase.recording;
      notifyListeners();
    }
  });

  // Android 전용: 모니터 서비스 시작
  if (Platform.isAndroid) {
    await PhoneCallState.instance.startMonitorService();
  }

  // 전화 앱 실행
  final uri = Uri.parse('tel:$phone');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  }
}

  // ═══════════════════════════════════════════════
  // v4: 결과 저장 + 자동 재시도 분류
  // ═══════════════════════════════════════════════

  Future<void> saveResult() async {
    final contact = currentContact;
    if (contact == null || currentSession == null) return;

    final idx = _findContactIndex(contact.id);
    if (idx < 0) return;

    // ── 재시도 트리거 여부 판단 ──
    final needsRetry = selectedResults.any(ResultCode.isRetryTrigger);

    final updated = contact.copyWith(
      resultCodes: List<String>.from(selectedResults),
      customerGrade: selectedGrade,
      memo: memoText,
      callDuration: callSeconds,
      isCompleted: !needsRetry,          // 재시도 대상은 완료 처리 안 함
      retryCount: needsRetry
          ? contact.retryCount + 1       // 재시도 횟수 증가
          : contact.retryCount,
    );

    currentSession!.contacts[idx] = updated;

    // DB 저장
    await _db.updateContact(currentSession!.id, updated);

    // ── 재시도 대상 → 큐 맨 뒤로 이동 ──
    if (needsRetry) {
      // contacts 리스트에서 제거 후 맨 뒤에 추가
      currentSession!.contacts.removeAt(idx);
      currentSession!.contacts.add(updated);
    }

    // 진행 위치 저장
    _currentIndex++;
    await _db.saveSessionProgress(currentSession!.id, _currentIndex);

    // 클라우드 동기화
    _syncToCloud(updated);

    // 다음 연락처로 이동
    _resetResultInput();
    _advanceToNextContact();
  }

  void _advanceToNextContact() {
    final pending = _pendingContacts;

    if (pending.isEmpty) {
      // 세션 완료
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

  /// v4: 재시도 연락처만 이어서 진행
  Future<void> startRetryRound() async {
    if (currentSession == null) return;

    final retryContacts = currentSession!.retryContacts;
    if (retryContacts.isEmpty) return;

    // 재시도 연락처만 새 세션으로 시작 (원 세션 유지)
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
  // 클라우드 동기화
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
      syncStatus = SyncStatus.error;
      // 오프라인 큐에 추가
      await _db.addToSyncQueue(
        sessionId: currentSession!.id,
        contactId: contact.id,
        payload: contact.toMap().toString(),
      );
    }
    notifyListeners();
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
    _timer?.cancel();
    currentSession = null;
    phase = SessionPhase.idle;
    _resetResultInput();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
