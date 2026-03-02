// home_screen.dart - v4: 미완료 세션 섹션 + 이어가기 배너
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/tm_provider.dart';
import '../models/tm_models.dart';
import 'contact_select_screen.dart';
import 'tm_session_screen.dart';
import 'results_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIncompleteSessions();
    });
  }

  /// v4: 앱 시작 시 미완료 세션 확인 팝업
  void _checkIncompleteSessions() {
    final provider = context.read<TMProvider>();
    final incomplete = provider.incompleteSessions;

    if (incomplete.isNotEmpty && mounted) {
      final session = incomplete.first;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.replay_circle_filled, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text('미완료 세션이 있습니다', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"${session.name}"',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: session.progressPercent,
                backgroundColor: Colors.grey[200],
                color: Colors.orange,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 6),
              Text(
                '${session.completedCount}/${session.totalContacts}명 완료'
                '${session.retryContacts.isNotEmpty ? " · 재시도 대기 ${session.retryContacts.length}명" : ""}',
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('나중에', style: TextStyle(color: Colors.grey)),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _resumeSession(session);
              },
              icon: const Icon(Icons.play_circle_outline, size: 18),
              label: const Text('이어서 진행하기'),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _resumeSession(TMSession session) async {
    final provider = context.read<TMProvider>();
    await provider.resumeSession(session);
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TMSessionScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('TM 자동 통화', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: '전체 결과',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ResultsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: '설정',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<TMProvider>(
        builder: (context, provider, _) {
          return CustomScrollView(
            slivers: [
              // ── 미완료 세션 섹션 ────────────────
              if (provider.incompleteSessions.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: _SectionHeader(
                    icon: Icons.replay_circle_filled,
                    label: '진행 중인 세션',
                    color: Colors.orange,
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _IncompleteSessionCard(
                      session: provider.incompleteSessions[i],
                      onResume: () => _resumeSession(provider.incompleteSessions[i]),
                    ),
                    childCount: provider.incompleteSessions.length,
                  ),
                ),
              ],

              // ── 완료된 세션 섹션 ─────────────────
              if (provider.completedSessions.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: _SectionHeader(
                    icon: Icons.check_circle_rounded,
                    label: '완료된 세션',
                    color: Colors.green,
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _CompletedSessionCard(
                      session: provider.completedSessions[i],
                    ),
                    childCount: provider.completedSessions.length,
                  ),
                ),
              ],

              // ── 세션 없을 때 빈 화면 ─────────────
              if (provider.sessions.isEmpty)
                const SliverFillRemaining(
                  child: _EmptyState(),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ContactSelectScreen()),
        ),
        icon: const Icon(Icons.add_call),
        label: const Text('새 세션 시작'),
        backgroundColor: Colors.blue,
      ),
    );
  }
}

// ──────────────────────────────────────────────────
// 섹션 헤더
// ──────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SectionHeader({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────
// 미완료 세션 카드 (주황색 강조)
// ──────────────────────────────────────────────────
class _IncompleteSessionCard extends StatelessWidget {
  final TMSession session;
  final VoidCallback onResume;

  const _IncompleteSessionCard({required this.session, required this.onResume});

  @override
  Widget build(BuildContext context) {
    final retry = session.retryContacts.length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.orange, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.replay_circle_filled, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    session.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: const Text(
                    '진행중',
                    style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: session.progressPercent,
                backgroundColor: Colors.orange.shade100,
                color: Colors.orange,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${session.completedCount}/${session.totalContacts}명 완료',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                if (retry > 0)
                  Row(
                    children: [
                      const Icon(Icons.refresh, size: 14, color: Colors.orange),
                      const SizedBox(width: 3),
                      Text(
                        '재시도 대기 $retry명',
                        style: const TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onResume,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('이어서 진행하기'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────
// 완료된 세션 카드
// ──────────────────────────────────────────────────
class _CompletedSessionCard extends StatelessWidget {
  final TMSession session;

  const _CompletedSessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade50,
          child: const Icon(Icons.check_circle_rounded, color: Colors.green),
        ),
        title: Text(
          session.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${session.totalContacts}명 · ${_formatDate(session.createdAt)}',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            '완료',
            style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        onTap: () {
          // 세션 상세 보기 (ResultsScreen)
        },
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
}

// ──────────────────────────────────────────────────
// 빈 상태 화면
// ──────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.phone_in_talk_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'TM 세션이 없습니다',
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            '"새 세션 시작" 버튼을 눌러 시작하세요',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }
}
