// api/image.js — Génération d'image côté serveur (Vercel Edge)
// Évite les blocages du navigateur : un seul appel propre, repli automatique, cache long.
export const config = { runtime: 'edge' };

const json = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });

// Transforme la demande (souvent en français) en prompt anglais détaillé via Gemini (facultatif).
async function enhance(prompt) {
  const key = process.env.GEMINI_API_KEY;
  if (!key) return prompt;
  try {
    const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-lite-latest:generateContent?key=${key}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      signal: AbortSignal.timeout(4000),
      body: JSON.stringify({ contents: [{ parts: [{ text: `Rewrite this as one detailed English prompt for an AI image generator (subject, style, lighting, composition, quality). Output only the prompt, max 60 words.\n\n${prompt}` }] }] })
    });
    const t = (await r.json())?.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
    return t ? t.slice(0, 600) : prompt;
  } catch { return prompt; }
}

export default async function handler(req) {
  const u = new URL(req.url);
  const prompt = (u.searchParams.get('prompt') || '').trim().slice(0, 500);
  const seed = parseInt(u.searchParams.get('seed'), 10) || 1;
  if (!prompt) return json({ error: 'prompt manquant' }, 400);

  const q = encodeURIComponent(await enhance(prompt));
  const pk = process.env.POLLINATIONS_API_KEY; // facultatif : lève la limite des requêtes anonymes
  const attempts = [['flux', 1024, 12000], ['turbo', 768, 7000]];

  for (const [model, size, ms] of attempts) {
    const url = pk
      ? `https://gen.pollinations.ai/image/${q}?model=${model}&width=${size}&height=${size}&seed=${seed}&nologo=true&key=${pk}`
      : `https://image.pollinations.ai/prompt/${q}?model=${model}&width=${size}&height=${size}&seed=${seed}&nologo=true`;
    try {
      const r = await fetch(url, { signal: AbortSignal.timeout(ms) });
      const type = r.headers.get('content-type') || '';
      if (r.ok && type.startsWith('image/')) {
        return new Response(r.body, { headers: { 'Content-Type': type, 'Cache-Control': 'public, max-age=31536000, s-maxage=31536000, immutable' } });
      }
    } catch { /* on tente le modèle suivant */ }
  }
  return json({ error: 'Service image occupé, réessayez.' }, 503);
}
