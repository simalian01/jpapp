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
      theme: () {
        final base = ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo);
        return base.copyWith(
          scaffoldBackgroundColor: const Color(0xfff7f7fb),
          cardTheme: base.cardTheme.copyWith(
            elevation: 0,
            color: Colors.white,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          appBarTheme: base.appBarTheme.copyWith(centerTitle: true, elevation: 0),
          inputDecorationTheme:
              base.inputDecorationTheme.copyWith(border: const OutlineInputBorder()),
        );
      }(),
      home: const AppRoot(child: HomeShell()),
    );
  }
}
