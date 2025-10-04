import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const NotesApp());

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Заметки',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: const NotesHomePage(),
    );
  }
}

class Note {
  String id;
  String text;
  bool pinned;
  int? colorHex;
  int updatedAt;
  Note({
    required this.id,
    required this.text,
    this.pinned = false,
    this.colorHex,
    required this.updatedAt,
  });

  factory Note.newNote() => Note(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: '',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'pinned': pinned,
        'colorHex': colorHex,
        'updatedAt': updatedAt,
      };

  static Note fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        text: (j['text'] ?? '') as String,
        pinned: (j['pinned'] ?? false) as bool,
        colorHex: j['colorHex'] as int?,
        updatedAt: (j['updatedAt'] ?? 0) as int,
      );
}

class NotesStore extends ChangeNotifier {
  static const _k = 'notes_v1_colors';
  final List<Note> _items = [];
  bool _loaded = false;
  String? _error;

  List<Note> get items => List.unmodifiable(_items);
  bool get isLoaded => _loaded;
  String? get error => _error;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_k);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw);
        if (data is List) {
          _items
            ..clear()
            ..addAll(data
                .cast<Map>()
                .map((e) => Map<String, dynamic>.from(e as Map))
                .map(Note.fromJson));
        } else {
          await p.remove(_k);
        }
      }
    } catch (e) {
      _error = 'Ошибка загрузки: $e';
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_k, jsonEncode(_items.map((e) => e.toJson()).toList()));
    } catch (e) {
      _error = 'Ошибка сохранения: $e';
      notifyListeners();
    }
  }

  Future<void> add(Note n) async {
    _items.add(n);
    await _save();
    notifyListeners();
  }

  Future<void> update(Note n) async {
    final i = _items.indexWhere((x) => x.id == n.id);
    if (i != -1) {
      _items[i] = n..updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _save();
      notifyListeners();
    }
  }

  Future<void> remove(String id) async {
    _items.removeWhere((n) => n.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> togglePin(String id) async {
    final i = _items.indexWhere((x) => x.id == id);
    if (i != -1) {
      final n = _items[i];
      n.pinned = !n.pinned;
      n.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _save();
      notifyListeners();
    }
  }
}

class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key});
  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  final store = NotesStore();
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    store.addListener(() => setState(() {}));
    store.load();
  }

  @override
  void dispose() {
    _search.dispose();
    store.dispose();
    super.dispose();
  }

  List<Note> get _visible {
    final q = _search.text.trim().toLowerCase();
    final src = q.isEmpty ? store.items : store.items.where((n) => n.text.toLowerCase().contains(q)).toList();
    src.sort((a, b) {
      if (a.pinned != b.pinned) return b.pinned ? 1 : -1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return src;
  }

  Future<void> _edit({Note? src}) async {
    final res = await showModalBottomSheet<Note>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => NoteEditor(note: src),
    );
    if (res == null) return;
    if (src == null) {
      await store.add(res);
    } else {
      await store.update(res);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!store.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (store.error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Заметки')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(store.error!, textAlign: TextAlign.center),
        )),
      );
    }

    final notes = _visible;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Поиск…', isDense: true),
                onChanged: (_) => setState(() {}),
              )
            : const Text('Заметки'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _searching = !_searching;
                if (!_searching) _search.clear();
              });
            },
            icon: Icon(_searching ? Icons.close : Icons.search),
          ),
        ],
      ),
      body: notes.isEmpty
          ? const _EmptyState()
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: notes.length,
              itemBuilder: (c, i) {
                final n = notes[i];
                return Dismissible(
                  key: ValueKey(n.id),
                  background: _swipeBg(context, left: true),
                  secondaryBackground: _swipeBg(context, left: false),
                  onDismissed: (_) => store.remove(n.id),
                  child: _NoteTile(
                    note: n,
                    onEdit: () => _edit(src: n),
                    onTogglePin: () => store.togglePin(n.id),
                    onDelete: () => store.remove(n.id),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Новая'),
      ),
    );
  }
}

Widget _swipeBg(BuildContext context, {required bool left}) => Container(
  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.errorContainer,
    borderRadius: BorderRadius.circular(16),
  ),
  alignment: left ? Alignment.centerLeft : Alignment.centerRight,
  padding: EdgeInsets.only(left: left ? 24 : 0, right: left ? 0 : 24),
  child: const Icon(Icons.delete),
);

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.note_alt_outlined, size: 72),
          const SizedBox(height: 16),
          const Text('Нет заметок', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Нажми «Новая», чтобы создать первую запись.',
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _NoteTile extends StatelessWidget {
  final Note note;
  final VoidCallback onEdit;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;
  const _NoteTile({required this.note, required this.onEdit, required this.onTogglePin, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final color = note.colorHex != null ? Color(note.colorHex!) : null;
    final updated = DateTime.fromMillisecondsSinceEpoch(note.updatedAt);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 6,
            decoration: BoxDecoration(
              color: color ?? Colors.transparent,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (note.pinned)
                  const Padding(
                    padding: EdgeInsets.only(top: 4, right: 8),
                    child: Icon(Icons.push_pin, size: 18),
                  ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          _firstLine(note.text).isEmpty ? 'Без названия' : _firstLine(note.text),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                      ),
                      if (color != null)
                        Container(
                          width: 14, height: 14, margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle,
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 6),
                    Text(_restText(note.text), maxLines: 3, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.access_time, size: 14, color: Theme.of(context).textTheme.bodySmall?.color),
                      const SizedBox(width: 4),
                      Text('Обновлено: ${_fmt(updated)}', style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ]),
                ),
                const SizedBox(width: 8),
                Column(children: [
                  IconButton(tooltip: note.pinned ? 'Открепить' : 'Закрепить',
                    onPressed: onTogglePin, icon: Icon(note.pinned ? Icons.push_pin : Icons.push_pin_outlined)),
                  IconButton(tooltip: 'Удалить', onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class NoteEditor extends StatefulWidget {
  final Note? note;
  const NoteEditor({super.key, this.note});
  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final TextEditingController _ctrl;
  Color? _color;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.note?.text ?? '');
    _color = widget.note?.colorHex != null ? Color(widget.note!.colorHex!) : null;
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
            tooltip: 'Вставить дату',
            onPressed: () {
              final now = DateTime.now();
              final s = '${_pad(now.day)}.${_pad(now.month)}.${now.year} ${_pad(now.hour)}:${_pad(now.minute)}';
              final sel = _ctrl.selection;
              final t = _ctrl.text;
              final start = sel.start >= 0 ? sel.start : t.length;
              final end = sel.end >= 0 ? sel.end : t.length;
              _ctrl.text = t.replaceRange(start, end, s);
              _ctrl.selection = TextSelection.collapsed(offset: start + s.length);
            },
            icon: const Icon(Icons.calendar_month),
          ),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8, runSpacing: 8,
            children: [
              _ColorDot(color: null, selected: _color == null, onTap: () => setState(() => _color = null), label: 'Без цвета'),
              for (final c in _palette())
                _ColorDot(color: c, selected: _color?.value == c.value, onTap: () => setState(() => _color = c)),
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
                final note = (widget.note ?? Note.newNote());
                note.text = _ctrl.text.trim();
                note.colorHex = _color?.value;
                note.updatedAt = DateTime.now().millisecondsSinceEpoch;
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

class _ColorDot extends StatelessWidget {
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  final String? label;
  const _ColorDot({required this.color, required this.selected, required this.onTap, this.label});
  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).colorScheme.outlineVariant;
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(999),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: color ?? Colors.transparent, shape: BoxShape.circle,
            border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : border, width: selected ? 2 : 1),
          ),
          child: color == null ? const Center(child: Icon(Icons.close, size: 16)) : null,
        ),
        if (label != null) ...[const SizedBox(width: 6), Text(label!, style: Theme.of(context).textTheme.bodySmall)],
      ]),
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

String _firstLine(String t) => (t.trim().split('\n').isEmpty) ? '' : t.trim().split('\n').first.trim();
String _restText(String t) {
  final ls = t.trim().split('\n');
  return ls.length <= 1 ? '' : ls.skip(1).join('\n').trim();
}
String _pad(int n) => n.toString().padLeft(2, '0');
String _fmt(DateTime dt) {
  final now = DateTime.now();
  final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
  return sameDay ? '${_pad(dt.hour)}:${_pad(dt.minute)}' : '${_pad(dt.day)}.${_pad(dt.month)}.${dt.year}';
}
