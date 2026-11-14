import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// URL de production. Surchargeable pour le développement :
/// flutter run --dart-define=MAKASI_API_BASE=http://10.0.2.2:3000
const String kDefaultApiBase = String.fromEnvironment(
  'MAKASI_API_BASE',
  defaultValue: 'https://makasi-ai.vercel.app',
);

const String kSupabaseUrlOverride = String.fromEnvironment('SUPABASE_URL');
const String kSupabaseAnonOverride = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Configuration publique récupérée depuis `/api/config`.
/// Le site et l'application lisent exactement la même source.
class RemoteConfig {
  const RemoteConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;

  bool get hasSupabase =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  static const empty = RemoteConfig(supabaseUrl: '', supabaseAnonKey: '');

  factory RemoteConfig.fromJson(Map<String, dynamic> json) => RemoteConfig(
        supabaseUrl: (json['supabaseUrl'] ?? '').toString().trim(),
        supabaseAnonKey: (json['supabaseAnonKey'] ?? '').toString().trim(),
      );

  Map<String, dynamic> toJson() => {
        'supabaseUrl': supabaseUrl,
        'supabaseAnonKey': supabaseAnonKey,
      };
}

class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kTheme = 'makasi.theme';
  static const _kServer = 'makasi.server';
  static const _kOnboarded = 'makasi.onboarded';
  static const _kLastSync = 'makasi.lastSync';
  static const _kConfig = 'makasi.remoteConfig';

  String get serverUrl {
    final saved = _prefs.getString(_kServer)?.trim();
    if (saved != null && saved.isNotEmpty) return saved;
    return kDefaultApiBase;
  }

  Future<void> setServerUrl(String url) => _prefs.setString(_kServer, url.trim());

  ThemeMode get themeMode {
    switch (_prefs.getString(_kTheme)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString(_kTheme, mode.name);

  bool get onboarded => _prefs.getBool(_kOnboarded) ?? false;

  Future<void> setOnboarded(bool value) => _prefs.setBool(_kOnboarded, value);

  DateTime? get lastSyncAt {
    final ms = _prefs.getInt(_kLastSync);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastSyncAt(DateTime? date) async {
    if (date == null) {
      await _prefs.remove(_kLastSync);
    } else {
      await _prefs.setInt(_kLastSync, date.millisecondsSinceEpoch);
    }
  }

  RemoteConfig? get cachedConfig {
    final raw = _prefs.getString(_kConfig);
    if (raw == null || raw.isEmpty) return null;
    try {
      return RemoteConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheConfig(RemoteConfig config) =>
      _prefs.setString(_kConfig, jsonEncode(config.toJson()));
}

class BootstrapResult {
  BootstrapResult({
    required this.settings,
    required this.config,
    required this.supabaseReady,
    this.supabaseError,
  });

  final SettingsStore settings;
  final RemoteConfig config;
  final bool supabaseReady;
  final String? supabaseError;
}

class Bootstrap {
  Bootstrap._();

  static Future<RemoteConfig> _fetchConfig(String baseUrl) async {
    final base = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final response = await http
        .get(
          Uri.parse('$base/api/config'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('Config indisponible (${response.statusCode})');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) throw StateError('Config invalide');
    return RemoteConfig.fromJson(data);
  }

  static Future<BootstrapResult> load() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStore(prefs);

    RemoteConfig config = RemoteConfig.empty;
    try {
      config = await _fetchConfig(settings.serverUrl);
      await settings.cacheConfig(config);
    } catch (_) {
      config = settings.cachedConfig ?? RemoteConfig.empty;
    }

    // Repli pour les builds autonomes (CI, stores) sans serveur de config.
    if (!config.hasSupabase &&
        kSupabaseUrlOverride.isNotEmpty &&
        kSupabaseAnonOverride.isNotEmpty) {
      config = RemoteConfig(
        supabaseUrl: kSupabaseUrlOverride,
        supabaseAnonKey: kSupabaseAnonOverride,
      );
    }

    var ready = false;
    String? error;
    if (config.hasSupabase) {
      try {
        await Supabase.initialize(
          url: config.supabaseUrl,
          publishableKey: config.supabaseAnonKey,
          debug: false,
        );
        ready = true;
      } catch (e) {
        error = e.toString();
      }
    }

    return BootstrapResult(
      settings: settings,
      config: config,
      supabaseReady: ready,
      supabaseError: error,
    );
  }
}
