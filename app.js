/* ============================================================
   MAKASI AI — Logique Frontend & Traitement Multimodal
   Créé avec Alphonse Design (WhatsApp : 0971404824)
   ============================================================ */

const CONFIG = {
  API_URL: '/api/chat',
  SYSTEM_PROMPT: `Tu es Makasi AI, un assistant d'élite intelligent, créatif, percutant et très chaleureux.
Tu as été conçu et développé par ALPHONSE DESIGN, designer et développeur web expert.

RÈGLES DE CONVERSATION :
1. Réponds de façon précise, naturelle, directe et structurée à TOUTES les questions des utilisateurs (code, explications, rédaction, devoirs, analyse de fichiers joints, conseils).
2. N'ajoute PAS de lien WhatsApp inutilement à chaque réponse ! Réponds simplement et efficacement à ce qui est demandé.
3. UNIQUEMENT si l'utilisateur te demande :
   - qui t'a créé ou qui est ton développeur,
   - des services de création de site web, logo, design graphique ou IA sur mesure,
   - ou un contact / devis professionnel,
   ALORS présente Alphonse Design avec fierté et donne son contact : WhatsApp / Téléphone : 0971404824 (https://wa.me/243971404824).
4. Lorsque l'utilisateur joint un fichier ou du code, analyse-le attentivement, résume-le ou réponds précisément aux instructions demandées sur ce document.

5. Adapte-toi toujours à la langue de l'utilisateur (français, lingala, swahili, anglais...).`,
  IMAGE_URL: '/api/image',
  MAX_HISTORY: 20
};

/* Format de la requête envoyé à /api/chat */
function buildRequest(messages) {
  const headers = { 'Content-Type': 'application/json' };
  const contents = messages.map(({ role, parts }) => ({
    role: role === 'assistant' ? 'model' : 'user',
    parts: Array.isArray(parts) ? parts : [{ text: parts || '' }]
  }));
  const body = {
    system_instruction: { parts: [{ text: CONFIG.SYSTEM_PROMPT }] },
    contents
  };
  return { headers, body: JSON.stringify(body) };
}

/* Extraction du token d'un chunk SSE Gemini */
function parseChunk(data) {
  return data?.candidates?.[0]?.content?.parts?.[0]?.text ?? '';
}

/* ============================================================
   Éléments DOM & État
   ============================================================ */
const $ = (id) => document.getElementById(id);
const ic = (n) => `<svg class="ic"><use href="#i-${n}"/></svg>`;
const rnd = () => Math.floor(Math.random() * 9e6) + 1e6;
const el = {
  app: $('app'), history: $('history'), search: $('search'), scroll: $('scroll'),
  messages: $('messages'), input: $('input'), form: $('form'), send: $('send'), stop: $('stop'),
  title: $('chatTitle'), greeting: $('greeting'), chips: $('chips'), toast: $('toast'),
  micBtn: $('micBtn'), voiceBar: $('voiceBar'), voiceText: $('voiceText'), cancelVoice: $('cancelVoice'),
  exportChatBtn: $('exportChatBtn'), attachBtn: $('attachBtn'), fileInput: $('fileInput'),
  filePreviewBar: $('filePreviewBar'), fileName: $('fileName'), fileSize: $('fileSize'),
  fileIcon: $('fileIcon'), removeFileBtn: $('removeFileBtn')
};

const KEY = 'makasi.chats', KEY_ACTIVE = 'makasi.active';
let chats = load(KEY, []);
let activeId = localStorage.getItem(KEY_ACTIVE);
let controller = null;
let busy = false;
let currentUtterance = null;
let recognition = null;
let isRecording = false;

// Fichier actuellement attaché en attente d'envoi
let currentAttachedFile = null;

function load(k, fb) { try { return JSON.parse(localStorage.getItem(k)) ?? fb; } catch { return fb; } }
function save() {
  try {
    localStorage.setItem(KEY, JSON.stringify(chats));
    localStorage.setItem(KEY_ACTIVE, activeId || '');
  } catch {
    toast('Stockage plein : supprimez d’anciennes discussions.');
  }
}

const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
const active = () => chats.find((c) => c.id === activeId);

function toast(msg) {
  el.toast.textContent = msg;
  el.toast.classList.add('show');
  clearTimeout(toast.t);
  toast.t = setTimeout(() => el.toast.classList.remove('show'), 2200);
}

/* ---------- Détection et Extraction des Requêtes d'Images ---------- */
function isImageRequest(text) {
  const t = (text || '').toLowerCase().trim();
  if (/^\/(image|img)\b/.test(t)) return true;
  if (/docker|conteneur|container|\biso\b|code\b|python|javascript/.test(t)) return false;
  return /\b(g[ée]n[èe]re[rz]?|cr[ée]+[rz]?|dessine[rz]?|fais|produis|generate|draw|create|make)\b[^.!?\n]{0,25}\b(image|photo|illustration|dessin|picture)\b/.test(t);
}

function extractImagePrompt(text) {
  const c = text.replace(/^\/(image|img)\s*/i, '')
    .replace(/^.*?\b(image|photo|illustration|dessin|picture)s?\b\s*(?:de |d'|du |des |sur |of |:)?\s*/i, '').trim();
  return c || text;
}

/* Format demandé dans la phrase (16:9, portrait, paysage…) */
function detectImageRatio(text) {
  const t = (text || '').toLowerCase();
  if (/\b16\s*[:/x]\s*9\b/.test(t)) return '16:9';
  if (/\b9\s*[:/x]\s*16\b/.test(t)) return '9:16';
  if (/\b4\s*[:/x]\s*3\b/.test(t)) return '4:3';
  if (/\b3\s*[:/x]\s*4\b/.test(t)) return '3:4';
  if (/\b(carr[ée]|square|1\s*[:/x]\s*1)\b/.test(t)) return '1:1';
  if (/\b(paysage|horizontal|landscape|banni[èe]re|banner|wide)\b/.test(t)) return '16:9';
  if (/\b(portrait|vertical|story|stories|tiktok|r[ée]el)\b/.test(t)) return '9:16';
  return '1:1';
}

/* Style demandé (photo, illustration, 3D, anime, logo) */
function detectImageStyle(text) {
  const t = (text || '').toLowerCase();
  if (/\b(logo|ic[ôo]ne|icon|embl[èe]me)\b/.test(t)) return 'logo';
  if (/\b(anime|manga|cartoon|dessin anim[ée])\b/.test(t)) return 'anime';
  if (/\b(3d|rendu|render)\b/.test(t)) return '3d';
  if (/\b(illustration|dessin|aquarelle|peinture|art|drawing|painting)\b/.test(t)) return 'illustration';
  if (/\b(photo|photor[ée]aliste|r[ée]aliste|realistic)\b/.test(t)) return 'photo';
  return '';
}

/* ---------- Markdown léger & soigné ---------- */
const esc = (s) => (s || '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function inline(s) {
  return s.split(/(`[^`\n]+`)/g).map((part, i) => {
    if (i % 2) return '<code>' + part.slice(1, -1) + '</code>';
    return part
      .replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>')
      .replace(/(^|[^*])\*([^*\n]+)\*/g, '$1<em>$2</em>')
      .replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');
  }).join('');
}

function md(text) {
  if (!text) return '';

  // 1. Extraire les blocs de code d'abord
  const blocks = [];
  let s = text.replace(/```([\w+-]*)\n?([\s\S]*?)(```|$)/g, (_, lang, code) => {
    blocks.push({ lang, code: code.replace(/\n$/, '') });
    return `\n\x00${blocks.length - 1}\x00\n`;
  });

  // 2. Extraire les blocs d'images Markdown ![alt](url)
  const imgBlocks = [];
  s = s.replace(/!\[([^\]]*)\]\((https?:\/\/[^\s)]+)\)/g, (_, alt, url) => {
    imgBlocks.push({ alt: alt.trim(), url: url.trim() });
    return `\n\x01${imgBlocks.length - 1}\x01\n`;
  });

  // 3. Échapper le reste en toute sécurité
  s = esc(s);

  const out = [];
  let list = null;
  let para = [];

  const flushP = () => {
    if (para.length) {
      out.push('<p>' + inline(para.join('<br>')) + '</p>');
      para = [];
    }
  };
  const flushL = () => {
    if (list) {
      out.push(`</${list}>`);
      list = null;
    }
  };

  for (const line of s.split('\n')) {
    let m;
    if ((m = line.match(/^\x00(\d+)\x00$/))) {
      flushP(); flushL();
      const b = blocks[+m[1]];
      const langLabel = esc(b.lang || 'code');
      out.push(`
        <div class="codeblock">
          <div class="codehead">
            <div class="codehead-left">
              <span class="term-dots"><i class="dot-r"></i><i class="dot-y"></i><i class="dot-g"></i></span>
              <span class="code-lang">${langLabel}</span>
            </div>
            <button class="code-copy-btn" data-copy aria-label="Copier le code">
              <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V6a2 2 0 0 1 2-2h8"/></svg>
              <span>Copier</span>
            </button>
          </div>
          <pre><code class="language-${langLabel}">${esc(b.code)}</code></pre>
        </div>
      `);
    } else if ((m = line.match(/^\x01(\d+)\x01$/))) {
      flushP(); flushL();
      const img = imgBlocks[+m[1]];
      out.push(`<img class="mdimg" src="${esc(img.url)}" alt="${esc(img.alt)}" loading="lazy">`);
    } else if ((m = line.match(/^(#{1,3})\s+(.*)/))) {
      flushP(); flushL(); out.push(`<h${m[1].length}>${inline(m[2])}</h${m[1].length}>`);
    } else if ((m = line.match(/^\s*[-*•]\s+(.*)/))) {
      flushP(); if (list !== 'ul') { flushL(); out.push('<ul>'); list = 'ul'; } out.push('<li>' + inline(m[1]) + '</li>');
    } else if ((m = line.match(/^\s*\d+[.)]\s+(.*)/))) {
      flushP(); if (list !== 'ol') { flushL(); out.push('<ol>'); list = 'ol'; } out.push('<li>' + inline(m[1]) + '</li>');
    } else if ((m = line.match(/^&gt;\s?(.*)/))) {
      flushP(); flushL(); out.push('<blockquote>' + inline(m[1]) + '</blockquote>');
    } else if (!line.trim()) {
      flushP(); flushL();
    } else {
      flushL();
      para.push(line);
    }
  }
  flushP(); flushL();
  return out.join('');
}

/* ---------- Synthèse Vocale (Text-to-Speech) ---------- */
function toggleSpeech(text, btn) {
  if (!('speechSynthesis' in window)) {
    toast('Audio non supporté sur ce navigateur.');
    return;
  }

  if (window.speechSynthesis.speaking) {
    window.speechSynthesis.cancel();
    document.querySelectorAll('[data-act="speak"]').forEach(b => {
      b.classList.remove('tts-speaking');
      b.innerHTML = ic('speaker');
    });
    if (btn && currentUtterance && currentUtterance.__btn === btn) {
      currentUtterance = null;
      return;
    }
  }

  const cleanText = text
    .replace(/```[\s\S]*?```/g, 'Bloc de code.')
    .replace(/[#*_`[\]()]/g, ' ')
    .replace(/https?:\/\/\S+/g, 'lien web')
    .trim();

  if (!cleanText) return;

  const utter = new SpeechSynthesisUtterance(cleanText);
  utter.__btn = btn;
  utter.rate = 1.05;

  const voices = window.speechSynthesis.getVoices();
  const frVoice = voices.find(v => v.lang.startsWith('fr')) || voices[0];
  if (frVoice) utter.voice = frVoice;

  btn.classList.add('tts-speaking');
  btn.innerHTML = ic('stop');

  utter.onend = () => {
    btn.classList.remove('tts-speaking');
    btn.innerHTML = ic('speaker');
    currentUtterance = null;
  };
  utter.onerror = () => {
    btn.classList.remove('tts-speaking');
    btn.innerHTML = ic('speaker');
    currentUtterance = null;
  };

  currentUtterance = utter;
  window.speechSynthesis.speak(utter);
}

/* ---------- Images générées ---------- */
const IMAGE_RATIOS = ['1:1', '16:9', '9:16', '4:3', '3:4'];
const imgCache = new Map();

function fetchImage({ prompt, seed, ratio, style }, onStatus) {
  const key = [prompt, seed, ratio, style].join('|');
  if (imgCache.has(key)) return imgCache.get(key);
  const p = (async () => {
    let lastErr = null;
    for (let i = 0; i < 2; i++) {
      if (i) {
        if (onStatus) onStatus('Nouvel essai…');
        await new Promise((res) => setTimeout(res, 1500));
      }
      try {
        const r = await fetch(CONFIG.IMAGE_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ prompt, seed, ratio, style }),
        });
        const type = (r.headers.get('content-type') || '').split(';')[0];
        if (r.ok && type.startsWith('image/')) {
          const b = await r.blob();
          return { url: URL.createObjectURL(b), mime: b.type || type };
        }
        let msg = '';
        try { msg = (await r.json())?.error || ''; } catch (_) {}
        lastErr = new Error(msg || `Erreur ${r.status}`);
        // Erreur définitive (demande invalide, sécurité…) : inutile de réessayer.
        if (r.status < 500) break;
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr || new Error('L’image n’a pas pu être créée.');
  })();
  imgCache.set(key, p);
  p.catch(() => imgCache.delete(key));
  return p;
}

function imageCard(img) {
  const ratio = img.ratio || '1:1';
  const ratios = IMAGE_RATIOS.map(
    (r) => `<button type="button" data-ratio="${r}" aria-pressed="${r === ratio}">${r}</button>`
  ).join('');
  return `<figure class="imgcard" data-state="loading" data-prompt="${esc(img.prompt)}" data-seed="${img.seed}" data-ratio="${ratio}" data-style="${esc(img.style || '')}">
    <div class="imgframe" style="--ratio:${ratio.replace(':', '/')}"><img alt="${esc(img.prompt)}" loading="lazy">
      <div class="imgph"><span>Création de l’image…</span></div>
      <div class="imgerr"><span>L’image n’a pas pu être créée.</span><button type="button" data-img="regen">${ic('refresh')} Réessayer</button></div>
    </div>
    <figcaption>
      <div class="imgratios" role="group" aria-label="Format de l’image">${ratios}</div>
      <span class="cap">${esc(img.prompt)}</span>
      <button type="button" class="icon-btn sm" data-img="regen" title="Nouvelle variante" aria-label="Nouvelle variante">${ic('refresh')}</button>
      <a class="icon-btn sm" data-img="dl" download="makasi-image.png" title="Télécharger" aria-label="Télécharger">${ic('download')}</a>
    </figcaption></figure>`;
}

function hydrate(card) {
  const { prompt, style } = card.dataset;
  const seed = +card.dataset.seed;
  const ratio = card.dataset.ratio || '1:1';
  const st = card.querySelector('.imgph span');
  const err = card.querySelector('.imgerr span');
  card.dataset.state = 'loading';
  st.textContent = 'Création de l’image…';
  const slow = setTimeout(() => {
    if (card.dataset.state === 'loading') st.textContent = 'Encore quelques secondes…';
  }, 9000);

  fetchImage({ prompt, seed, ratio, style }, (m) => { if (m) st.textContent = m; })
    .then(({ url, mime }) => {
      card.querySelector('img').src = url;
      const dl = card.querySelector('[data-img="dl"]');
      dl.href = url;
      dl.download = 'makasi-image.' + (/jpeg|jpg/.test(mime) ? 'jpg' : /webp/.test(mime) ? 'webp' : 'png');
      card.dataset.state = 'ready';
    })
    .catch((e) => {
      err.textContent = e?.message || 'L’image n’a pas pu être créée.';
      card.dataset.state = 'error';
    })
    .finally(() => clearTimeout(slow));
}

/* ---------- Rendu des Messages ---------- */
function msgNode(m, idx) {
  const d = document.createElement('div');
  d.className = 'msg ' + (m.role === 'user' ? 'user' : 'bot') + (m.error ? ' err' : '');
  d.dataset.idx = idx;

  if (m.role === 'user') {
    let fileBadgeHtml = '';
    if (m.attachment) {
      fileBadgeHtml = `<div class="attached-file-badge">${ic('clip')} ${esc(m.attachment.name)}</div>`;
    }
    d.innerHTML = `<div class="body">${fileBadgeHtml}<div class="user-text"></div></div>`;
    d.querySelector('.user-text').textContent = m.displayText || m.content || '';
  } else {
    d.innerHTML = `
      <div class="avatar">${ic('logo')}</div>
      <div class="content-wrap">
        <div class="body"></div>
        ${m.image ? '' : `<div class="actions">
          <button data-act="copy" title="Copier" aria-label="Copier">${ic('copy')}</button>
          <button data-act="speak" title="Écouter" aria-label="Écouter">${ic('speaker')}</button>
          <button data-act="retry" title="Régénérer" aria-label="Régénérer">${ic('refresh')}</button>
        </div>`}
      </div>`;
    d.querySelector('.body').innerHTML =
      (m.image ? imageCard(m.image) : '') +
      md(m.content || '');
  }
  return d;
}

function renderMessages() {
  const c = active();
  el.messages.innerHTML = '';
  el.app.classList.toggle('has-msgs', !!(c && c.messages.length));
  el.title.textContent = c && c.title ? c.title : 'Makasi AI';
  document.title = c && c.title ? c.title + ' · Makasi AI' : 'Makasi AI';
  if (c) c.messages.forEach((m, i) => el.messages.appendChild(msgNode(m, i)));
  el.messages.querySelectorAll('.imgcard[data-state="loading"]').forEach(hydrate);
  scrollDown(false);
}

function renderHistory() {
  const q = el.search.value.trim().toLowerCase();
  const list = chats.filter((c) => !q || (c.title || '').toLowerCase().includes(q) || c.messages.some((m) => (m.content || '').toLowerCase().includes(q)))
    .sort((a, b) => b.updated - a.updated);
  el.history.innerHTML = '';
  if (!list.length) {
    el.history.innerHTML = '<div class="empty-hist">' + (q ? 'Aucun résultat.' : 'Historique vide.') + '</div>';
    return;
  }

  const day = 864e5;
  const groups = [['Aujourd’hui', 0], ['Hier', day], ['7 derniers jours', 7 * day], ['Plus ancien', Infinity]];
  const buckets = groups.map(() => []);

  list.forEach((c) => {
    const startToday = new Date().setHours(0, 0, 0, 0), age = startToday - c.updated;
    const i = c.updated >= startToday ? 0 : age <= day ? 1 : age <= 7 * day ? 2 : 3;
    buckets[i].push(c);
  });

  buckets.forEach((b, i) => {
    if (!b.length) return;
    const l = document.createElement('div');
    l.className = 'group-label';
    l.textContent = groups[i][0];
    el.history.appendChild(l);

    b.forEach((c) => {
      const it = document.createElement('div');
      it.className = 'item' + (c.id === activeId ? ' active' : '');
      it.innerHTML = '<button class="t"></button><button class="x" aria-label="Supprimer" title="Supprimer">' + ic('x') + '</button>';
      it.querySelector('.t').textContent = c.title || 'Nouvelle discussion';
      it.querySelector('.t').onclick = () => { openChat(c.id); closeSide(); };
      it.querySelector('.x').onclick = (e) => { e.stopPropagation(); removeChat(c.id); };
      el.history.appendChild(it);
    });
  });
}

function scrollDown(smooth = true) {
  el.scroll.style.scrollBehavior = smooth ? 'smooth' : 'auto';
  el.scroll.scrollTop = el.scroll.scrollHeight;
}

/* ---------- Gestion des Conversations ---------- */
function newChat() {
  if (busy) return;
  const c = active();
  if (c && !c.messages.length) { el.input.focus(); return; }
  const n = { id: uid(), title: '', messages: [], updated: Date.now() };
  chats.push(n);
  activeId = n.id;
  clearAttachment();
  save();
  renderHistory();
  renderMessages();
  el.input.focus();
}

function openChat(id) {
  if (busy) return;
  activeId = id;
  clearAttachment();
  save();
  renderHistory();
  renderMessages();
}

function removeChat(id) {
  if (busy && id === activeId) return;
  chats = chats.filter((c) => c.id !== id);
  if (activeId === id) activeId = chats.length ? chats.sort((a, b) => b.updated - a.updated)[0].id : null;
  save();
  renderHistory();
  renderMessages();
}

/* ---------- Exportation de Conversation ---------- */
function exportCurrentChat() {
  const c = active();
  if (!c || !c.messages.length) {
    toast('Aucun message à exporter.');
    return;
  }
  let mdContent = `# ${c.title || 'Discussion Makasi AI'}\n\n`;
  c.messages.forEach(m => {
    let body = m.displayText || m.content;
    if (m.image) body = `[Image générée : ${m.image.prompt}]`;
    mdContent += `### ${m.role === 'user' ? 'Vous' : 'Makasi AI'}\n\n${body}\n\n---\n\n`;
  });

  const blob = new Blob([mdContent], { type: 'text/markdown;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `makasi-ai-${c.title ? c.title.slice(0, 20).replace(/\s+/g, '_') : 'discussion'}.md`;
  a.click();
  URL.revokeObjectURL(url);
  toast('Discussion exportée !');
}

/* ---------- Gestion des Fichiers Joints ---------- */
function formatFileSize(bytes) {
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

function getFileIcon(name, type) {
  if (type.startsWith('image/')) return 'image';
  if (/\.(js|ts|py|html|css|json|sql|php|cpp|c|java)$/i.test(name)) return 'code';
  if (/\.(csv|xlsx)$/i.test(name)) return 'table';
  return 'file';
}

async function handleFileSelect(file) {
  if (!file) return;

  // Limite de taille : 10MB
  if (file.size > 10 * 1024 * 1024) {
    toast('Fichier trop volumineux (maximum 10 MB).');
    return;
  }

  const isImage = file.type.startsWith('image/');

  try {
    if (isImage) {
      // Lecture Base64 pour image
      const base64Data = await new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result.split(',')[1]);
        reader.onerror = reject;
        reader.readAsDataURL(file);
      });

      currentAttachedFile = {
        name: file.name,
        size: formatFileSize(file.size),
        type: file.type,
        isImage: true,
        base64: base64Data
      };
    } else {
      // Lecture texte pour code / documents texte
      const textContent = await new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = reject;
        reader.readAsText(file);
      });

      currentAttachedFile = {
        name: file.name,
        size: formatFileSize(file.size),
        type: file.type || 'text/plain',
        isImage: false,
        text: textContent
      };
    }

    // Affichage dans la barre de prévisualisation
    el.fileName.textContent = currentAttachedFile.name;
    el.fileSize.textContent = currentAttachedFile.size;
    el.fileIcon.innerHTML = ic(getFileIcon(file.name, file.type));
    el.filePreviewBar.hidden = false;
    refreshSend();
    el.input.focus();
    toast(`Fichier "${file.name}" attaché !`);

  } catch (err) {
    console.error('Erreur lecture fichier:', err);
    toast('Impossible de lire ce fichier.');
    clearAttachment();
  }
}

function clearAttachment() {
  currentAttachedFile = null;
  el.filePreviewBar.hidden = true;
  el.fileInput.value = '';
  refreshSend();
}

/* ---------- Envoi & Streaming ---------- */
function setBusy(b) {
  busy = b;
  el.stop.hidden = !b;
  el.send.hidden = b;
  el.input.disabled = false;
  refreshSend();
  const dot = document.getElementById('statusDot');
  if (dot) {
    dot.classList.toggle('busy', b);
    dot.title = b ? 'Génération en cours…' : 'Connecté';
  }
}

function refreshSend() {
  const hasText = !!el.input.value.trim();
  const hasFile = !!currentAttachedFile;
  el.send.disabled = busy || (!hasText && !hasFile);
}

async function ask(c) {
  const last = c.messages[c.messages.length - 1];
  const lastText = last ? (last.displayText || last.content || '') : '';

  // Demande d'image : génération dédiée, sans passer par le chat texte
  if (last && !last.attachment && isImageRequest(lastText)) {
    const prompt = extractImagePrompt(lastText);
    c.messages.push({
      role: 'assistant',
      content: '',
      image: { prompt, seed: rnd(), ratio: detectImageRatio(lastText), style: detectImageStyle(lastText) },
    });
    c.updated = Date.now();
    save(); renderMessages(); renderHistory(); scrollDown();
    return;
  }

  setBusy(true);
  const holder = document.createElement('div');
  holder.className = 'msg bot';
  holder.innerHTML = `<div class="avatar">${ic('logo')}</div><div class="content-wrap"><div class="body"><span class="typing"><i></i><i></i><i></i></span></div></div>`;
  el.messages.appendChild(holder);
  scrollDown();
  const bodyEl = holder.querySelector('.body');

  controller = new AbortController();
  let fullText = '';

  try {
    const history = c.messages.filter((m) => !m.error && !m.image).slice(-CONFIG.MAX_HISTORY)
      .map((m) => ({ role: m.role, parts: m.parts || [{ text: m.content || '' }] }));

    const { headers, body } = buildRequest(history);
    const res = await fetch(CONFIG.API_URL, { method: 'POST', headers, body, signal: controller.signal });

    if (!res.ok) {
      let friendly = '';
      try {
        const errJson = await res.json();
        friendly = typeof errJson?.error === 'string' ? errJson.error : errJson?.error?.message || '';
      } catch (_) {}
      const err = new Error(friendly || `Le service Gemini est indisponible (erreur ${res.status}).`);
      err.friendly = true;
      throw err;
    }

    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buf = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += decoder.decode(value, { stream: true });
      const lines = buf.split('\n');
      buf = lines.pop();

      for (const line of lines) {
        if (!line.startsWith('data: ')) continue;
        const raw = line.slice(6).trim();
        if (!raw || raw === '[DONE]') continue;
        try {
          const token = parseChunk(JSON.parse(raw));
          if (token) {
            fullText += token;
            bodyEl.innerHTML = md(fullText);
            scrollDown();
          }
        } catch { /* chunk partiel ignoré */ }
      }
    }

    if (!fullText) throw new Error('Réponse vide.');
    c.messages.push({ role: 'assistant', content: fullText.trim(), parts: [{ text: fullText.trim() }] });

  } catch (e) {
    if (e.name === 'AbortError') {
      c.messages.push({ role: 'assistant', content: '_Génération interrompue._', error: false });
    } else {
      console.error('[Makasi]', e);
      const message = e.friendly
        ? e.message
        : 'Désolé, je n’ai pas pu répondre. Vérifiez votre connexion puis réessayez.';
      c.messages.push({ role: 'assistant', content: message, error: true });
    }
  }

  c.updated = Date.now();
  save();
  controller = null;
  setBusy(false);
  renderMessages();
  renderHistory();
  scrollDown();
}

function send(text) {
  text = text.trim();
  const attached = currentAttachedFile;

  if (!text && !attached) return;
  if (busy) return;

  let c = active();
  if (!c) {
    c = { id: uid(), title: '', messages: [], updated: Date.now() };
    chats.push(c);
    activeId = c.id;
  }

  // Préparation du message utilisateur et de ses parts
  const userParts = [];
  let userDisplayText = text;

  if (attached) {
    if (attached.isImage) {
      userParts.push({
        inline_data: {
          mime_type: attached.type,
          data: attached.base64
        }
      });
      const promptText = text || 'Analyse cette image.';
      userParts.push({ text: promptText });
      if (!userDisplayText) userDisplayText = 'Analyse de l\'image jointe';
    } else {
      // Document / Code / Texte
      const fileHeader = `[Fichier joint : ${attached.name}]\n\`\`\`\n${attached.text}\n\`\`\`\n\n`;
      const fullPrompt = fileHeader + (text || 'Voici un fichier. Analyse son contenu et résume-le ou aide-moi dessus.');
      userParts.push({ text: fullPrompt });
      if (!userDisplayText) userDisplayText = `Analyse du fichier ${attached.name}`;
    }
  } else {
    userParts.push({ text: text });
  }

  if (!c.messages.length) {
    c.title = userDisplayText.length > 36 ? userDisplayText.slice(0, 36).trim() + '…' : userDisplayText;
  }

  c.messages.push({
    role: 'user',
    content: text || (attached ? attached.name : ''),
    displayText: userDisplayText,
    parts: userParts,
    attachment: attached ? { name: attached.name, size: attached.size } : null
  });

  c.updated = Date.now();
  save();

  // Reset champ et pièce jointe
  el.input.value = '';
  clearAttachment();
  autosize();
  refreshSend();
  renderMessages();
  renderHistory();
  ask(c);
}

/* ---------- Reconnaissance Vocale (Speech-to-Text) ---------- */
function initVoiceRecognition() {
  const SpeechRec = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRec) {
    el.micBtn.style.display = 'none';
    return;
  }

  recognition = new SpeechRec();
  recognition.lang = 'fr-FR';
  recognition.continuous = false;
  recognition.interimResults = true;

  recognition.onstart = () => {
    isRecording = true;
    el.micBtn.classList.add('active');
    el.voiceBar.hidden = false;
    el.voiceText.textContent = 'Parlez... Makasi AI écoute';
  };

  recognition.onresult = (e) => {
    const transcript = Array.from(e.results).map(r => r[0].transcript).join('');
    el.input.value = transcript;
    autosize();
    refreshSend();
    el.voiceText.textContent = `"${transcript}"`;
  };

  recognition.onerror = () => {
    isRecording = false;
    el.micBtn.classList.remove('active');
    el.voiceBar.hidden = true;
  };

  recognition.onend = () => {
    isRecording = false;
    el.micBtn.classList.remove('active');
    el.voiceBar.hidden = true;
    if (el.input.value.trim()) {
      el.input.focus();
    }
  };

  el.micBtn.addEventListener('click', () => {
    if (isRecording) {
      recognition.stop();
    } else {
      try {
        recognition.start();
      } catch (err) {
        recognition.stop();
      }
    }
  });

  el.cancelVoice.addEventListener('click', () => {
    if (recognition) recognition.abort();
  });
}

/* ---------- Événements ---------- */
function autosize() {
  el.input.style.height = 'auto';
  el.input.style.height = Math.min(el.input.scrollHeight, 160) + 'px';
}

el.input.addEventListener('input', () => { autosize(); refreshSend(); });
el.input.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && innerWidth > 768) {
    e.preventDefault();
    send(el.input.value);
  }
});
el.form.addEventListener('submit', (e) => { e.preventDefault(); send(el.input.value); });
el.stop.addEventListener('click', () => controller && controller.abort());
$('newChat').onclick = () => { newChat(); closeSide(); };
el.search.addEventListener('input', renderHistory);
if (el.exportChatBtn) el.exportChatBtn.onclick = exportCurrentChat;

// Événements Fichiers
el.attachBtn.addEventListener('click', () => el.fileInput.click());
el.fileInput.addEventListener('change', (e) => {
  const file = e.target.files && e.target.files[0];
  if (file) handleFileSelect(file);
});
el.removeFileBtn.addEventListener('click', clearAttachment);

$('clearAll').onclick = () => {
  if (!chats.length) return;
  if (confirm('Voulez-vous supprimer toutes vos discussions ?')) {
    chats = [];
    activeId = null;
    save();
    renderHistory();
    renderMessages();
    toast('Discussions effacées.');
  }
};

el.messages.addEventListener('click', async (e) => {
  const copyCode = e.target.closest('[data-copy]');
  if (copyCode) {
    const code = copyCode.closest('.codeblock').querySelector('code').textContent;
    await navigator.clipboard.writeText(code);
    copyCode.classList.add('copied');
    copyCode.innerHTML = `<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M20 6L9 17l-5-5"/></svg><span>Copié !</span>`;
    setTimeout(() => {
      copyCode.classList.remove('copied');
      copyCode.innerHTML = `<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V6a2 2 0 0 1 2-2h8"/></svg><span>Copier</span>`;
    }, 1800);
    return;
  }

  const ratioBtn = e.target.closest('.imgratios [data-ratio]');
  if (ratioBtn) {
    const card = ratioBtn.closest('.imgcard');
    const ratio = ratioBtn.dataset.ratio;
    if (card && ratio && ratio !== card.dataset.ratio) {
      const c = active(), m = c && c.messages[+card.closest('.msg')?.dataset.idx];
      card.dataset.ratio = ratio;
      card.querySelector('.imgframe').style.setProperty('--ratio', ratio.replace(':', '/'));
      card.querySelectorAll('.imgratios [data-ratio]').forEach((b) => b.setAttribute('aria-pressed', String(b === ratioBtn)));
      card.dataset.seed = rnd();
      if (m && m.image) { m.image.ratio = ratio; m.image.seed = +card.dataset.seed; save(); }
      hydrate(card);
    }
    return;
  }

  const imgBtn = e.target.closest('[data-img]');
  if (imgBtn) {
    const card = imgBtn.closest('.imgcard');
    if (card && imgBtn.dataset.img === 'regen') {
      const c = active(), m = c && c.messages[+card.closest('.msg')?.dataset.idx];
      card.dataset.seed = rnd();
      if (m && m.image) { m.image.seed = +card.dataset.seed; save(); }
      hydrate(card);
    }
    return;
  }

  const b = e.target.closest('[data-act]');
  if (!b || busy) return;
  const c = active();
  const idx = +b.closest('.msg').dataset.idx;

  if (b.dataset.act === 'copy') {
    await navigator.clipboard.writeText(c.messages[idx].content);
    toast('Réponse copiée !');
  } else if (b.dataset.act === 'speak') {
    toggleSpeech(c.messages[idx].content, b);
  } else if (b.dataset.act === 'retry') {
    c.messages.splice(idx);
    save();
    renderMessages();
    ask(c);
  }
});

/* Menu mobile */
const openSide = () => el.app.classList.add('side-open');
const closeSide = () => el.app.classList.remove('side-open');
$('openSide').onclick = openSide;
$('closeSide').onclick = closeSide;
$('scrim').onclick = closeSide;

/* Thème */
function applyTheme(t) {
  if (t) document.documentElement.dataset.theme = t;
  const dark = document.documentElement.dataset.theme !== 'light';
  $('themeIcon').innerHTML = ic(dark ? 'sun' : 'moon');
  document.querySelector('meta[name="theme-color"]').content = dark ? '#131314' : '#ffffff';
}
$('themeBtn').onclick = () => {
  const next = document.documentElement.dataset.theme === 'light' ? 'dark' : 'light';
  try { localStorage.setItem('makasi.theme', next); } catch (e) {}
  applyTheme(next);
};

/* ---------- Démarrage & Suggestions Normales ---------- */
(function init() {
  const h = new Date().getHours();
  el.greeting.textContent = h < 5 ? 'Bonne nuit !' : h < 18 ? 'Bonjour !' : 'Bonsoir !';

  const suggestions = [
    { icon: 'image', title: 'Créer une image', prompt: 'Génère une image de ' },
    { icon: 'pen', title: 'Écrire ou corriger un texte', prompt: 'Corrige et améliore ce texte : ' },
    { icon: 'code', title: 'Écrire ou déboguer du code', prompt: 'Aide-moi à écrire une fonction JavaScript qui ' },
    { icon: 'bulb', title: 'Trouver des idées', prompt: 'Donne-moi 5 idées originales de projets web.' }
  ];

  el.chips.innerHTML = '';
  suggestions.forEach(({ icon, title, prompt }, i) => {
    const b = document.createElement('button');
    b.className = 'chip';
    b.style.animationDelay = 0.08 * i + 's';
    b.innerHTML = `<span>${title}</span>${ic(icon)}`;
    b.onclick = () => { el.input.value = prompt; autosize(); refreshSend(); el.input.focus(); };
    el.chips.appendChild(b);
  });

  chats = chats.filter((c) => c && Array.isArray(c.messages));
  if (!chats.find((c) => c.id === activeId)) activeId = null;

  applyTheme();
  renderHistory();
  renderMessages();
  refreshSend();
  initVoiceRecognition();
  initPwaInstall();
})();

/* ---------- PWA Installation & Service Worker ---------- */
function initPwaInstall() {
  if ('serviceWorker' in navigator && location.protocol.startsWith('http')) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('/sw.js').catch(() => {});
    });
  }

  let deferredPrompt = null;
  const sideBtn = $('installAppBtn');
  const topBtn = $('topInstallBtn');

  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredPrompt = e;
    if (sideBtn) sideBtn.hidden = false;
    if (topBtn) topBtn.hidden = false;
  });

  async function promptInstall() {
    if (deferredPrompt) {
      deferredPrompt.prompt();
      const choice = await deferredPrompt.userChoice;
      if (choice && choice.outcome === 'accepted') {
        toast('Application installée avec succès !');
      }
      deferredPrompt = null;
      if (sideBtn) sideBtn.hidden = true;
      if (topBtn) topBtn.hidden = true;
    } else {
      const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream;
      if (isIOS) {
        alert('Pour installer Makasi AI sur iPhone/iPad :\n\n1. Appuyez sur le bouton Partager ⎋ dans Safari.\n2. Sélectionnez "Sur l\'écran d\'accueil" ➕.');
      } else {
        toast('Utilisez l\'option "Installer" ou "Ajouter à l\'écran d\'accueil" de votre navigateur.');
      }
    }
  }

  if (sideBtn) sideBtn.addEventListener('click', promptInstall);
  if (topBtn) topBtn.addEventListener('click', promptInstall);
}
