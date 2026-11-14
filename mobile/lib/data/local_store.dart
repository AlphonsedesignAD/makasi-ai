import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Compte simple, enregistré uniquement sur ce téléphone.
class LocalAccount {
  const LocalAccount({
    required this.name,
    required this.email,
    required this.passwordHash,
    required this.createdAt,
  });

  final String name;
  final String email;
  final String passwordHash;
  final DateTime createdAt;

  LocalAccount copyWith({String? name}) => LocalAccount(
        name: name ?? this.name,
        email: email,
        passwordHash: passwordHash,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'passwordHash': passwordHash,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory LocalAccount.fromJson(Map<String, dynamic> json) => LocalAccount(
        name: (json['name'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        passwordHash: (json['passwordHash'] ?? '').toString(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] is num)
              ? (json['createdAt'] as num).toInt()
              : DateTime.now().millisecondsSinceEpoch,
        ),
      );
}

/// Empreinte du mot de passe. Le mot de passe lui-même n'est jamais stocké.
String hashLocalPassword(String email, String password) {
  final normalized = email.trim().toLowerCase();
  return sha256
      .convert(utf8.encode('makasi-local-v1:$normalized:$password'))
      .toString();
}

/// Mémoire locale de l'appareil (compte, discussions et cache hors ligne).
/// Le format JSON des discussions est identique à celui du site web.
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kChats = 'makasi.chats';
  static const _kActive = 'makasi.active';
  static const _kAccount = 'makasi.localAccount';

  List<Chat> loadChats() {
    final raw = _prefs.getString(_kChats);
    if (raw == null || raw.isEmpty) return <Chat>[];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return <Chat>[];
      final chats = <Chat>[];
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          try {
            chats.add(Chat.fromJson(item));
          } catch (_) {
            // Discussion illisible : on ignore sans bloquer le démarrage.
          }
        }
      }
      chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return chats;
    } catch (_) {
      return <Chat>[];
    }
  }

  Future<void> saveChats(List<Chat> chats) async {
    final data = chats.map((c) => c.toJson()).toList();
    await _prefs.setString(_kChats, jsonEncode(data));
  }

  String? get activeId => _prefs.getString(_kActive);

  Future<void> setActiveId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kActive);
    } else {
      await _prefs.setString(_kActive, id);
    }
  }

  LocalAccount? loadAccount() {
    final raw = _prefs.getString(_kAccount);
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return null;
      final account = LocalAccount.fromJson(data);
      if (account.email.isEmpty || account.passwordHash.isEmpty) return null;
      return account;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAccount(LocalAccount account) =>
      _prefs.setString(_kAccount, jsonEncode(account.toJson()));

  Future<void> clearAccount() => _prefs.remove(_kAccount);

  Future<void> clear() async {
    await _prefs.remove(_kChats);
    await _prefs.remove(_kActive);
  }
}
