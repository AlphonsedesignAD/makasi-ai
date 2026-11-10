# Makasi AI 🚀

Un assistant conversationnel intelligent propulsé par l'API Gemini, doté d'une interface moderne et de streaming en temps réel mot-par-mot.

## Structure du projet

```text
makasi-ai/
├── api/
│   ├── chat.js        # Chat texte (Gemini, streaming)
│   └── image.js       # Génération d'images (serveur, avec repli et cache)
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


## Images

Tapez par exemple « génère une image de … » ou `/image …`. La génération passe par `/api/image` (plus fiable que l'appel direct depuis le navigateur).

- **Formats** : `1:1`, `16:9`, `9:16`, `4:3`, `3:4`. Le format est déduit de la phrase (« en portrait », « format 16:9 », « paysage »…) et reste modifiable sous l'image.
- **Styles** : photo, illustration, 3D, anime, logo — déduits de la phrase ou passés via `style`.
- **Moteur** : Gemini Image (`gemini-3.1-flash-image` → `gemini-3-pro-image` → `gemini-2.5-flash-image`).
- **Quota** : la génération d'images Gemini nécessite un projet Google AI avec facturation activée. Sans facturation, l'API renvoie `429 RESOURCE_EXHAUSTED` et l'interface affiche un message explicite.

### API

```http
GET  /api/image?prompt=un%20chat&ratio=16:9&style=photo&seed=42
POST /api/image   { "prompt": "un chat", "ratio": "16:9", "style": "photo", "seed": 42 }
```

Réponse : l'image binaire (`image/png` ou `image/jpeg`), avec les en-têtes `X-Image-Source` et `X-Image-Ratio`. En cas d'échec : JSON `{ "error": "…", "code": "quota|blocked|unavailable|invalid_request" }`.

## Test en local

`vercel dev` dans le dossier (les deux fonctions `/api/chat` et `/api/image` ont besoin du serveur Vercel et du fichier `.env`).
