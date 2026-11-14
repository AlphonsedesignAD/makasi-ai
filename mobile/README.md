# Makasi AI — application mobile

Application Flutter pour Android, iOS et le web. Elle reprend l’identité du site et communique avec le **même serveur Makasi**.

## Fonctionnalités

- Conversation en streaming, mot par mot.
- Compte simple : nom, e-mail et mot de passe, **enregistré sur le téléphone**.
- Conversations conservées dans l’application.
- Export des conversations en fichier Markdown avant une désinstallation.
- Mode invité avec mémoire locale.
- Pièces jointes : photos, caméra, PDF, fichiers texte et code.
- Dictée vocale en français.
- Lecture des réponses à voix haute.
- Thème clair, sombre ou automatique.
- Interface adaptative : tiroir sur téléphone, barre latérale sur tablette, ordinateur et web.
- Aucune génération d’images.

## Compte et conversations

- Le compte est **local** : il n’y a pas de serveur de comptes à configurer.
- Les conversations ne quittent pas le téléphone.
- **Si l’application est désinstallée, le compte et les conversations sont supprimés.**
- Avant de désinstaller, utilisez **« Enregistrer mes conversations »** dans le compte ou les paramètres : un fichier Markdown est créé et peut être conservé ailleurs.
- Se déconnecter ne supprime pas les conversations de l’application.

## Prérequis

- Flutter 3.41 ou plus récent.
- Un serveur Makasi déployé (par défaut `https://makasi-ai.vercel.app`).

## Lancer l’application

```bash
flutter pub get
flutter run
```

Le serveur de production est utilisé par défaut. Pour un serveur local :

```bash
# Émulateur Android
flutter run --dart-define=MAKASI_API_BASE=http://10.0.2.2:3000

# Simulateur iOS / navigateur / appareil physique
flutter run --dart-define=MAKASI_API_BASE=http://192.168.1.20:3000
```

## Construire les versions de production

```bash
# Android App Bundle (Play Store)
flutter build appbundle --release

# APK direct
flutter build apk --release

# iOS (macOS + Xcode requis)
flutter build ipa --release

# Version web
flutter build web --release
```

L’APK généré se trouve dans `build/app/outputs/flutter-apk/app-release.apk`.

Pour un serveur différent :

```bash
flutter build apk --release \
  --dart-define=MAKASI_API_BASE=https://votre-domaine.com
```

## Structure

```text
lib/
├── main.dart
├── core/          # thème, configuration, textes, utilitaires
├── data/          # modèles, stockage local, compte local, export, API
├── state/         # contrôleur global de l’application
├── screens/       # démarrage, connexion, accueil, tiroir, compte, réglages
└── widgets/       # logo, avatar, messages, composeur, Markdown
```

## Icône et polices

- Police Inter embarquée (`assets/fonts/`) sous licence OFL.
- Icône générée depuis `assets/icon/` avec `flutter_launcher_icons`.
- Pour régénérer les icônes après modification :

```bash
dart run flutter_launcher_icons
```

## Vérifications

```bash
flutter analyze
flutter test
```
