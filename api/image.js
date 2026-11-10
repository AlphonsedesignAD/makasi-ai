// api/image.js — Génération d'image via Gemini Imagen (Vercel Edge)
// Utilise gemini-3.1-flash-image puis fallback gemini-2.5-flash-image
export const config = { runtime: 'edge' };

const jsonRes = (o, s = 200) =>
  new Response(JSON.stringify(o), {
    status: s,
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
  });

// Enrichir le prompt français → anglais via un appel rapide à Gemini
async function enhance(prompt, key) {
  try {
    const r = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent?key=${key}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        signal: AbortSignal.timeout(5000),
        body: JSON.stringify({
          contents: [
            {
              parts: [
                {
                  text: `You are an expert prompt engineer for AI image generators. Rewrite this request as one single detailed English prompt for an AI image generator. Include subject, style, lighting, composition, colors, and quality. Output ONLY the prompt, nothing else. Max 80 words.\n\nRequest: ${prompt}`,
                },
              ],
            },
          ],
          generationConfig: { maxOutputTokens: 200 },
        }),
      }
    );
    const t = (await r.json())?.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
    return t || prompt;
  } catch {
    return prompt;
  }
}

// Tente la génération Gemini Imagen
async function generateWithGeminiImagen(prompt, key, model, timeoutMs) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`;

  const body = {
    contents: [
      {
        parts: [{ text: `Generate a high quality image: ${prompt}` }],
      },
    ],
    generationConfig: {
      responseModalities: ['IMAGE', 'TEXT'],
      maxOutputTokens: 4096,
    },
  };

  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    signal: AbortSignal.timeout(timeoutMs),
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text().catch(() => '');
    throw new Error(`Gemini ${model} ${res.status}: ${errText.slice(0, 200)}`);
  }

  const data = await res.json();
  const parts = data?.candidates?.[0]?.content?.parts;
  if (!parts) throw new Error('No content in response');

  // Chercher la partie image (inline_data)
  const imgPart = parts.find((p) => p.inlineData);
  if (imgPart && imgPart.inlineData) {
    const { mimeType, data: b64 } = imgPart.inlineData;
    const binary = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    return new Response(binary, {
      headers: {
        'Content-Type': mimeType || 'image/png',
        'Cache-Control': 'public, max-age=31536000, s-maxage=31536000, immutable',
        'Access-Control-Allow-Origin': '*',
      },
    });
  }

  throw new Error('No image generated');
}

// Fallback Pollinations (dernier recours)
async function generateWithPollinations(prompt, seed) {
  const q = encodeURIComponent(prompt);
  const attempts = [
    ['flux', 1024, 15000],
    ['turbo', 768, 8000],
  ];
  for (const [model, size, ms] of attempts) {
    try {
      const url = `https://image.pollinations.ai/prompt/${q}?model=${model}&width=${size}&height=${size}&seed=${seed}&nologo=true`;
      const r = await fetch(url, { signal: AbortSignal.timeout(ms) });
      const type = r.headers.get('content-type') || '';
      if (r.ok && type.startsWith('image/')) {
        return new Response(r.body, {
          headers: {
            'Content-Type': type,
            'Cache-Control': 'public, max-age=31536000, immutable',
            'Access-Control-Allow-Origin': '*',
          },
        });
      }
    } catch {
      /* next */
    }
  }
  return null;
}

export default async function handler(req) {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
      },
    });
  }

  const u = new URL(req.url);
  const rawPrompt = (u.searchParams.get('prompt') || '').trim().slice(0, 500);
  const seed = parseInt(u.searchParams.get('seed'), 10) || 1;
  if (!rawPrompt) return jsonRes({ error: 'prompt manquant' }, 400);

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) return jsonRes({ error: 'API key not configured' }, 500);

  // Enrichir le prompt
  const enhancedPrompt = await enhance(rawPrompt, apiKey);

  // 1. Essayer Gemini 3.1 Flash Image (meilleur)
  try {
    return await generateWithGeminiImagen(enhancedPrompt, apiKey, 'gemini-3.1-flash-image', 25000);
  } catch (e) {
    console.log('[image] gemini-3.1-flash-image failed:', e.message);
  }

  // 2. Fallback Gemini 2.5 Flash Image
  try {
    return await generateWithGeminiImagen(enhancedPrompt, apiKey, 'gemini-2.5-flash-image', 20000);
  } catch (e) {
    console.log('[image] gemini-2.5-flash-image failed:', e.message);
  }

  // 3. Dernier recours : Pollinations
  const pollinationsRes = await generateWithPollinations(enhancedPrompt, seed);
  if (pollinationsRes) return pollinationsRes;

  return jsonRes({ error: 'Tous les services image sont indisponibles. Réessayez.' }, 503);
}
