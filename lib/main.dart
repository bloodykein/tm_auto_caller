import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/tm_provider.dart';
import 'services/webhook_sync_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final syncService = WebhookSyncService();
  runApp(TMApp(syncService: syncService));
}

class TMApp extends StatelessWidget {
  final WebhookSyncService syncService;
  const TMApp({super.key, required this.syncService});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TMProvider(cloudSync: syncService)..initialize(),
      child: MaterialApp(
        title: 'TM 자동 통화',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
