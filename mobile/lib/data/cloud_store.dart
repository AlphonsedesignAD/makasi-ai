import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Table `chats` partagée avec le site web.
/// Une ligne = une discussion, les messages sont stockés en JSON.
class CloudStore {
  CloudStore(this._client);

  final SupabaseClient _client;

  String? get userId => _client.auth.currentUser?.id;

  Future<List<Chat>> pullChats() async {
    final rows = await _client
        .from('chats')
        .select('id,title,messages,updated_at')
        .order('updated_at', ascending: false)
        .limit(500);

    final chats = <Chat>[];
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row);
      final rawMessages = map['messages'];
      final messages = <ChatMessage>[];
      if (rawMessages is List) {
        for (final raw in rawMessages) {
          if (raw is Map<String, dynamic>) {
            messages.add(ChatMessage.fromJson(raw));
          } else if (raw is Map) {
            messages.add(ChatMessage.fromJson(Map<String, dynamic>.from(raw)));
          }
        }
      }
      chats.add(
        Chat(
          id: (map['id'] ?? '').toString(),
          title: (map['title'] ?? '').toString(),
          messages: messages,
          updatedAt: _parseDate(map['updated_at']),
        ),
      );
    }
    return chats;
  }

  Future<void> upsertChats(List<Chat> chats) async {
    if (chats.isEmpty) return;
    final uid = userId;
    if (uid == null) throw StateError('Utilisateur non connecté.');
    final rows = chats
        .map(
          (chat) => <String, dynamic>{
            'id': chat.id,
            'user_id': uid,
            'title': chat.title.length > 200 ? chat.title.substring(0, 200) : chat.title,
            'messages': chat.messages.map((m) => m.toJson()).toList(),
            'updated_at': chat.updatedAt.toUtc().toIso8601String(),
          },
        )
        .toList();
    await _client.from('chats').upsert(rows, onConflict: 'id');
  }

  Future<void> deleteChat(String id) async {
    if (userId == null) return;
    await _client.from('chats').delete().eq('id', id);
  }

  Future<void> clear() async {
    final uid = userId;
    if (uid == null) return;
    await _client.from('chats').delete().eq('user_id', uid);
  }

  Future<String?> fetchDisplayName() async {
    final uid = userId;
    if (uid == null) return null;
    final row = await _client
        .from('profiles')
        .select('display_name')
        .eq('id', uid)
        .maybeSingle();
    final name = (row?['display_name'] ?? '').toString().trim();
    return name.isEmpty ? null : name;
  }

  static DateTime _parseDate(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
    }
    return DateTime.now();
  }
}
