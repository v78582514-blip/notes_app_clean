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
    AppThemeMode.system => ThemeMode.system,
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
        updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
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
          _notes..clear()..addAll(ns);
          _groups..clear()..addAll(gs);
        }
      }
      if (_notes.isEmpty) {
        _notes.addAll([
          Note(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            text: '👋 Добро пожаловать!\nПеретащите заметку на другую — получится группа.',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            colorHex: const Color(0xFF64B5F6).value,
          ),
          Note(
            id: (DateTime.now().microsecondsSinceEpoch + 1).toString(),
            text: 'Удаление: перетащите заметку в левый верхний красный «Удалить».',
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
    filteredGroups.sort((a, b) => b.group!.updatedAt.compareTo(a.group!.updatedAt));
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
                      padding: const EdgeInsets.only(top: 8, left: 8, right: 8, bottom: 80),
                      child: GridView.builder(
                        itemCount: items.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                        top: 12,
                        left: 12,
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
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => NoteEditor(note: source),
    );
    if (result == null) return;

    if (result.delete) {
      final ok = await _confirm(title: 'Удалить заметку?', message: 'Действие необратимо.', confirmText: 'Удалить');
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
          final ok = await _confirm(title: 'Удалить заметку?', message: 'Действие необратимо.', confirmText: 'Удалить');
          if (ok == true) await store.deleteNote(note.id);
        },
      ),
    );
  }

  Future<bool?> _confirm({required String title, required String message, String confirmText = 'ОК'}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(confirmText)),
        ],
      ),
    );
  }
}

/* ===================== SETTINGS SHEET (кнопки сверху) ===================== */

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
          left: 16, right: 16, top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Кнопки сохраняем сверху — не перекрываются системой
            Row(
              children: [
                Text('Панель управления', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close), label: const Text('Отмена'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () async { await settings.setTheme(_mode); if (context.mounted) Navigator.pop(context); },
                  icon: const Icon(Icons.save), label: const Text('Сохранить'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Тема приложения', style: Theme.of(context).textTheme.labelLarge),
            ),
            const SizedBox(height: 8),
            SegmentedButton<AppThemeMode>(
              segments: const [
                ButtonSegment(value: AppThemeMode.system, label: Text('Системная'), icon: Icon(Icons.phone_android)),
                ButtonSegment(value: AppThemeMode.light, label: Text('Светлая'), icon: Icon(Icons.wb_sunny_outlined)),
                ButtonSegment(value: AppThemeMode.dark, label: Text('Тёмная'), icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/* ===================== DRAG PAYLOAD / TILE ===================== */

class DragPayload {
  final String type; // 'note' | 'group'
  final String id;
  DragPayload._(this.type, this.id);
  factory DragPayload.note(String id) => DragPayload._('note', id);
  factory DragPayload.group(String id) => DragPayload._('group', id);
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
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.85, child: SizedBox(width: 160, child: child)),
      ),
      onDragStarted: onDragStart,
      onDragEnd: (_) => onDragEnd(),
      child: child,
    );
  }
}

/* ===================== DELETE CORNER ===================== */

class _DeleteCorner extends StatelessWidget {
  final void Function(DragPayload) onAccept;
  const _DeleteCorner({required this.onAccept});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DragTarget<DragPayload>(
      onWillAccept: (_) => true,
      onAccept: onAccept,
      builder: (context, candidate, rejected) {
        final hover = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: hover ? cs.error : cs.error.withOpacity(0.85),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.15), blurRadius: 8)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.delete_forever, color: Colors.white),
              const SizedBox(width: 8),
              Text('Удалить', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
            ],
          ),
        );
      },
    );
  }
}

/* ===================== CARDS ===================== */

class _NoteCardGrid extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final Future<void> Function(DragPayload) onAcceptDrop;

  const _NoteCardGrid({required this.note, required this.onTap, required this.onAcceptDrop});

  @override
  Widget build(BuildContext context) {
    final color = note.colorHex != null ? Color(note.colorHex!) : null;
    final updated = _formatDate(note.updatedAt);

    final card = Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onDoubleTap: () async {
          await Clipboard.setData(ClipboardData(text: note.text));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Текст скопирован')));
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              children: [
                Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    color: color ?? Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _firstLine(note.text).isEmpty ? 'Без названия' : _firstLine(note.text),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                _restText(note.text),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Theme.of(context).textTheme.bodySmall?.color),
                const SizedBox(width: 6),
                Text('Обновлено: $updated', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ]),
        ),
      ),
    );

    return DragTarget<DragPayload>(
      onWillAccept: (p) => p != null && (p.isNote || p.isGroup),
      onAccept: onAcceptDrop,
      builder: (_, __, ___) => card,
    );
  }
}

class _GroupCard extends StatelessWidget {
  final Group group;
  final List<Note> notes;
  final VoidCallback onTap;
  final Future<void> Function(DragPayload) onAcceptDrop;

  const _GroupCard({
    required this.group,
    required this.notes,
    required this.onTap,
    required this.onAcceptDrop,
  });

  @override
  Widget build(BuildContext context) {
    final preview = notes.take(3).toList();
    final count = notes.length;

    final card = Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              children: [
                const Icon(Icons.folder, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    group.title.isEmpty ? 'Группа' : group.title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('$count', style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(children: [
                for (final n in preview)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: (n.colorHex != null ? Color(n.colorHex!) : Theme.of(context).colorScheme.surfaceVariant).withOpacity(0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _firstLine(n.text).isEmpty ? 'Без названия' : _firstLine(n.text),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                if (preview.length < 3)
                  Expanded(
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: const Icon(Icons.add, size: 20),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );

    return DragTarget<DragPayload>(
      onWillAccept: (p) => p != null && (p.isNote || p.isGroup),
      onAccept: onAcceptDrop,
      builder: (_, __, ___) => card,
    );
  }
}

/* ===================== EDITORS ===================== */

class NoteActionResult {
  final Note note;
  final bool delete;
  final bool detachedFromGroup;
  NoteActionResult({required this.note, this.delete = false, this.detachedFromGroup = false});
}

class NoteEditor extends StatefulWidget {
  final Note? note;
  const NoteEditor({super.key, this.note});
  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final TextEditingController _ctrl;
  TextEditingValue _lastValue = const TextEditingValue(text: '');
  bool _internalEdit = false;
  Color? _selectedColor;
  bool _detachFromGroup = false;
  bool _numbered = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.note?.text ?? '');
    _lastValue = _ctrl.value;
    _selectedColor = widget.note?.colorHex != null ? Color(widget.note!.colorHex!) : null;
    _numbered = widget.note?.numbered ?? false;
    _ctrl.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_handleTextChanged);
    _ctrl.dispose();
    super.dispose();
  }

  /* ==== НУМЕРАЦИЯ: умная вставка, двойной Enter завершает список ==== */
  void _handleTextChanged() {
    if (_internalEdit) { _lastValue = _ctrl.value; return; }
    final now = _ctrl.value;
    final old = _lastValue;

    // Только если включена нумерация
    if (_numbered) {
      // Случай 1: вставлен ровно один символ и это \n
      final insertedNewline = now.text.length == old.text.length + 1 &&
          now.selection.baseOffset == old.selection.baseOffset + 1 &&
          now.text.substring(0, now.selection.baseOffset).endsWith('\n');

      if (insertedNewline) {
        final caret = now.selection.baseOffset;
        // Текст до каретки (включая только что вставленный \n)
        final before = now.text.substring(0, caret);
        final lines = before.split('\n');

        // Предыдущая строка (до вставленного \n)
        final prevLine = lines.length >= 2 ? lines[lines.length - 2] : '';

        // Если предыдущая строка — только номер без текста: "<N>. " => двойной Enter -> завершить список
        final isEmptyNumbered = RegExp(r'^\d+\. $').hasMatch(prevLine);
        if (isEmptyNumbered) {
          // Удаляем "<N>. " из предыдущей строки и выходим без вставки нового номера
          final startOfPrevLine = before.lastIndexOf('\n', before.length - prevLine.length - 2);
          final absStart = startOfPrevLine == -1 ? 0 : startOfPrevLine + 1;
          final absEnd = absStart + prevLine.length; // позиция конца предыдущей строки
          final newText = now.text.replaceRange(absStart, absEnd, '');
          final delta = prevLine.length; // сколько удалили
          _internalEdit = true;
          _ctrl.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: caret - delta),
          );
          _internalEdit = false;
          _lastValue = _ctrl.value;
          return;
        }

        // Иначе — нормальный случай: вставить следующий номер после пустой строки счет обнуляется
        final lastEmptyBreak = before.substring(0, before.length - 1).lastIndexOf('\n\n'); // двойной \n — граница блоков
        final blockStart = lastEmptyBreak >= 0 ? lastEmptyBreak + 2 : 0;
        final blockText = before.substring(blockStart, before.length - 1); // без завершающего \n
        final blockLines = blockText.isEmpty ? <String>[] : blockText.split('\n');

        // Считаем непустые строки в блоке (игнорируя префикс N. )
        int nonEmpty = 0;
        for (final l in blockLines) {
          final stripped = l.replaceFirst(RegExp(r'^\d+\. '), '');
          if (stripped.trim().isNotEmpty) nonEmpty++;
        }
        final nextNumber = nonEmpty + 1;
        final insert = '$nextNumber. ';
        _internalEdit = true;
        _ctrl.value = TextEditingValue(
          text: now.text.replaceRange(caret, caret, insert),
          selection: TextSelection.collapsed(offset: caret + insert.length),
        );
        _internalEdit = false;
        _lastValue = _ctrl.value;
        return;
      }
    }

    _lastValue = now;
  }

  // При изменении тумблера — если включаем и курсор на пустой/новой строке, вставим "1. "
  void _maybeInsertFirstNumber() {
    final v = _ctrl.value;
    final caret = v.selection.baseOffset;
    if (caret < 0) return;
    // Найти начало текущей строки
    final lineStart = v.text.lastIndexOf('\n', caret - 1) + 1;
    final lineEnd = v.text.indexOf('\n', caret);
    final end = lineEnd == -1 ? v.text.length : lineEnd;
    final line = v.text.substring(lineStart, end);
    final leftOfCaret = v.text.substring(lineStart, caret);

    final hasNumberPrefix = RegExp(r'^\d+\. ').hasMatch(line);
    final isAtStart = leftOfCaret.trim().isEmpty;

    if (!hasNumberPrefix && isAtStart) {
      // Определим стартовый номер: если это новый блок (перед ним пустая строка) => 1
      // Иначе посчитаем предыдущие непустые строки в блоке
      final before = v.text.substring(0, lineStart);
      final lastEmptyBreak = before.lastIndexOf('\n\n');
      final blockStart = lastEmptyBreak >= 0 ? lastEmptyBreak + 2 : 0;
      final blockText = before.substring(blockStart);
      final blockLines = blockText.isEmpty ? <String>[] : blockText.split('\n');

      int nonEmpty = 0;
      for (final l in blockLines) {
        final stripped = l.replaceFirst(RegExp(r'^\d+\. '), '');
        if (stripped.trim().isNotEmpty) nonEmpty++;
      }
      final number = nonEmpty == 0 ? 1 : nonEmpty + 1;

      final insert = '$number. ';
      _internalEdit = true;
      _ctrl.value = TextEditingValue(
        text: v.text.replaceRange(lineStart, lineStart, insert),
        selection: TextSelection.collapsed(offset: caret + insert.length),
      );
      _internalEdit = false;
      _lastValue = _ctrl.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.note == null;
    final inGroup = widget.note?.groupId != null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          left: 16, right: 16, top: 8,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text(isNew ? 'Новая заметка' : 'Редактирование', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.close),
              label: const Text('Отмена'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () {
                final text = _ctrl.text.trimRight();
                var note = (widget.note ?? Note.newNote()).copyWith(
                  text: text,
                  numbered: _numbered,
                  updatedAt: DateTime.now(),
                  colorHex: _selectedColor?.value,
                  keepNullColor: _selectedColor == null,
                );
                final detached = _detachFromGroup && widget.note?.groupId != null;
                if (detached) {
                  note = note.copyWith(groupId: null, setGroupId: true);
                }
                Navigator.of(context).pop(NoteActionResult(note: note, detachedFromGroup: detached));
              },
              icon: const Icon(Icons.save),
              label: const Text('Сохранить'),
            ),
          ]),

          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _numbered,
                  onChanged: (v) {
                    setState(() => _numbered = v);
                    if (v) _maybeInsertFirstNumber(); // при включении — сразу "1. "
                  },
                  title: const Text('Нумерация строк'),
                ),
              ),
              if (inGroup)
                TextButton.icon(
                  onPressed: () => setState(() => _detachFromGroup = !_detachFromGroup),
                  icon: Icon(_detachFromGroup ? Icons.check_box : Icons.check_box_outline_blank),
                  label: const Text('Отделить от группы'),
                ),
            ],
          ),

          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _ColorDot(
                  color: null,
                  selected: _selectedColor == null,
                  onTap: () => setState(() => _selectedColor = null),
                  label: 'Без цвета',
                ),
                for (final c in _palette())
                  _ColorDot(
                    color: c,
                    selected: _selectedColor?.value == c.value,
                    onTap: () => setState(() => _selectedColor = c),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            autofocus: true,
            minLines: 8,
            maxLines: 16,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(hintText: 'Текст заметки…'),
          ),

          if (!isNew) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Удалить заметку?'),
                      content: const Text('Действие необратимо.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    final note = widget.note!;
                    Navigator.of(context).pop(NoteActionResult(note: note, delete: true));
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Удалить заметку'),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

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
  late final TextEditingController _title;

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
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 16, right: 16, top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Группа', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close), label: const Text('Отмена'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () async { await widget.onRename(_title.text.trim()); if (context.mounted) Navigator.pop(context); },
                  icon: const Icon(Icons.save), label: const Text('Сохранить'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Заголовок группы', hintText: 'Например: Проект А'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Заметки в группе (${notes.length}):', style: Theme.of(context).textTheme.labelLarge),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                itemCount: notes.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (c, i) {
                  final n = notes[i];
                  return Dismissible(
                    key: ValueKey('ungroup_${n.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      color: Theme.of(context).colorScheme.primary.withOpacity(.15),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const Icon(Icons.call_split),
                    ),
                    confirmDismiss: (_) async {
                      await widget.onUngroupNote(n);
                      setState(() {});
                      return false;
                    },
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.note),
                      title: Text(
                        _firstLine(n.text).isEmpty ? 'Без названия' : _firstLine(n.text),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        _restText(n.text),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () async { await widget.onEditNote(n); setState(() {}); },
                      trailing: Wrap(spacing: 8, children: [
                        IconButton(
                          tooltip: 'Отделить от группы',
                          icon: const Icon(Icons.call_split),
                          onPressed: () async { await widget.onUngroupNote(n); setState(() {}); },
                        ),
                        IconButton(
                          tooltip: 'Удалить',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Удалить заметку?'),
                                content: const Text('Действие необратимо.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
                                ],
                              ),
                            );
                            if (ok == true) { await widget.onDeleteNote(n); setState(() {}); }
                          },
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ===================== HELPERS & UTILS ===================== */

List<Color> _palette() => const [
  Color(0xFFE57373), Color(0xFFF06292), Color(0xFFBA68C8), Color(0xFF9575CD),
  Color(0xFF7986CB), Color(0xFF64B5F6), Color(0xFF4FC3F7), Color(0xFF4DD0E1),
  Color(0xFF4DB6AC), Color(0xFF81C784), Color(0xFFAED581), Color(0xFFDCE775),
  Color(0xFFFFF176), Color(0xFFFFD54F), Color(0xFFFFB74D), Color(0xFFFF8A65),
  Color(0xFFA1887F), Color(0xFF90A4AE),
];

class _ColorDot extends StatelessWidget {
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  final String? label;
  const _ColorDot({required this.color, required this.selected, required this.onTap, this.label});

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.outlineVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: color ?? Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : borderColor,
              width: selected ? 2 : 1,
            ),
          ),
          child: color == null ? const Center(child: Icon(Icons.close, size: 16)) : null,
        ),
        if (label != null) ...[
          const SizedBox(width: 6),
          Text(label!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  final String err;
  final VoidCallback onReset;
  const _ErrorPane({required this.err, required this.onReset});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(err, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onReset, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

String _firstLine(String t) {
  final ls = t.trim().split('\n');
  return ls.isEmpty ? '' : ls.first.trim();
}
String _restText(String t) {
  final ls = t.trim().split('\n');
  if (ls.length <= 1) return '';
  return ls.skip(1).join('\n').trim();
}
String _pad(int n) => n.toString().padLeft(2, '0');
String _formatDate(DateTime dt) {
  final now = DateTime.now();
  final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
  return sameDay ? '${_pad(dt.hour)}:${_pad(dt.minute)}' : '${_pad(dt.day)}.${_pad(dt.month)}.${dt.year}';
}
