// Serveur local Express — remplace "vercel dev" pour tester en local
require('dotenv').config();
const path = require('path');
const express = require('express');
const chatHandler = require('./api/chat');

const app = express();
app.use(express.json({ limit: '10mb' }));

// Fichiers statiques (index.html, css/, js/)
app.use(express.static(__dirname));

// Route API — adapte le handler Vercel pour Express
app.post('/api/chat', (req, res) => chatHandler(req, res));

// Page d'accueil
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`\n  ✅ Makasi AI tourne sur : http://localhost:${PORT}\n`);
});

