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
    return MaterialApp(
      title: 'JP Study Offline',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const AppRoot(child: HomeShell()),
    );
  }
}
