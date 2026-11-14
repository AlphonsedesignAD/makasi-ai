import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'models.dart';

/// Enregistre toutes les conversations dans un fichier Markdown lisible.
///
/// Le fichier est choisi par l'utilisateur via le sélecteur du téléphone,
/// ce qui permet de le conserver avant de désinstaller l'application.
Future<Uri?> exportChatsToFile({
  required List<Chat> chats,
  required String owner,
}) async {
  if (chats.isEmpty) return null;

  final now = DateTime.now();
  final buffer = StringBuffer()
    ..writeln('# Makasi AI — mes conversations')
    ..writeln()
    ..writeln('Compte : ${owner.isEmpty ? 'Invité' : owner}')
    ..writeln(
      'Enregistré le ${now.day.toString().padLeft(2, '0')}/'
      '${now.month.toString().padLeft(2, '0')}/${now.year} à '
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}',
    )
    ..writeln()
    ..writeln('---')
    ..writeln();

  final sorted = [...chats]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  for (final chat in sorted) {
    final title = chat.title.trim().isEmpty ? 'Discussion' : chat.title.trim();
    buffer
      ..writeln('## $title')
      ..writeln();

    for (final message in chat.messages) {
      if (message.text.trim().isEmpty && message.attachment == null) continue;
      final who = message.isUser ? 'Vous' : 'Makasi AI';
      buffer.writeln('### $who');
      buffer.writeln();
      if (message.attachment != null) {
        buffer.writeln('*Fichier joint : ${message.attachment!.name}*');
        buffer.writeln();
      }
      final text = message.text.trim().isEmpty
          ? (message.displayText ?? '').trim()
          : message.text.trim();
      if (text.isNotEmpty) {
        buffer
          ..writeln(text)
          ..writeln();
      }
    }

    buffer
      ..writeln('---')
      ..writeln();
  }

  final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
  final stamp = '${now.year}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';

  return FilePicker.saveFile(
    fileName: 'makasi-conversations-$stamp.md',
    bytes: bytes,
    mimeType: 'text/markdown',
    dialogTitle: 'Enregistrer mes conversations',
  );
}
