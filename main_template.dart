import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await settings.load();
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
    if (raw != null && raw.isNotEmpty) {
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      switch (m['theme'] as String? ?? 'system') {
        case 'light':
          themeMode = AppThemeMode.light;
          break;
        case 'dark':
          themeMode = AppThemeMode.dark;
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
        'theme': themeMode == AppThemeMode.light
            ? 'light'
            : themeMode == AppThemeMode.dark
                ? 'dark'
                : 'system',
      }),
    );
  }

  Future<void> setTheme(AppThemeMode m) async {
    themeMode = m;
    await _save();
    notifyListeners();
  }

  ThemeMode get flutterThemeMode {
    switch (themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
      default:
        return ThemeMode.system;
    }
  }
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
          home: const NotesHomePage(),
        );
      },
    );
  }
}

/* ===================== MODEL ===================== */

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

  Group({required this.id, required this.title, required this.updatedAt});

  Group copyWith({String? title, DateTime? updatedAt}) => Group(
        id: id,
        title: title ?? this.title,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  static Group fromJson(Map<String, dynamic> json) => Group(
        id: json['id'] as String,
        title: (json['title'] ?? '') as String,
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
      );
}

/* ===================== STORE ===================== */

class NotesStore extends ChangeNotifier {
  static const _prefsKey = 'notes_v5_grid_groups_numbering_smart_ui';
  final List<Note> _notes = [];
  final List<Group> _groups = [];
  bool _loaded = false;
  String? _error;

  List<Note> get notes => List.unmodifiable(_notes);
  List<Group> get groups => List.unmodifiable(_groups);
  bool get isLoaded => _loaded;
  String? get lastError => _error;

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
          _notes
            ..clear()
            ..addAll(ns);
          _groups
            ..clear()
            ..addAll(gs);
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
          groupId: groupId, setGroupId: true, updatedAt: DateTime.now());
      await _persist();
      notifyListeners();
    }
  }

  Future<void> removeNoteFromGroup(String noteId) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx != -1) {
      _notes[idx] = _notes[idx].copyWith(
          groupId: null, setGroupId: true, updatedAt: DateTime.now());
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
        updatedAt: DateTime.now());
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

class GridItem {
  final Note? note;
  final Group? group;
  GridItem.note(this.note) : group = null;
  GridItem.group(this.group) : note = null;
  bool get isNote => note != null;
  bool get isGroup => group != null;
}

/* ===================== UI (GRID) ===================== */

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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => GroupEditor(
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

  Future<bool?> _confirm(
      {required String title,
      required String message,
      String confirmText = 'ОК'}) {
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

/* ===================== SETTINGS SHEET (кнопки на своей строке) ===================== */

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
                    ButtonSegment(value: AppThemeMode.system, label: Text('Система')),
                    ButtonSegment(value: AppThemeMode.light, label: Text('Светлая')),
                    ButtonSegment(value: AppThemeMode.dark, label: Text('Тёмная')),
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

/* ===================== КАРТОЧКИ В СЕТКЕ ===================== */

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
                Text(group.title,
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
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

/* ===================== ПЕРЕТАСКИВАНИЕ ===================== */

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

/* ===================== РЕДАКТОР ЗАМЕТКИ ===================== */

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
  bool _detached = false;

  @override
  void initState() {
    super.initState();
    _model = widget.note?.copyWith() ?? Note.newNote();
    _text = TextEditingController(text: _model.text);
    _text.addListener(_onChanged);
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
      if (_model.numbered) {
        _ensureFirstNumber();
      }
    });
  }

  // Вставка "умной" нумерации (аналог нашей прошлой логики)
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isModifier = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (isModifier &&
        HardwareKeyboard.instance.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyL) {
      _toggleNumbering();
      return KeyEventResult.handled;
    }
    if (_model.numbered && event.logicalKey == LogicalKeyboardKey.enter) {
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
      final newText =
          text.replaceRange(lineStart, lineStart, '1. ');
      _text.value = _text.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + 3),
      );
    }
  }

  void _insertNextNumberOnNewline() {
    final sel = _text.selection;
    final text = _text.text;
    final idx = sel.start;
    final prevLine = _lineBefore(text, idx);
    final match = RegExp(r'^(\s*)(\d+)\.(\s*)').firstMatch(prevLine);
    if (match != null) {
      final indent = match.group(1) ?? '';
      final n = int.tryParse(match.group(2)!) ?? 1;
      final spaces = (match.group(3) ?? ' ').isEmpty ? ' ' : match.group(3)!;
      final insert = '\n$indent${n + 1}.$spaces';
      _text.value = _text.value.copyWith(
        text: text.replaceRange(idx, idx, insert),
        selection: TextSelection.collapsed(offset: idx + insert.length),
      );
    } else {
      const insert = '\n1. ';
      _text.value = _text.value.copyWith(
        text: text.replaceRange(idx, idx, insert),
        selection: TextSelection.collapsed(offset: idx + insert.length),
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

  String _lineBefore(String text, int pos) {
    final i = text.lastIndexOf('\n', pos - 1);
    if (i == -1) return text.substring(0, pos);
    final j = text.lastIndexOf('\n', i - 1);
    final start = j == -1 ? 0 : j + 1;
    return text.substring(start, i);
  }

  @override
  Widget build(BuildContext context) {
    final color = _model.colorHex != null ? Color(_model.colorHex!) : null;

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
                    onSelectionChanged: (s) {
                      _toggleNumbering();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Скопировать текст (как есть)',
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
              ],
            ),
            const SizedBox(height: 8),
            Focus(
              onKeyEvent: _handleKey,
              child: TextField(
                controller: _text,
                maxLines: 12,
                decoration: const InputDecoration(
                  hintText:
                      'Текст заметки...\nПодсказка: Ctrl/Cmd + Shift + L — переключить нумерацию',
                ),
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
                      onTap: () => setState(
                          () => _model = _model.copyWith(colorHex: c.value)),
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
                      onPressed: () {
                        _detached = true;
                        Navigator.pop(
                            context,
                            NoteActionResult(
                                note: _model, detachedFromGroup: true));
                      },
                    ),
                  ),
                if (_model.groupId != null) const SizedBox(width: 12),
                if (widget.note != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Удалить'),
                      onPressed: () => Navigator.pop(
                          context, NoteActionResult(note: _model, delete: true)),
                    ),
                  ),
                if (widget.note != null) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Сохранить'),
                    onPressed: () => Navigator.pop(
                        context, NoteActionResult(note: _model)),
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

/* ===================== ГРУППА: Лист и действия ===================== */

class GroupEditor extends StatefulWidget {
  final Group group;
  final List<Note> Function() notesProvider;
  final Future<void> Function(String title) onRename;
  final Future<void> Function(Note note) onEditNote;
  final Future<void> Function(Note note) onUngroupNote;
  final Future<void> Function(Note note) onDeleteNote;

  const GroupEditor({
    super.key,
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
  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.group.title);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'Название группы',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Сохранить'),
                  onPressed: () async {
                    await widget.onRename(_title.text.trim().isEmpty
                        ? 'Группа'
                        : _title.text.trim());
                    if (mounted) Navigator.pop(context);
                  },
                ),
              ],
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
                      subtitle: n.numbered
                          ? const Text('Нумерация включена')
                          : null,
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
                'Обновлено: ${_fmtDate(widget.group.updatedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ===================== МЕЛОЧИ/ПОМOЩНИКИ ===================== */

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

String _fmtDate(DateTime dt) {
  final d = dt;
  final two = (int n) => n < 10 ? '0$n' : '$n';
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}
