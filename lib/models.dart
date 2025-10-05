import 'dart:convert';


NoteModel copyWith({String? title, String? content, String? groupId}) => NoteModel(
id: id,
groupId: groupId ?? this.groupId,
title: title ?? this.title,
content: content ?? this.content,
createdAt: createdAt,
updatedAt: DateTime.now(),
);


Map<String, dynamic> toJson() => {
'id': id,
'groupId': groupId,
'title': title,
'content': content,
'createdAt': createdAt.toIso8601String(),
'updatedAt': updatedAt.toIso8601String(),
};


static NoteModel fromJson(Map<String, dynamic> j) => NoteModel(
id: j['id'],
groupId: j['groupId'],
title: j['title'] ?? '',
content: j['content'] ?? '',
createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
updatedAt: DateTime.tryParse(j['updatedAt'] ?? '') ?? DateTime.now(),
);


String toPrettyTextExport() => content; // исходное форматирование сохраняется
}


class GroupModel {
String id;
String name;
bool isPrivate;


GroupModel({String? id, required this.name, this.isPrivate = false}) : id = id ?? _uuid.v4();


Map<String, dynamic> toJson() => {
'id': id,
'name': name,
'isPrivate': isPrivate,
};


static GroupModel fromJson(Map<String, dynamic> j) => GroupModel(
id: j['id'],
name: j['name'] ?? 'Untitled',
isPrivate: j['isPrivate'] ?? false,
);
}


class SnapshotExport {
final List<GroupModel> groups;
final List<NoteModel> notes;
SnapshotExport(this.groups, this.notes);
Map<String, dynamic> toJson() => {
'groups': groups.map((e) => e.toJson()).toList(),
'notes': notes.map((e) => e.toJson()).toList(),
};
String toJsonString() => const JsonEncoder.withIndent(' ').convert(toJson());
}
