// main.dart - v4 entry point
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/tm_provider.dart';
import 'services/database_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TMApp());
}

class TMApp extends StatelessWidget {
  const TMApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TMProvider()..initialize(),
      child: MaterialApp(
        title: 'TM 자동 통화',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            elevation: 0,
            centerTitle: false,
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
