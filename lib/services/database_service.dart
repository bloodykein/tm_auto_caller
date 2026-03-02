// database_service.dart - v4: supports session resume, retry queue
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/tm_models.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'tm_app_v4.db');
    return openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        current_index INTEGER DEFAULT 0,
        is_complete INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE contacts (
        id INTEGER,
        session_id TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        result_codes TEXT DEFAULT '',
        customer_grade TEXT,
        memo TEXT DEFAULT '',
        call_duration INTEGER DEFAULT 0,
        call_start_time TEXT,
        is_completed INTEGER DEFAULT 0,
        retry_count INTEGER DEFAULT 0,
        is_skipped INTEGER DEFAULT 0,
        sort_order INTEGER DEFAULT 0,
        PRIMARY KEY (id, session_id),
        FOREIGN KEY (session_id) REFERENCES sessions(id)
      )
    ''');

    // 오프라인 동기화 큐
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        contact_id INTEGER NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) {
      // 기존 contacts 테이블에 v4 컬럼 추가
      try {
        await db.execute('ALTER TABLE contacts ADD COLUMN retry_count INTEGER DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE contacts ADD COLUMN is_skipped INTEGER DEFAULT 0');
      } catch (_) {}
      // sessions 테이블에 current_index 추가
      try {
        await db.execute('ALTER TABLE sessions ADD COLUMN current_index INTEGER DEFAULT 0');
      } catch (_) {}
    }
  }

  // ──────────────────────────────────────────
  // Session CRUD
  // ──────────────────────────────────────────

  Future<void> insertSession(TMSession session) async {
    final db = await database;
    await db.insert(
      'sessions',
      {
        'id': session.id,
        'name': session.name,
        'created_at': session.createdAt.toIso8601String(),
        'updated_at': session.updatedAt?.toIso8601String(),
        'current_index': session.currentIndex,
        'is_complete': session.isComplete ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 연락처 배치 삽입
    final batch = db.batch();
    for (var i = 0; i < session.contacts.length; i++) {
      final c = session.contacts[i];
      batch.insert(
        'contacts',
        {...c.toMap(), 'session_id': session.id, 'sort_order': i},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateSession(TMSession session) async {
    final db = await database;
    await db.update(
      'sessions',
      {
        'name': session.name,
        'updated_at': DateTime.now().toIso8601String(),
        'current_index': session.currentIndex,
        'is_complete': session.isComplete ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  /// v4: 진행 위치 저장 (앱 재시작 시 이어가기용)
  Future<void> saveSessionProgress(String sessionId, int currentIndex) async {
    final db = await database;
    await db.update(
      'sessions',
      {
        'current_index': currentIndex,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<List<TMSession>> getAllSessions() async {
    final db = await database;
    final rows = await db.query('sessions', orderBy: 'created_at DESC');
    final sessions = <TMSession>[];
    for (final row in rows) {
      final contacts = await getContactsForSession(row['id'] as String);
      sessions.add(TMSession(
        id: row['id'] as String,
        name: row['name'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: row['updated_at'] != null
            ? DateTime.tryParse(row['updated_at'] as String)
            : null,
        contacts: contacts,
        currentIndex: row['current_index'] as int? ?? 0,
        isComplete: (row['is_complete'] as int? ?? 0) == 1,
      ));
    }
    return sessions;
  }

  /// v4: 미완료 세션만 조회
  Future<List<TMSession>> getIncompleteSessions() async {
    final all = await getAllSessions();
    return all.where((s) => !s.isComplete).toList();
  }

  Future<void> deleteSession(String sessionId) async {
    final db = await database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
    await db.delete('contacts', where: 'session_id = ?', whereArgs: [sessionId]);
  }

  // ──────────────────────────────────────────
  // Contact CRUD
  // ──────────────────────────────────────────

  Future<List<TMContact>> getContactsForSession(String sessionId) async {
    final db = await database;
    final rows = await db.query(
      'contacts',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'sort_order ASC',
    );
    return rows.map(TMContact.fromMap).toList();
  }

  Future<void> updateContact(String sessionId, TMContact contact) async {
    final db = await database;
    await db.update(
      'contacts',
      {...contact.toMap(), 'session_id': sessionId},
      where: 'id = ? AND session_id = ?',
      whereArgs: [contact.id, sessionId],
    );
  }

  // ──────────────────────────────────────────
  // Sync Queue
  // ──────────────────────────────────────────

  Future<void> addToSyncQueue({
    required String sessionId,
    required int contactId,
    required String payload,
  }) async {
    final db = await database;
    await db.insert('sync_queue', {
      'session_id': sessionId,
      'contact_id': contactId,
      'payload': payload,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPendingSyncItems() async {
    final db = await database;
    return db.query('sync_queue', orderBy: 'id ASC', limit: 50);
  }

  Future<void> removeSyncQueueItem(int id) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getSyncQueueCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM sync_queue');
    return result.first['cnt'] as int? ?? 0;
  }
}
