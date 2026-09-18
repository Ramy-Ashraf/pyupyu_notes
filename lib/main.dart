import 'package:flutter/material.dart';

import 'controllers/notes_controller.dart';
import 'pages/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = NotesController();
  await controller.load();
  runApp(NotesApp(controller: controller));
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key, required this.controller});

  final NotesController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final seed = controller.accent;
        final density = controller.compact
            ? VisualDensity.compact
            : VisualDensity.standard;
        return MaterialApp(
          title: 'Notes',
          debugShowCheckedModeBanner: false,
          themeMode: controller.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Segoe UI',
            visualDensity: density,
            colorScheme: ColorScheme.fromSeed(
                seedColor: seed, brightness: Brightness.light),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Segoe UI',
            visualDensity: density,
            colorScheme: ColorScheme.fromSeed(
                seedColor: seed, brightness: Brightness.dark),
          ),
          home: HomePage(controller: controller),
        );
      },
    );
  }
}
