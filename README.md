# Makasi AI 🚀

Un assistant conversationnel intelligent propulsé par l'API Gemini, doté d'une interface moderne et de streaming en temps réel mot-par-mot.

## Structure du projet

```text
makasi-ai/
├── api/
│   └── chat.js        # Fonction Serverless Vercel (sécurise la clé secrète)
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

