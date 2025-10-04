import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) => FlutterError.presentError(details);
  runZonedGuarded(() => runApp(const NotesApp()), (e, s) {});
}

/* ===================== APP ===================== */

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Заметки',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: const NotesHomePage(),
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
  String? groupId; // если в группе — тут id группы

  Note({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.colorHex,
    this.groupId,
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
  }) =>
      Note(
        id: id,
        text: text ?? this.text,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        colorHex: keepNullColor ? null : (colorHex ?? this.colorHex),
        groupId: groupId ?? this.groupId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'colorHex': colorHex,
        'groupId': groupId,
      };

  static Note fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        text: (json['text'] ?? '') as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
        colorHex: json['colorHex'] as int?,
        groupId: json['groupId'] as String?,
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
  static const _prefsKey = 'notes_v2_grid_groups';
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
            text: 'Удаление: потяните заметку в левый верхний красный угол.',
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
    // удалить все заметки, входящие в группу?
    // По ТЗ — удаляем группу целиком (и её заметки).
    _notes.removeWhere((n) => n.groupId == groupId);
    _groups.removeWhere((g) => g.id == groupId);
    await _persist();
    notifyListeners();
  }

  List<Note> notesInGroup(String groupId) => _notes.where((n) => n.groupId == groupId).toList();
  Group? findGroup(String id) => _groups.firstWhere((g) => g.id == id, orElse: () => Group(id: '', title: '', updatedAt: DateTime(0))).id.isEmpty ? null : _groups.firstWhere((g) => g.id == id);

  Future<void> addNoteToGroup(String noteId, String groupId) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx != -1) {
      _notes[idx] = _notes[idx].copyWith(groupId: groupId, updatedAt: DateTime.now());
      await _persist();
      notifyListeners();
    }
  }

  Future<void> removeNoteFromGroup(String noteId) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx != -1) {
      _notes[idx] = _notes[idx].copyWith(groupId: null, updatedAt: DateTime.now());
      await _persist();
      notifyListeners();
    }
  }

  Future<void> createGroupWith(String noteAId, String noteBId) async {
    // если любая из заметок уже в группе — используем её группу
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
      // обе в группах — объединим группы
      if (a.groupId != b.groupId) {
        final target = a.groupId!;
        final source = b.groupId!;
        for (final n in _notes.where((n) => n.groupId == source)) {
          await addNoteToGroup(n.id, target);
        }
        _groups.removeWhere((g) => g.id == source);
        await _persist();
        notifyListeners();
      }
      return;
    }
    // создать новую группу
    final g = Group(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: 'Группа',
      updatedAt: DateTime.now(),
    );
    _groups.add(g);
    final ia = _notes.indexWhere((n) => n.id == a.id);
    final ib = _notes.indexWhere((n) => n.id == b.id);
    _notes[ia] = a.copyWith(groupId: g.id, updatedAt: DateTime.now());
    _notes[ib] = b.copyWith(groupId: g.id, updatedAt: DateTime.now());
    await _persist();
    notifyListeners();
  }

  // Все элементы, которые отображаем в гриде (группы + одиночные заметки не в группе)
  List<GridItem> getGridItems({String query = ''}) {
    final q = query.trim().toLowerCase();
    final singles = _notes.where((n) => n.groupId == null);
    final gs = _groups.map((g) => GridItem.group(g)).toList();
    final ns = singles
        .where((n) => q.isEmpty ? true : n.text.toLowerCase().contains(q))
        .map((n) => GridItem.note(n))
        .toList();
    // фильтрация групп по тексту заметок/заголовку
    final filteredGroups = gs.where((gi) {
      final g = gi.group!;
      final inTitle = q.isEmpty ? true : g.title.toLowerCase().contains(q);
      if (inTitle) return true;
      if (q.isEmpty) return true;
      final notes = notesInGroup(g.id);
      return notes.any((n) => n.text.toLowerCase().contains(q));
    }).toList();
    // сортировка — по обновлению (группы по updatedAt, заметки по updatedAt)
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

/* ===================== UI (ONLY GRID) ===================== */

class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key});
  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  final store = NotesStore();
  final _searchCtrl = TextEditingController();
  bool _dragging = false; // показывать красный «угол удаления»

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
                    // сам GRID
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
                    // угол удаления (верхний левый)
                    if (_dragging)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: _DeleteCorner(
                          onAccept: (payload) => _handleDelete(payload),
                        ),
                      ),
                  ],
                ),
    );
  }

  /* ====== DROP HANDLERS ====== */

  Future<void> _handleDropOnNote(DragPayload payload, Note target) async {
    if (payload.isNote) {
      if (payload.id == target.id) return;
      await store.createGroupWith(payload.id, target.id);
    } else if (payload.isGroup) {
      // Перетащили группу на заметку: добавим одиночную заметку в эту группу
      final gid = payload.id;
      if (target.groupId == gid) return; // уже в этой группе
      // если у заметки есть другая группа — перенесём в новую
      await store.addNoteToGroup(target.id, gid);
    }
  }

  Future<void> _handleDropOnGroup(DragPayload payload, Group target) async {
    if (payload.isNote) {
      // добавить заметку в группу
      await store.addNoteToGroup(payload.id, target.id);
    } else if (payload.isGroup) {
      // объединить группы (payload -> target)
      final source = payload.id;
      if (source == target.id) return;
      // переместим всех участников source в target
      final moving = store.notesInGroup(source);
      for (final n in moving) {
        await store.addNoteToGroup(n.id, target.id);
      }
      await store.deleteGroup(source);
    }
  }

  Future<void> _handleDelete(DragPayload payload) async {
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

  /* ====== EDITORS ====== */

  Future<void> _openEditor({Note? source}) async {
    final result = await showModalBottomSheet<Note>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => NoteEditor(note: source),
    );
    if (result == null) return;
    if (source == null) {
      await store.addNote(result);
    } else {
      await store.updateNote(result);
    }
  }

  Future<void> _openGroup(Group g) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => GroupEditor(
        group: g,
        notes: store.notesInGroup(g.id),
        onRename: (title) async => store.updateGroup(g.copyWith(title: title)),
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
        // ⬇️ КОПИРОВАНИЕ ПЕРЕНЕСЕНО НА ДВОЙНОЙ ТАП (а не long-press)
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
                  width: 14,
                  height: 14,
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

    // Принимаем дроп (заметка/группа → на заметку)
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
            // превью из 3 маленьких «плашек»
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

class NoteEditor extends StatefulWidget {
  final Note? note;
  const NoteEditor({super.key, this.note});
  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final TextEditingController _ctrl;
  Color? _selectedColor;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.note?.text ?? '');
    _selectedColor = widget.note?.colorHex != null ? Color(widget.note!.colorHex!) : null;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.note == null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16, right: 16, top: 8,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text(isNew ? 'Новая заметка' : 'Редактирование', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
            tooltip: 'Вставить текущую дату',
            onPressed: () {
              final now = DateTime.now();
              final s = '${_pad(now.day)}.${_pad(now.month)}.${now.year} ${_pad(now.hour)}:${_pad(now.minute)}';
              final sel = _ctrl.selection;
              final t = _ctrl.text;
              final inserted = t.replaceRange(sel.start >= 0 ? sel.start : t.length, sel.end >= 0 ? sel.end : t.length, s);
              _ctrl.text = inserted;
              _ctrl.selection = TextSelection.collapsed(offset: (sel.start >= 0 ? sel.start : t.length) + s.length);
            },
            icon: const Icon(Icons.calendar_month),
          ),
        ]),
        const SizedBox(height: 8),
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
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl, autofocus: true, minLines: 6, maxLines: 12,
          decoration: const InputDecoration(hintText: 'Текст заметки…'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () {
                final raw = _ctrl.text.trim();
                final text = raw.isEmpty ? '' : raw;
                final note = (widget.note ?? Note.newNote()).copyWith(
                  text: text,
                  updatedAt: DateTime.now(),
                  colorHex: _selectedColor?.value,
                  keepNullColor: _selectedColor == null,
                );
                Navigator.of(context).pop(note);
              },
              icon: const Icon(Icons.check), label: const Text('Сохранить'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close), label: const Text('Отмена'),
            ),
          ),
        ]),
      ]),
    );
  }
}

class GroupEditor extends StatefulWidget {
  final Group group;
  final List<Note> notes;
  final Future<void> Function(String title) onRename;

  const GroupEditor({super.key, required this.group, required this.notes, required this.onRename});

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
    final notes = widget.notes;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16, right: 16, top: 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Группа', style: Theme.of(context).textTheme.titleLarge),
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
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.separated(
              itemCount: notes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (c, i) {
                final n = notes[i];
                return ListTile(
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
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    await widget.onRename(_title.text.trim());
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Сохранить'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close),
                  label: const Text('Отмена'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ===================== SMALL WIDGETS & UTILS ===================== */

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
          width: 28,
          height: 28,
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

List<Color> _palette() => const [
  Color(0xFFE57373), Color(0xFFF06292), Color(0xFFBA68C8), Color(0xFF9575CD),
  Color(0xFF7986CB), Color(0xFF64B5F6), Color(0xFF4FC3F7), Color(0xFF4DD0E1),
  Color(0xFF4DB6AC), Color(0xFF81C784), Color(0xFFAED581), Color(0xFFDCE775),
  Color(0xFFFFF176), Color(0xFFFFD54F), Color(0xFFFFB74D), Color(0xFFFF8A65),
  Color(0xFFA1887F), Color(0xFF90A4AE),
];

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
