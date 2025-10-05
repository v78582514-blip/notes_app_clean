// ===============================
// pubspec.yaml (put at project root)
// ===============================
/*
name: notes_app
publish_to: "none"
description: Simple notes app with groups, sharing, export/import, private groups
version: 1.0.0+1

environment:
  sdk: ">=3.3.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  shared_preferences: ^2.2.3
  share_plus: ^10.0.2
  flutter_secure_storage: ^9.2.2

flutter:
  uses-material-design: true
*/

// ===============================
// lib/main.dart (single-file app)
// ===============================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await settings.load();
  await NotesStore.instance.load();
  runZonedGuarded(() => runApp(const NotesApp()), (e, s) {});
}

/* ===================== SETTINGS (только тема) ===================== */
final settings = SettingsStore();

enum AppThemeMode { system, light, dark }

class SettingsStore extends ChangeNotifier {
  static const _k = 'settings_v1_theme_only';
  AppThemeMode themeMode = AppThemeMode.system;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k);
    if (raw != null) {
      themeMode = AppThemeMode.values[int.parse(raw)];
    }
  }

  Future<void> setTheme(AppThemeMode m) async {
    themeMode = m;
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, m.index.toString());
    notifyListeners();
  }
}

/* ===================== MODELS ===================== */
class NoteModel {
  String id;
  String title;
  String text;
  DateTime createdAt;
  DateTime updatedAt;

  NoteModel({
    required this.id,
    required this.title,
    required this.text,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static NoteModel fromJson(Map<String, dynamic> j) => NoteModel(
        id: j['id'],
        title: j['title'] ?? '',
        text: j['text'] ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt'] ?? '') ?? DateTime.now(),
      );
}

class GroupModel {
  String id;
  String name;
  List<String> noteIds;
  bool isPrivate;
  String? passwordHash; // stored via secure storage key

  GroupModel({
    required this.id,
    required this.name,
    this.noteIds = const [],
    this.isPrivate = false,
    this.passwordHash,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'noteIds': noteIds,
        'isPrivate': isPrivate,
        'passwordHash': passwordHash,
      };

  static GroupModel fromJson(Map<String, dynamic> j) => GroupModel(
        id: j['id'],
        name: j['name'] ?? 'Group',
        noteIds: (j['noteIds'] as List?)?.map((e) => e.toString()).toList() ?? [],
        isPrivate: j['isPrivate'] == true,
        passwordHash: j['passwordHash'],
      );
}

/* ===================== STORAGE ===================== */
class NotesStore extends ChangeNotifier {
  static final NotesStore instance = NotesStore._();
  NotesStore._();

  static const _kNotes = 'notes_v2';
  static const _kGroups = 'groups_v2';
  final _secure = const FlutterSecureStorage();

  final Map<String, NoteModel> notes = {};
  final Map<String, GroupModel> groups = {};

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final notesRaw = p.getString(_kNotes);
    final groupsRaw = p.getString(_kGroups);
    if (notesRaw != null) {
      final list = (jsonDecode(notesRaw) as List).cast<Map>();
      for (final j in list) {
        final n = NoteModel.fromJson(j.cast());
        notes[n.id] = n;
      }
    }
    if (groupsRaw != null) {
      final list = (jsonDecode(groupsRaw) as List).cast<Map>();
      for (final j in list) {
        final g = GroupModel.fromJson(j.cast());
        groups[g.id] = g;
      }
    }
    if (groups.isEmpty) {
      // Default group
      final g = GroupModel(id: _gid(), name: 'Мои заметки');
      groups[g.id] = g;
      await save();
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kNotes,
      jsonEncode(notes.values.map((e) => e.toJson()).toList()),
    );
    await p.setString(
      _kGroups,
      jsonEncode(groups.values.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  // Password helpers
  Future<void> setGroupPassword(GroupModel g, String password) async {
    final hash = _hash(password);
    g.isPrivate = true;
    g.passwordHash = hash;
    await save();
    await _secure.write(key: 'group:${g.id}:hash', value: hash);
  }

  Future<void> clearGroupPassword(GroupModel g) async {
    g.isPrivate = false;
    g.passwordHash = null;
    await _secure.delete(key: 'group:${g.id}:hash');
    await save();
  }

  Future<bool> checkGroupPassword(GroupModel g, String password) async {
    final stored = g.passwordHash ?? await _secure.read(key: 'group:${g.id}:hash');
    return stored != null && stored == _hash(password);
  }

  // CRUD
  GroupModel createGroup(String name) {
    final g = GroupModel(id: _gid(), name: name);
    groups[g.id] = g;
    save();
    return g;
  }

  NoteModel createNote({required String groupId, String title = '', String text = ''}) {
    final n = NoteModel(id: _nid(), title: title, text: text);
    notes[n.id] = n;
    groups[groupId]?.noteIds = [n.id, ...groups[groupId]!.noteIds];
    save();
    return n;
  }

  void deleteNote(NoteModel n) {
    notes.remove(n.id);
    for (final g in groups.values) {
      g.noteIds.remove(n.id);
    }
    save();
  }

  void deleteGroup(GroupModel g) {
    for (final id in g.noteIds) {
      notes.remove(id);
    }
    groups.remove(g.id);
    save();
  }

  void moveNote(String noteId, String fromGroupId, String toGroupId) {
    groups[fromGroupId]?.noteIds.remove(noteId);
    groups[toGroupId]?.noteIds.insert(0, noteId);
    save();
  }

  // Export/Import (JSON strings)
  String exportNote(NoteModel n) => jsonEncode(n.toJson());

  NoteModel importNote(String jsonStr, {required String intoGroupId}) {
    final n = NoteModel.fromJson(jsonDecode(jsonStr));
    // ensure new id to avoid clashes
    final newNote = NoteModel(
      id: _nid(),
      title: n.title,
      text: n.text,
      createdAt: n.createdAt,
      updatedAt: DateTime.now(),
    );
    notes[newNote.id] = newNote;
    groups[intoGroupId]?.noteIds.insert(0, newNote.id);
    save();
    return newNote;
  }

  String exportGroup(GroupModel g) {
    final gJson = g.toJson();
    final noteObjs = g.noteIds.map((id) => notes[id]?.toJson()).whereType<Map<String, dynamic>>().toList();
    return jsonEncode({
      'group': gJson,
      'notes': noteObjs,
    });
  }

  GroupModel importGroup(String jsonStr) {
    final obj = jsonDecode(jsonStr);
    final g0 = GroupModel.fromJson(obj['group'] as Map<String, dynamic>);
    final g = GroupModel(id: _gid(), name: g0.name, isPrivate: false);
    groups[g.id] = g;
    final notesList = (obj['notes'] as List).cast<Map<String, dynamic>>();
    for (final j in notesList) {
      final n0 = NoteModel.fromJson(j);
      final n = NoteModel(id: _nid(), title: n0.title, text: n0.text);
      notes[n.id] = n;
      g.noteIds.add(n.id);
    }
    save();
    return g;
  }
}

/* ===================== UTIL ===================== */
String _nid() => 'n_${DateTime.now().microsecondsSinceEpoch}';
String _gid() => 'g_${DateTime.now().microsecondsSinceEpoch}';
String _hash(String s) => base64Url.encode(const Utf8Encoder().convert(s)).split('').reversed.join(); // simple reversible obfuscation (demo)

/* ===================== APP ===================== */
class NotesApp extends StatefulWidget {
  const NotesApp({super.key});

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  @override
  void initState() {
    super.initState();
    settings.addListener(_onSettings);
    NotesStore.instance.addListener(_onSettings);
  }

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    NotesStore.instance.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final themeMode = switch (settings.themeMode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };

    return MaterialApp(
      title: 'Notes',
      themeMode: themeMode,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorSchemeSeed: Colors.indigo),
      home: const SafeArea(child: GroupsScreen()),
    );
  }
}

/* ===================== SCREENS ===================== */
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  @override
  Widget build(BuildContext context) {
    final store = NotesStore.instance;
    final groups = store.groups.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Группы заметок'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Настройки',
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'theme', child: Text('Тема')),
            ],
            onSelected: (v) async {
              if (v == 'theme') {
                await _chooseTheme(context);
              }
            },
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: groups.length,
        itemBuilder: (c, i) {
          final g = groups[i];
          return ListTile(
            leading: Icon(g.isPrivate ? Icons.lock : Icons.folder),
            title: Text(g.name),
            subtitle: Text('${g.noteIds.length} заметок'),
            onTap: () async {
              if (g.isPrivate) {
                final ok = await _askPassword(context, g);
                if (!ok) return;
              }
              if (!context.mounted) return;
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotesScreen(groupId: g.id)));
            },
            trailing: PopupMenuButton<String>(
              onSelected: (v) => _onGroupAction(context, g, v),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                PopupMenuItem(value: g.isPrivate ? 'unlock' : 'lock', child: Text(g.isPrivate ? 'Сделать публичной' : 'Сделать приватной')),
                const PopupMenuItem(value: 'export', child: Text('Экспортировать группу')),
                const PopupMenuItem(value: 'import', child: Text('Импорт в новую группу')),
                const PopupMenuItem(value: 'delete', child: Text('Удалить')),
              ],
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FloatingActionButton.extended(
          onPressed: () async {
            final name = await _promptText(context, title: 'Новая группа', hint: 'Название группы');
            if (name == null || name.trim().isEmpty) return;
            NotesStore.instance.createGroup(name.trim());
          },
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Добавить группу'),
        ),
      ),
      bottomNavigationBar: const SizedBox(height: 56), // чтобы FAB не перекрывался
    );
  }

  Future<void> _onGroupAction(BuildContext context, GroupModel g, String v) async {
    switch (v) {
      case 'rename':
        final name = await _promptText(context, title: 'Переименовать группу', initial: g.name);
        if (name != null && name.trim().isNotEmpty) {
          g.name = name.trim();
          await NotesStore.instance.save();
        }
        break;
      case 'lock':
        final pass = await _promptPassword(context, 'Пароль для приватной группы');
        if (pass != null && pass.length >= 4) {
          await NotesStore.instance.setGroupPassword(g, pass);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Группа сделана приватной')));
        }
        break;
      case 'unlock':
        await NotesStore.instance.clearGroupPassword(g);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Группа сделана публичной')));
        break;
      case 'export':
        final jsonStr = NotesStore.instance.exportGroup(g);
        await Share.share(jsonStr, subject: 'Экспорт группы: ${g.name}');
        break;
      case 'import':
        final pasted = await _promptMultiline(context,
            title: 'Вставьте JSON группы', hint: '{"group": {...}, "notes": [...]}');
        if (pasted != null && pasted.trim().isNotEmpty) {
          final newG = NotesStore.instance.importGroup(pasted.trim());
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Импорт завершён: ${newG.name}')));
        }
        break;
      case 'delete':
        final ok = await _confirm(context, 'Удалить группу «${g.name}» и все заметки?');
        if (ok) NotesStore.instance.deleteGroup(g);
        break;
    }
  }
}

class NotesScreen extends StatefulWidget {
  final String groupId;
  const NotesScreen({super.key, required this.groupId});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  @override
  Widget build(BuildContext context) {
    final store = NotesStore.instance;
    final g = store.groups[widget.groupId]!;
    final noteIds = g.noteIds;

    return Scaffold(
      appBar: AppBar(
        title: Text(g.name),
        actions: [
          IconButton(
            tooltip: 'Импорт заметки',
            onPressed: () async {
              final pasted = await _promptMultiline(context, title: 'Импорт заметки (JSON)', hint: '{"id":...,"title":...,"text":...}');
              if (pasted != null && pasted.trim().isNotEmpty) {
                NotesStore.instance.importNote(pasted.trim(), intoGroupId: g.id);
              }
            },
            icon: const Icon(Icons.file_download),
          )
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemBuilder: (c, i) {
          final n = store.notes[noteIds[i]]!;
          return ListTile(
            title: Text(n.title.isEmpty ? 'Без названия' : n.title),
            subtitle: Text(
              n.text.replaceAll('\n', ' ').trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorScreen(noteId: n.id, groupId: g.id))),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'share':
                    await Share.share(n.text, subject: n.title.isEmpty ? 'Заметка' : n.title);
                    break;
                  case 'export':
                    await Share.share(NotesStore.instance.exportNote(n), subject: 'Экспорт заметки: ${n.title}');
                    break;
                  case 'delete':
                    final ok = await _confirm(context, 'Удалить заметку «${n.title.isEmpty ? 'Без названия' : n.title}»?');
                    if (ok) NotesStore.instance.deleteNote(n);
                    break;
                }
              },
              itemBuilder: (c) => const [
                PopupMenuItem(value: 'share', child: Text('Поделиться (текст как есть)')),
                PopupMenuItem(value: 'export', child: Text('Экспорт (JSON)')),
                PopupMenuItem(value: 'delete', child: Text('Удалить')),
              ],
            ),
          );
        },
        separatorBuilder: (c, i) => const Divider(height: 1),
        itemCount: noteIds.length,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FloatingActionButton.extended(
          onPressed: () {
            final n = NotesStore.instance.createNote(groupId: g.id, title: '', text: '');
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorScreen(noteId: n.id, groupId: g.id)));
          },
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('Новая заметка'),
        ),
      ),
      bottomNavigationBar: const SizedBox(height: 56),
    );
  }
}

/* ===================== EDITOR ===================== */
class EditorScreen extends StatefulWidget {
  final String noteId;
  final String groupId;
  const EditorScreen({super.key, required this.noteId, required this.groupId});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late TextEditingController _title;
  late TextEditingController _text;
  bool numbering = false; // умная нумерация

  @override
  void initState() {
    super.initState();
    final n = NotesStore.instance.notes[widget.noteId]!;
    _title = TextEditingController(text: n.title);
    _text = TextEditingController(text: n.text);

    _text.addListener(_onChanged);
  }

  @override
  void dispose() {
    _title.dispose();
    _text.removeListener(_onChanged);
    _text.dispose();
    super.dispose();
  }

  void _onChanged() {
    final store = NotesStore.instance;
    final n = store.notes[widget.noteId]!;
    n.title = _title.text;
    n.text = _text.text;
    n.updatedAt = DateTime.now();
    store.save();
  }

  // Вставка следующего номера при Enter
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Шорткаты: Ctrl/Cmd + Shift + L — переключить нумерацию
    final isModifier = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (isModifier && HardwareKeyboard.instance.isShiftPressed && event.logicalKey == LogicalKeyboardKey.keyL) {
      setState(() => numbering = !numbering);
      // Автовставка "1. " если включили и курсор в начале строки
      _ensureFirstNumber();
      return KeyEventResult.handled;
    }

    if (numbering && event.logicalKey == LogicalKeyboardKey.enter) {
      _insertNextNumberOnNewline();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _ensureFirstNumber() {
    final sel = _text.selection;
    final text = _text.text;
    final lineStart = _lineStartIndex(text, sel.start);
    final line = _lineAt(text, sel.start);
    if (line.trim().isEmpty) {
      _text.value = _text.value.copyWith(
        text: text.replaceRange(lineStart, lineStart, '1. '),
        selection: TextSelection.collapsed(offset: sel.start + 3),
      );
    }
  }

  void _insertNextNumberOnNewline() {
    final sel = _text.selection;
    final text = _text.text;
    final idx = sel.start;
    final prevLine = _lineBefore(text, idx);
    final match = RegExp(r'^(\s*)(\d+)\.(\s+)').firstMatch(prevLine);
    if (match != null) {
      final indent = match.group(1) ?? '';
      final n = int.tryParse(match.group(2)!) ?? 1;
      final spaces = match.group(3) ?? ' ';
      final insert = '\n$indent${n + 1}.$spaces';
      _text.value = _text.value.copyWith(
        text: text.replaceRange(idx, idx, insert),
        selection: TextSelection.collapsed(offset: idx + insert.length),
      );
    } else {
      // если предыдущая строка пустая — вставляем "1. "
      final insert = '\n1. ';
      _text.value = _text.value.copyWith(
        text: text.replaceRange(idx, idx, insert),
        selection: TextSelection.collapsed(offset: idx + insert.length),
      );
    }
  }

  // utils for editor
  int _lineStartIndex(String text, int pos) {
    final prev = text.lastIndexOf('\n', pos - 1);
    return prev == -1 ? 0 : prev + 1;
  }

  String _lineAt(String text, int pos) {
    final start = _lineStartIndex(text, pos);
    final end = text.indexOf('\n', pos);
    return text.substring(start, end == -1 ? text.length : end);
  }

  String _lineBefore(String text, int pos) {
    final i = text.lastIndexOf('\n', pos - 1);
    if (i == -1) return text.substring(0, pos);
    final j = text.lastIndexOf('\n', i - 1);
    final start = j == -1 ? 0 : j + 1;
    return text.substring(start, i);
  }

  @override
  Widget build(BuildContext context) {
    final store = NotesStore.instance;
    final n = store.notes[widget.noteId]!;

    return Scaffold(
      appBar: AppBar(
        title: Text(n.title.isEmpty ? 'Редактор' : n.title),
        actions: [
          IconButton(
            tooltip: 'Поделиться текстом (как есть)',
            onPressed: () => Share.share(_text.text, subject: _title.text.isEmpty ? 'Заметка' : _title.text),
            icon: const Icon(Icons.ios_share),
          ),
          PopupMenuButton<String>(
            tooltip: 'Ещё',
            onSelected: (v) async {
              switch (v) {
                case 'toggle_numbering':
                  setState(() => numbering = !numbering);
                  if (numbering) _ensureFirstNumber();
                  break;
                case 'copy_json':
                  final jsonStr = NotesStore.instance.exportNote(n);
                  await Clipboard.setData(ClipboardData(text: jsonStr));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON скопирован в буфер')));
                  break;
              }
            },
            itemBuilder: (c) => [
              PopupMenuItem(
                value: 'toggle_numbering',
                child: Row(children: [Icon(numbering ? Icons.format_list_numbered_rtl : Icons.format_list_numbered), const SizedBox(width: 8), const Text('Нумерация (умная)')]),
              ),
              const PopupMenuItem(value: 'copy_json', child: Text('Скопировать JSON заметки')),
            ],
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            children: [
              TextField(
                controller: _title,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'Заголовок',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Focus(
                  onKeyEvent: _handleKey,
                  child: TextField(
                    controller: _text,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: 'Текст заметки...\nСовет: Ctrl/Cmd + Shift + L — включить/выключить умную нумерацию',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.all(12),
                      suffixIcon: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(numbering ? Icons.format_list_numbered : Icons.text_fields, size: 20),
                          const SizedBox(height: 4),
                          const Text('Num', style: TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      // Удобные кнопки в нижней панели — не перекрываются системной панелью
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    numbering = !numbering;
                    setState(_ensureFirstNumber);
                  },
                  icon: const Icon(Icons.format_list_numbered),
                  label: Text(numbering ? 'Нумерация: ВКЛ' : 'Нумерация: ВЫКЛ'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final jsonStr = NotesStore.instance.exportNote(n);
                    await Share.share(jsonStr, subject: 'Экспорт заметки: ${_title.text}');
                  },
                  icon: const Icon(Icons.file_upload),
                  label: const Text('Экспорт JSON'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ===================== DIALOG HELPERS ===================== */
Future<String?> _promptText(BuildContext context, {required String title, String? hint, String? initial}) async {
  final c = TextEditingController(text: initial ?? '');
  return showDialog<String>(context: context, builder: (cxt) {
    return AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint ?? '')), 
      actions: [TextButton(onPressed: () => Navigator.pop(cxt), child: const Text('Отмена')), TextButton(onPressed: () => Navigator.pop(cxt, c.text), child: const Text('OK'))],
    );
  });
}

Future<String?> _promptMultiline(BuildContext context, {required String title, String? hint}) async {
  final c = TextEditingController();
  return showDialog<String>(context: context, builder: (cxt) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: TextField(controller: c, autofocus: true, maxLines: 8, decoration: InputDecoration(hintText: hint ?? '')), 
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(cxt), child: const Text('Отмена')), TextButton(onPressed: () => Navigator.pop(cxt, c.text), child: const Text('OK'))],
    );
  });
}

Future<String?> _promptPassword(BuildContext context, String title) async {
  final c = TextEditingController();
  return showDialog<String>(context: context, builder: (cxt) {
    return AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, obscureText: true, decoration: const InputDecoration(hintText: 'Минимум 4 символа')), 
      actions: [TextButton(onPressed: () => Navigator.pop(cxt), child: const Text('Отмена')), TextButton(onPressed: () => Navigator.pop(cxt, c.text), child: const Text('OK'))],
    );
  });
}

Future<bool> _confirm(BuildContext context, String title) async {
  final ok = await showDialog<bool>(context: context, builder: (cxt) {
    return AlertDialog(
      title: Text(title),
      actions: [
        TextButton(onPressed: () => Navigator.pop(cxt, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(cxt, true), child: const Text('Удалить')),
      ],
    );
  });
  return ok ?? false;
}

Future<bool> _askPassword(BuildContext context, GroupModel g) async {
  final pass = await _promptPassword(context, 'Введите пароль для «${g.name}»');
  if (pass == null) return false;
  final ok = await NotesStore.instance.checkGroupPassword(g, pass);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Неверный пароль')));
  }
  return ok;
}

Future<void> _chooseTheme(BuildContext context) async {
  final m = settings.themeMode;
  final selected = await showDialog<AppThemeMode>(context: context, builder: (cxt) {
    return SimpleDialog(title: const Text('Тема'), children: [
      RadioListTile<AppThemeMode>(value: AppThemeMode.system, groupValue: m, onChanged: (v) => Navigator.pop(cxt, v), title: const Text('Системная')),
      RadioListTile<AppThemeMode>(value: AppThemeMode.light, groupValue: m, onChanged: (v) => Navigator.pop(cxt, v), title: const Text('Светлая')),
      RadioListTile<AppThemeMode>(value: AppThemeMode.dark, groupValue: m, onChanged: (v) => Navigator.pop(cxt, v), title: const Text('Тёмная')),
    ]);
  });
  if (selected != null) settings.setTheme(selected);
}
