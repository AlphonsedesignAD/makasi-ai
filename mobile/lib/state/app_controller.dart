import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/bootstrap.dart';
import '../core/utils.dart';
import '../data/api_client.dart';
import '../data/auth_service.dart';
import '../data/chat_export.dart';
import '../data/cloud_store.dart';
import '../data/local_store.dart';
import '../data/models.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.bootstrap,
    required LocalStore localStore,
    MakasiApi? api,
  })  : _local = localStore,
        _settings = bootstrap.settings,
        _api = api ?? MakasiApi(baseUrl: bootstrap.settings.serverUrl) {
    final client =
        bootstrap.supabaseReady ? Supabase.instance.client : null;
    _auth = client == null ? null : AuthService(client);
    _cloud = client == null ? null : CloudStore(client);

    _themeMode = _settings.themeMode;
    _onboarded = _settings.onboarded;
    themeModeNotifier = ValueNotifier<ThemeMode>(_themeMode);
    onboardedNotifier = ValueNotifier<bool>(_onboarded);

    _tts = FlutterTts();
    _configureTts();
  }

  final BootstrapResult bootstrap;
  final LocalStore _local;
  final SettingsStore _settings;
  final MakasiApi _api;
  late final AuthService? _auth;
  late final CloudStore? _cloud;
  late final FlutterTts _tts;

  bool _disposed = false;
  bool _ready = false;
  bool _onboarded = true;
  late ThemeMode _themeMode;
  late final ValueNotifier<ThemeMode> themeModeNotifier;
  late final ValueNotifier<bool> onboardedNotifier;
  List<Chat> _chats = <Chat>[];
  String? _activeId;
  bool _streaming = false;
  bool _syncing = false;
  String? _syncError;
  DateTime? _lastSyncAt;
  User? _user;
  LocalAccount? _account;
  String? _profileName;
  String? _speakingId;

  Timer? _pushTimer;
  StreamSubscription<String>? _streamSub;
  int _streamToken = 0;
  String? _streamingChatId;
  final Map<String, int> _cloudKnown = <String, int>{};

  /* ---------- Getters ---------- */
  bool get ready => _ready;
  bool get onboarded => _onboarded;
  ThemeMode get themeMode => _themeMode;
  List<Chat> get chats => List.unmodifiable(_chats);
  String? get activeId => _activeId;
  bool get streaming => _streaming;
  bool get syncing => _syncing;
  String? get syncError => _syncError;
  DateTime? get lastSyncAt => _lastSyncAt;
  bool get isSignedIn => _account != null || _user != null;
  bool get isLocalAccount => _account != null;
  bool get cloudAvailable => true;
  String get userEmail => _account?.email ?? _user?.email ?? '';
  String get userName {
    final account = _account;
    if (account != null) return account.name;
    if (_user == null) return '';
    final name = (_profileName ?? '').trim();
    if (name.isNotEmpty) return name;
    return _auth?.displayName ?? '';
  }

  String get displayServer => _api.baseUrl;
  String get supabaseStatus => bootstrap.supabaseReady
      ? 'Connecté'
      : (bootstrap.supabaseError == null ? 'Non configuré' : 'Erreur de configuration');
  SettingsStore get settings => _settings;
  String? get speakingId => _speakingId;

  Chat? get activeChat {
    for (final chat in _chats) {
      if (chat.id == _activeId) return chat;
    }
    return null;
  }

  bool get canNavigate => !_streaming;

  /* ---------- Démarrage ---------- */
  Future<void> start() async {
    _chats = _local.loadChats();
    _activeId = _local.activeId;
    _lastSyncAt = _settings.lastSyncAt;
    _normalizeActive();
    _user = _auth?.currentUser;
    _account = _local.loadAccount();
    _ready = true;
    notifyListeners();

    if (_user != null) {
      unawaited(_refreshProfileName());
      unawaited(syncNow(initial: true));
    }
  }

  void _normalizeActive() {
    if (_activeId != null && _chats.any((c) => c.id == _activeId)) return;
    _activeId = _chats.isEmpty ? null : _chats.first.id;
  }

  /* ---------- Navigation / discussions ---------- */
  void newChat() {
    if (_streaming) return;
    final current = activeChat;
    if (current != null && current.isEmpty) return;
    final chat = Chat();
    _chats.insert(0, chat);
    _activeId = chat.id;
    unawaited(_persist());
    notifyListeners();
  }

  Future<void> openChat(String id) async {
    if (_streaming) return;
    if (!_chats.any((c) => c.id == id)) return;
    _activeId = id;
    await _local.setActiveId(id);
    notifyListeners();
  }

  Future<void> renameChat(String id, String title) async {
    if (_streaming) return;
    final clean = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return;
    for (final chat in _chats) {
      if (chat.id != id) continue;
      chat.title = clean.length > 120 ? clean.substring(0, 120) : clean;
      chat.touch();
      _chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await _persist();
      notifyListeners();
      return;
    }
  }

  Future<void> deleteChat(String id) async {
    if (_streaming && id == _streamingChatId) return;
    _chats.removeWhere((c) => c.id == id);
    if (_activeId == id) _normalizeActive();
    await _persist();
    notifyListeners();
  }

  Future<void> clearAllChats() async {
    if (_streaming) return;
    _chats = <Chat>[];
    _activeId = null;
    _cloudKnown.clear();
    await _local.clear();
    if (_user != null && _cloud != null) {
      try {
        await _cloud.clear();
      } catch (_) {
        // La synchronisation réessaiera plus tard.
      }
    }
    await _settings.setLastSyncAt(DateTime.now());
    _lastSyncAt = DateTime.now();
    notifyListeners();
  }

  /* ---------- Envoi d'un message ---------- */
  Future<void> send(String text, {Attachment? attachment}) async {
    final content = text.trim();
    if (_streaming) return;
    if (content.isEmpty && attachment == null) return;

    var chat = activeChat;
    if (chat == null) {
      chat = Chat();
      _chats.insert(0, chat);
      _activeId = chat.id;
    }

    final display = content.isNotEmpty
        ? content
        : attachment == null
            ? ''
            : attachment.isImage
                ? 'Analyse de l’image jointe'
                : 'Analyse du fichier ${attachment.name}';

    if (chat.messages.isEmpty) {
      chat.title = truncateTitle(
        content.isNotEmpty ? content : (attachment?.name ?? 'Nouvelle discussion'),
      );
    }

    chat.messages.add(
      ChatMessage(
        role: ChatRole.user,
        text: content,
        displayText: display,
        attachment: attachment,
      ),
    );
    chat.touch();
    await _persist();
    notifyListeners();

    await _replyTo(chat);
  }

  Future<void> _replyTo(Chat chat) async {
    final last = chat.messages.isEmpty ? null : chat.messages.last;
    if (last == null || !last.isUser) return;

    final contents = _buildContents(chat);
    final placeholder = ChatMessage(role: ChatRole.assistant, text: '');
    chat.messages.add(placeholder);
    _streaming = true;
    _streamingChatId = chat.id;
    _syncError = null;
    notifyListeners();

    final token = ++_streamToken;
    final buffer = StringBuffer();
    var lastNotify = DateTime.now();
    final completer = Completer<void>();

    _streamSub = _api.streamChat(contents).listen(
      (chunk) {
        if (token != _streamToken) return;
        buffer.write(chunk);
        placeholder.text = buffer.toString();
        final now = DateTime.now();
        if (now.difference(lastNotify).inMilliseconds > 55) {
          lastNotify = now;
          notifyListeners();
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    try {
      await completer.future;
      if (token != _streamToken) return;
      final text = buffer.toString().trim();
      if (text.isEmpty) {
        throw ApiException('La réponse est vide. Réessayez.');
      }
      placeholder.text = text;
    } catch (error) {
      if (token != _streamToken) return;
      placeholder
        ..text = error is ApiException
            ? error.message
            : 'Désolé, je n’ai pas pu répondre. Vérifiez votre connexion puis réessayez.'
        ..error = true;
    } finally {
      if (token == _streamToken) {
        _streaming = false;
        _streamingChatId = null;
        _streamSub = null;
        chat.touch();
        await _persist();
        notifyListeners();
      }
    }
  }

  void stopStreaming() {
    if (!_streaming) return;
    _streamToken++;
    _streamSub?.cancel();
    _streamSub = null;

    final chatId = _streamingChatId;
    Chat? chat;
    for (final c in _chats) {
      if (c.id == chatId) {
        chat = c;
        break;
      }
    }
    if (chat != null && chat.messages.isNotEmpty) {
      final last = chat.messages.last;
      if (!last.isUser) {
        if (last.text.trim().isEmpty) {
          last.text = 'Génération interrompue.';
        }
        last.interrupted = true;
      }
      chat.touch();
    }
    _streaming = false;
    _streamingChatId = null;
    unawaited(_persist());
    notifyListeners();
  }

  Future<void> retryFrom(Chat chat, int index) async {
    if (_streaming) return;
    if (index < 0 || index >= chat.messages.length) return;
    chat.messages.removeRange(index, chat.messages.length);
    chat.touch();
    await _persist();
    notifyListeners();
    await _replyTo(chat);
  }

  /* ---------- Construction de l'historique de conversation ---------- */
  List<Map<String, dynamic>> _buildContents(Chat chat) {
    final usable = <ChatMessage>[];
    for (final message in chat.messages) {
      if (!message.isUser && (message.text.trim().isEmpty || message.error)) {
        continue;
      }
      usable.add(message);
    }
    final recent = usable.length > 20
        ? usable.sublist(usable.length - 20)
        : usable;

    final contents = <Map<String, dynamic>>[];
    for (var i = 0; i < recent.length; i++) {
      final message = recent[i];
      if (!message.isUser) {
        contents.add({
          'role': 'model',
          'parts': [
            {'text': message.text},
          ],
        });
        continue;
      }

      final isLast = i == recent.length - 1;
      final attachment = message.attachment;
      var text = message.text;
      final parts = <Map<String, dynamic>>[];

      if (attachment != null && isLast) {
        if (attachment.isImage && attachment.bytes != null) {
          parts.add({
            'inline_data': {
              'mime_type': attachment.mime.isEmpty ? 'image/jpeg' : attachment.mime,
              'data': base64Encode(attachment.bytes!),
            },
          });
          if (text.isEmpty) text = 'Analyse cette image.';
        } else if (attachment.isPdf && attachment.bytes != null) {
          parts.add({
            'inline_data': {
              'mime_type': 'application/pdf',
              'data': base64Encode(attachment.bytes!),
            },
          });
          if (text.isEmpty) text = 'Analyse ce document.';
        } else if (attachment.kind == AttachmentKind.text &&
            attachment.text != null) {
          var fileText = attachment.text!;
          if (fileText.length > 30000) fileText = fileText.substring(0, 30000);
          text = '[Fichier joint : ${attachment.name}]\n```\n$fileText\n```\n\n$text';
        }
      }

      if (text.trim().isEmpty && attachment != null) {
        text = '[Fichier joint : ${attachment.name}]';
      }
      if (text.trim().isNotEmpty) parts.add({'text': text});
      if (parts.isEmpty) parts.add({'text': ''});

      contents.add({'role': 'user', 'parts': parts});
    }
    return contents;
  }

  /* ---------- Comptes ---------- */
  // Compte simple, stocké uniquement sur ce téléphone. Aucun serveur de
  // comptes n'est nécessaire, et les conversations restent dans l'application.
  Future<AuthOutcome> signIn(String email, String password) async {
    final existing = _local.loadAccount();
    final cleanEmail = email.trim().toLowerCase();
    if (existing == null) {
      throw StateError(
        'Aucun compte sur ce téléphone. Créez d’abord votre compte.',
      );
    }
    if (existing.email.toLowerCase() != cleanEmail ||
        existing.passwordHash != hashLocalPassword(cleanEmail, password)) {
      throw StateError('E-mail ou mot de passe incorrect.');
    }
    _account = existing;
    await _setOnboarded(true);
    notifyListeners();
    return AuthOutcome(user: null, needsConfirmation: false);
  }

  Future<AuthOutcome> signUp(
    String name,
    String email,
    String password,
  ) async {
    final cleanName = name.trim();
    final cleanEmail = email.trim().toLowerCase();
    final existing = _local.loadAccount();
    if (existing != null && existing.email.toLowerCase() == cleanEmail) {
      throw StateError(
        'Un compte existe déjà avec cet e-mail. Connectez-vous.',
      );
    }

    final account = LocalAccount(
      name: cleanName.isEmpty ? cleanEmail.split('@').first : cleanName,
      email: cleanEmail,
      passwordHash: hashLocalPassword(cleanEmail, password),
      createdAt: DateTime.now(),
    );
    await _local.saveAccount(account);
    _account = account;
    await _setOnboarded(true);
    notifyListeners();
    return AuthOutcome(user: null, needsConfirmation: false);
  }

  Future<void> signOut({bool wipeLocal = false}) async {
    _streamToken++;
    _streamSub?.cancel();
    _streamSub = null;
    _pushTimer?.cancel();
    _streaming = false;
    _streamingChatId = null;

    await _auth?.signOut();
    _user = null;
    _account = null;
    await _local.clearAccount();
    _profileName = null;
    _cloudKnown.clear();
    _syncError = null;
    await _settings.setLastSyncAt(null);
    _lastSyncAt = null;

    // Les conversations restent dans l'application, même après déconnexion.
    if (wipeLocal) {
      _chats = <Chat>[];
      _activeId = null;
      await _local.clear();
    }
    await _setOnboarded(false);
    notifyListeners();
  }

  Future<void> continueAsGuest() async {
    await _setOnboarded(true);
    notifyListeners();
  }

  Future<void> _setOnboarded(bool value) async {
    _onboarded = value;
    onboardedNotifier.value = value;
    await _settings.setOnboarded(value);
  }

  Future<void> resetPassword(String email) async {
    throw StateError(
      'Votre compte est enregistré sur ce téléphone : le mot de passe ne peut '
      'pas être réinitialisé par e-mail.',
    );
  }

  /// Enregistre toutes les conversations dans un fichier choisi par
  /// l'utilisateur, pour les conserver avant une désinstallation.
  Future<Uri?> exportChats() {
    return exportChatsToFile(
      chats: _chats,
      owner: userName.isNotEmpty ? userName : (userEmail.isNotEmpty ? userEmail : 'Invité'),
    );
  }

  Future<void> _refreshProfileName() async {
    try {
      final name = await _cloud?.fetchDisplayName();
      if (name != null && name.isNotEmpty) {
        _profileName = name;
        notifyListeners();
      }
    } catch (_) {
      // Le nom du compte reste celui des métadonnées d'authentification.
    }
  }

  Future<void> updateDisplayName(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    final account = _account;
    if (account != null) {
      final updated = account.copyWith(name: clean);
      _account = updated;
      _profileName = clean;
      notifyListeners();
      await _local.saveAccount(updated);
      return;
    }
    await _auth?.updateDisplayName(clean);
    _profileName = clean;
    notifyListeners();
  }

  /* ---------- Synchronisation cloud ---------- */
  Future<void> syncNow({bool initial = false}) async {
    final cloud = _cloud;
    if (cloud == null || _user == null || _syncing) return;
    if (_streaming && !initial) return;

    _syncing = true;
    _syncError = null;
    notifyListeners();

    try {
      final since = _settings.lastSyncAt?.millisecondsSinceEpoch ?? 0;
      final remote = await cloud.pullChats();
      final remoteMap = <String, Chat>{for (final chat in remote) chat.id: chat};
      final merged = <String, Chat>{...remoteMap};
      final toPush = <Chat>[];

      for (final chat in _chats) {
        final localUpdated = chat.updatedAt.millisecondsSinceEpoch;
        final existing = remoteMap[chat.id];
        if (existing == null) {
          if (since == 0 || localUpdated > since) toPush.add(chat);
        } else if (localUpdated > existing.updatedAt.millisecondsSinceEpoch) {
          merged[chat.id] = chat;
          toPush.add(chat);
        }
      }

      if (toPush.isNotEmpty) await cloud.upsertChats(toPush);

      final list = merged.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _chats = list;
      _normalizeActive();
      await _local.saveChats(_chats);
      await _local.setActiveId(_activeId);

      _cloudKnown
        ..clear()
        ..addAll({for (final chat in _chats) chat.id: chat.updatedAt.millisecondsSinceEpoch});

      final now = DateTime.now();
      _lastSyncAt = now;
      await _settings.setLastSyncAt(now);
      notifyListeners();
    } catch (error) {
      _syncError = friendlyAuthMessage(error);
      debugPrint('[Makasi sync] $error');
      notifyListeners();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  void _schedulePush() {
    if (_cloud == null || _user == null) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(milliseconds: 1000), () {
      unawaited(_pushNow());
    });
  }

  Future<void> _pushNow() async {
    final cloud = _cloud;
    if (cloud == null || _user == null) return;
    final current = <String, Chat>{for (final chat in _chats) chat.id: chat};
    final changed = <Chat>[];
    for (final chat in _chats) {
      if (_cloudKnown[chat.id] != chat.updatedAt.millisecondsSinceEpoch) {
        changed.add(chat);
      }
    }
    final removed = _cloudKnown.keys
        .where((id) => !current.containsKey(id))
        .toList(growable: false);
    if (changed.isEmpty && removed.isEmpty) return;

    _syncing = true;
    notifyListeners();
    try {
      if (changed.isNotEmpty) await cloud.upsertChats(changed);
      for (final id in removed) {
        await cloud.deleteChat(id);
      }
      _cloudKnown
        ..clear()
        ..addAll({for (final chat in _chats) chat.id: chat.updatedAt.millisecondsSinceEpoch});
      _lastSyncAt = DateTime.now();
      await _settings.setLastSyncAt(_lastSyncAt);
      _syncError = null;
    } catch (error) {
      _syncError = friendlyAuthMessage(error);
      debugPrint('[Makasi push] $error');
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /* ---------- Persistance locale ---------- */
  Future<void> _persist() async {
    await _local.saveChats(_chats);
    await _local.setActiveId(_activeId);
    _schedulePush();
  }

  /* ---------- Thème ---------- */
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    themeModeNotifier.value = mode;
    await _settings.setThemeMode(mode);
    notifyListeners();
  }

  /* ---------- Synthèse vocale ---------- */
  void _configureTts() {
    _tts.setLanguage('fr-FR');
    _tts.setSpeechRate(0.5);
    _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      _speakingId = null;
      notifyListeners();
    });
    _tts.setCancelHandler(() {
      _speakingId = null;
      notifyListeners();
    });
    _tts.setErrorHandler((_) {
      _speakingId = null;
      notifyListeners();
    });
  }

  Future<void> toggleSpeak(ChatMessage message) async {
    final text = speechText(message.text);
    if (text.isEmpty) return;
    if (_speakingId == message.id) {
      await _tts.stop();
      _speakingId = null;
      notifyListeners();
      return;
    }
    await _tts.stop();
    _speakingId = message.id;
    notifyListeners();
    await _tts.speak(text);
  }

  @override
  void dispose() {
    _disposed = true;
    _pushTimer?.cancel();
    _streamSub?.cancel();
    _tts.stop();
    _api.dispose();
    themeModeNotifier.dispose();
    onboardedNotifier.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }
}
