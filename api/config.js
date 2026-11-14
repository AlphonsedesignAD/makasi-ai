// api/config.js — Configuration publique partagée entre le site et l'app mobile
//
// Cette fonction ne renvoie QUE des informations publiques :
//   - l'URL et la clé "anon" Supabase (prévues pour être exposées)
//   - jamais la moindre clé Gemini.
//
// Le site et l'application Flutter lisent ce même endpoint : une seule
// configuration à maintenir.

export const config = { runtime: 'edge' };

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

export default async function handler(req) {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method !== 'GET') {
    return new Response(JSON.stringify({ error: 'Méthode non autorisée.' }), {
      status: 405,
      headers: { ...CORS, 'Content-Type': 'application/json; charset=utf-8' },
    });
  }

  const payload = {
    app: 'Makasi AI',
    version: '2.0.0',
    // Supabase : authentification + mémoire partagée.
    supabaseUrl: process.env.SUPABASE_URL || '',
    supabaseAnonKey: process.env.SUPABASE_ANON_KEY || '',
    // Endpoints utilisés par le mobile (relatifs au domaine).
    chatEndpoint: '/api/chat',
    imageEndpoint: '/api/image',
  };

  return new Response(JSON.stringify(payload), {
    status: 200,
    headers: {
      ...CORS,
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'public, max-age=60, s-maxage=60',
    },
  });
}
