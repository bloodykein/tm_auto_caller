// settings_screen.dart - sync settings
import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _syncEnabled = false;
  String _serviceType = 'firebase';
  bool _instantSync = true;
  bool _wifiOnly = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          // ── 클라우드 동기화 ─────────────────────
          const _SectionTitle('클라우드 동기화'),
          SwitchListTile(
            title: const Text('실시간 동기화'),
            subtitle: const Text('TM 결과를 클라우드에 자동 저장'),
            value: _syncEnabled,
            onChanged: (v) => setState(() => _syncEnabled = v),
          ),
          if (_syncEnabled) ...[
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              title: const Text('동기화 서비스'),
              trailing: DropdownButton<String>(
                value: _serviceType,
                items: const [
                  DropdownMenuItem(value: 'firebase', child: Text('Firebase')),
                  DropdownMenuItem(value: 'sheets', child: Text('Google Sheets')),
                ],
                onChanged: (v) => setState(() => _serviceType = v!),
              ),
            ),
            SwitchListTile(
              title: const Text('즉시 동기화'),
              subtitle: const Text('결과 저장 즉시 클라우드에 전송'),
              value: _instantSync,
              onChanged: (v) => setState(() => _instantSync = v),
            ),
            SwitchListTile(
              title: const Text('Wi-Fi만 사용'),
              subtitle: const Text('모바일 데이터 사용 안 함'),
              value: _wifiOnly,
              onChanged: (v) => setState(() => _wifiOnly = v),
            ),
          ],

          // ── 앱 정보 ─────────────────────────────
          const _SectionTitle('앱 정보'),
          const ListTile(
            title: Text('버전'),
            trailing: Text('v4.0.0', style: TextStyle(color: Colors.grey)),
          ),
          const ListTile(
            title: Text('개발'),
            trailing: Text('TM Auto Caller', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}
