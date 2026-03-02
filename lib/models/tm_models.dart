// tm_models.dart - v4: session resume + auto-retry

enum SyncStatus { idle, syncing, synced, error }

/// 개별 통화 결과 상수
class ResultCode {
  static const callable = 'callable';       // 통화가능
  static const smsOk = 'sms_ok';           // 문자가능
  static const allRejected = 'all_rejected'; // 모두거부
  static const callback = 'callback';       // 콜백요청 → 재시도 대상
  static const noConnect = 'no_connect';    // 연결안됨 → 재시도 대상
  static const wrongNumber = 'wrong_number'; // 잘못된번호

  static const List<String> retryTriggers = [callback, noConnect];

  static String label(String code) {
    switch (code) {
      case callable:      return '통화가능';
      case smsOk:         return '문자가능';
      case allRejected:   return '모두거부';
      case callback:      return '콜백요청';
      case noConnect:     return '연결안됨';
      case wrongNumber:   return '잘못된번호';
      default:            return code;
    }
  }

  static bool isRetryTrigger(String code) => retryTriggers.contains(code);
}

/// 고객 평가 등급
class CustomerGrade {
  static const a = 'A';
  static const b = 'B';
  static const c = 'C';

  static String label(String grade) {
    switch (grade) {
      case a: return '우수고객';
      case b: return '일반고객';
      case c: return '관리필요';
      default: return grade;
    }
  }
}

/// 연락처 + 통화 결과
class TMContact {
  final int id;
  final String name;
  final String phone;

  // 통화 결과
  List<String> resultCodes;   // 다중 선택 가능
  String? customerGrade;      // A/B/C
  String memo;
  int callDuration;           // 초 단위
  DateTime? callStartTime;

  // v4: 세션 이어가기 / 재시도 관련
  bool isCompleted;           // 완료 여부 (재시도 대상은 false)
  int retryCount;             // 재시도 횟수
  bool isSkipped;             // 건너뛰기 여부

  TMContact({
    required this.id,
    required this.name,
    required this.phone,
    this.resultCodes = const [],
    this.customerGrade,
    this.memo = '',
    this.callDuration = 0,
    this.callStartTime,
    this.isCompleted = false,
    this.retryCount = 0,
    this.isSkipped = false,
  });

  /// 재시도가 필요한 연락처 여부
  bool get needsRetry =>
      !isCompleted && resultCodes.any((c) => ResultCode.isRetryTrigger(c));

  /// 재시도 횟수 표시 라벨
  String get retryLabel => retryCount > 0 ? '재시도 ${retryCount}회차' : '';

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'result_codes': resultCodes.join(','),
    'customer_grade': customerGrade,
    'memo': memo,
    'call_duration': callDuration,
    'call_start_time': callStartTime?.toIso8601String(),
    'is_completed': isCompleted ? 1 : 0,
    'retry_count': retryCount,
    'is_skipped': isSkipped ? 1 : 0,
  };

  factory TMContact.fromMap(Map<String, dynamic> m) => TMContact(
    id: m['id'] as int,
    name: m['name'] as String,
    phone: m['phone'] as String,
    resultCodes: m['result_codes'] != null && (m['result_codes'] as String).isNotEmpty
        ? (m['result_codes'] as String).split(',')
        : [],
    customerGrade: m['customer_grade'] as String?,
    memo: m['memo'] as String? ?? '',
    callDuration: m['call_duration'] as int? ?? 0,
    callStartTime: m['call_start_time'] != null
        ? DateTime.tryParse(m['call_start_time'] as String)
        : null,
    isCompleted: (m['is_completed'] as int? ?? 0) == 1,
    retryCount: m['retry_count'] as int? ?? 0,
    isSkipped: (m['is_skipped'] as int? ?? 0) == 1,
  );

  TMContact copyWith({
    List<String>? resultCodes,
    String? customerGrade,
    String? memo,
    int? callDuration,
    DateTime? callStartTime,
    bool? isCompleted,
    int? retryCount,
    bool? isSkipped,
  }) => TMContact(
    id: id,
    name: name,
    phone: phone,
    resultCodes: resultCodes ?? this.resultCodes,
    customerGrade: customerGrade ?? this.customerGrade,
    memo: memo ?? this.memo,
    callDuration: callDuration ?? this.callDuration,
    callStartTime: callStartTime ?? this.callStartTime,
    isCompleted: isCompleted ?? this.isCompleted,
    retryCount: retryCount ?? this.retryCount,
    isSkipped: isSkipped ?? this.isSkipped,
  );
}

/// TM 세션
class TMSession {
  final String id;
  String name;
  DateTime createdAt;
  DateTime? updatedAt;

  List<TMContact> contacts;
  int currentIndex;         // v4: 마지막 통화 위치 저장
  bool isComplete;

  // v4: 재시도 관련
  List<int> retryQueue;     // 재시도 대기 연락처 id 목록

  TMSession({
    required this.id,
    required this.name,
    required this.createdAt,
    this.updatedAt,
    this.contacts = const [],
    this.currentIndex = 0,
    this.isComplete = false,
    this.retryQueue = const [],
  });

  // --- 집계 계산 ---

  int get totalContacts => contacts.length;

  int get completedCount =>
      contacts.where((c) => c.isCompleted || c.isSkipped).length;

  int get pendingCount =>
      contacts.where((c) => !c.isCompleted && !c.isSkipped).length;

  /// 재시도 대기 중인 연락처 목록
  List<TMContact> get retryContacts =>
      contacts.where((c) => c.needsRetry).toList();

  double get progressPercent =>
      totalContacts > 0 ? completedCount / totalContacts : 0.0;

  /// 결과 코드별 건수
  Map<String, int> get resultStats {
    final stats = <String, int>{};
    for (final c in contacts) {
      for (final code in c.resultCodes) {
        stats[code] = (stats[code] ?? 0) + 1;
      }
    }
    return stats;
  }

  /// 고객 등급별 건수
  Map<String, int> get gradeStats {
    final stats = <String, int>{};
    for (final c in contacts.where((c) => c.customerGrade != null)) {
      final g = c.customerGrade!;
      stats[g] = (stats[g] ?? 0) + 1;
    }
    return stats;
  }
}

/// 동기화 설정
class SyncConfig {
  bool enabled;
  String serviceType; // 'firebase' | 'sheets' | 'none'
  bool instantSync;
  bool wifiOnly;

  SyncConfig({
    this.enabled = false,
    this.serviceType = 'none',
    this.instantSync = true,
    this.wifiOnly = false,
  });
}
