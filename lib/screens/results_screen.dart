// results_screen.dart - v4: shows all sessions with retry info
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/tm_provider.dart';
import '../models/tm_models.dart';
import '../services/excel_service.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('전체 결과')),
      body: Consumer<TMProvider>(
        builder: (context, provider, _) {
          if (provider.sessions.isEmpty) {
            return const Center(child: Text('세션이 없습니다'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: provider.sessions.length,
            itemBuilder: (ctx, i) {
              final session = provider.sessions[i];
              return _SessionResultCard(session: session);
            },
          );
        },
      ),
    );
  }
}

class _SessionResultCard extends StatelessWidget {
  final TMSession session;
  const _SessionResultCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final stats = session.resultStats;
    final retryCount = session.retryContacts.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    session.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                _StatusBadge(session: session),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${session.completedCount}/${session.totalContacts}명 완료 · ${_formatDate(session.createdAt)}',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            if (retryCount > 0) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.refresh, size: 14, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text(
                    '재시도 대기 $retryCount명',
                    style: const TextStyle(color: Colors.orange, fontSize: 13),
                  ),
                ],
              ),
            ],
            const Divider(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: stats.entries.map((e) => Chip(
                label: Text('${ResultCode.label(e.key)}: ${e.value}건',
                    style: const TextStyle(fontSize: 12)),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )).toList(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await ExcelService().exportSession(session);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Excel 저장 완료')),
                    );
                  }
                },
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Excel 내보내기', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
}

class _StatusBadge extends StatelessWidget {
  final TMSession session;
  const _StatusBadge({required this.session});

  @override
  Widget build(BuildContext context) {
    if (session.isComplete) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('완료', style: TextStyle(color: Colors.green, fontSize: 12)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: const Text('진행중', style: TextStyle(color: Colors.orange, fontSize: 12)),
    );
  }
}
