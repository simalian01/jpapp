import 'package:flutter/material.dart';
import 'app_state.dart';
import 'pages/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JPStudyApp());
}

class JPStudyApp extends StatelessWidget {
  const JPStudyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF5B4B8A);
    return MaterialApp(
      title: 'JP Study Offline',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF5F2FF),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          filled: true,
          fillColor: Colors.white,
        ),
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      home: const AppRoot(child: HomeShell()),
    );
  }
}
