import 'package:flutter_test/flutter_test.dart';
import 'package:makasi_ai/core/utils.dart';
import 'package:makasi_ai/data/models.dart';

void main() {
  group('Titres et textes', () {
    test('tronque proprement un titre trop long', () {
      final title = truncateTitle('Explique-moi comment fonctionne une API REST');
      expect(title.endsWith('…'), isTrue);
      expect(title.length, lessThanOrEqualTo(43));
    });

    test('garde un titre court intact', () {
      expect(truncateTitle('Bonjour Makasi'), 'Bonjour Makasi');
    });

    test('salutation selon l’heure', () {
      expect(greetingForHour(3), 'Bonne nuit');
      expect(greetingForHour(9), 'Bonjour');
      expect(greetingForHour(20), 'Bonsoir');
    });

    test('regroupe les dates comme le site', () {
      final now = DateTime(2026, 5, 10, 12);
      expect(relativeDayLabel(DateTime(2026, 5, 10, 8), now: now), 'Aujourd’hui');
      expect(relativeDayLabel(DateTime(2026, 5, 9, 8), now: now), 'Hier');
      expect(relativeDayLabel(DateTime(2026, 5, 5, 8), now: now), '7 derniers jours');
      expect(relativeDayLabel(DateTime(2026, 4, 1, 8), now: now), 'Plus ancien');
    });
  });

  group('Mémoire des discussions', () {
    test('sérialise et restaure une discussion', () {
      final chat = Chat(
        id: 'chat-test',
        title: 'Test',
        messages: [
          ChatMessage(
            role: ChatRole.user,
            text: 'Bonjour',
            displayText: 'Bonjour',
          ),
          ChatMessage(
            role: ChatRole.assistant,
            text: 'Bonjour ! Comment puis-je aider ?',
          ),
        ],
      );

      final restored = Chat.fromJson(chat.toJson());
      expect(restored.id, 'chat-test');
      expect(restored.title, 'Test');
      expect(restored.messages, hasLength(2));
      expect(restored.messages.first.isUser, isTrue);
      expect(restored.messages.last.text, contains('aider'));
    });

    test('ignore les anciens messages qui ne contenaient qu’une image', () {
      final chat = Chat.fromJson({
        'id': 'ancienne-discussion',
        'title': 'Ancienne image',
        'messages': [
          {'role': 'user', 'content': 'Crée une image de lion'},
          {
            'role': 'assistant',
            'content': '',
            'image': {'prompt': 'lion', 'seed': 42, 'ratio': '1:1'},
          },
          {'role': 'assistant', 'content': 'Réponse conservée'},
        ],
      });

      expect(chat.messages, hasLength(2));
      expect(chat.messages.last.text, 'Réponse conservée');
    });

    test('reconnaît le type d’un fichier joint', () {
      expect(Attachment.kindFrom('photo.jpg', 'image/jpeg'), AttachmentKind.image);
      expect(Attachment.kindFrom('contrat.pdf', ''), AttachmentKind.pdf);
      expect(Attachment.kindFrom('script.dart', 'text/plain'), AttachmentKind.text);
      expect(Attachment.kindFrom('archive.zip', ''), AttachmentKind.other);
    });
  });
}
