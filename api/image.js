// api/image.js — Génération d'image via Gemini Image (Vercel Edge)
// Modèles : gemini-3.1-flash-image → gemini-3-pro-image → gemini-2.5-flash-image
//
// GET  /api/image?prompt=...&ratio=16:9&style=photo&seed=123
// POST /api/image  { "prompt": "...", "ratio": "16:9", "style": "photo", "seed": 123 }

export const config = { runtime: 'edge' };

/* Budget de la fonction (les Edge Functions Vercel coupent à 30 s) */
const TOTAL_BUDGET_MS = 27000;
const MIN_ATTEMPT_MS = 8000;

const RATIOS = ['1:1', '16:9', '9:16', '4:3', '3:4'];

const MODELS = [
  { id: 'gemini-3.1-flash-image', ratio: true },
  { id: 'gemini-3-pro-image', ratio: true },
  { id: 'gemini-2.5-flash-image', ratio: false },
];

const STYLE_HINTS = {
  photo:
    'photorealistic photography, natural lighting, sharp focus, 50mm lens, shallow depth of field, ultra detailed, high dynamic range',
  illustration:
    'high quality digital illustration, clean line art, rich colors, detailed shading, professional composition',
  '3d':
    'polished 3D render, octane render, soft studio lighting, physically based materials, highly detailed',
  anime:
    'anime style, cel shading, expressive characters, detailed background, studio quality animation still',
  logo:
    'professional vector logo design, flat colors, minimal, centered composition, clean background, scalable',
};

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

const json = (payload, status = 200, extra = {}) =>
  new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS, ...extra },
  });

class ImageError extends Error {
  constructor(message, code, status = 502) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

const MESSAGES = {
  quota:
    "Le quota de génération d'images Gemini est épuisé. Activez la facturation sur votre projet Google AI (aistudio.google.com) puis réessayez.",
  blocked: 'La demande a été bloquée par les filtres de sécurité. Reformulez votre description.',
  upstream: "Le service d'images Gemini est momentanément indisponible. Réessayez dans un instant.",
  unavailable: "Impossible de générer l'image pour le moment. Réessayez dans un instant.",
};

function cleanRatio(value) {
  const r = String(value || '').trim().replace(/\s*(?::|\/|x)\s*/gi, ':').replace(/:+/g, ':');
  return RATIOS.includes(r) ? r : '1:1';
}

function cleanStyle(value) {
  const s = String(value || '').toLowerCase().trim();
  return Object.prototype.hasOwnProperty.call(STYLE_HINTS, s) ? s : '';
}

/* Construit un prompt unique et détaillé (sans appel supplémentaire à Gemini) */
function buildPrompt(prompt, style, ratio) {
  const parts = [prompt.trim()];
  if (style) parts.push(STYLE_HINTS[style]);
  else parts.push('high quality, sharp focus, well composed, detailed');
  parts.push(`aspect ratio ${ratio}`);
  parts.push(
    'Do not add any caption, signature or watermark. If text is explicitly requested, render it exactly as written.'
  );
  return parts.join('. ');
}

function b64ToBytes(b64) {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

async function geminiImage(prompt, ratio, key, model, timeoutMs) {
  const body = {
    contents: [{ role: 'user', parts: [{ text: prompt }] }],
    generationConfig: {
      responseModalities: ['IMAGE', 'TEXT'],
      ...(model.ratio ? { imageConfig: { aspectRatio: ratio } } : {}),
    },
  };

  let res;
  try {
    res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model.id}:generateContent?key=${key}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        signal: AbortSignal.timeout(timeoutMs),
        body: JSON.stringify(body),
      }
    );
  } catch (e) {
    throw new ImageError(`Gemini ${model.id}: ${e.message}`, 'upstream', 504);
  }

  if (!res.ok) {
    const text = await res.text().catch(() => '');
    let err = null;
    try {
      err = JSON.parse(text)?.error;
    } catch (_) {
      /* réponse non JSON */
    }
    const detail = err?.message || text.slice(0, 300) || `HTTP ${res.status}`;
    if (res.status === 429 || err?.status === 'RESOURCE_EXHAUSTED') {
      throw new ImageError(detail, 'quota', 429);
    }
    if (/safety|blocked|prohibited/i.test(detail)) {
      throw new ImageError(detail, 'blocked', 422);
    }
    throw new ImageError(detail, 'upstream', res.status >= 500 ? 502 : res.status);
  }

  const data = await res.json();
  const candidate = data?.candidates?.[0];
  const parts = candidate?.content?.parts || [];
  const imgPart = parts.find((p) => p?.inlineData?.data || p?.inline_data?.data);

  if (!imgPart) {
    const reason = data?.promptFeedback?.blockReason || candidate?.finishReason;
    throw new ImageError(
      `Aucune image générée${reason ? ` (${reason})` : ''}`,
      'blocked',
      422
    );
  }

  const inline = imgPart.inlineData || imgPart.inline_data;
  return {
    bytes: b64ToBytes(inline.data),
    mime: inline.mimeType || inline.mime_type || 'image/png',
    source: `gemini:${model.id}`,
  };
}

function imageResponse({ bytes, mime, source }, ratio) {
  return new Response(bytes, {
    status: 200,
    headers: {
      'Content-Type': mime,
      'Content-Length': String(bytes.length),
      'Cache-Control': 'public, max-age=31536000, s-maxage=31536000, immutable',
      'X-Image-Source': source,
      'X-Image-Ratio': ratio,
      ...CORS,
    },
  });
}

export default async function handler(req) {
  const started = Date.now();
  const budget = () => TOTAL_BUDGET_MS - (Date.now() - started);

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS });
  }

  let input = {};
  if (req.method === 'POST') {
    try {
      input = await req.json();
    } catch (_) {
      return json({ error: 'Corps JSON invalide.', code: 'invalid_request' }, 400);
    }
  } else if (req.method === 'GET') {
    const u = new URL(req.url);
    input = {
      prompt: u.searchParams.get('prompt'),
      ratio: u.searchParams.get('ratio'),
      style: u.searchParams.get('style'),
      seed: u.searchParams.get('seed'),
    };
  } else {
    return json({ error: 'Méthode non autorisée.', code: 'method_not_allowed' }, 405, {
      Allow: 'GET, POST, OPTIONS',
    });
  }

  const rawPrompt = String(input.prompt || '').trim().slice(0, 600);
  if (!rawPrompt) {
    return json({ error: 'Décrivez l’image à générer.', code: 'invalid_request' }, 400);
  }

  const ratio = cleanRatio(input.ratio);
  const style = cleanStyle(input.style);
  const prompt = buildPrompt(rawPrompt, style, ratio);
  const apiKey = process.env.GEMINI_API_KEY;

  let lastError = null;

  // Gemini Image — du plus rapide au plus ancien
  if (apiKey) {
    for (const model of MODELS) {
      const remaining = budget();
      if (remaining < MIN_ATTEMPT_MS) break;
      try {
        const result = await geminiImage(prompt, ratio, apiKey, model, Math.min(remaining, 25000));
        return imageResponse(result, ratio);
      } catch (e) {
        lastError = e;
        // Inutile d'essayer les autres modèles : le quota ou le filtre s'appliquent au compte.
        if (e.code === 'quota' || e.code === 'blocked') break;
      }
    }
  } else {
    lastError = new ImageError('GEMINI_API_KEY manquante', 'unavailable', 500);
  }

  const code = lastError?.code || 'unavailable';
  const status = lastError?.status && lastError.status >= 400 ? lastError.status : 503;
  return json(
    {
      error: MESSAGES[code] || MESSAGES.unavailable,
      code,
      detail: lastError?.message ? String(lastError.message).slice(0, 300) : undefined,
    },
    status
  );
}
