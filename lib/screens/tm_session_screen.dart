// tm_session_screen.dart - v4: retry badge + retry warning
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/tm_provider.dart';
import '../models/tm_models.dart';
import '../widgets/sync_status_chip.dart';
import '../services/excel_service.dart';

class TMSessionScreen extends StatelessWidget {
  const TMSessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          final exit = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('세션 중단'),
              content: const Text('진행 중인 세션을 나가시겠습니까?\n진행 상황은 저장됩니다.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('계속 진행')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('나가기')),
              ],
            ),
          );
          if (exit == true && context.mounted) {
            context.read<TMProvider>().exitSession();
            Navigator.pop(context);
          }
        }
      },
      child: Consumer<TMProvider>(
        builder: (context, provider, _) {
          return switch (provider.phase) {
            SessionPhase.waiting   => _WaitingView(provider: provider),
            SessionPhase.calling   => _CallingView(provider: provider),
            SessionPhase.recording => _RecordingView(provider: provider),
            SessionPhase.completed => _CompletedView(provider: provider),
            _                      => const SizedBox.shrink(),
          };
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────
// 1. 통화 대기 화면
// ──────────────────────────────────────────────────
class _WaitingView extends StatelessWidget {
  final TMProvider provider;
  const _WaitingView({required this.provider});

  @override
  Widget build(BuildContext context) {
    final contact = provider.currentContact;
    final next = provider.nextContact;
    final session = provider.currentSession!;

    return Scaffold(
      appBar: AppBar(
        title: Text(session.name),
        actions: const [SyncStatusChip()],
      ),
      body: Column(
        children: [
          _ProgressBar(session: session),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 재시도 배지
                  if (contact != null && contact.retryCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🔄', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(
                            contact.retryLabel,
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // 연락처 정보
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: Colors.blue.shade50,
                    child: Text(
                      contact?.name.substring(0, 1) ?? '?',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    contact?.name ?? '',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    contact?.phone ?? '',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),

                  const SizedBox(height: 40),

                  // 통화 버튼
                  GestureDetector(
                    onTap: () => provider.startCall(),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.call, color: Colors.white, size: 36),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('통화 시작', style: TextStyle(color: Colors.grey)),

                  const SizedBox(height: 32),

                  // 다음 연락처 미리보기
                  if (next != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('다음', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          const SizedBox(width: 8),
                          Text(next.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                          const SizedBox(width: 6),
                          Text(next.phone, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          if (next.retryCount > 0) ...[
                            const SizedBox(width: 6),
                            const Text('🔄', style: TextStyle(fontSize: 12)),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton.icon(
              onPressed: () => provider.skipContact(),
              icon: const Icon(Icons.skip_next, size: 18, color: Colors.grey),
              label: const Text('건너뛰기', style: TextStyle(color: Colors.grey)),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────
// 2. 통화 중 화면
// ──────────────────────────────────────────────────
class _CallingView extends StatelessWidget {
  final TMProvider provider;
  const _CallingView({required this.provider});

  @override
  Widget build(BuildContext context) {
    final contact = provider.currentContact;
    final secs = provider.callSeconds;
    final min = (secs ~/ 60).toString().padLeft(2, '0');
    final sec = (secs % 60).toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: Colors.blue.shade700,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              children: [
                const SizedBox(height: 40),
                CircleAvatar(
                  radius: 56,
                  backgroundColor: Colors.white24,
                  child: Text(
                    contact?.name.substring(0, 1) ?? '?',
                    style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  contact?.name ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Text(
                  contact?.phone ?? '',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  '$min:$sec',
                  style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w300),
                ),
                const Text('통화 중', style: TextStyle(color: Colors.white70)),
              ],
            ),
            GestureDetector(
              onTap: () => provider.endCall(),
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.call_end, color: Colors.white, size: 32),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────
// 3. 결과 입력 화면 (v4: 재시도 경고 포함)
// ──────────────────────────────────────────────────
class _RecordingView extends StatefulWidget {
  final TMProvider provider;
  const _RecordingView({required this.provider});

  @override
  State<_RecordingView> createState() => _RecordingViewState();
}

class _RecordingViewState extends State<_RecordingView> {
  final _memoController = TextEditingController();

  bool get _willRetry => widget.provider.selectedResults
      .any(ResultCode.isRetryTrigger);

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;

    return Scaffold(
      appBar: AppBar(
        title: Text(provider.currentContact?.name ?? '결과 입력'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 재시도 경고 배너 ──────────────────
            if (_willRetry)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '⚠️ 이 연락처는 재시도 목록에 추가됩니다',
                        style: TextStyle(color: Colors.orange, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // ── 통화 결과 ─────────────────────────
            const Text('통화 결과', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            _buildResultGrid(provider),

            const SizedBox(height: 20),

            // ── 고객 평가 ─────────────────────────
            const Text('고객 평가', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            _buildGradeRow(provider),

            const SizedBox(height: 20),

            // ── 메모 ──────────────────────────────
            const Text('메모', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            TextField(
              controller: _memoController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '메모를 입력하세요...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              onChanged: provider.setMemo,
            ),

            const SizedBox(height: 24),

            // ── 저장 버튼 ─────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: provider.selectedResults.isEmpty ? null : () => provider.saveResult(),
                icon: const Icon(Icons.save_rounded),
                label: const Text('저장하고 다음으로', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultGrid(TMProvider provider) {
    final results = [
      (ResultCode.callable,     '통화가능', Colors.blue),
      (ResultCode.smsOk,        '문자가능', Colors.purple),
      (ResultCode.allRejected,  '모두거부', Colors.red),
      (ResultCode.callback,     '콜백요청', Colors.orange),
      (ResultCode.noConnect,    '연결안됨', Colors.blueGrey),
      (ResultCode.wrongNumber,  '잘못된번호', Colors.brown),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 3,
      children: results.map((r) {
        final isSelected = provider.selectedResults.contains(r.$1);
        return GestureDetector(
          onTap: () {
            provider.toggleResult(r.$1);
            setState(() {});
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: isSelected ? r.$3 : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? r.$3 : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              r.$2,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade700,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGradeRow(TMProvider provider) {
    final grades = [
      (CustomerGrade.a, 'A · 우수고객', Colors.green),
      (CustomerGrade.b, 'B · 일반고객', Colors.blue),
      (CustomerGrade.c, 'C · 관리필요', Colors.grey),
    ];

    return Row(
      children: grades.map((g) {
        final isSelected = provider.selectedGrade == g.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              provider.setGrade(g.$1);
              setState(() {});
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? g.$3 : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? g.$3 : Colors.grey.shade300,
                  width: isSelected ? 2 : 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                g.$2,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ──────────────────────────────────────────────────
// 4. 세션 완료 화면 (v4: 재시도 섹션 추가)
// ──────────────────────────────────────────────────
class _CompletedView extends StatelessWidget {
  final TMProvider provider;
  const _CompletedView({required this.provider});

  @override
  Widget build(BuildContext context) {
    final session = provider.currentSession!;
    final retryContacts = session.retryContacts;
    final stats = session.resultStats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('세션 완료'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 완료 헤더
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: retryContacts.isEmpty
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    child: Icon(
                      retryContacts.isEmpty ? Icons.check_circle : Icons.replay_circle_filled,
                      color: retryContacts.isEmpty ? Colors.green : Colors.orange,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    session.name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    retryContacts.isEmpty ? '모든 통화 완료' : '기본 통화 완료',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 요약 통계
            _StatRow('총 연락처', '${session.totalContacts}명'),
            _StatRow('완료', '${session.completedCount}명', color: Colors.green),
            _StatRow('건너뜀', '${session.contacts.where((c) => c.isSkipped).length}명', color: Colors.grey),
            if (retryContacts.isNotEmpty)
              _StatRow('재시도 대기', '${retryContacts.length}명', color: Colors.orange),

            const Divider(height: 24),

            // 결과별 통계
            const Text('결과 통계', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            ...stats.entries.map(
              (e) => _StatRow(ResultCode.label(e.key), '${e.value}건'),
            ),

            const SizedBox(height: 24),

            // ── v4: 재시도 대기 카드 ──────────────
            if (retryContacts.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.refresh, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text(
                          '재시도 대기 중 (${retryContacts.length}명)',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...retryContacts.map((c) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Text('• ${c.name}', style: const TextStyle(fontWeight: FontWeight.w500)),
                          const SizedBox(width: 8),
                          ...c.resultCodes.where(ResultCode.isRetryTrigger).map(
                            (code) => Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                ResultCode.label(code),
                                style: const TextStyle(fontSize: 11, color: Colors.orange),
                              ),
                            ),
                          ),
                          if (c.retryCount > 1)
                            Text(
                              ' (${c.retryCount}회차)',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                        ],
                      ),
                    )),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => provider.startRetryRound(),
                        icon: const Icon(Icons.replay, size: 18),
                        label: const Text('재시도 계속 진행하기'),
                        style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Excel 내보내기
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await ExcelService().exportSession(session);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('📥 Excel 파일이 저장되었습니다')),
                    );
                  }
                },
                icon: const Icon(Icons.table_chart_rounded),
                label: const Text('Excel 내보내기'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  provider.exitSession();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.home_rounded),
                label: const Text('홈으로'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700])),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────
// 진행률 바
// ──────────────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  final TMSession session;
  const _ProgressBar({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${session.completedCount}/${session.totalContacts}명 완료',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              if (session.retryContacts.isNotEmpty)
                Row(
                  children: [
                    const Icon(Icons.refresh, size: 14, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      '재시도 ${session.retryContacts.length}명',
                      style: const TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: session.progressPercent,
              backgroundColor: Colors.grey.shade200,
              color: Colors.blue,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}
