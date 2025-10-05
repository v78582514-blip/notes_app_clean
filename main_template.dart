import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/* ===================== BOOT ===================== */

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await settings.load();
  runZonedGuarded(() => runApp(const NotesApp()), (e, s) {});
}

/* ===================== SETTINGS ===================== */

final settings = SettingsStore();

enum AppThemeMode { system, light, dark }

class SettingsStore extends ChangeNotifier {
  static const _k = 'settings_v1_theme_only';
  AppThemeMode themeMode = AppThemeMode.system;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k);
    if (raw != null && raw.isNotEmpty) {
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      switch (m['theme'] as String? ?? 'system') {
        case 'light': themeMode = AppThemeMode.light; break;
        case 'dark': themeMode = AppThemeMode.dark; break;
        default: themeMode = AppThemeMode.system;
      }
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode({
      'theme': switch (themeMode) {
        AppThemeMode.light => 'light',
        AppThemeMode.dark => 'dark',
        _ => 'system',
      }
    }));
  }

  Future<void> setTheme(AppThemeMode m) async { themeMode = m; await _save(); notifyListeners(); }

  ThemeMode get flutterThemeMode => switch (themeMode) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

/* ===================== APP ===================== */

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (_, __) {
        final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Заметки',
          themeMode: settings.flutterThemeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: scheme,
            inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
          ),
          darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
          ),
          home: const NotesScreen(),
        );
      },
    );
  }
}

/* ===================== MODELS ===================== */

class Note {
  String id;
  String title;
  String text;
  DateTime createdAt;
  DateTime updatedAt;
  int? colorHex;
  String? groupId;
  bool numbered;

  Note({
    required this.id,
    required this.title,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.colorHex,
    this.groupId,
    this.numbered = false,
  });

  factory Note.newNote() {
    final now = DateTime.now();
    return Note(
      id: now.microsecondsSinceEpoch.toString(),
      title: '',
      text: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  Note copyWith({
    String? title,
    String? text,
    DateTime? updatedAt,
    int? colorHex,
    bool keepNullColor = false,
    String? groupId,
    bool setGroupId = false,
    bool? numbered,
  }) => Note(
    id: id,
    title: title ?? this.title,
    text: text ?? this.text,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    colorHex: keepNullColor ? null : (colorHex ?? this.colorHex),
    groupId: setGroupId ? groupId : this.groupId,
    numbered: numbered ?? this.numbered,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'text': text,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'colorHex': colorHex,
    'groupId': groupId,
    'numbered': numbered,
  };

  static Note fromJson(Map<String, dynamic> json) => Note(
    id: json['id'] as String,
    title: (json['title'] ?? '') as String,
    text: (json['text'] ?? '') as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
    colorHex: json['colorHex'] as int?,
    groupId: json['groupId'] as String?,
    numbered: (json['numbered'] as bool?) ?? false,
  );
}

class Group {
  String id;
  String title;
  DateTime updatedAt;

  bool isPrivate;
  String? salt;
  String? passHash;

  Group({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.isPrivate = false,
    this.salt,
    this.passHash,
  });

  Group copyWith({
    String? title,
    DateTime? updatedAt,
    bool? isPrivate,
    String? salt,
    String? passHash,
  }) => Group(
    id: id,
    title: title ?? this.title,
    updatedAt: updatedAt ?? this.updatedAt,
    isPrivate: isPrivate ?? this.isPrivate,
    salt: salt ?? this.salt,
    passHash: passHash ?? this.passHash,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'isPrivate': isPrivate,
    'salt': salt,
    'passHash': passHash,
  };

  static Group fromJson(Map<String, dynamic> json) => Group(
    id: json['id'] as String,
    title: (json['title'] ?? '') as String,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
    isPrivate: (json['isPrivate'] as bool?) ?? false,
    salt: json['salt'] as String?,
    passHash: json['passHash'] as String?,
  );
}

/* ===================== STORE ===================== */

class NotesStore extends ChangeNotifier {
  static const _prefsKey = 'notes_v12_privacy_numbering_native_share';
  final List<Note> _notes = [];
  final List<Group> _groups = [];
  bool _loaded = false;
  String? _error;

  List<Note> get notes => List.unmodifiable(_notes);
  List<Group> get groups => List.unmodifiable(_groups);
  bool get isLoaded => _loaded;
  String? get lastError => _error;

  Group? groupById(String id) => _groups.cast<Group?>().firstWhere(
        (g) => g?.id == id, orElse: () => null);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final ns = (decoded['notes'] as List? ?? [])
              .map((e) => Note.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          final gs = (decoded['groups'] as List? ?? [])
              .map((e) => Group.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          _notes..clear()..addAll(ns);
          _groups..clear()..addAll(gs);
        }
      }
      if (_notes.isEmpty) {
        _notes.addAll([
          Note(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: 'Советы',
            text: '👋 Перетащите заметку на другую — получится группа.\nДолгое нажатие — перетаскивание.',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            colorHex: const Color(0xFF64B5F6).value,
          ),
          Note(
            id: (DateTime.now().microsecondsSinceEpoch + 1).toString(),
            title: 'Удаление',
            text: 'Перетащите заметку в верхний левый красный блок «Удалить».',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            colorHex: const Color(0xFFFFD54F).value,
          ),
        ]);
        await _persist();
      }
    } catch (e) {
      _error = 'Ошибка загрузки: $e';
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode({
        'notes': _notes.map((e) => e.toJson()).toList(),
        'groups': _groups.map((e) => e.toJson()).toList(),
      });
      await prefs.setString(_prefsKey, raw);
    } catch (e) {
      _error = 'Ошибка сохранения: $e';
      notifyListeners();
    }
  }

  Future<void> addNote(Note note) async { _notes.add(note); await _persist(); notifyListeners(); }
  Future<void> updateNote(Note note) async {
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i != -1) {
      _notes[i] = note.copyWith(updatedAt: DateTime.now());
      await _persist(); notifyListeners();
    }
  }
  Future<void> deleteNote(String id) async { _notes.removeWhere((n) => n.id == id); await _persist(); notifyListeners(); }

  Future<void> addGroup(Group g) async { _groups.add(g); await _persist(); notifyListeners(); }
  Future<void> updateGroup(Group g) async {
    final i = _groups.indexWhere((x) => x.id == g.id);
    if (i != -1) { _groups[i] = g.copyWith(updatedAt: DateTime.now()); await _persist(); notifyListeners(); }
  }
  Future<void> deleteGroup(String groupId) async {
    _notes.removeWhere((n) => n.groupId == groupId);
    _groups.removeWhere((g) => g.id == groupId);
    await _persist(); notifyListeners();
  }

  List<Note> notesInGroup(String groupId) => _notes.where((n) => n.groupId == groupId).toList();

  Future<void> addNoteToGroup(String noteId, String groupId) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx != -1) {
      _notes[idx] = _notes[idx].copyWith(groupId: groupId, setGroupId: true, updatedAt: DateTime.now());
      await _persist(); notifyListeners();
    }
  }
  Future<void> removeNoteFromGroup(String noteId) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx != -1) {
      _notes[idx] = _notes[idx].copyWith(groupId: null, setGroupId: true, updatedAt: DateTime.now());
      await _persist(); notifyListeners();
    }
  }

  Future<void> createGroupWith(String noteAId, String noteBId) async {
    final a = _notes.firstWhere((n) => n.id == noteAId);
    final b = _notes.firstWhere((n) => n.id == noteBId);
    if (a.groupId != null && b.groupId == null) { await addNoteToGroup(b.id, a.groupId!); return; }
    if (b.groupId != null && a.groupId == null) { await addNoteToGroup(a.id, b.groupId!); return; }
    if (a.groupId != null && b.groupId != null) {
      if (a.groupId != b.groupId) {
        final target = a.groupId!, source = b.groupId!;
        for (final n in _notes.where((n) => n.groupId == source)) { await addNoteToGroup(n.id, target); }
        _groups.removeWhere((g) => g.id == source);
        await _persist(); notifyListeners();
      }
      return;
    }
    final g = Group(id: DateTime.now().microsecondsSinceEpoch.toString(), title: 'Группа', updatedAt: DateTime.now());
    _groups.add(g);
    final ia = _notes.indexWhere((n) => n.id == a.id);
    final ib = _notes.indexWhere((n) => n.id == b.id);
    _notes[ia] = a.copyWith(groupId: g.id, setGroupId: true, updatedAt: DateTime.now());
    _notes[ib] = b.copyWith(groupId: g.id, setGroupId: true, updatedAt: DateTime.now());
    await _persist(); notifyListeners();
  }

  /* ======== Private groups (simple hash) ======== */

  String _randomSalt([int length = 20]) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  String _fastHash(String password, String salt) {
    final bytes = utf8.encode('$salt::$password');
    int acc = 0;
    for (var i = 0; i < bytes.length; i++) {
      acc = (acc + ((bytes[i] + i) * 31)) & 0x7fffffff;
    }
    final mixed = bytes.map((b) => b ^ (acc & 0xFF)).toList();
    return base64Url.encode(mixed);
  }

  Future<void> setGroupPassword(Group g, String password) async {
    final salt = _randomSalt(20);
    final hash = _fastHash(password, salt);
    final idx = _groups.indexWhere((x) => x.id == g.id);
    if (idx != -1) {
      _groups[idx] = _groups[idx].copyWith(isPrivate: true, salt: salt, passHash: hash, updatedAt: DateTime.now());
      await _persist(); notifyListeners();
    }
  }

  Future<void> clearGroupPassword(Group g) async {
    final idx = _groups.indexWhere((x) => x.id == g.id);
    if (idx != -1) {
      _groups[idx] = _groups[idx].copyWith(isPrivate: false, salt: null, passHash: null, updatedAt: DateTime.now());
      await _persist(); notifyListeners();
    }
  }

  Future<bool> verifyGroupPassword(Group g, String password) async {
    final salt = g.salt;
    final hash = g.passHash;
    if (salt == null || hash == null) return false;
    final candidate = _fastHash(password, salt);
    return candidate == hash;
  }

  /* ======== Query ======== */

  List<GridItem> getGridItems({String query = ''}) {
    final q = query.trim().toLowerCase();
    final singles = _notes.where((n) => n.groupId == null);
    final gs = _groups.map((g) => GridItem.group(g)).toList();
    final ns = singles
        .where((n) => q.isEmpty ? true : (n.title + '\n' + n.text).toLowerCase().contains(q))
        .map((n) => GridItem.note(n))
        .toList();
    final filteredGroups = gs.where((gi) {
      final g = gi.group!;
      final inTitle = q.isEmpty ? true : g.title.toLowerCase().contains(q);
      if (inTitle || q.isEmpty) return true;
      return notesInGroup(g.id).any((n) => (n.title + '\n' + n.text).toLowerCase().contains(q));
    }).toList();
    filteredGroups.sort((a, b) => b.group!.updatedAt.compareTo(a.group!.updatedAt));
    ns.sort((a, b) => b.note!.updatedAt.compareTo(a.note!.updatedAt));
    return [...filteredGroups, ...ns];
  }
}

/* ===================== GRID ITEM ===================== */

class GridItem {
  final Note? note;
  final Group? group;
  GridItem.note(this.note) : group = null;
  GridItem.group(this.group) : note = null;
  bool get isNote => note != null;
  bool get isGroup => group != null;
}

/* ===================== HOME (NotesScreen) ===================== */

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final store = NotesStore();
  final _searchCtrl = TextEditingController();
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    store.addListener(() => setState(() {}));
    store.load();
  }

  @override
  void dispose() {
    store.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _shareQuick(String text) async {
    await ShareHelper.shareText(text);
  }

  @override
  Widget build(BuildContext context) {
    final loaded = store.isLoaded;
    final err = store.lastError;
    final items = store.getGridItems(query: _searchCtrl.text);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(hintText: 'Поиск…', isDense: true),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          IconButton(
            tooltip: 'Настройки',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Добавить заметку',
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? _ErrorPane(err: err, onReset: () => setState(() => store.load()))
              : Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 8, right: 8, bottom: 80),
                      child: GridView.builder(
                        itemCount: items.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.95,
                        ),
                        itemBuilder: (c, i) {
                          final it = items[i];
                          if (it.isGroup) {
                            final g = it.group!;
                            final within = store.notesInGroup(g.id);
                            return _DraggableTile(
                              data: DragPayload.group(g.id),
                              dragging: _dragging,
                              child: _GroupCard(
                                group: g,
                                notes: within,
                                onTap: () => _openGroup(g),
                                onAcceptDrop: (payload) => _handleDropOnGroup(payload, g),
                              ),
                              onDragStart: () => setState(() => _dragging = true),
                              onDragEnd: () => setState(() => _dragging = false),
                            );
                          } else {
                            final n = it.note!;
                            return _DraggableTile(
                              data: DragPayload.note(n.id),
                              dragging: _dragging,
                              child: _NoteCardGrid(
                                note: n,
                                onTap: () => _openEditor(source: n),
                                onAcceptDrop: (payload) => _handleDropOnNote(payload, n),
                                onShare: () => _shareQuick(n.text),
                              ),
                              onDragStart: () => setState(() => _dragging = true),
                              onDragEnd: () => setState(() => _dragging = false),
                            );
                          }
                        },
                      ),
                    ),
                    if (_dragging)
                      Positioned(
                        top: 12, left: 12,
                        child: _DeleteCorner(onAccept: (payload) => _handleDelete(payload)),
                      ),
                  ],
                ),
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const SettingsSheet(),
    );
  }

  Future<void> _handleDropOnNote(DragPayload payload, Note target) async {
    if (payload.isNote) {
      if (payload.id == target.id) return;
      await store.createGroupWith(payload.id, target.id);
    } else if (payload.isGroup) {
      final gid = payload.id;
      if (target.groupId == gid) return;
      await store.addNoteToGroup(target.id, gid);
    }
  }

  Future<void> _handleDropOnGroup(DragPayload payload, Group target) async {
    if (payload.isNote) {
      await store.addNoteToGroup(payload.id, target.id);
    } else if (payload.isGroup) {
      final source = payload.id;
      if (source == target.id) return;
      final moving = store.notesInGroup(source);
      for (final n in moving) { await store.addNoteToGroup(n.id, target.id); }
      await store.deleteGroup(source);
    }
  }

  Future<void> _handleDelete(DragPayload payload) async {
    final ok = await _confirm(
      title: 'Удалить?',
      message: payload.isNote ? 'Удалить эту заметку навсегда?' : 'Удалить группу и все её заметки?',
      confirmText: 'Удалить',
    );
    if (ok != true) return;

    if (payload.isNote) {
      await store.deleteNote(payload.id);
    } else if (payload.isGroup) {
      await store.deleteGroup(payload.id);
    }
    setState(() => _dragging = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Удалено')));
    }
  }

  Future<void> _openEditor({Note? source}) async {
    final result = await showModalBottomSheet<NoteActionResult>(
      context: context          break;
        default:
          themeMode = AppThemeMode.system;
      }
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _k,
      jsonEncode({
        'theme': switch (themeMode) {
          AppThemeMode.light => 'light',
          AppThemeMode.dark => 'dark',
          _ => 'system',
        }
      }),
    );
  }

  Future<void> setTheme(AppThemeMode m) async {
    themeMode = m;
    await _save();
    notifyListeners();
  }

  ThemeMode get flutterThemeMode => switch (themeMode) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

/* ===================== APP ===================== */

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (_, __) {
        final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Заметки',
          themeMode: settings.flutterThemeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: scheme,
            inputDecorationTheme:
                const InputDecorationTheme(border: OutlineInputBorder()),
          ),
          darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.indigo, brightness: Brightness.dark),
          ),
          home: const NotesScreen(),
        );
      },
    );
  }
}

/* ===================== MODELS ===================== */

class Note {
  String id;
  String title;
  String text;
  DateTime createdAt;
  DateTime updatedAt;
  int? colorHex;
  String? groupId;
  bool numbered;

  Note({
    required this.id,
    required this.title,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.colorHex,
    this.groupId,
    this.numbered = false,
  });

  factory Note.newNote() {
    final now = DateTime.now();
    return Note(
      id: now.microsecondsSinceEpoch.toString(),
      title: '',
      text: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  Note copyWith({
    String? title,
    String? text,
    DateTime? updatedAt,
    int? colorHex,
    bool keepNullColor = false,
    String? groupId,
    bool setGroupId = false,
    bool? numbered,
  }) =>
      Note(
        id: id,
        title: title ?? this.title,
        text: text ?? this.text,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        colorHex: keepNullColor ? null : (colorHex ?? this.colorHex),
        groupId: setGroupId ? groupId : this.groupId,
        numbered: numbered ?? this.numbered,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'text': text,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'colorHex': colorHex,
        'groupId': groupId,
        'numbered': numbered,
      };

  static Note fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        title: (json['title'] ?? '') as String,
        text: (json['text'] ?? '') as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
        colorHex: json['colorHex'] as int?,
        groupId: json['groupId'] as String?,
        numbered: (json['numbered'] as bool?) ?? false,
      );
}

class Group {
  String id;
  String title;
  DateTime updatedAt;

  // Приватность
  bool isPrivate;
  String? salt;
  String? passHash;

  Group({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.isPrivate = false,
    this.salt,
    this.passHash,
  });

  Group copyWith({
    String? title,
    DateTime? updatedAt,
    bool? isPrivate,
    String? salt,
    String? passHash,
  }) =>
      Group(
        id: id,
        title: title ?? this.title,
        updatedAt: updatedAt ?? this.updatedAt,
        isPrivate: isPrivate ?? this.isPrivate,
        salt: salt ?? this.salt,
        passHash: passHash ?? this.passHash,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'isPrivate': isPrivate,
        'salt': salt,
        'passHash': passHash,
      };

  static Group fromJson(Map<String, dynamic> json) => Group(
        id: json['id'] as String,
        title: (json['title'] ?? '') as String,
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
        isPrivate: (json['isPrivate'] as bool?) ?? false,
        salt: json['salt'] as String?,
        passHash: json['passHash'] as String?,
      );
}

/* ===================== STORE ===================== */

class NotesStore extends ChangeNotifier {
  static const _prefsKey = 'notes_v11_privacy_numbering_native_share';
  final List<Note> _notes = [];
  final List<Group> _groups = [];
  bool _loaded = false;
  String? _error;

  List<Note> get notes => List.unmodifiable(_notes);
  List<Group> get groups => List.unmodifiable(_groups);
  bool get isLoaded => _loaded;
  String? get lastError => _error;

  Group? groupById(String id) =>
      _groups.where((g) => g.id == id).cast<Group?>().firstWhere(
            (g) => g != null,
            orElse: () => null,
          );

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final ns = (decoded['notes'] as List? ?? [])
              .map((e) => Note.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          final gs = (decoded['groups'] as List? ?? [])
              .map((e) => Group.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          _notes..clear()..addAll(ns);
          _groups..clear()..addAll(gs);
        }
      }
      if (_notes.isEmpty) {
        _notes.addAll([
          Note(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: 'Советы',
            text:
                '👋 Перетащите заметку на другую — получится группа.\nДолгое нажатие — перетаскивание.',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            colorHex: const Color(0xFF64B5F6).value,
          ),
          Note(
            id: (DateTime.now().microsecondsSinceEpoch + 1).toString(),
            title: 'Удаление',
            text: 'Перетащите заметку в верхний левый красный блок «Удалить».',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            colorHex: const Color(0xFFFFD54F).value,
          ),
        ]);
        await _persist();
      }
    } catch (e) {
      _error = 'Ошибка загрузки: $e';
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode({
        'notes': _notes.map((e) => e.toJson()).toList(),
        'groups': _groups.map((e) => e.toJson()).toList(),
      });
      await prefs.setString(_prefsKey, raw);
    } catch (e) {
      _error = 'Ошибка сохранения: $e';
      notifyListeners();
    }
  }

  Future<void> addNote(Note note) async {
    _notes.add(note);
    await _persist();
    notifyListeners();
  }

  Future<void> updateNote(Note note) async {
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i != -1) {
      _notes[i] = note.copyWith(updatedAt: DateTime.now());
      await _persist();
      notifyListeners();
    }
  }

  Future<void> deleteNote(String id) async {
    _notes.removeWhere((n) => n.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> addGroup(Group g) async {
    _groups.add(g);
    await _persist();
    notifyListeners();
  }

  Future<void> updateGroup(Group g) async {
    final i = _groups.indexWhere((x) => x.id == g.id);
    if (i != -1) {
      _groups[i] = g.copyWith(updatedAt: DateTime.now());
      await _persist();
      notifyListeners();
    }
  }

  Future<void> deleteGroup(String groupId) async {
    _notes.removeWhere((n) => n.groupId == groupId);
    _groups.removeWhere((g) => g.id == groupId);
    await _persist();
    notifyListeners();
  }

  List<Note> notesInGroup(String groupId) =>
      _notes.where((n) => n.groupId == groupId).toList();

  Future<void> addNoteToGroup(String noteId, String groupId) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx != -1) {
      _notes[idx] = _notes[idx].copyWith(
        groupId: groupId,
        setGroupId: true,
        updatedAt: DateTime.now(),
      );
      await _persist();
      notifyListeners();
    }
  }

  Future<void> removeNoteFromGroup(String noteId) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx != -1) {
      _notes[idx] = _notes[idx].copyWith(
        groupId: null,
        setGroupId: true,
        updatedAt: DateTime.now(),
      );
      await _persist();
      notifyListeners();
    }
  }

  Future<void> createGroupWith(String noteAId, String noteBId) async {
    final a = _notes.firstWhere((n) => n.id == noteAId);
    final b = _notes.firstWhere((n) => n.id == noteBId);
    if (a.groupId != null && b.groupId == null) {
      await addNoteToGroup(b.id, a.groupId!);
      return;
    }
    if (b.groupId != null && a.groupId == null) {
      await addNoteToGroup(a.id, b.groupId!);
      return;
    }
    if (a.groupId != null && b.groupId != null) {
      if (a.groupId != b.groupId) {
        final target = a.groupId!, source = b.groupId!;
        for (final n in _notes.where((n) => n.groupId == source)) {
          await addNoteToGroup(n.id, target);
        }
        _groups.removeWhere((g) => g.id == source);
        await _persist();
        notifyListeners();
      }
      return;
    }
    final g = Group(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: 'Группа',
      updatedAt: DateTime.now(),
    );
    _groups.add(g);
    final ia = _notes.indexWhere((n) => n.id == a.id);
    final ib = _notes.indexWhere((n) => n.id == b.id);
    _notes[ia] =
        a.copyWith(groupId: g.id, setGroupId: true, updatedAt: DateTime.now());
    _notes[ib] =
        b.copyWith(groupId: g.id, setGroupId: true, updatedAt: DateTime.now());
    await _persist();
    notifyListeners();
  }

  /* ======== Private groups (simple hash, no ext deps) ======== */

  String _randomSalt([int length = 20]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// Не криптостойко; просто для локальной проверки пароля.
  String _fastHash(String password, String salt) {
    final bytes = utf8.encode('$salt::$password');
    int acc = 0;
    for (var i = 0; i < bytes.length; i++) {
      acc = (acc + ((bytes[i] + i) * 31)) & 0x7fffffff;
    }
    final mixed = bytes.map((b) => b ^ (acc & 0xFF)).toList();
    return base64Url.encode(mixed);
  }

  Future<void> setGroupPassword(Group g, String password) async {
    final salt = _randomSalt(20);
    final hash = _fastHash(password, salt);
    final idx = _groups.indexWhere((x) => x.id == g.id);
    if (idx != -1) {
      _groups[idx] = _groups[idx].copyWith(
        isPrivate: true,
        salt: salt,
        passHash: hash,
        updatedAt: DateTime.now(),
      );
      await _persist();
      notifyListeners();
    }
  }

  Future<void> clearGroupPassword(Group g) async {
    final idx = _groups.indexWhere((x) => x.id == g.id);
    if (idx != -1) {
      _groups[idx] = _groups[idx].copyWith(
        isPrivate: false,
        salt: null,
        passHash: null,
        updatedAt: DateTime.now(),
      );
      await _persist();
      notifyListeners();
    }
  }

  Future<bool> verifyGroupPassword(Group g, String password) async {
    final salt = g.salt;
    final hash = g.passHash;
    if (salt == null || hash == null) return false;
    final candidate = _fastHash(password, salt);
    return candidate == hash;
  }

  /* ======== Query for grid/list ======== */

  List<GridItem> getGridItems({String query = ''}) {
    final q = query.trim().toLowerCase();
    final singles = _notes.where((n) => n.groupId == null);
    final gs = _groups.map((g) => GridItem.group(g)).toList();
    final ns = singles
        .where((n) =>
            q.isEmpty ? true : (n.title + '\n' + n.text).toLowerCase().contains(q))
        .map((n) => GridItem.note(n))
        .toList();
    final filteredGroups = gs.where((gi) {
      final g = gi.group!;
      final inTitle = q.isEmpty ? true : g.title.toLowerCase().contains(q);
      if (inTitle || q.isEmpty) return true;
      return notesInGroup(g.id)
          .any((n) => (n.title + '\n' + n.text).toLowerCase().contains(q));
    }).toList();
    filteredGroups
        .sort((a, b) => b.group!.updatedAt.compareTo(a.group!.updatedAt));
    ns.sort((a, b) => b.note!.updatedAt.compareTo(a.note!.updatedAt));
    return [...filteredGroups, ...ns];
  }
}

/* ===================== GRID ITEM ===================== */

class GridItem {
  final Note? note;
  final Group? group;
  GridItem.note(this.note) : group = null;
  GridItem.group(this.group) : note = null;
  bool get isNote => note != null;
  bool get isGroup => group != null;
}

/* ===================== HOME (NotesScreen) ===================== */

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final store = NotesStore();
  final _searchCtrl = TextEditingController();
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    store.addListener(() => setState(() {}));
    store.load();
  }

  @override
  void dispose() {
    store.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _shareQuick(String text, {String? subject}) async {
    await ShareHelper.shareText(text); // subject игнорируем: только текст
  }

  @override
  Widget build(BuildContext context) {
    final loaded = store.isLoaded;
    final err = store.lastError;
    final items = store.getGridItems(query: _searchCtrl.text);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(hintText: 'Поиск…', isDense: true),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          IconButton(
            tooltip: 'Настройки',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Добавить заметку',
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? _ErrorPane(err: err, onReset: () => setState(() => store.load()))
              : Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                          top: 8, left: 8, right: 8, bottom: 80),
                      child: GridView.builder(
                        itemCount: items.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.95,
                        ),
                        itemBuilder: (c, i) {
                          final it = items[i];
                          if (it.isGroup) {
                            final g = it.group!;
                            final within = store.notesInGroup(g.id);
                            return _DraggableTile(
                              data: DragPayload.group(g.id),
                              dragging: _dragging,
                              child: _GroupCard(
                                group: g,
                                notes: within,
                                onTap: () => _openGroup(g),
                                onAcceptDrop: (payload) =>
                                    _handleDropOnGroup(payload, g),
                              ),
                              onDragStart: () =>
                                  setState(() => _dragging = true),
                              onDragEnd: () => setState(() => _dragging = false),
                            );
                          } else {
                            final n = it.note!;
                            return _DraggableTile(
                              data: DragPayload.note(n.id),
                              dragging: _dragging,
                              child: _NoteCardGrid(
                                note: n,
                                onTap: () => _openEditor(source: n),
                                onAcceptDrop: (payload) =>
                                    _handleDropOnNote(payload, n),
                                onShare: () =>
                                    _shareQuick(n.text, subject: n.title),
                              ),
                              onDragStart: () =>
                                  setState(() => _dragging = true),
                              onDragEnd: () => setState(() => _dragging = false),
                            );
                          }
                        },
                      ),
                    ),
                    if (_dragging)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: _DeleteCorner(
                            onAccept: (payload) => _handleDelete(payload)),
                      ),
                  ],
                ),
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const SettingsSheet(),
    );
  }

  Future<void> _handleDropOnNote(DragPayload payload, Note target) async {
    if (payload.isNote) {
      if (payload.id == target.id) return;
            break;
        default:
          themeMode = AppThemeMode.system;
      }
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _k,
      jsonEncode({
        'theme': switch (themeMode) {
          AppThemeMode.light => 'light',
          AppThemeMode.dark => 'dark',
          _ => 'system'
        }
      }),
    );
  }

  Future<void> setTheme(AppThemeMode m) async {
    themeMode = m;
    await _save();
    notifyListeners();
  }

  ThemeMode get flutterThemeMode => switch (themeMode) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

/* ======== APP ======== */

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (_, __) {
        final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Заметки',
          themeMode: settings.flutterThemeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: scheme,
            inputDecorationTheme:
                const InputDecorationTheme(border: OutlineInputBorder()),
          ),
          darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.dark,
            ),
          ),
          home: const NotesHomePage(),
        );
      },
    );
  }
}

/* ======== MODELS ======== */

class Note {
  String id;
  String text;
  DateTime createdAt;
  DateTime updatedAt;
  int? colorHex;
  String? groupId;
  bool numbered;

  Note({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.colorHex,
    this.groupId,
    this.numbered = false,
  });

  factory Note.newNote() {
    final now = DateTime.now();
    return Note(
      id: now.microsecondsSinceEpoch.toString(),
      text: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  Note copyWith({
    String? text,
    DateTime? updatedAt,
    int? colorHex,
    bool keepNullColor = false,
    String? groupId,
    bool setGroupId = false,
    bool? numbered,
  }) =>
      Note(
        id: id,
        text: text ?? this.text,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        colorHex: keepNullColor ? null : (colorHex ?? this.colorHex),
        groupId: setGroupId ? groupId : this.groupId,
        numbered: numbered ?? this.numbered,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'colorHex': colorHex,
        'groupId': groupId,
        'numbered': numbered,
      };

  static Note fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        text: (json['text'] ?? '') as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
        colorHex: json['colorHex'] as int?,
        groupId: json['groupId'] as String?,
        numbered: (json['numbered'] as bool?) ?? false,
      );
}

class Group {
  String id;
  String title;
  DateTime updatedAt;

  // Приватность
  bool isPrivate;
  String? salt; // случайная «соль»
  String? passHash; // лёгкая обфускация (без внешних пакетов)

  Group({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.isPrivate = false,
    this.salt,
    this.passHash,
  });

  Group copyWith({
    String? title,
    DateTime? updatedAt,
    bool? isPrivate,
    String? salt,
    String? passHash,
  }) =>
      Group(
        id: id,
        title: title ?? this.title,
        updatedAt: updatedAt ?? this.updatedAt,
        isPrivate: isPrivate ?? this.isPrivate,
        salt: salt ?? this.salt,
        passHash: passHash ?? this.passHash,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'isPrivate': isPrivate,
        'salt': salt,
        'passHash': passHash,
      };

  static Group fromJson(Map<String, dynamic> json) => Group(
        id: json['id'] as String,
        title: (json['title'] ?? '') as String,
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
        isPrivate: (json['isPrivate'] as bool?) ?? false,
        salt: json['salt'] as String?,
        passHash: json['passHash'] as String?,
      );
}

/* ======== STORE ======== */

class NotesStore extends ChangeNotifier {
  static const _prefsKey = 'notes_v10_privacy_autosave_native_share';
  final List<Note> _notes = [];
  final List<Group> _groups = [];
  bool _loaded = false;
  String? _error;

  List<Note> get notes => List.unmodifiable(_notes);
  List<Group> get groups => List.unmodifiable(_groups);
  bool get isLoaded => _loaded;
  String? get lastError => _error;

  Group? groupById(String id) {
    for (final g in _groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final ns = (decoded['notes'] as List? ?? [])
              .map((e) => Note.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          final gs = (decoded['groups'] as List? ?? [])
              .map((e) => Group.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          _notes..clear()..addAll(ns);
          _groups..clear()..addAll(gs);
        }
      }
      if (_notes.isEmpty) {
        _notes.addAll([
          Note(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            text:
                '👋 Добро пожаловать!\nПеретащите заметку на другую — получится группа.',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            colorHex: const Color(0xFF64B5F6).value,
          ),
          Note(
            id: (DateTime.now().microsecondsSinceEpoch + 1).toString(),
            text:
                'Удаление: перетащите заметку в левый верхний красный «Удалить».',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            colorHex: const Color(0xFFFFD54F).value,
          ),
        ]);
        await _persist();
      }
    } catch (e) {
      _error = 'Ошибка загрузки: $e';
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode({
        'notes': _notes.map((e) => e.toJson()).toList(),
        'groups': _groups.map((e) => e.toJson()).toList(),
      });
      await prefs.setString(_prefsKey, raw);
    } catch (e) {
      _error = 'Ошибка сохранения: $e';
      notifyListeners();
    }
  }

  Future<void> addNote(Note note) async {
    _notes.add(note);
    await _persist();
    notifyListeners();
  }

  Future<void> updateNote(Note note) async {
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i != -1) {
      _notes[i] = note.copyWith(updatedAt: DateTime.now());
      await _persist();
      notifyListeners();
    }
  }

  Future<void> deleteNote(String id) async {
    _notes.removeWhere((n) => n.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> addGroup(Group g) async {
    _groups.add(g);
    await _persist();
    notifyListeners();
  }

  Future<void> updateGroup(Group g) async {
    final i = _groups.indexWhere((x) => x.id == g.id);
    if (i != -1) {
      _groups[i] = g.copyWith(updatedAt: DateTime.now());
      await _persist();
      notifyListeners();
    }
  }

  Future<void> deleteGroup(String groupId) async {
    _notes.removeWhere((n) => n.groupId == groupId);
    _groups.removeWhere((g) => g.id == groupId);
    await _persist();
    notifyListeners();
  }

  List<Note> notesInGroup(String groupId) =>
      _notes.where((n) => n.groupId == groupId).toList();

  Future<void> addNoteToGroup(String noteId, String groupId) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx != -1) {
      _notes[idx] = _notes[idx].copyWith(
        groupId: groupId,
        setGroupId: true,
        updatedAt: DateTime.now(),
      );
      await _persist();
      notifyListeners();
    }
  }

  Future<void> removeNoteFromGroup(String noteId) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx != -1) {
      _notes[idx] = _notes[idx].copyWith(
        groupId: null,
        setGroupId: true,
        updatedAt: DateTime.now(),
      );
      await _persist();
      notifyListeners();
    }
  }

  Future<void> createGroupWith(String noteAId, String noteBId) async {
    final a = _notes.firstWhere((n) => n.id == noteAId);
    final b = _notes.firstWhere((n) => n.id == noteBId);
    if (a.groupId != null && b.groupId == null) {
      await addNoteToGroup(b.id, a.groupId!);
      return;
    }
    if (b.groupId != null && a.groupId == null) {
      await addNoteToGroup(a.id, b.groupId!);
      return;
    }
    if (a.groupId != null && b.groupId != null) {
      if (a.groupId != b.groupId) {
        final target = a.groupId!, source = b.groupId!;
        for (final n in _notes.where((n) => n.groupId == source)) {
          await addNoteToGroup(n.id, target);
        }
        _groups.removeWhere((g) => g.id == source);
        await _persist();
        notifyListeners();
      }
      return;
    }
    final g = Group(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: 'Группа',
      updatedAt: DateTime.now(),
    );
    _groups.add(g);
    final ia = _notes.indexWhere((n) => n.id == a.id);
    final ib = _notes.indexWhere((n) => n.id == b.id);
    _notes[ia] =
        a.copyWith(groupId: g.id, setGroupId: true, updatedAt: DateTime.now());
    _notes[ib] =
        b.copyWith(groupId: g.id, setGroupId: true, updatedAt: DateTime.now());
    await _persist();
    notifyListeners();
  }

  /* ======== Private groups (no external crypto) ======== */

  String _randomSalt([int length = 20]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// НЕ криптостойко (для отсутствия внешних пакетов).
  String _fastHash(String password, String salt) {
    final bytes = utf8.encode('$salt::$password');
    int acc = 0;
    for (var i = 0; i < bytes.length; i++) {
      acc = (acc + ((bytes[i] + i) * 31)) & 0x7fffffff;
    }
    final mixed = bytes.map((b) => b ^ (acc & 0xFF)).toList();
    return base64Url.encode(mixed);
  }

  Future<void> setGroupPassword(Group g, String password) async {
    final salt = _randomSalt(20);
    final hash = _fastHash(password, salt);
    final idx = _groups.indexWhere((x) => x.id == g.id);
    if (idx != -1) {
      _groups[idx] = _groups[idx].copyWith(
        isPrivate: true,
        salt: salt,
        passHash: hash,
        updatedAt: DateTime.now(),
      );
      await _persist();
      notifyListeners();
    }
  }

  Future<void> clearGroupPassword(Group g) async {
    final idx = _groups.indexWhere((x) => x.id == g.id);
    if (idx != -1) {
      _groups[idx] = _groups[idx].copyWith(
        isPrivate: false,
        salt: null,
        passHash: null,
        updatedAt: DateTime.now(),
      );
      await _persist();
      notifyListeners();
    }
  }

  Future<bool> verifyGroupPassword(Group g, String password) async {
    final salt = g.salt;
    final hash = g.passHash;
    if (salt == null || hash == null) return false;
    final candidate = _fastHash(password, salt);
    return candidate == hash;
  }

  /* ======== Data for grid ======== */

  List<GridItem> getGridItems({String query = ''}) {
    final q = query.trim().toLowerCase();
    final singles = _notes.where((n) => n.groupId == null);
    final gs = _groups.map((g) => GridItem.group(g)).toList();
    final ns = singles
        .where((n) => q.isEmpty ? true : n.text.toLowerCase().contains(q))
        .map((n) => GridItem.note(n))
        .toList();
    final filteredGroups = gs.where((gi) {
      final g = gi.group!;
      final inTitle = q.isEmpty ? true : g.title.toLowerCase().contains(q);
      if (inTitle || q.isEmpty) return true;
      return notesInGroup(g.id).any((n) => n.text.toLowerCase().contains(q));
    }).toList();
    filteredGroups
        .sort((a, b) => b.group!.updatedAt.compareTo(a.group!.updatedAt));
    ns.sort((a, b) => b.note!.updatedAt.compareTo(a.note!.updatedAt));
    return [...filteredGroups, ...ns];
  }
}

/* ======== GRID / HOME ======== */

class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key});
  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  final store = NotesStore();
  final _searchCtrl = TextEditingController();
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    store.addListener(() => setState(() {}));
    store.load();
  }

  @override
  void dispose() {
    store.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loaded = store.isLoaded;
    final err = store.lastError;
    final items = store.getGridItems(query: _searchCtrl.text);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(hintText: 'Поиск…', isDense: true),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          IconButton(
            tooltip: 'Настройки',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Добавить заметку',
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? _ErrorPane(err: err, onReset: () => setState(() => store.load()))
              : Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                          top: 8, left: 8, right: 8, bottom: 80),
                      child: GridView.builder(
                        itemCount: items.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.95,
                        ),
                        itemBuilder: (c, i) {
                          final it = items[i];
                          if (it.isGroup) {
                            final g = it.group!;
                            final within = store.notesInGroup(g.id);
                            return _DraggableTile(
                              data: DragPayload.group(g.id),
                              dragging: _dragging,
                              child: _GroupCard(
                                group: g,
                                notes: within,
                                onTap: () => _openGroup(g),
                                onAcceptDrop: (payload) =>
                                    _handleDropOnGroup(payload, g),
                              ),
                              onDragStart: () =>
                                  setState(() => _dragging = true),
                              onDragEnd: () => setState(() => _dragging = false),
                            );
                          } else {
                            final n = it.note!;
                            return _DraggableTile(
                              data: DragPayload.note(n.id),
                              dragging: _dragging,
                              child: _NoteCardGrid(
                                note: n,
                                onTap: () => _openEditor(source: n),
                                onAcceptDrop: (payload) =>
                                    _handleDropOnNote(payload, n),
                              ),
                              onDragStart: () =>
                                  setState(() => _dragging = true),
                              onDragEnd: () => setState(() => _dragging = false),
                            );
                          }
                        },
                      ),
                    ),
                    if (_dragging)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: _DeleteCorner(
                            onAccept: (payload) => _handleDelete(payload)),
                      ),
                  ],
                ),
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const SettingsSheet(),
    );
  }

  Future<void> _handleDropOnNote(DragPayload payload, Note target) async {
    if (payload.isNote) {
      if (payload.id == target.id) return;
      await store.createGroupWith(payload.id, target.id);
    } else if (payload.isGroup) {
      final gid = payload.id;
      if (target.groupId == gid) return;
      await store.addNoteToGroup(target.id, gid);
    }
  }

  Future<void> _handleDropOnGroup(DragPayload payload, Group target) async {
    if (payload.isNote) {
      await store.addNoteToGroup(payload.id, target.id);
    } else if (payload.isGroup) {
      final source = payload.id;
      if (source == target.id) return;
      final moving = store.notesInGroup(source);
      for (final n in moving) {
        await store.addNoteToGroup(n.id, target.id);
      }
      await store.deleteGroup(source);
    }
  }

  Future<void> _handleDelete(DragPayload payload) async {
    final ok = await _confirm(
      title: 'Удалить?',
      message: payload.isNote
          ? 'Удалить эту заметку навсегда?'
          : 'Удалить группу и все её заметки?',
      confirmText: 'Удалить',
    );
    if (ok != true) return;

    if (payload.isNote) {
      await store.deleteNote(payload.id);
    } else if (payload.isGroup) {
      await store.deleteGroup(payload.id);
    }
    setState(() => _dragging = false);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Удалено')));
    }
  }

  Future<void> _openEditor({Note? source}) async {
    final result = await showModalBottomSheet<NoteActionResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => NoteEditor(note: source),
    );
    if (result == null) return;

    if (result.delete) {
      final ok = await _confirm(
          title: 'Удалить заметку?',
          message: 'Действие необратимо.',
          confirmText: 'Удалить');
      if (ok == true) {
        await store.deleteNote(result.note.id);
      }
      return;
    }

    if (source == null) {
      await store.addNote(result.note);
    } else {
      await store.updateNote(result.note);
    }
    if (result.detachedFromGroup) {
      await store.removeNoteFromGroup(result.note.id);
    }
  }

  Future<void> _openGroup(Group g) async {
    if (g.isPrivate) {
      final pass = await _promptPassword(
        context: context,
        title: 'Доступ к группе',
        hint: 'Введите пароль',
      );
      if (pass == null) return;
      final ok = await store.verifyGroupPassword(g, pass);
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Неверный пароль')),
        );
        return;
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => GroupEditor(
        store: store,
        group: g,
        notesProvider: () => store.notesInGroup(g.id),
        onRename: (title) async => store.updateGroup(g.copyWith(title: title)),
        onEditNote: (note) async => _openEditor(source: note),
        onUngroupNote: (note) async => store.removeNoteFromGroup(note.id),
        onDeleteNote: (note) async {
          final ok = await _confirm(
              title: 'Удалить заметку?',
              message: 'Действие необратимо.',
              confirmText: 'Удалить');
          if (ok == true) await store.deleteNote(note.id);
        },
      ),
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    String confirmText = 'ОК',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmText)),
        ],
      ),
    );
  }
}

/* ======== SETTINGS SHEET ======== */

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});
  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  AppThemeMode _mode = settings.themeMode;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          left: 16,
          right: 16,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Grabber(),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Тема', style: TextStyle(fontSize: 16)),
                const Spacer(),
                SegmentedButton<AppThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: AppThemeMode.system, label: Text('Система')),
                    ButtonSegment(
                        value: AppThemeMode.light, label: Text('Светлая')),
                    ButtonSegment(
                        value: AppThemeMode.dark, label: Text('Тёмная')),
                  ],
                  selected: <AppThemeMode>{_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('Закрыть'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Сохранить'),
                    onPressed: () async {
                      await settings.setTheme(_mode);
                      if (mounted) Navigator.pop(context);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/* ======== GRID CARDS ======== */

class _NoteCardGrid extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final ValueChanged<DragPayload> onAcceptDrop;

  const _NoteCardGrid({
    required this.note,
    required this.onTap,
    required this.onAcceptDrop,
  });

  @override
  Widget build(BuildContext context) {
    final bg = note.colorHex != null
        ? Color(note.colorHex!)
        : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5);
    final textTheme = Theme.of(context).textTheme;
    return DragTarget<DragPayload>(
      onWillAccept: (_) => true,
      onAccept: onAcceptDrop,
      builder: (c, _, __) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note.numbered)
                  Row(
                    children: [
                      Icon(Icons.format_list_numbered,
                          size: 16, color: textTheme.bodySmall?.color),
                      const SizedBox(width: 6),
                      Text('Нумерация',
                          style: textTheme.labelSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                if (note.numbered) const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    note.text.trim().isEmpty ? 'Пустая заметка' : note.text,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _fmtDate(note.updatedAt),
                  style: textTheme.bodySmall?.copyWith(
                    color: textTheme.bodySmall?.color?.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final Group group;
  final List<Note> notes;
  final VoidCallback onTap;
  final ValueChanged<DragPayload> onAcceptDrop;

  const _GroupCard({
    required this.group,
    required this.notes,
    required this.onTap,
    required this.onAcceptDrop,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DragTarget<DragPayload>(
      onWillAccept: (_) => true,
      onAccept: onAcceptDrop,
      builder: (c, _, __) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color:
                Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      group.title,
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    if (group.isPrivate) const Icon(Icons.lock, size: 16),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: notes.isEmpty
                      ? const Center(child: Text('Пусто'))
                      : ListView.builder(
                          itemCount: notes.length.clamp(0, 4),
                          itemBuilder: (c, i) {
                            final n = notes[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (n.numbered)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 4),
                                      child: Icon(Icons.format_list_numbered,
                                          size: 14),
                                    ),
                                  if (n.numbered) const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      n.text.trim().isEmpty
                                          ? 'Пустая заметка'
                                          : n.text,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Обновлено: ${_fmtDate(group.updatedAt)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: textTheme.bodySmall?.color?.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ======== DRAG & DROP ======== */

class DragPayload {
  final String id;
  final String type; // 'note' | 'group'
  DragPayload._(this.id, this.type);
  factory DragPayload.note(String id) => DragPayload._(id, 'note');
  factory DragPayload.group(String id) => DragPayload._(id, 'group');
  bool get isNote => type == 'note';
  bool get isGroup => type == 'group';
}

class _DraggableTile extends StatelessWidget {
  final DragPayload data;
  final Widget child;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final bool dragging;

  const _DraggableTile({
    required this.data,
    required this.child,
    required this.onDragStart,
    required this.onDragEnd,
    required this.dragging,
  });

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<DragPayload>(
      data: data,
      feedback: Opacity(
        opacity: 0.8,
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: MediaQuery.of(context).size.width / 2 - 16,
            child: child,
          ),
        ),
      ),
      onDragStarted: onDragStart,
      onDraggableCanceled: (_, __) => onDragEnd(),
      onDragEnd: (_) => onDragEnd(),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: IgnorePointer(child: child),
      ),
      child: child,
    );
  }
}

class _DeleteCorner extends StatelessWidget {
  final ValueChanged<DragPayload> onAccept;
  const _DeleteCorner({required this.onAccept});

  @override
  Widget build(BuildContext context) {
    return DragTarget<DragPayload>(
      onWillAccept: (_) => true,
      onAccept: onAccept,
      builder: (c, _, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          children: [
            Icon(Icons.delete, color: Colors.white),
            SizedBox(width: 6),
            Text('Удалить', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/* ======== NOTE EDITOR (numbering + share) ======== */

class NoteActionResult {
  final Note note;
  final bool delete;
  final bool detachedFromGroup;
  const NoteActionResult(
      {required this.note, this.delete = false, this.detachedFromGroup = false});
}

class NoteEditor extends StatefulWidget {
  final Note? note;
  const NoteEditor({super.key, this.note});

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late Note _model;
  late TextEditingController _text;
  late NumberingFormatter _numberingFormatter;

  @override
  void initState() {
    super.initState();
    _model = widget.note?.copyWith() ?? Note.newNote();
    _text = TextEditingController(text: _model.text);
    _text.addListener(_onChanged);
    _numberingFormatter = NumberingFormatter(() => _model.numbered);
  }

  @override
  void dispose() {
    _text.removeListener(_onChanged);
    _text.dispose();
    super.dispose();
  }

  void _onChanged() {
    final now = DateTime.now();
    _model = _model.copyWith(text: _text.text, updatedAt: now);
    setState(() {});
  }

  void _toggleNumbering() {
    setState(() {
      _model = _model.copyWith(numbered: !_model.numbered);
      if (_model.numbered) _ensureFirstNumberAlways();
    });
  }

  /// Вставляет "1. " в НАЧАЛО текущей строки, если там ещё нет цифры.
  void _ensureFirstNumberAlways() {
    final sel = _text.selection;
    final text = _text.text;
    final ls = _lineStartIndex(text, sel.start);
    final line = _lineAt(text, sel.start);
    final hasNumberPrefix = RegExp(r'^\s*\d+\.\s*').hasMatch(line);
    if (!hasNumberPrefix) {
      final insert = '1. ';
      final newText = text.replaceRange(ls, ls, insert);
      final delta = insert.length;
      _text.value = _text.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + delta),
      );
    }
  }

  int _lineStartIndex(String text, int pos) {
    final prev = text.lastIndexOf('\n', pos - 1);
    return prev == -1 ? 0 : prev + 1;
  }

  String _lineAt(String text, int pos) {
    final start = _lineStartIndex(text, pos);
    final end = text.indexOf('\n', pos);
    return text.substring(start, end == -1 ? text.length : end);
  }

  Future<void> _share() async {
    final content = _text.text; // только текст, как есть
    await ShareHelper.shareText(content);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Grabber(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Обычный')),
                      ButtonSegment(value: true, label: Text('Нумер.')),
                    ],
                    selected: <bool>{_model.numbered},
                    onSelectionChanged: (_) => _toggleNumbering(),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Копировать',
                  child: IconButton(
                    icon: const Icon(Icons.copy_all),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _text.text));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Скопировано в буфер')),
                        );
                      }
                    },
                  ),
                ),
                Tooltip(
                  message: 'Поделиться (только текст)',
                  child: IconButton(
                    icon: const Icon(Icons.ios_share),
                    onPressed: _share,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _text,
              maxLines: 12,
              inputFormatters: <TextInputFormatter>[_numberingFormatter],
              decoration: const InputDecoration(
                hintText:
                    'Текст заметки...\nПодсказка: включите «Нумер.» — Enter добавляет следующий номер',
              ),
            ),
            const SizedBox(height: 8),
            // Цвет
            Row(
              children: [
                const Text('Цвет:'),
                const SizedBox(width: 8),
                _ColorDot(
                  color: null,
                  selected: _model.colorHex == null,
                  onTap: () => setState(() => _model =
                      _model.copyWith(keepNullColor: true, colorHex: null)),
                ),
                const SizedBox(width: 8),
                for (final c in const [
                  Color(0xFFFFF59D),
                  Color(0xFFB39DDB),
                  Color(0xFF80CBC4),
                  Color(0xFFFFAB91),
                  Color(0xFF90CAF9),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _ColorDot(
                      color: c,
                      selected: _model.colorHex == c.value,
                      onTap: () =>
                          setState(() => _model = _model.copyWith(colorHex: c.value)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Кнопки
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('Отмена'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                if (_model.groupId != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.link_off),
                      label: const Text('Исключить из группы'),
                      onPressed: () => Navigator.pop(
                        context,
                        NoteActionResult(note: _model, detachedFromGroup: true),
                      ),
                    ),
                  ),
                if (_model.groupId != null) const SizedBox(width: 12),
                if (widget.note != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Удалить'),
                      onPressed: () => Navigator.pop(
                        context,
                        NoteActionResult(note: _model, delete: true),
                      ),
                    ),
                  ),
                if (widget.note != null) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Сохранить'),
                    onPressed: () =>
                        Navigator.pop(context, NoteActionResult(note: _model)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/* === Numbering inputFormatter (работает на мобильной клавиатуре) === */

class NumberingFormatter extends TextInputFormatter {
  final bool Function() isEnabled;
  NumberingFormatter(this.isEnabled);

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (!isEnabled()) return newValue;

    final old = oldValue.text;
    final neu = newValue.text;
    final insPos = newValue.selection.baseOffset;

    // Вставка \n?
    if (insPos > 0 && neu.length == old.length + 1 && neu[insPos - 1] == '\n') {
      final prevNL = neu.lastIndexOf('\n', insPos - 2);
      final start = prevNL == -1 ? 0 : prevNL + 1;
      final prevLine = neu.substring(start, insPos - 1);

      final match = RegExp(r'^(\s*)(\d+)\.(\s*)').firstMatch(prevLine);
      String indent = '';
      int nextNum = 1;
      String spaces = ' ';

      if (match != null) {
        indent = match.group(1) ?? '';
        nextNum = (int.tryParse(match.group(2)!) ?? 0) + 1;
        final s = match.group(3) ?? ' ';
        spaces = s.isEmpty ? ' ' : s;
      }

      final insert = '$indent$nextNum.$spaces';
      final textWith = neu.replaceRange(insPos, insPos, insert);
      final newSelection =
          TextSelection.collapsed(offset: insPos + insert.length);
      return TextEditingValue(
          text: textWith, selection: newSelection, composing: TextRange.empty);
    }

    return newValue;
  }
}

/* ======== GROUP EDITOR (auto-save, no Save button) ======== */

class GroupEditor extends StatefulWidget {
  final NotesStore store;
  final Group group;
  final List<Note> Function() notesProvider;
  final Future<void> Function(String title) onRename;
  final Future<void> Function(Note note) onEditNote;
  final Future<void> Function(Note note) onUngroupNote;
  final Future<void> Function(Note note) onDeleteNote;

  const GroupEditor({
    super.key,
    required this.store,
    required this.group,
    required this.notesProvider,
    required this.onRename,
    required this.onEditNote,
    required this.onUngroupNote,
    required this.onDeleteNote,
  });

  @override
  State<GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<GroupEditor> {
  late TextEditingController _title;
  late Group _group;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _title = TextEditingController(text: _group.title);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    super.dispose();
  }

  void _refreshLocalGroup() {
    _group = widget.store.groupById(_group.id) ?? _group;
  }

  void _onTitleChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      await widget.onRename(v.trim().isEmpty ? 'Группа' : v.trim());
      if (mounted) setState(_refreshLocalGroup);
    });
  }

  @override
  Widget build(BuildContext context) {
    _refreshLocalGroup();
    final notes = widget.notesProvider();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Grabber(),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              onChanged: _onTitleChanged, // автосохранение
              decoration: const InputDecoration(
                labelText: 'Название группы',
                helperText: 'Сохраняется автоматически',
              ),
            ),
            const SizedBox(height: 12),

            // Приватность
            Card(
              elevation: 0,
              color:
                  Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock_outline),
                        const SizedBox(width: 8),
                        Text('Приватность',
                            style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        Switch(
                          value: _group.isPrivate,
                          onChanged: (v) async {
                            if (v) {
                              final pass = await _promptPassword(
                                context: context,
                                title: 'Задать пароль',
                                hint: 'Пароль для группы',
                              );
                              if (pass == null || pass.length < 4) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Пароль не задан (мин. 4 символа).')),
                                );
                                return;
                              }
                              await widget.store.setGroupPassword(_group, pass);
                              setState(_refreshLocalGroup);
                            } else {
                              await widget.store.clearGroupPassword(_group);
                              setState(_refreshLocalGroup);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_group.isPrivate)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.password),
                              label: const Text('Сменить пароль'),
                              onPressed: () async {
                                final pass = await _promptPassword(
                                  context: context,
                                  title: 'Новый пароль',
                                  hint: 'Введите новый пароль',
                                );
                                if (pass == null || pass.length < 4) return;
                                await widget.store
                                    .setGroupPassword(_group, pass);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Пароль обновлён')),
                                  );
                                }
                                setState(_refreshLocalGroup);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.lock_open),
                              label: const Text('Сделать публичной'),
                              onPressed: () async {
                                await widget.store.clearGroupPassword(_group);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Группа теперь публичная')),
                                  );
                                }
                                setState(_refreshLocalGroup);
                              },
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
            if (notes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('В группе пока нет заметок'),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: notes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final n = notes[i];
                    return ListTile(
                      title: Text(
                        n.text.trim().isEmpty ? 'Пустая заметка' : n.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle:
                          n.numbered ? const Text('Нумерация включена') : null,
                      onTap: () => widget.onEditNote(n),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          switch (v) {
                            case 'edit':
                              await widget.onEditNote(n);
                              break;
                            case 'ungroup':
                              await widget.onUngroupNote(n);
                              setState(() {});
                              break;
                            case 'delete':
                              await widget.onDeleteNote(n);
                              setState(() {});
                              break;
                            case 'share':
                              await ShareHelper.shareText(n.text);
                              break;
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'edit', child: Text('Редактировать')),
                          PopupMenuItem(
                              value: 'ungroup',
                              child: Text('Исключить из группы')),
                          PopupMenuItem(
                              value: 'delete', child: Text('Удалить')),
                          PopupMenuItem(
                              value: 'share', child: Text('Поделиться')),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Обновлено: ${_fmtDate(_group.updatedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ======== COMMON WIDGETS & UTILS ======== */

class _ErrorPane extends StatelessWidget {
  final String err;
  final VoidCallback onReset;
  const _ErrorPane({required this.err, required this.onReset});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(err, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              onPressed: onReset,
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outline.withOpacity(0.6),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot(
      {required this.color, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final bg = color ?? Colors.transparent;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: color == null
            ? Icon(Icons.block,
                size: 16,
                color: Theme.of(context).colorScheme.outline.withOpacity(0.6))
            : null,
      ),
    );
  }
}

Future<String?> _promptPassword({
  required BuildContext context,
  String title = 'Пароль',
  String hint = 'Введите пароль',
}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        obscureText: true,
        decoration: InputDecoration(hintText: hint),
        autofocus: true,
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Отмена')),
        FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('ОК')),
      ],
    ),
  );
}

String _fmtDate(DateTime dt) {
  final d = dt;
  String two(int n) => n < 10 ? '0$n' : '$n';
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/* ======== GRID ITEM WRAPPER ======== */

class GridItem {
  final Note? note;
  final Group? group;
  GridItem.note(this.note) : group = null;
  GridItem.group(this.group) : note = null;
  bool get isNote => note != null;
  bool get isGroup => group != null;
}

/* ======== Native share helper (MethodChannel) ======== */

class ShareHelper {
  static const _ch = MethodChannel('app.share');

  static Future<void> shareText(String text) async {
    final content = text.trim();
    if (content.isEmpty) return;
    try {
      await _ch.invokeMethod('shareText', {'text': content});
    } catch (_) {
      // Фолбэк: копируем в буфер, чтобы не потерять контент
      await Clipboard.setData(ClipboardData(text: content));
    }
  }
}
