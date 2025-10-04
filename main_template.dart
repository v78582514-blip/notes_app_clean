import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  // ВАЖНО: гарантируем инициализацию, чтобы плагины (SharedPreferences) работали стабильно
  WidgetsFlutterBinding.ensureInitialized();

  // Ловушки ошибок, чтобы не было «белого экрана»
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };
  runZonedGuarded(() {
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Ошибка запуска')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(details.exceptionAsString(), style: const TextStyle(fontSize: 14)),
          ),
        ),
      );
    };
    runApp(const NotesApp());
  }, (error, stack) {});
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Заметки',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: ThemeMode.system,
      home: const NotesHomePage(),
    );
  }
}

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
  static const _firstRunKey = 'notes_first_run_done';

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

      // Если это первый запуск и список пуст — добавим демо-заметку
      final firstRunDone = prefs.getBool(_firstRunKey) ?? false;
      if (!firstRunDone && _items.isEmpty) {
        _items.add(
          Note(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            text: 'Это ваша первая заметка!\nНажмите «Новая», чтобы создать ещё.',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            colorHex: const Color(0xFF64B5F6).value,
          ),
        );
        await _persist();
        await prefs.setBool(_firstRunKey, true);
      }
    } catch (e) {
      _error = 'Ошибка загрузки данных: $e';
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

  Future<void> resetStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    await prefs.remove(_firstRunKey);
    _items.clear();
    _error = null;
    notifyListeners();
  }
}

class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key});
  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  final store = NotesStore();
  bool searching = false;
  final _searchCtrl = TextEditingController();

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

  // Копируем список перед сортировкой (чтобы не трогать unmodifiable)
  List<Note> get _visibleNotes {
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? List<Note>.from(store.items)
        : store.items.where((n) => n.text.toLowerCase().contains(q)).toList();
    filtered.sort((a, b) {
      if (a.pinned != b.pinned) return b.pinned ? 1 : -1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return filtered;
  }

  Future<void> _openEditor({Note? source}) async {
    final created = await showModalBottomSheet<Note>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => NoteEditor(note: source),
    );
    if (created == null) return;
    if (source == null) {
      await store.add(created);
    } else {
      await store.update(created);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = _visibleNotes;

    return Scaffold(
      appBar: AppBar(
        title: searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Поиск заметок…', isDense: true),
                onChanged: (_) => setState(() {}),
              )
            : const Text('Заметки'),
        actions: [
          IconButton(
            tooltip: searching ? 'Закрыть поиск' : 'Поиск',
            onPressed: () {
              setState(() {
                searching = !searching;
                if (!searching) _searchCtrl.clear();
              });
            },
            icon: Icon(searching ? Icons.close : Icons.search),
          ),
          IconButton(
            tooltip: 'Сбросить данные',
            onPressed: () async {
              await store.resetStorage();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Хранилище очищено')),
                );
              }
            },
            icon: const Icon(Icons.restore),
          ),
        ],
      ),
      body: !store.isLoaded
          ? const Center(child: CircularProgressIndicator())
          : notes.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: notes.length,
                  itemBuilder: (context, i) {
                    final n = notes[i];
                    return Dismissible(
                      key: ValueKey(n.id),
                      background: _swipeBg(context, left: true),
                      secondaryBackground: _swipeBg(context, left: false),
                      onDismissed: (_) => store.remove(n.id),
                      child: _NoteTile(
                        note: n,
                        onEdit: () => _openEditor(source: n),
                        onTogglePin: () => store.togglePin(n.id),
                        onDelete: () => store.remove(n.id),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
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
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
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
}

class _NoteTile extends StatelessWidget {
  final Note note;
  final VoidCallback onEdit;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;
  const _NoteTile({required this.note, required this.onEdit, required this.onTogglePin, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final updated = _formatDate(note.updatedAt);
    final color = note.colorHex != null ? Color(note.colorHex!) : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onEdit,
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Текст скопирован')),
              );
            }
          } else if (action == 'delete') {
            onDelete();
          }
        },
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
              padding: const EdgeInsets.all(12.0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (note.pinned)
                  const Padding(
                    padding: EdgeInsets.only(top: 4.0, right: 8),
                    child: Icon(Icons.push_pin, size: 18),
                  ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          _firstLine(note.text).isEmpty ? 'Без названия' : _firstLine(note.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                      Text('Обновлено: $updated', style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ]),
                ),
                const SizedBox(width: 8),
                Column(children: [
                  IconButton(
                    tooltip: note.pinned ? 'Открепить' : 'Закрепить',
                    onPressed: onTogglePin,
                    icon: Icon(note.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                  ),
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
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8, runSpacing: 8,
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
                  // если цвет не выбран, сохраняем null
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
      onTap: onTap, borderRadius: BorderRadius.circular(999),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: color ?? Colors.transparent, shape: BoxShape.circle,
            border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : borderColor, width: selected ? 2 : 1),
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

List<Color> _palette() => const [
  Color(0xFFE57373), Color(0xFFF06292), Color(0xFFBA68C8), Color(0xFF9575CD),
  Color(0xFF7986CB), Color(0xFF64B5F6), Color(0xFF4FC3F7), Color(0xFF4DD0E1),
  Color(0xFF4DB6AC), Color(0xFF81C784), Color(0xFFAED581), Color(0xFFDCE775),
  Color(0xFFFFF176), Color(0xFFFFD54F), Color(0xFFFFB74D), Color(0xFFFF8A65),
  Color(0xFFA1887F), Color(0xFF90A4AE),
];

String _firstLine(String text) {
  final lines = text.trim().split('\n');
  return lines.isEmpty ? '' : lines.first.trim();
}
String _restText(String text) {
  final lines = text.trim().split('\n');
  if (lines.length <= 1) return '';
  return lines.skip(1).join('\n').trim();
}
String _pad(int n) => n.toString().padLeft(2, '0');
String _formatDate(DateTime dt) {
  final now = DateTime.now();
  final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
  return isToday ? '${_pad(dt.hour)}:${_pad(dt.minute)}' : '${_pad(dt.day)}.${_pad(dt.month)}.${dt.year}';
}
