import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/webhook_sync_service.dart';
import '../services/tm_provider.dart';
import '../models/tm_models.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  bool _isTesting = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  Future<void> _loadUrl() async {
    final svc = context.read<TMProvider>().cloudSync as WebhookSyncService?;
    if (svc != null) {
      final url = await svc.getWebhookUrl();
      if (mounted) setState(() => _urlController.text = url);
    }
  }

  Future<void> _saveUrl() async {
    final svc = context.read<TMProvider>().cloudSync as WebhookSyncService?;
    if (svc != null) {
      await svc.saveWebhookUrl(_urlController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 저장되었습니다'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() { _isTesting = true; _testResult = null; });
    final svc = context.read<TMProvider>().cloudSync as WebhookSyncService?;
    if (svc == null) {
      setState(() { _isTesting = false; _testResult = '❌ 서비스 초기화 오류'; _testSuccess = false; });
      return;
    }
    try {
      await svc.saveWebhookUrl(_urlController.text.trim());
      await svc.syncResult(
        sessionId: 'test_session',
        sessionName: '연결 테스트',
        contact: TMContact(
          id: 'test_001', name: '테스트 고객', phone: '010-0000-0000',
          resultCodes: ['통화가능'], customerGrade: 'A', memo: '앱 연결 테스트',
          callDuration: 30, retryCount: 0, isCompleted: true, isSkipped: false,
        ),
      );
      setState(() { _isTesting = false; _testResult = '✅ 연결 성공! 구글 시트를 확인하세요.'; _testSuccess = true; });
    } catch (e) {
      setState(() { _isTesting = false; _testResult = '❌ 연결 실패: $e'; _testSuccess = false; });
    }
  }

  @override
  void dispose() { _urlController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('구글 시트 동기화'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Apps Script 웹훅 URL', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    hintText: 'https://script.google.com/macros/s/.../exec',
                    border: OutlineInputBorder(), isDense: true,
                  ),
                  maxLines: 2,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: ElevatedButton.icon(onPressed: _saveUrl, icon: const Icon(Icons.save), label: const Text('저장'))),
                  const SizedBox(width: 8),
                  Expanded(child: ElevatedButton.icon(
                    onPressed: _isTesting ? null : _testConnection,
                    icon: _isTesting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_tethering),
                    label: Text(_isTesting ? '테스트 중...' : '연결 테스트'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  )),
                ]),
                if (_testResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _testSuccess ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _testSuccess ? Colors.green : Colors.red),
                    ),
                    child: Text(_testResult!, style: TextStyle(color: _testSuccess ? Colors.green.shade800 : Colors.red.shade800)),
                  ),
                ],
                const SizedBox(height: 8),
                const Text('💡 통화 결과 저장 시 구글 시트에 자동 기록됩니다.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('앱 정보'),
          const Card(child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('TM Auto Caller'),
            subtitle: Text('v4.0.3 · 개발: TM Auto Caller'),
          )),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
  );
}
