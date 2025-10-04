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
        cardTheme: CardTheme(
          elevation: 2,
          shadowColor: scheme.primary.withOpacity(.15),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
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
  bool pinned;
  int? colorHex;

  Note({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.pinned = false,
    this.colorHex,
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
    bool? pinned,
    DateTime? updatedAt,
    int? colorHex,
    bool keepNullColor = false,
  }) =>
      Note(
        id: id,
        text: text ?? this.text,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        pinned: pinned ?? this.pinned,
        colorHex: keepNullColor ? null : (colorHex ?? this.colorHex),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'pinned': pinned,
        'colorHex': colorHex,
      };

  static Note fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        text: (json['text'] ?? '') as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
        pinned: (json['pinned'] ?? false) as bool,
        colorHex: json['colorHex'] as int?,
      );
}

class NotesStore extends ChangeNotifier {
  static const _prefsKey = 'notes_v1_colors';
  final List<Note> _items = [];
  bool _loaded = false;
  String? _error;

  List<Note> get items => List.unmodifiable(_items);
  bool get isLoaded => _loaded;
  String? get lastError => _error;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final list = decoded
              .map((e) => Map<String, dynamic>.from(e as Map))
              .map(Note.fromJson)
              .toList();
          _items
            ..clear()
            ..addAll(list);
        } else {
          await prefs.remove(_prefsKey);
        }
      }
      if (_items.isEmpty) {
        // Первая заметка для пустого состояния
        _items.add(Note(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: '👋 Добро пожаловать!\nСоздайте свою первую заметку.',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          colorHex: const Color(0xFF64B5F6).value,
        ));
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
      final raw = jsonEncode(_items.map((e) => e.toJson()).toList());
      await prefs.setString(_prefsKey, raw);
    } catch (e) {
      _error = 'Ошибка сохранения: $e';
      notifyListeners();
    }
  }

  Future<void> add(Note note) async {
    _items.add(note);
    await _persist();
    notifyListeners();
  }

  Future<void> update(Note note) async {
    final idx = _items.indexWhere((n) => n.id == note.id);
    if (idx != -1) {
      _items[idx] = note.copyWith(updatedAt: DateTime.now());
      await _persist();
      notifyListeners();
    }
  }

  Future<void> remove(String id) async {
    _items.removeWhere((n) => n.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> togglePin(String id) async {
    final idx = _items.indexWhere((n) => n.id == id);
    if (idx != -1) {
      final n = _items[idx];
      _items[idx] = n.copyWith(pinned: !n.pinned, updatedAt: DateTime.now());
      await _persist();
      notifyListeners();
    }
  }
}

/* ===================== UI ===================== */
class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key});
  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  final store = NotesStore();
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  bool _grid = false;

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

  List<Note> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    final base = List<Note>.from(store.items); // копия (не трогаем unmodifiable)
    final list = q.isEmpty ? base : base.where((n) => n.text.toLowerCase().contains(q)).toList();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return b.pinned ? 1 : -1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  Iterable<Note> get _pinned => _filtered.where((n) => n.pinned);
  Iterable<Note> get _others => _filtered.where((n) => !n.pinned);

  Future<void> _edit({Note? src}) async {
    final result = await showModalBottomSheet<Note>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => NoteEditor(note: src),
    );
    if (result == null) return;
    if (src == null) {
      await store.add(result);
    } else {
      await store.update(result);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сохранено')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = store.isLoaded;
    final err = store.lastError;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Поиск…', isDense: true),
                onChanged: (_) => setState(() {}),
              )
            : const Text('Заметки'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Закрыть поиск' : 'Поиск',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _searchCtrl.clear();
            }),
            icon: Icon(_searching ? Icons.close : Icons.search),
          ),
          IconButton(
            tooltip: _grid ? 'Список' : 'Сетка',
            onPressed: () => setState(() => _grid = !_grid),
            icon: Icon(_grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded),
          ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? _ErrorPane(err: err, onReset: () => setState(() => store.load()))
              : _Content(
                  grid: _grid,
                  pinned: _pinned.toList(),
                  others: _others.toList(),
                  onOpen: (n) => _edit(src: n),
                  onDelete: (id) => store.remove(id),
                  onTogglePin: (id) => store.togglePin(id),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Новая'),
      ),
    );
  }
}

/* ==== CONTENT with sections & grid/list ==== */
class _Content extends StatelessWidget {
  final bool grid;
  final List<Note> pinned;
  final List<Note> others;
  final void Function(Note) onOpen;
  final void Function(String) onDelete;
  final void Function(String) onTogglePin;

  const _Content({
    required this.grid,
    required this.pinned,
    required this.others,
    required this.onOpen,
    required this.onDelete,
    required this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    if (pinned.isEmpty && others.isEmpty) return const _EmptyState();

    // Используем один прокручиваемый список и вкладываем внутрь Grid/List с shrinkWrap
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pinned.isNotEmpty) ...[
            const _SectionHeader(title: 'Закреплённые'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: grid
                  ? _NotesGrid(
                      notes: pinned,
                      onOpen: onOpen,
                      onDelete: onDelete,
                      onTogglePin: onTogglePin,
                    )
                  : _NotesList(
                      notes: pinned,
                      onOpen: onOpen,
                      onDelete: onDelete,
                      onTogglePin: onTogglePin,
                    ),
            ),
            const SizedBox(height: 12),
          ],
          if (others.isNotEmpty) ...[
            const _SectionHeader(title: 'Остальные'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: grid
                  ? _NotesGrid(
                      notes: others,
                      onOpen: onOpen,
                      onDelete: onDelete,
                      onTogglePin: onTogglePin,
                    )
                  : _NotesList(
                      notes: others,
                      onOpen: onOpen,
                      onDelete: onDelete,
                      onTogglePin: onTogglePin,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

/* ==== LIST MODE ==== */
class _NotesList extends StatelessWidget {
  final List<Note> notes;
  final void Function(Note) onOpen;
  final void Function(String) onDelete;
  final void Function(String) onTogglePin;

  const _NotesList({required this.notes, required this.onOpen, required this.onDelete, required this.onTogglePin});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: notes.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (c, i) => _NoteCard(
        note: notes[i],
        layout: _CardLayout.list,
        onOpen: onOpen,
        onDelete: onDelete,
        onTogglePin: onTogglePin,
      ),
    );
  }
}

/* ==== GRID MODE ==== */
class _NotesGrid extends StatelessWidget {
  final List<Note> notes;
  final void Function(Note) onOpen;
  final void Function(String) onDelete;
  final void Function(String) onTogglePin;

  const _NotesGrid({required this.notes, required this.onOpen, required this.onDelete, required this.onTogglePin});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cross = w > 720 ? 3 : 2;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: notes.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cross,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.95,
      ),
      itemBuilder: (c, i) => _NoteCard(
        note: notes[i],
        layout: _CardLayout.grid,
        onOpen: onOpen,
        onDelete: onDelete,
        onTogglePin: onTogglePin,
      ),
    );
  }
}

/* ==== CARD ==== */
enum _CardLayout { list, grid }

class _NoteCard extends StatelessWidget {
  final Note note;
  final _CardLayout layout;
  final void Function(Note) onOpen;
  final void Function(String) onDelete;
  final void Function(String) onTogglePin;

  const _NoteCard({
    required this.note,
    required this.layout,
    required this.onOpen,
    required this.onDelete,
    required this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    final color = note.colorHex != null ? Color(note.colorHex!) : null;
    final updated = _formatDate(note.updatedAt);

    Widget actionsBar = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: note.pinned ? 'Открепить' : 'Закрепить',
          icon: Icon(note.pinned ? Icons.push_pin : Icons.push_pin_outlined),
          onPressed: () => onTogglePin(note.id),
        ),
        IconButton(
          tooltip: 'Удалить',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => onDelete(note.id),
        ),
      ],
    );

    final card = Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => onOpen(note),
        onLongPress: () async {
          final action = await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.copy),
                    title: const Text('Копировать текст'),
                    onTap: () => Navigator.pop(ctx, 'copy'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Удалить'),
                    onTap: () => Navigator.pop(ctx, 'delete'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
          if (action == 'copy') {
            await Clipboard.setData(ClipboardData(text: note.text));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Текст скопирован')));
            }
          } else if (action == 'delete') {
            onDelete(note.id);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Цветная полоска
              Container(
                width: 6,
                decoration: BoxDecoration(
                  color: color ?? Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Заголовок
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _firstLine(note.text).isEmpty ? 'Без названия' : _firstLine(note.text),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (layout == _CardLayout.list) actionsBar,
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Превью
                      Text(
                        _restText(note.text),
                        maxLines: layout == _CardLayout.grid ? 6 : 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      // Метаданные
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Theme.of(context).textTheme.bodySmall?.color),
                          const SizedBox(width: 6),
                          Text('Обновлено: $updated', style: Theme.of(context).textTheme.bodySmall),
                          const Spacer(),
                          if (layout == _CardLayout.grid) actionsBar,
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (layout == _CardLayout.grid) {
      return card;
    }
    return card;
  }
}

/* ==== Editor ==== */
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

/* ==== Small widgets & utils ==== */
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
