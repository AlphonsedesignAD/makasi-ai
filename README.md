# Makasi AI

Assistant personnel avec une interface soignée, un streaming mot par mot, la dictée vocale, les pièces jointes et une **mémoire conservée dans l’application mobile**.

Le site et l’application utilisent le même serveur Makasi. Les clés du moteur d’IA restent uniquement côté serveur.

## Architecture

```text
makasi-ai/
├── api/
│   ├── _keys.js        # Lecture des clés serveur (1 à N clés)
│   ├── chat.js         # Chat en streaming
│   └── config.js       # Configuration publique
├── index.html          # Site web
├── style.css
├── app.js              # Logique du site
├── mobile/             # Application Flutter (Android, iOS, Web)
├── vercel.json
└── .env.example
```

- **Web** : HTML/CSS/JavaScript, hébergé sur Vercel. Pas de compte : les discussions restent dans le navigateur.
- **Mobile** : Flutter/Dart, dans `mobile/`.
- **Compte mobile** : simple, enregistré sur le téléphone, avec export des conversations.
- **IA** : uniquement appelée par les fonctions serverless Vercel. Aucune clé n’est envoyée au navigateur ni au téléphone.

## Application mobile

L’application se trouve dans [`mobile/`](mobile/). Voir le guide détaillé : [`mobile/README.md`](mobile/README.md).

```bash
cd mobile
flutter pub get
flutter run
```

L’application utilise par défaut `https://makasi-ai.vercel.app`. Pour tester un serveur local :

```bash
flutter run --dart-define=MAKASI_API_BASE=http://10.0.2.2:3000
```

### Compte et conversations

- L’utilisateur crée un **compte simple** : nom, e-mail et mot de passe.
- Le compte et les conversations restent **sur le téléphone**, dans l’application.
- Si l’application est désinstallée, le compte et les conversations sont perdus.
- L’application propose donc **« Enregistrer mes conversations »** : un fichier Markdown est créé et peut être conservé avant la désinstallation.
- Sans compte, le mode invité fonctionne aussi, avec les conversations sur l’appareil.

## Déployer le site sur Vercel

1. Poussez le dépôt sur GitHub.
2. Importez le dépôt sur [vercel.com](https://vercel.com).
3. Dans **Settings > Environment Variables**, ajoutez pour **Production** et **Preview** :

```bash
# Moteur d’IA (côté serveur uniquement)
GEMINI_API_KEY=votre_cle_serveur
```

4. Déployez, puis vérifiez `https://votre-site.vercel.app/api/config`.

`GEMINI_API_KEY` est le nom technique attendu par le serveur. Cette valeur n’est jamais exposée au client. Des clés de secours peuvent être ajoutées avec `GEMINI_API_KEY_2`, `GEMINI_API_KEY_3`… ou `GEMINI_API_KEYS`.

## Développement local

```bash
npm install -g vercel
vercel dev
```

`vercel dev` sert le site et les fonctions `/api/chat` et `/api/config` avec le fichier `.env`.

Pour vérifier la syntaxe JavaScript :

```bash
node --check app.js
node --check api/chat.js
node --check api/config.js
```

## Sécurité

- `.env` est ignoré par Git et ne doit jamais être commité.
- Les clés du moteur d’IA ne quittent pas le serveur.
- La génération d’images a été retirée du site et de l’application.
- Le site n’a pas de compte : les discussions restent dans le navigateur.
- Les conversations du téléphone ne sont pas envoyées à un serveur de comptes.
