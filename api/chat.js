// Fonction serveur Vercel : garde les clés secrètes + bascule automatique entre 4 clés.
const KEYS = () => [1, 2, 3, 4]
  .map(i => (process.env['CODECRAFT_KEY_' + i] || '').trim())
  .filter(Boolean);

const cleanUrl = url => {
  let u = (url || 'https://codecraftapi.com/v1/chat/completions').trim();
  if (u.startsWith('ttps://')) u = 'h' + u;
  u = u.replace(/\/v1\/v1\//, '/v1/');
  return u;
};

const RETRY = [401, 402, 403, 429, 500, 502, 503, 529]; // clé épuisée/invalide ou service saturé

const PROMPTS = {
  chat: `Tu es Makasi AI, un assistant IA tout-en-un puissant, polyvalent et bienveillant.
RÈGLES ABSOLUES SUR LES FICHIERS ET DOCUMENTS :
- Tu ne dois JAMAIS dire "je ne peux pas envoyer de pièce jointe", "je ne peux pas créer de fichier" ou "je suis seulement un modèle de texte".
- L'application Makasi AI intègre un convertisseur automatique : sous chacune de tes réponses se trouvent des boutons pour télécharger le résultat en Word (.doc), Excel (.xlsx) ou PDF (.pdf).
- Si l'utilisateur demande un tableau, un fichier Excel, un budget, des comptes ou une feuille de calcul : génère toujours un tableau Markdown propre et complet (| Colonne 1 | Colonne 2 |). Conclus en disant : "📥 **Téléchargement disponible :** Cliquez sur le bouton **Excel** juste en dessous pour télécharger ce fichier au format .xlsx."
- Si l'utilisateur demande un document Word, un rapport, un courrier ou un texte structuré : rédige-le en Markdown avec des titres (#, ##), des listes et une mise en page soignée. Conclus en disant : "📥 **Téléchargement disponible :** Cliquez sur le bouton **Word** ou **PDF** juste en dessous pour télécharger ce document."
- Réponds toujours directement avec le contenu demandé, sans hésiter et dans la langue de l'utilisateur.`,

  doc: `Tu es Makasi AI en mode Rédacteur Professionnel.
Ne dis JAMAIS que tu ne peux pas créer de fichier. Produis un document exhaustif et impeccable en Markdown (# Titres, ## Sous-titres, listes à puces, tableaux).
Conclus toujours en indiquant à l'utilisateur qu'il peut cliquer sur les boutons 'Word', 'PDF' ou 'Excel' situés juste sous ta réponse pour télécharger le fichier.`,

  code: `Tu es Makasi AI, ingénieur logiciel senior. Donne du code complet, moderne, robuste et commenté dans des blocs \`\`\`langage, puis explique brièvement.`,

  files: `Tu es Makasi AI, analyste de documents. Analyse, résume et structure le contenu des fichiers ou images fournis avec clarté et précision.`
};

async function checkUser(token) {
  const r = await fetch(process.env.SUPABASE_URL + '/auth/v1/user', {
    headers: { Authorization: 'Bearer ' + token, apikey: process.env.SUPABASE_ANON_KEY }
  });
  return r.ok;
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Méthode non autorisée' });
  const token = (req.headers.authorization || '').replace('Bearer ', '');
  if (!token || !(await checkUser(token))) return res.status(401).json({ error: 'Connexion requise' });

  const { messages = [], mode = 'chat' } = req.body || {};
  const keys = KEYS();
  if (!keys.length) return res.status(500).json({ error: 'Aucune clé API configurée' });

  const apiUrl = cleanUrl(process.env.CODECRAFT_API_URL);
  const model = (process.env.CODECRAFT_MODEL || 'claude-sonnet-5').trim();

  const body = JSON.stringify({
    model,
    messages: [{ role: 'system', content: PROMPTS[mode] || PROMPTS.chat }, ...messages.slice(-20)]
  });

  let lastError = null;

  for (let i = 0; i < keys.length; i++) {
    try {
      const r = await fetch(apiUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + keys[i] },
        body
      });
      if (r.ok) {
        const d = await r.json();
        const reply = d.choices?.[0]?.message?.content ?? d.content?.[0]?.text ?? '';
        return res.status(200).json({ reply, key: i + 1 });
      }
      const errText = await r.text().catch(() => '');
      lastError = `Clé ${i + 1} (${r.status}): ${errText || r.statusText}`;
      if (!RETRY.includes(r.status)) {
        return res.status(r.status).json({ error: lastError });
      }
      console.warn('Clé ' + (i + 1) + ' refusée (' + r.status + '), bascule…', lastError);
    } catch (e) {
      lastError = `Clé ${i + 1} erreur réseau: ${e.message}`;
      console.warn('Clé ' + (i + 1) + ' injoignable, bascule…', e.message);
    }
  }
  res.status(503).json({ error: lastError || 'Toutes les clés sont épuisées. Réessaie plus tard.' });
};
