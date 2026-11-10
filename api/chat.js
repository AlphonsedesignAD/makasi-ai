// api/chat.js — Vercel Serverless Function (proxy Gemini, streaming SSE)
// La clé API est dans les variables d'env Vercel, jamais dans le code.
//
// Le quota gratuit Gemini est journalier ET par modèle. On bascule donc
// automatiquement vers un autre modèle (puis une autre clé si fournie)
// quand un modèle est épuisé, au lieu d'afficher une erreur brute.

export const config = { runtime: 'edge' };

// Modèles essayés dans l'ordre (le premier qui répond est utilisé).
const MODELS = [
  'gemini-3.5-flash-lite',
  'gemini-2.5-flash-lite',
  'gemini-2.5-flash',
  'gemini-3.1-flash-lite',
  'gemini-3.5-flash',
];

// Modèles en quota atteint : on les saute pendant un moment.
const cooldown = new Map();

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

function json(status, payload) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

function humanDelay(seconds) {
  const s = Number(seconds) || 0;
  if (s < 60) return 'quelques instants';
  const h = Math.floor(s / 3600);
  const m = Math.round((s % 3600) / 60);
  if (h >= 1) return `${h} h${m ? ` ${m} min` : ''}`;
  return `${m} min`;
}

function parseGeminiError(status, text) {
  let message = '';
  let retryAfter = 0;
  try {
    const err = JSON.parse(text)?.error;
    message = err?.message || '';
    const retry = (err?.details || []).find((d) => String(d?.['@type'] || '').includes('RetryInfo'));
    if (retry?.retryDelay) retryAfter = parseInt(retry.retryDelay, 10) || 0;
  } catch (_) {
    /* réponse non JSON */
  }
  const quota = status === 429 || /RESOURCE_EXHAUSTED|quota/i.test(message);
  return { status, quota, retryAfter, detail: String(message).slice(0, 300) };
}

export default async function handler(req) {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method !== 'POST') return json(405, { error: 'Méthode non autorisée.', code: 'method_not_allowed' });

  const keys = [process.env.GEMINI_API_KEY, process.env.GEMINI_API_KEY_2, process.env.GEMINI_API_KEY_3].filter(Boolean);
  if (!keys.length) return json(500, { error: 'Clé Gemini non configurée.', code: 'unavailable' });

  let body;
  try {
    body = await req.json();
  } catch (_) {
    return json(400, { error: 'Requête invalide.', code: 'invalid_request' });
  }

  // Injecter maxOutputTokens pour avoir des réponses complètes
  body.generationConfig = {
    ...(body.generationConfig || {}),
    maxOutputTokens: 16384,
  };

  let last = null;
  let quotaInfo = null;

  for (const key of keys) {
    for (const model of MODELS) {
      const until = cooldown.get(model) || 0;
      if (until > Date.now()) {
        if (!quotaInfo) {
          quotaInfo = { quota: true, retryAfter: Math.ceil((until - Date.now()) / 1000), detail: 'cooldown' };
        }
        continue;
      }

      let res;
      try {
        res = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse&key=${key}`,
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
            signal: AbortSignal.timeout(120000),
          }
        );
      } catch (e) {
        last = { status: 504, quota: false, retryAfter: 0, detail: e.message };
        continue;
      }

      if (res.ok) {
        // Retransmet le flux SSE directement au navigateur
        return new Response(res.body, {
          status: 200,
          headers: {
            'Content-Type': 'text/event-stream; charset=utf-8',
            'Cache-Control': 'no-cache, no-transform',
            'Access-Control-Allow-Origin': '*',
            'X-Gemini-Model': model,
          },
        });
      }

      const info = parseGeminiError(res.status, await res.text().catch(() => ''));
      last = info;

      // Requête refusée (clé invalide, historique, format) : inutile d'insister.
      if (!info.quota && res.status >= 400 && res.status < 500) {
        return json(res.status, {
          error:
            res.status === 403 || res.status === 401
              ? 'La clé Gemini a été refusée. Vérifiez-la dans les variables d’environnement Vercel.'
              : 'La requête a été refusée par Gemini. Raccourcissez la conversation ou réessayez.',
          code: 'invalid_request',
          detail: info.detail,
        });
      }

      if (info.quota) {
        quotaInfo = info;
        // On met le modèle de côté (max 6 h) pour ne pas gaspiller d'appels.
        const wait = Math.min(info.retryAfter || 3600, 6 * 3600);
        cooldown.set(model, Date.now() + wait * 1000);
      }
    }
  }

  if (quotaInfo) {
    return json(429, {
      error:
        "Le quota gratuit Gemini est atteint pour aujourd'hui sur tous les modèles disponibles. " +
        (quotaInfo.retryAfter ? `Réessayez dans ${humanDelay(quotaInfo.retryAfter)} ` : 'Réessayez plus tard ') +
        'ou activez la facturation sur votre projet Google AI.',
      code: 'quota',
      retryAfter: quotaInfo.retryAfter || null,
    });
  }

  return json(503, {
    error: 'Le service Gemini est momentanément indisponible. Réessayez dans quelques instants.',
    code: 'upstream',
    detail: last?.detail,
  });
}
