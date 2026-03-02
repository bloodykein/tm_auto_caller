// contact_select_screen.dart - v4: retry badge on contacts
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
  final _searchController = TextEditingController();
  bool _loading = true;
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
    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      setState(() => _loading = false);
      return;
    }
    final contacts = await fc.FlutterContacts.getContacts(withProperties: true);
    setState(() {
      _allContacts = contacts.where((c) => c.phones.isNotEmpty).toList();
      _filtered = _allContacts;
      _loading = false;
    });
  }

  void _filter(String query) {
    setState(() {
      _filtered = _allContacts.where((c) =>
        c.displayName.contains(query) ||
        c.phones.any((p) => p.number.contains(query)),
      ).toList();
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

    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('세션 이름'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '예: 3월 TM 캠페인',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('시작'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    final selected = _allContacts
        .where((c) => _selectedIds.contains(c.id))
        .toList();

    final contacts = selected.asMap().entries.map((e) => TMContact(
      id: e.key + 1,
      name: e.value.displayName,
      phone: e.value.phones.first.number,
    )).toList();

    if (mounted) {
      await context.read<TMProvider>().startNewSession(
        name: name,
        contacts: contacts,
      );
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TMSessionScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('연락처 선택'),
        actions: [
          TextButton(
            onPressed: _selectAll,
            child: Text(
              _selectedIds.length == _filtered.length ? '전체 해제' : '전체 선택',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 검색
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: _filter,
              decoration: InputDecoration(
                hintText: '이름 또는 번호 검색',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),

          // 선택된 개수
          if (_selectedIds.isNotEmpty)
            Container(
              color: Colors.blue.shade50,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '${_selectedIds.length}명 선택됨',
                    style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _startSession,
                    child: const Text('세션 시작'),
                  ),
                ],
              ),
            ),

          // 목록
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) {
                      final c = _filtered[i];
                      final isSelected = _selectedIds.contains(c.id);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSelected ? Colors.blue.shade100 : Colors.grey.shade100,
                          child: Text(
                            c.displayName.isNotEmpty ? c.displayName.substring(0, 1) : '?',
                            style: TextStyle(
                              color: isSelected ? Colors.blue : Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(c.displayName),
                        subtitle: Text(
                          c.phones.isNotEmpty ? c.phones.first.number : '',
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: Colors.blue)
                            : const Icon(Icons.circle_outlined, color: Colors.grey),
                        onTap: () => _toggleContact(c.id),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _selectedIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _startSession,
              icon: const Icon(Icons.play_arrow),
              label: Text('${_selectedIds.length}명 시작'),
            )
          : null,
    );
  }
}
