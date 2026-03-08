import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/tm_provider.dart';
import '../models/tm_models.dart';
import 'tm_session_screen.dart';

class ContactSelectScreen extends StatefulWidget {
  const ContactSelectScreen({super.key});

  @override
  State<ContactSelectScreen> createState() => _ContactSelectScreenState();
}

class _ContactSelectScreenState extends State<ContactSelectScreen> {
  List<fc.Contact> _allContacts = [];
  List<fc.Contact> _filtered = [];
  final Set<String> _selectedIds = {};
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  String _loadingMessage = '연락처 불러오는 중...';
  String? _errorMessage;
  String _sessionName = '';

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _loadingMessage = '권한 확인 중...';
    });

    try {
      // 1단계: 권한 요청
      final status = await Permission.contacts.request();
      if (!status.isGranted) {
        setState(() {
          _loading = false;
          _errorMessage = '연락처 권한이 필요합니다.\n설정에서 권한을 허용해 주세요.';
        });
        return;
      }

      setState(() => _loadingMessage = '연락처 로딩 중... (잠시 기다려 주세요)');

      // 2단계: 사진 없이 빠르게 로드 (핵심 수정)
      final contacts = await fc.FlutterContacts.getContacts(
        withProperties: true,   // 전화번호 포함
        withPhoto: false,        // 사진 제외 → 속도 대폭 향상
        withThumbnail: false,    // 썸네일 제외
        sorted: true,
      );

      setState(() => _loadingMessage = '전화번호 필터링 중...');

      // 3단계: 전화번호 있는 연락처만 필터
      final withPhone = contacts
          .where((c) => c.phones.isNotEmpty)
          .toList();

      if (!mounted) return;

      setState(() {
        _allContacts = withPhone;
        _filtered = withPhone;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = '연락처를 불러오지 못했습니다.\n오류: $e';
      });
    }
  }

  void _filter(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filtered = _allContacts.where((c) {
        final name = c.displayName.toLowerCase();
        final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
        return name.contains(q) || phone.contains(q);
      }).toList();
    });
  }

  void _toggleContact(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _filtered.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_filtered.map((c) => c.id));
      }
    });
  }

  Future<void> _startSession() async {
    if (_selectedIds.isEmpty) return;

    final nameController = TextEditingController(
      text: '세션_${DateTime.now().month}월${DateTime.now().day}일',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('세션 이름'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: '세션 이름 입력'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('시작'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    _sessionName = nameController.text.trim().isEmpty
        ? '세션_${DateTime.now().millisecondsSinceEpoch}'
        : nameController.text.trim();

    final provider = Provider.of<TMProvider>(context, listen: false);

    final selectedContacts = _allContacts
        .where((c) => _selectedIds.contains(c.id))
        .map((c) => TMContact(
              id: c.id,
              name: c.displayName,
              phone: c.phones.first.number,
            ))
        .toList();

    final session = await provider.startNewSession(
      name: _sessionName,
      contacts: selectedContacts,
    );

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TMSessionScreen(session: session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_loading
            ? '연락처 로딩 중'
            : '연락처 선택 (${_allContacts.length}명)'),
        actions: [
          if (!_loading && _errorMessage == null)
            TextButton(
              onPressed: _selectAll,
              child: Text(
                _selectedIds.length == _filtered.length ? '전체 해제' : '전체 선택',
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _selectedIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _startSession,
              icon: const Icon(Icons.play_arrow),
              label: Text('세션 시작 (${_selectedIds.length}명)'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    // 로딩 중
    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(_loadingMessage, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            const Text(
              '연락처가 많을 경우 10~30초 걸릴 수 있습니다.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // 에러 발생
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadContacts,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => openAppSettings(),
                child: const Text('앱 권한 설정 열기'),
              ),
            ],
          ),
        ),
      );
    }

    // 연락처 없음
    if (_allContacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.contacts, size: 60, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('전화번호가 있는 연락처가 없습니다.'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadContacts,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 불러오기'),
            ),
          ],
        ),
      );
    }

    // 정상 표시
    return Column(
      children: [
        // 검색창
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            onChanged: _filter,
            decoration: InputDecoration(
              hintText: '이름 또는 전화번호 검색',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _filter('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
            ),
          ),
        ),

        // 선택 카운터 바
        if (_selectedIds.isNotEmpty)
          Container(
            color: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('${_selectedIds.length}명 선택됨'),
                const Spacer(),
                TextButton(
                  onPressed: _startSession,
                  child: const Text('세션 시작 →'),
                ),
              ],
            ),
          ),

        // 연락처 목록
        Expanded(
          child: ListView.builder(
            itemCount: _filtered.length,
            itemBuilder: (ctx, index) {
              final contact = _filtered[index];
              final isSelected = _selectedIds.contains(contact.id);
              final phone = contact.phones.isNotEmpty
                  ? contact.phones.first.number
                  : '번호 없음';

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade300,
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white)
                      : Text(
                          contact.displayName.isNotEmpty
                              ? contact.displayName[0]
                              : '?',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
                title: Text(contact.displayName),
                subtitle: Text(phone),
                trailing: isSelected
                    ? Icon(Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary)
                    : const Icon(Icons.radio_button_unchecked,
                        color: Colors.grey),
                onTap: () => _toggleContact(contact.id),
              );
            },
          ),
        ),
      ],
    );
  }
}
