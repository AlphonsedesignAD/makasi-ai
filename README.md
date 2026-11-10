# Makasi AI 🚀

Un assistant conversationnel intelligent propulsé par l'API Gemini, doté d'une interface moderne et de streaming en temps réel mot-par-mot.

## Structure du projet

```text
makasi-ai/
├── api/
│   ├── chat.js        # Chat texte (Gemini, streaming)
│   ├── image.js       # Génération d'images (serveur, avec repli et cache)
│   └── documents.js   # Génération de documents Word, Excel et PDF
├── index.html         # Interface utilisateur
├── style.css          # Design soigné & responsive avec animations
├── app.js             # Logique frontend (SSE streaming)
├── package.json       # Dépendances serveur (docx, exceljs, pdf-lib)
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

## Documents (Word, Excel, PDF)

Demandez un document dans le chat, par exemple « crée un rapport Word sur … », « fais-moi un budget Excel » ou « génère une lettre de motivation PDF ». Vous pouvez aussi utiliser une commande : `/pdf …`, `/word …`, `/excel …`.

L'application détecte le format, appelle `/api/documents`, puis affiche une carte avec :

- le **téléchargement** du vrai fichier (`.docx`, `.xlsx`, `.pdf`) ;
- le **changement de format** (PDF ↔ Word ↔ Excel) sans réécrire la demande ;
- la **régénération** du document.

Gemini rédige le contenu (titre, sections, paragraphes, puces, tableaux) au format JSON structuré, puis le serveur fabrique le fichier :

| Format | Bibliothèque | Contenu |
| --- | --- | --- |
| Word `.docx` | `docx` | Titre, sous-titre, sections, listes à puces, tableaux stylés |
| Excel `.xlsx` | `exceljs` | Feuilles multiples, en-têtes colorés, filtres, nombres typés |
| PDF | `pdf-lib` | Mise en page A4, tableaux, pagination « Page x / y » |

Les documents sont générés par `gemini-3.5-flash-lite` en priorité, avec bascule automatique vers `gemini-2.5-flash-lite`, `gemini-2.5-flash`, `gemini-3.1-flash-lite` puis `gemini-3.5-flash` si un modèle est saturé ou à court de quota. Reprise automatique et délai maximal de 60 s.

### API

```http
POST /api/documents
Content-Type: application/json

{ "prompt": "rapport sur l'IA dans l'éducation", "format": "docx" }
```

`format` vaut `docx`, `xlsx` ou `pdf` (par défaut `pdf`). En cas de succès, la réponse est le fichier binaire avec `Content-Disposition`, `X-Document-Title` et `X-Document-Format`. En cas d'échec : JSON `{ "error": "…", "code": "quota|format|upstream|unavailable|invalid_request" }`.

> La génération de documents utilise le quota Gemini texte (aucune facturation n'est nécessaire en principe). Si le quota gratuit est momentanément épuisé, l'interface affiche un message clair et permet de réessayer.

## Quotas Gemini

Le quota gratuit Gemini est **journalier et par modèle**. Makasi AI en tient compte :

- le chat et les documents **basculent automatiquement** vers un autre modèle quand le modèle courant est épuisé (liste : `gemini-3.5-flash-lite`, `gemini-2.5-flash-lite`, `gemini-2.5-flash`, `gemini-3.1-flash-lite`, `gemini-3.5-flash`) ;
- un modèle en quota atteint est mis de côté pendant quelques heures pour ne pas gaspiller d'appels ;
- si **tous** les modèles sont épuisés, l'interface affiche un message lisible avec le délai avant nouvel essai — jamais le JSON brut de Google ;
- pour multiplier le quota, ajoutez des clés de secours `GEMINI_API_KEY_2` et `GEMINI_API_KEY_3` (autres projets Google AI). Elles sont utilisées automatiquement.

La génération d'**images** reste soumise à la facturation Google AI (quota gratuit à 0).

## Test en local

```bash
npm install
vercel dev
```

`vercel dev` sert le site et les trois fonctions (`/api/chat`, `/api/image`, `/api/documents`) avec le fichier `.env`.
