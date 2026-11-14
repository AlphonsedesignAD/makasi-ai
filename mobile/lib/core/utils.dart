import 'dart:math';

/// Identifiant local, compatible avec celui utilisé par le site web.
String newId() {
  final now = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final rand = Random().nextInt(0x7FFFFFFF).toRadixString(36);
  return now + rand;
}

String greetingForHour(int hour) {
  if (hour < 5) return 'Bonne nuit';
  if (hour < 18) return 'Bonjour';
  return 'Bonsoir';
}

String truncateTitle(String text, {int max = 42}) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.length <= max) return clean;
  return '${clean.substring(0, max).trim()}…';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
}

/// Regroupe comme le site : Aujourd'hui / Hier / 7 derniers jours / Plus ancien.
String relativeDayLabel(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final startToday = DateTime(today.year, today.month, today.day);
  final d = DateTime(date.year, date.month, date.day);
  final days = startToday.difference(d).inDays;
  if (days <= 0) return 'Aujourd’hui';
  if (days == 1) return 'Hier';
  if (days <= 7) return '7 derniers jours';
  return 'Plus ancien';
}

String formatTime(DateTime date) {
  final h = date.hour.toString().padLeft(2, '0');
  final m = date.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Texte lisible pour la synthèse vocale.
String speechText(String markdown) {
  return markdown
      .replaceAll(RegExp(r'```[\s\S]*?```'), 'Bloc de code.')
      .replaceAll(RegExp(r'[#*_`\[\]()]'), ' ')
      .replaceAll(RegExp(r'https?://\S+'), 'lien web')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Message d'erreur lisible à partir du JSON renvoyé par /api/chat.
String parseApiError(String body, int status) {
  try {
    final match = RegExp(r'"error"\s*:\s*"((?:\\.|[^"\\])*)"').firstMatch(body);
    if (match != null) {
      final raw = match.group(1) ?? '';
      return raw
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', '\\');
    }
  } catch (_) {
    // ignore
  }
  if (status == 401 || status == 403) {
    return 'Le service Makasi a refusé la requête. Réessayez dans un instant.';
  }
  if (status == 429) {
    return 'La limite Makasi est atteinte pour le moment. Réessayez plus tard.';
  }
  if (status == 404) {
    return 'Cette fonctionnalité n’est plus disponible.';
  }
  if (status >= 500) {
    return 'Le service est momentanément indisponible. Réessayez dans un instant.';
  }
  return 'La requête a été refusée (erreur $status).';
}

/// Transforme une exception Supabase en message français utile.
String friendlyAuthMessage(Object error) {
  final raw = error.toString();
  final m = raw
      .replaceFirst(RegExp(r'^[A-Za-z]+Exception:\s*'), '')
      .replaceFirst(RegExp(r'^Bad state:\s*'), '')
      .trim();
  final lower = m.toLowerCase();
  if (lower.contains('invalid login credentials')) {
    return 'E-mail ou mot de passe incorrect.';
  }
  if (lower.contains('already registered') || lower.contains('already been registered')) {
    return 'Un compte existe déjà avec cet e-mail. Connectez-vous.';
  }
  if (lower.contains('email not confirmed')) {
    return 'Confirmez votre e-mail (lien reçu dans votre boîte) avant de vous connecter.';
  }
  if (lower.contains('password') && (lower.contains('6') || lower.contains('short'))) {
    return 'Le mot de passe doit contenir au moins 6 caractères.';
  }
  if (lower.contains('invalid') && lower.contains('email')) {
    return 'Cette adresse e-mail n’est pas valide.';
  }
  if (lower.contains('rate limit') || lower.contains('too many')) {
    return 'Trop de tentatives. Patientez un instant puis réessayez.';
  }
  if (lower.contains('socket') ||
      lower.contains('connection') ||
      lower.contains('network') ||
      lower.contains('failed host lookup')) {
    return 'Connexion impossible. Vérifiez votre réseau.';
  }
  return m.isEmpty ? 'Une erreur est survenue. Réessayez.' : m;
}
