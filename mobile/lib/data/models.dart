import 'dart:typed_data';

import '../core/utils.dart';

enum ChatRole { user, assistant }

enum AttachmentKind { image, pdf, text, other }

class Attachment {
  Attachment({
    required this.name,
    required this.size,
    required this.mime,
    required this.kind,
    this.bytes,
    this.text,
  });

  final String name;
  final int size;
  final String mime;
  final AttachmentKind kind;

  /// Données binaires : uniquement en mémoire, jamais stockées/synchronisées.
  final Uint8List? bytes;

  /// Contenu texte : uniquement en mémoire.
  final String? text;

  bool get isImage => kind == AttachmentKind.image;
  bool get isPdf => kind == AttachmentKind.pdf;
  String get sizeLabel => formatBytes(size);

  Map<String, dynamic> toJson() => {
        'name': name,
        'size': size,
        'mime': mime,
        'kind': kind.name,
      };

  factory Attachment.fromJson(Map<String, dynamic> json) {
    final mime = (json['mime'] ?? '').toString();
    final name = (json['name'] ?? 'Fichier').toString();
    AttachmentKind kind;
    final kindName = (json['kind'] ?? '').toString();
    if (kindName.isNotEmpty) {
      kind = AttachmentKind.values.firstWhere(
        (k) => k.name == kindName,
        orElse: () => kindFrom(name, mime),
      );
    } else {
      kind = kindFrom(name, mime);
    }
    return Attachment(
      name: name,
      size: (json['size'] is num) ? (json['size'] as num).toInt() : 0,
      mime: mime,
      kind: kind,
    );
  }

  static AttachmentKind kindFrom(String name, String mime) {
    if (mime.startsWith('image/')) return AttachmentKind.image;
    if (mime == 'application/pdf' || name.toLowerCase().endsWith('.pdf')) {
      return AttachmentKind.pdf;
    }
    const textExtensions = {
      'txt', 'md', 'markdown', 'js', 'mjs', 'ts', 'tsx', 'jsx', 'py', 'html',
      'htm', 'css', 'json', 'csv', 'sql', 'php', 'java', 'c', 'cpp', 'h', 'hpp',
      'cs', 'go', 'rs', 'rb', 'swift', 'kt', 'kts', 'dart', 'yaml', 'yml',
      'xml', 'ini', 'conf', 'log', 'sh', 'bat', 'env', 'toml',
    };
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (mime.startsWith('text/') || textExtensions.contains(ext)) {
      return AttachmentKind.text;
    }
    return AttachmentKind.other;
  }
}

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    this.displayText,
    this.attachment,
    this.error = false,
    this.interrupted = false,
    String? id,
    DateTime? createdAt,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final ChatRole role;
  String text;
  String? displayText;
  Attachment? attachment;
  bool error;
  bool interrupted;
  final DateTime createdAt;

  bool get isUser => role == ChatRole.user;

  /// Version affichée dans une bulle utilisateur.
  String get visibleText => displayText ?? text;

  Map<String, dynamic> toJson() => {
        'role': isUser ? 'user' : 'assistant',
        'content': text,
        if (displayText != null) 'displayText': displayText,
        if (attachment != null) 'attachment': attachment!.toJson(),
        if (error) 'error': true,
        if (interrupted) 'interrupted': true,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final role = (json['role'] ?? '').toString() == 'user'
        ? ChatRole.user
        : ChatRole.assistant;
    final attachmentJson = json['attachment'];
    return ChatMessage(
      id: json['id']?.toString(),
      role: role,
      text: (json['content'] ?? json['text'] ?? '').toString(),
      displayText: json['displayText']?.toString(),
      attachment: attachmentJson is Map<String, dynamic>
          ? Attachment.fromJson(attachmentJson)
          : (attachmentJson is Map
              ? Attachment.fromJson(Map<String, dynamic>.from(attachmentJson))
              : null),
      error: json['error'] == true,
      interrupted: json['interrupted'] == true,
    );
  }
}

class Chat {
  Chat({
    String? id,
    this.title = '',
    List<ChatMessage>? messages,
    DateTime? updatedAt,
  })  : id = id ?? newId(),
        messages = messages ?? <ChatMessage>[],
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  final List<ChatMessage> messages;
  DateTime updatedAt;

  bool get isEmpty => messages.isEmpty;

  void touch() => updatedAt = DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'updated': updatedAt.millisecondsSinceEpoch,
      };

  factory Chat.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    final messages = <ChatMessage>[];
    if (rawMessages is List) {
      for (final raw in rawMessages) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final message = ChatMessage.fromJson(map);
        // Anciennes discussions : les messages qui ne contenaient qu'une image
        // générée sont ignorés maintenant que la création d'images est retirée.
        if (map['image'] != null && message.text.trim().isEmpty) continue;
        messages.add(message);
      }
    }
    return Chat(
      id: (json['id'] ?? newId()).toString(),
      title: (json['title'] ?? '').toString(),
      messages: messages,
      updatedAt: _parseDate(json['updated'] ?? json['updated_at']),
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String && value.isNotEmpty) {
      final ms = int.tryParse(value);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toLocal();
    }
    return DateTime.now();
  }
}
