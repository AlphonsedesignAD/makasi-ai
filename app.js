/* ============================================================
   MAKASI AI — configuration
   ============================================================ */
const CONFIG = {
  // En production Vercel : l'API route sécurisée /api/chat utilise la clé
  // stockée dans les variables d'environnement (GEMINI_API_KEY).
  // Aucune clé secrète n'apparaît dans le code client !
  API_URL: '/api/chat',
  SYSTEM_PROMPT: "Tu es Makasi AI, un assistant intelligent, clair et chaleureux. Réponds dans la langue de l'utilisateur.",
  MAX_HISTORY: 20
};

/* Format de la requête envoyé à /api/chat */
function buildRequest(messages) {
  const headers = { 'Content-Type': 'application/json' };
  const contents = messages.map(({ role, content }) => ({
    role: role === 'assistant' ? 'model' : 'user',
    parts: [{ text: content }]
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
   Application
   ============================================================ */
const $ = (id) => document.getElementById(id);
const el = {
  app: $('app'), history: $('history'), search: $('search'), scroll: $('scroll'),
  messages: $('messages'), input: $('input'), form: $('form'), send: $('send'), stop: $('stop'),
  title: $('chatTitle'), greeting: $('greeting'), chips: $('chips'), toast: $('toast')
};

const KEY = 'makasi.chats', KEY_ACTIVE = 'makasi.active';
let chats = load(KEY, []);
let activeId = localStorage.getItem(KEY_ACTIVE);
let controller = null;
let busy = false;

function load(k, fb) { try { return JSON.parse(localStorage.getItem(k)) ?? fb; } catch { return fb; } }
function save() {
  try { localStorage.setItem(KEY, JSON.stringify(chats)); localStorage.setItem(KEY_ACTIVE, activeId || ''); }
  catch { toast('Stockage plein : supprimez d\u2019anciennes conversations.'); }
}
const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
const active = () => chats.find((c) => c.id === activeId);

function toast(msg) {
  el.toast.textContent = msg; el.toast.classList.add('show');
  clearTimeout(toast.t); toast.t = setTimeout(() => el.toast.classList.remove('show'), 2200);
}

/* ---------- Markdown léger et sûr ---------- */
const esc = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

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
  const blocks = [];
  let s = esc(text).replace(/```([\w+-]*)\n?([\s\S]*?)(```|$)/g, (_, lang, code) => {
    blocks.push({ lang, code: code.replace(/\n$/, '') });
    return '\n\x00' + (blocks.length - 1) + '\x00\n';
  });

  const out = []; let list = null, para = [];
  const flushP = () => { if (para.length) { out.push('<p>' + inline(para.join('<br>')) + '</p>'); para = []; } };
  const flushL = () => { if (list) { out.push(`</${list}>`); list = null; } };

  for (const line of s.split('\n')) {
    let m;
    if ((m = line.match(/^\x00(\d+)\x00$/))) {
      flushP(); flushL();
      const b = blocks[+m[1]];
      out.push(`<div class="codeblock"><div class="codehead"><span>${b.lang || 'code'}</span><button data-copy>Copier</button></div><pre><code>${b.code}</code></pre></div>`);
    } else if ((m = line.match(/^(#{1,3})\s+(.*)/))) {
      flushP(); flushL(); out.push(`<h${m[1].length}>${inline(m[2])}</h${m[1].length}>`);
    } else if ((m = line.match(/^\s*[-*•]\s+(.*)/))) {
      flushP(); if (list !== 'ul') { flushL(); out.push('<ul>'); list = 'ul'; } out.push('<li>' + inline(m[1]) + '</li>');
    } else if ((m = line.match(/^\s*\d+[.)]\s+(.*)/))) {
      flushP(); if (list !== 'ol') { flushL(); out.push('<ol>'); list = 'ol'; } out.push('<li>' + inline(m[1]) + '</li>');
    } else if ((m = line.match(/^&gt;\s?(.*)/))) {
      flushP(); flushL(); out.push('<blockquote>' + inline(m[1]) + '</blockquote>');
    } else if (!line.trim()) { flushP(); flushL(); }
    else { flushL(); para.push(line); }
  }
  flushP(); flushL();
  return out.join('');
}

/* ---------- Rendu ---------- */
function msgNode(m, idx) {
  const d = document.createElement('div');
  d.className = 'msg ' + (m.role === 'user' ? 'user' : 'bot') + (m.error ? ' err' : '');
  d.dataset.idx = idx;
  if (m.role === 'user') {
    d.innerHTML = '<div class="body"></div>';
    d.querySelector('.body').textContent = m.content;
  } else {
    d.innerHTML = '<div class="avatar"><svg viewBox="0 0 32 32" width="16" height="16"><path d="M8 23V9l8 9 8-9v14" fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/></svg></div><div><div class="body"></div><div class="actions"><button data-act="copy">Copier</button><button data-act="retry">Régénérer</button></div></div>';
    d.querySelector('.body').innerHTML = md(m.content);
    d.lastElementChild.style.flex = '1'; d.lastElementChild.style.minWidth = '0';
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
  scrollDown(false);
}

function renderHistory() {
  const q = el.search.value.trim().toLowerCase();
  const list = chats.filter((c) => !q || (c.title || '').toLowerCase().includes(q) || c.messages.some((m) => m.content.toLowerCase().includes(q)))
    .sort((a, b) => b.updated - a.updated);
  el.history.innerHTML = '';
  if (!list.length) { el.history.innerHTML = '<div class="empty-hist">' + (q ? 'Aucun résultat.' : 'Vos conversations apparaîtront ici.') + '</div>'; return; }

  const day = 864e5, now = Date.now();
  const groups = [['Aujourd\u2019hui', 0], ['Hier', day], ['7 derniers jours', 7 * day], ['Plus ancien', Infinity]];
  const buckets = groups.map(() => []);
  list.forEach((c) => {
    const startToday = new Date().setHours(0, 0, 0, 0), age = startToday - c.updated;
    const i = c.updated >= startToday ? 0 : age <= day ? 1 : age <= 7 * day ? 2 : 3;
    buckets[i].push(c);
  });
  buckets.forEach((b, i) => {
    if (!b.length) return;
    const l = document.createElement('div'); l.className = 'group-label'; l.textContent = groups[i][0]; el.history.appendChild(l);
    b.forEach((c) => {
      const it = document.createElement('div'); it.className = 'item' + (c.id === activeId ? ' active' : '');
      it.innerHTML = '<button class="t"></button><button class="x" aria-label="Supprimer">✕</button>';
      it.querySelector('.t').textContent = c.title || 'Nouvelle conversation';
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

/* ---------- Conversations ---------- */
function newChat() {
  if (busy) return;
  const c = active();
  if (c && !c.messages.length) { el.input.focus(); return; }
  const n = { id: uid(), title: '', messages: [], updated: Date.now() };
  chats.push(n); activeId = n.id; save(); renderHistory(); renderMessages(); el.input.focus();
}
function openChat(id) { if (busy) return; activeId = id; save(); renderHistory(); renderMessages(); }
function removeChat(id) {
  if (busy && id === activeId) return;
  chats = chats.filter((c) => c.id !== id);
  if (activeId === id) activeId = chats.length ? chats.sort((a, b) => b.updated - a.updated)[0].id : null;
  save(); renderHistory(); renderMessages();
}

/* ---------- Envoi ---------- */
function setBusy(b) {
  busy = b; el.stop.hidden = !b; el.send.hidden = b; el.input.disabled = false; refreshSend();
}
function refreshSend() { el.send.disabled = busy || !el.input.value.trim(); }

async function ask(c) {
  setBusy(true);

  // Bulle de réponse avec animation de chargement
  const holder = document.createElement('div'); holder.className = 'msg bot';
  holder.innerHTML = '<div class="avatar"><svg viewBox="0 0 32 32" width="16" height="16"><path d="M8 23V9l8 9 8-9v14" fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/></svg></div><div style="flex:1;min-width:0"><div class="body"><span class="typing"><i></i><i></i><i></i></span></div><div class="actions" style="display:none"></div></div>';
  el.messages.appendChild(holder); scrollDown();
  const bodyEl = holder.querySelector('.body');

  controller = new AbortController();
  let fullText = '';

  try {
    const history = c.messages.filter((m) => !m.error).slice(-CONFIG.MAX_HISTORY).map(({ role, content }) => ({ role, content }));
    const { headers, body } = buildRequest(history);
    const res = await fetch(CONFIG.API_URL, { method: 'POST', headers, body, signal: controller.signal });

    if (!res.ok) {
      let detail = 'Erreur ' + res.status;
      try {
        const errJson = await res.json();
        if (errJson?.error) detail += ': ' + (typeof errJson.error === 'string' ? errJson.error : JSON.stringify(errJson.error));
      } catch (_) {}
      throw new Error(detail);
    }

    // Lecture du stream SSE chunk par chunk
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buf = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += decoder.decode(value, { stream: true });
      const lines = buf.split('\n');
      buf = lines.pop(); // conserver la ligne potentiellement incomplète

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
        } catch { /* chunk JSON invalide, ignoré */ }
      }
    }

    if (!fullText) throw new Error('Réponse vide de l\'API.');
    c.messages.push({ role: 'assistant', content: fullText.trim() });

  } catch (e) {
    if (e.name === 'AbortError') {
      c.messages.push({ role: 'assistant', content: '_Génération interrompue._', error: false });
    } else {
      console.error('[Makasi]', e);
      c.messages.push({ role: 'assistant', content: 'Désolé, je n\'ai pas pu répondre (' + e.message + '). Vérifiez votre connexion ou la configuration de l\'API.', error: true });
    }
  }

  c.updated = Date.now(); save();
  controller = null; setBusy(false);
  renderMessages(); renderHistory(); scrollDown();
}

function send(text) {
  text = text.trim(); if (!text || busy) return;
  let c = active();
  if (!c) { c = { id: uid(), title: '', messages: [], updated: Date.now() }; chats.push(c); activeId = c.id; }
  if (!c.messages.length) c.title = text.length > 44 ? text.slice(0, 44).trim() + '\u2026' : text;
  c.messages.push({ role: 'user', content: text }); c.updated = Date.now();
  save(); el.input.value = ''; autosize(); refreshSend();
  renderMessages(); renderHistory(); ask(c);
}

/* ---------- Événements ---------- */
function autosize() { el.input.style.height = 'auto'; el.input.style.height = Math.min(el.input.scrollHeight, 200) + 'px'; }
el.input.addEventListener('input', () => { autosize(); refreshSend(); });
el.input.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && innerWidth > 820) { e.preventDefault(); send(el.input.value); }
});
el.form.addEventListener('submit', (e) => { e.preventDefault(); send(el.input.value); });
el.stop.addEventListener('click', () => controller && controller.abort());
$('newChat').onclick = () => { newChat(); closeSide(); };
el.search.addEventListener('input', renderHistory);

$('clearAll').onclick = () => {
  if (!chats.length) return;
  if (confirm('Supprimer toutes vos conversations ? Cette action est définitive.')) {
    chats = []; activeId = null; save(); renderHistory(); renderMessages(); toast('Conversations supprimées');
  }
};

el.messages.addEventListener('click', async (e) => {
  const copyCode = e.target.closest('[data-copy]');
  if (copyCode) {
    await navigator.clipboard.writeText(copyCode.closest('.codeblock').querySelector('code').textContent);
    copyCode.textContent = 'Copié ✓'; setTimeout(() => (copyCode.textContent = 'Copier'), 1500); return;
  }
  const b = e.target.closest('[data-act]'); if (!b || busy) return;
  const c = active(), idx = +b.closest('.msg').dataset.idx;
  if (b.dataset.act === 'copy') { await navigator.clipboard.writeText(c.messages[idx].content); toast('Copié'); }
  if (b.dataset.act === 'retry') { c.messages.splice(idx); save(); renderMessages(); ask(c); }
});

/* Menu mobile */
const openSide = () => el.app.classList.add('side-open'), closeSide = () => el.app.classList.remove('side-open');
$('openSide').onclick = openSide; $('closeSide').onclick = closeSide; $('scrim').onclick = closeSide;

/* Thème */
function applyTheme(t) {
  if (t) document.documentElement.dataset.theme = t;
  const dark = (document.documentElement.dataset.theme || (matchMedia('(prefers-color-scheme:dark)').matches ? 'dark' : 'light')) === 'dark';
  $('themeIcon').textContent = dark ? '☀️' : '🌙'; $('themeLabel').textContent = dark ? 'Mode clair' : 'Mode sombre';
}
$('themeBtn').onclick = () => {
  const dark = (document.documentElement.dataset.theme || (matchMedia('(prefers-color-scheme:dark)').matches ? 'dark' : 'light')) === 'dark';
  const next = dark ? 'light' : 'dark'; localStorage.setItem('makasi.theme', next); applyTheme(next);
};

/* ---------- Démarrage ---------- */
(function init() {
  const h = new Date().getHours();
  el.greeting.textContent = h < 5 ? 'Bonne nuit' : h < 18 ? 'Bonjour' : 'Bonsoir';
  ['Explique-moi un concept simplement', 'Aide-moi à écrire un message', 'Donne-moi des idées de projet', 'Corrige et améliore mon texte']
    .forEach((t) => { const b = document.createElement('button'); b.className = 'chip'; b.textContent = t; b.onclick = () => { el.input.value = t + ' : '; autosize(); refreshSend(); el.input.focus(); }; el.chips.appendChild(b); });
  chats = chats.filter((c) => c && Array.isArray(c.messages));
  if (!chats.find((c) => c.id === activeId)) activeId = null;
  applyTheme(); renderHistory(); renderMessages(); refreshSend();
})();
