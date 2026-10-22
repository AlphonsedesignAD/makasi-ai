# Makasi AI

Chat IA multitâche : discussion, analyse d'images, export Word/PDF/Excel, lecture de fichiers, aide au code.

## Architecture
- **Frontend** (HTML/CSS/JS, sans build) : `index.html`, `css/`, `js/`
- **Backend** (fonction Vercel) : `api/chat.js` garde les clés IA secrètes, vérifie la connexion Supabase et bascule sur la clé suivante (1 → 2 → 3 → 4) quand une est épuisée
- **Supabase** : comptes (Auth), discussions/messages/fichiers (Postgres + RLS), stockage privé (Storage)

## Installation
1. Supabase : crée un projet, exécute `supabase/schema.sql` dans le SQL Editor
2. Colle l'URL et la clé `anon` dans `js/config.js`
3. Copie `.env.example` en `.env` et remplis tes 4 clés + l'URL de l'API CodeCraft
4. Test local : `npm i -g vercel` puis `vercel dev` → http://localhost:3000
5. Déploiement : `vercel --prod`, puis ajoute les mêmes variables dans Vercel > Settings > Environment Variables
