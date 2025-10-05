import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'storage.dart';
import 'screens/home_screen.dart';


Future<void> main() async {
WidgetsFlutterBinding.ensureInitialized();
await settings.load();
await AppStorage.instance.init();
runApp(const NotesApp());
}


/* ===================== SETTINGS (тема) ===================== */
final settings = SettingsStore();


enum AppThemeMode { system, light, dark }


class SettingsStore extends ChangeNotifier {
static const _k = 'settings_v1_theme_only';
AppThemeMode themeMode = AppThemeMode.system;


Future<void> load() async {
final p = await SharedPreferences.getInstance();
final raw = p.getString(_k);
if (raw != null) {
try {
final m = jsonDecode(raw) as Map<String, dynamic>;
themeMode = AppThemeMode.values[m['theme'] as int? ?? 0];
} catch (_) {}
}
}


Future<void> setTheme(AppThemeMode mode) async {
themeMode = mode;
notifyListeners();
final p = await SharedPreferences.getInstance();
await p.setString(_k, jsonEncode({'theme': mode.index}));
}
}


class NotesApp extends StatefulWidget {
const NotesApp({super.key});
@override
State<NotesApp> createState() => _NotesAppState();
}


class _NotesAppState extends State<NotesApp> {
@override
Widget build(BuildContext context) {
return AnimatedBuilder(
animation: settings,
builder: (context, _) {
final theme = ThemeData(useMaterial3: true, brightness: Brightness.light);
final dark = ThemeData(useMaterial3: true, brightness: Brightness.dark);
return MaterialApp(
title: 'Notes',
debugShowCheckedModeBanner: false,
theme: theme,
darkTheme: dark,
themeMode: switch (settings.themeMode) {
AppThemeMode.system => ThemeMode.system,
AppThemeMode.light => ThemeMode.light,
AppThemeMode.dark => ThemeMode.dark,
},
home: const HomeScreen(),
);
},
);
}
}
