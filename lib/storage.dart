import 'dart:convert';
}


Future<void> saveNote(NoteModel note) async {
final i = notes.indexWhere((e) => e.id == note.id);
if (i >= 0) {
notes[i] = note.copyWith();
}
await _persist();
}


Future<void> deleteNote(String id) async {
notes.removeWhere((e) => e.id == id);
await _persist();
}


// ======= Export / Import ========
Future<File> exportNoteJson(NoteModel n) async {
final dir = await getTemporaryDirectory();
final f = File('${dir.path}/note_${n.title.replaceAll(' ', '_')}_${n.id.substring(0,6)}.json');
await f.writeAsString(const JsonEncoder.withIndent(' ').convert(n.toJson()));
return f;
}


Future<File> exportNoteTxt(NoteModel n) async {
final dir = await getTemporaryDirectory();
final f = File('${dir.path}/note_${n.title.replaceAll(' ', '_')}_${n.id.substring(0,6)}.txt');
await f.writeAsString(n.toPrettyTextExport());
return f;
}


Future<File> exportGroupJson(GroupModel g) async {
final dir = await getTemporaryDirectory();
final related = notes.where((e) => e.groupId == g.id).toList();
final snap = SnapshotExport([g], related);
final f = File('${dir.path}/group_${g.name.replaceAll(' ', '_')}_${g.id.substring(0,6)}.json');
await f.writeAsString(snap.toJsonString());
return f;
}


Future<void> importFromJsonString(String raw) async {
final data = jsonDecode(raw);
if (data is Map<String, dynamic> && data.containsKey('groups') && data.containsKey('notes')) {
// импорт группы со своими заметками
final importedGroups = (data['groups'] as List).map((e) => GroupModel.fromJson((e as Map).cast<String, dynamic>())).toList();
final importedNotes = (data['notes'] as List).map((e) => NoteModel.fromJson((e as Map).cast<String, dynamic>())).toList();
// создаём новые id для избежания коллизий
for (final g in importedGroups) {
final newGroup = GroupModel(name: g.name, isPrivate: false); // пароль не переносим по соображениям безопасности
groups.add(newGroup);
for (final n in importedNotes.where((n) => n.groupId == g.id)) {
notes.add(NoteModel(groupId: newGroup.id, title: n.title, content: n.content));
}
}
await _persist();
} else if (data is Map<String, dynamic> && data.containsKey('id') && data.containsKey('content')) {
// одиночная заметка
final n = NoteModel(groupId: groups.first.id, title: data['title'] ?? 'Импортированная заметка', content: data['content'] ?? '');
notes.insert(0, n);
await _persist();
} else {
// пробуем как чистый текст заметки
final n = NoteModel(groupId: groups.first.id, title: 'Импортированный текст', content: raw);
notes.insert(0, n);
await _persist();
}
}
}
