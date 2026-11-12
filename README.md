# Makasi AI 🚀

Un assistant conversationnel intelligent propulsé par l'API Gemini, doté d'une interface moderne et de streaming en temps réel mot-par-mot.

## Structure du projet

```text
makasi-ai/
├── api/
│   ├── _keys.js       # Lecture des clés Gemini (1 à N clés)
│   └── chat.js        # Chat texte (Gemini, streaming, repli multi-modèles)
├── index.html         # Interface utilisateur
├── style.css          # Design soigné & responsive avec animations
├── app.js             # Logique frontend (SSE streaming)
├── vercel.json        # Configuration de routage Vercel
├── .env.example       # Modèle de variable d'environnement
└── .gitignore         # Empêche la publication des secrets (.env)
```

## Déploiement sur Vercel

1. Poussez ce dossier sur un dépôt GitHub (privé ou public).
2. Rendez-vous sur [vercel.com](https://vercel.com) et cliquez sur **Add New > Project**.
3. Importez votre dépôt GitHub.
4. Dans la section **Environment Variables**, ajoutez :
   - **Key** : `GEMINI_API_KEY`
   - **Value** : votre clé API Gemini (ex: `AQ.Ab8...` ou `AIza...`)
5. Cliquez sur **Deploy**.

Votre site sera en ligne et votre clé d'API restera 100% sécurisée côté serveur, invisible pour les visiteurs et absente de GitHub !

## Plusieurs clés API Gemini

Le quota gratuit est journalier **et par modèle, pour chaque projet Google**. Ajouter une deuxième clé (créée sur un autre projet Google AI) multiplie donc le quota disponible.

### En local (`.env`)

Deux formats sont acceptés, au choix :

```bash
# Format 1 — une variable par clé
GEMINI_API_KEY=AQ.premiere_cle
GEMINI_API_KEY_2=AQ.deuxieme_cle
GEMINI_API_KEY_3=AQ.troisieme_cle
```

```bash
# Format 2 — une seule variable, clés séparées par des virgules
GEMINI_API_KEYS=AQ.premiere_cle,AQ.deuxieme_cle,AQ.troisieme_cle
```

Les deux formats peuvent être combinés. Les clés en double sont ignorées.

### Sur Vercel

**Settings → Environment Variables** : ajoutez `GEMINI_API_KEY_2` (puis `GEMINI_API_KEY_3`, …) avec vos autres clés, pour **Production** et **Preview**, puis **Redeploy**.

L'application utilise les clés dans l'ordre et passe automatiquement à la suivante quand une clé est refusée ou que ses modèles sont épuisés.

## Quotas Gemini

Le quota gratuit Gemini est **journalier et par modèle**. Makasi AI en tient compte :

- le chat **bascule automatiquement** vers un autre modèle quand le modèle courant est épuisé (liste : `gemini-3.5-flash-lite`, `gemini-2.5-flash-lite`, `gemini-2.5-flash`, `gemini-3.1-flash-lite`, `gemini-3.5-flash`) ;
- un modèle en quota atteint est mis de côté pendant quelques heures pour ne pas gaspiller d'appels ;
- si **tous** les modèles et toutes les clés sont épuisés, l'interface affiche un message lisible avec le délai avant nouvel essai — jamais le JSON brut de Google ;
- ajoutez `GEMINI_API_KEY_2`, `GEMINI_API_KEY_3`… (ou `GEMINI_API_KEYS`) pour multiplier le quota.

## Test en local

```bash
vercel dev
```

`vercel dev` sert le site et la fonction (`/api/chat`) avec le fichier `.env`.
