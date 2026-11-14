import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/prompts.dart';
import '../core/utils.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status, this.code});

  final String message;
  final int? status;
  final String? code;

  @override
  String toString() => message;
}

class MakasiApi {
  MakasiApi({required String baseUrl, http.Client? client})
      : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  String get baseUrl => _baseUrl;

  /// Stream SSE de /api/chat — les clés de l'IA restent côté serveur.
  Stream<String> streamChat(List<Map<String, dynamic>> contents) async* {
    final client = http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$_baseUrl/api/chat'),
      );
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      });
      request.body = jsonEncode({
        'system_instruction': {
          'parts': [
            {'text': kSystemPrompt},
          ],
        },
        'contents': contents,
      });

      final response =
          await client.send(request).timeout(const Duration(seconds: 35));

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw ApiException(
          parseApiError(body, response.statusCode),
          status: response.statusCode,
        );
      }

      final lines =
          response.stream.transform(utf8.decoder).transform(const LineSplitter());

      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final raw = line.substring(5).trim();
        if (raw.isEmpty || raw == '[DONE]') continue;

        try {
          final data = jsonDecode(raw);
          if (data is! Map<String, dynamic>) continue;
          final candidates = data['candidates'];
          if (candidates is! List || candidates.isEmpty) continue;
          final candidate = candidates.first;
          if (candidate is! Map) continue;
          final content = candidate['content'];
          if (content is! Map) continue;
          final parts = content['parts'];
          if (parts is! List) continue;

          final buffer = StringBuffer();
          var hasText = false;
          for (final part in parts) {
            if (part is! Map) continue;
            if (part['thought'] == true) continue;
            final text = part['text'];
            if (text is String && text.isNotEmpty) {
              buffer.write(text);
              hasText = true;
            }
          }
          if (hasText) yield buffer.toString();
        } catch (_) {
          // Chunk partiel ou non pertinent : on l'ignore.
        }
      }
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(
        'Le serveur met trop de temps à répondre. Vérifiez votre connexion puis réessayez.',
      );
    } on http.ClientException {
      throw ApiException(
        'Connexion impossible. Vérifiez votre réseau puis réessayez.',
      );
    } catch (e) {
      final text = e.toString();
      if (text.contains('SocketException') ||
          text.contains('Failed host lookup') ||
          text.contains('Connection')) {
        throw ApiException(
          'Connexion impossible. Vérifiez votre réseau puis réessayez.',
        );
      }
      throw ApiException('Impossible de contacter le serveur. Réessayez.');
    } finally {
      client.close();
    }
  }

  void dispose() => _client.close();
}
