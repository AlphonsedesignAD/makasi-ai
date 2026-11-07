/* ============================================================
   MAKASI AI — Application Frontend
   Créé par Alphonse Design (WhatsApp : 0971404824)
   ============================================================ */

const CONFIG = {
  API_URL: '/api/chat',
  SYSTEM_PROMPT: `Tu es Makasi AI, un assistant d'élite intelligent, créatif, percutant et très chaleureux.
Tu as été pensé, conçu et développé avec passion par ALPHONSE DESIGN, designer créatif, développeur web et expert en solutions digitales et intelligence artificielle.

TES DIRECTIVES IMPORTANTES SUR TON CRÉATEUR & SES SERVICES :
1. Ton créateur et mentor est ALPHONSE DESIGN.
2. Coordonnées directes officielles :
   - WhatsApp / Téléphone : 0971404824 (format international : +243971404824)
   - Lien WhatsApp direct : https://wa.me/243971404824
3. Domaines d'expertise d'Alphonse Design :
   - Création de sites web professionnels, vitrines & e-commerce ultra-rapides et responsive.
   - Design d'identités visuelles complètes : logos distinctifs, chartes graphiques, affiches, cartes de visite et branding de marque.
   - Conception d'assistants IA sur mesure, chatbots et intégrations modernes.
   - Stratégies digitales et visuels publicitaires pour booster les ventes des entreprises et créateurs.
4. Si l'utilisateur demande des informations sur toi, sur tes services, demande un devis, ou a un projet créatif/technique :
   - Présente avec enthousiasme et professionnalisme la valeur ajoutée d'Alphonse Design.
   - Donne systématiquement le contact WhatsApp 0971404824 avec le lien cliquable : [Écrire à Alphonse Design sur WhatsApp](https://wa.me/243971404824?text=Bonjour%20Alphonse%20Design,%20je%20souhaite%20un%20devis%20pour%20un%20projet).
5. Pour toutes les requêtes (programmation, rédaction, entrepreneuriat, études, astuces, créativité), sois exceptionnellement précis, bienveillant, structuré avec des puces et des émojis pertinents.
6. Réponds avec fluidité dans la langue de l'utilisateur (français, lingala, swahili, anglais...).`,
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
   Éléments DOM & État
   ============================================================ */
const $ = (id) => document.getElementById(id);
const el = {
  app: $('app'), history: $('history'), search: $('search'), scroll: $('scroll'),
  messages: $('messages'), input: $('input'), form: $('form'), send: $('send'), stop: $('stop'),
  title: $('chatTitle'), greeting: $('greeting'), chips: $('chips'), toast: $('toast'),
  micBtn: $('micBtn'), voiceBar: $('voiceBar'), voiceText: $('voiceText'), cancelVoice: $('cancelVoice'),
  exportChatBtn: $('exportChatBtn')
};

const KEY = 'makasi.chats', KEY_ACTIVE = 'makasi.active';
let chats = load(KEY, []);
let activeId = localStorage.getItem(KEY_ACTIVE);
let controller = null;
let busy = false;
let currentUtterance = null;
let recognition = null;
let isRecording = false;

function load(k, fb) { try { return JSON.parse(localStorage.getItem(k)) ?? fb; } catch { return fb; } }
function save() {
  try {
    localStorage.setItem(KEY, JSON.stringify(chats));
    localStorage.setItem(KEY_ACTIVE, activeId || '');
  } catch {
    toast('Stockage plein : supprimez d’anciennes conversations.');
  }
}

const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
const active = () => chats.find((c) => c.id === activeId);

function toast(msg) {
  el.toast.textContent = msg;
  el.toast.classList.add('show');
  clearTimeout(toast.t);
  toast.t = setTimeout(() => el.toast.classList.remove('show'), 2400);
}

/* ---------- Fonction globale pour les puces rapides ---------- */
window.sendPrompt = function(promptText) {
  if (busy) return;
  el.input.value = promptText;
  autosize();
  refreshSend();
  send(promptText);
};

/* ---------- Markdown léger & soigné ---------- */
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

/* ---------- Synthèse Vocale (Text-to-Speech) ---------- */
function toggleSpeech(text, btn) {
  if (!('speechSynthesis' in window)) {
    toast('Synthèse vocale non supportée sur ce navigateur.');
    return;
  }

  if (window.speechSynthesis.speaking) {
    window.speechSynthesis.cancel();
    document.querySelectorAll('[data-act="speak"]').forEach(b => {
      b.classList.remove('tts-speaking');
      b.innerHTML = '🔊 Écouter';
    });
    if (btn && currentUtterance && currentUtterance.__btn === btn) {
      currentUtterance = null;
      return;
    }
  }

  // Nettoyage Markdown pour lecture fluide
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
  btn.innerHTML = '⏹ Arrêter';

  utter.onend = () => {
    btn.classList.remove('tts-speaking');
    btn.innerHTML = '🔊 Écouter';
    currentUtterance = null;
  };
  utter.onerror = () => {
    btn.classList.remove('tts-speaking');
    btn.innerHTML = '🔊 Écouter';
    currentUtterance = null;
  };

  currentUtterance = utter;
  window.speechSynthesis.speak(utter);
}

/* ---------- Rendu des Messages ---------- */
function msgNode(m, idx) {
  const d = document.createElement('div');
  d.className = 'msg ' + (m.role === 'user' ? 'user' : 'bot') + (m.error ? ' err' : '');
  d.dataset.idx = idx;

  if (m.role === 'user') {
    d.innerHTML = '<div class="body"></div>';
    d.querySelector('.body').textContent = m.content;
  } else {
    d.innerHTML = `
      <div class="avatar">
        <svg viewBox="0 0 32 32" width="18" height="18" fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M8 23V9l8 9 8-9v14"/>
        </svg>
      </div>
      <div class="content-wrap">
        <div class="body"></div>
        <div class="actions">
          <button data-act="copy" title="Copier la réponse">📋 Copier</button>
          <button data-act="speak" title="Écouter la réponse vocalement">🔊 Écouter</button>
          <button data-act="retry" title="Régénérer cette réponse">🔄 Relancer</button>
          <a href="https://wa.me/243971404824?text=Bonjour%20Alphonse%20Design,%20suite%20%C3%A0%20mon%20%C3%A9change%20avec%20Makasi%20AI,%20je%20souhaite%20un%20devis." target="_blank" rel="noopener noreferrer" style="display:inline-flex;align-items:center;gap:4px;padding:5px 10px;border-radius:var(--radius-sm);background:rgba(37,211,102,0.12);color:#2fd36b;font-size:12px;font-weight:700;border:1px solid rgba(37,211,102,0.3)">
            💬 WhatsApp
          </a>
        </div>
      </div>
    `;
    d.querySelector('.body').innerHTML = md(m.content);
  }
  return d;
}

function renderMessages() {
  const c = active();
  el.messages.innerHTML = '';
  el.app.classList.toggle('has-msgs', !!(c && c.messages.length));
  el.title.textContent = c && c.title ? c.title : 'Makasi AI';
  document.title = c && c.title ? c.title + ' · Makasi AI' : 'Makasi AI — Par Alphonse Design';
  if (c) c.messages.forEach((m, i) => el.messages.appendChild(msgNode(m, i)));
  scrollDown(false);
}

function renderHistory() {
  const q = el.search.value.trim().toLowerCase();
  const list = chats.filter((c) => !q || (c.title || '').toLowerCase().includes(q) || c.messages.some((m) => m.content.toLowerCase().includes(q)))
    .sort((a, b) => b.updated - a.updated);
  el.history.innerHTML = '';
  if (!list.length) {
    el.history.innerHTML = '<div class="empty-hist">' + (q ? 'Aucun résultat trouvé.' : 'Vos discussions apparaîtront ici.') + '</div>';
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
      it.innerHTML = '<button class="t"></button><button class="x" aria-label="Supprimer la discussion" title="Supprimer">✕</button>';
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
  save();
  renderHistory();
  renderMessages();
  el.input.focus();
}

function openChat(id) {
  if (busy) return;
  activeId = id;
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
  let mdContent = `# ${c.title || 'Discussion Makasi AI'}\n*Créé avec Makasi AI — par Alphonse Design (WhatsApp : 0971404824)*\n\n---\n\n`;
  c.messages.forEach(m => {
    mdContent += `### ${m.role === 'user' ? '👤 Vous' : '🤖 Makasi AI'}\n\n${m.content}\n\n---\n\n`;
  });

  const blob = new Blob([mdContent], { type: 'text/markdown;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `makasi-ai-${c.title ? c.title.slice(0, 20).replace(/\s+/g, '_') : 'chat'}.md`;
  a.click();
  URL.revokeObjectURL(url);
  toast('Discussion exportée avec succès !');
}

/* ---------- Envoi & Streaming ---------- */
function setBusy(b) {
  busy = b;
  el.stop.hidden = !b;
  el.send.hidden = b;
  el.input.disabled = false;
  refreshSend();
}

function refreshSend() {
  el.send.disabled = busy || !el.input.value.trim();
}

async function ask(c) {
  setBusy(true);

  // Bulle de réponse avec animation de chargement
  const holder = document.createElement('div');
  holder.className = 'msg bot';
  holder.innerHTML = `
    <div class="avatar">
      <svg viewBox="0 0 32 32" width="18" height="18" fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M8 23V9l8 9 8-9v14"/>
      </svg>
    </div>
    <div class="content-wrap">
      <div class="body"><span class="typing"><i></i><i></i><i></i></span></div>
    </div>
  `;
  el.messages.appendChild(holder);
  scrollDown();
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

    // Lecture du stream SSE
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
        } catch { /* chunk JSON incomplet */ }
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
  if (!text || busy) return;
  let c = active();
  if (!c) {
    c = { id: uid(), title: '', messages: [], updated: Date.now() };
    chats.push(c);
    activeId = c.id;
  }
  if (!c.messages.length) {
    c.title = text.length > 44 ? text.slice(0, 44).trim() + '…' : text;
  }
  c.messages.push({ role: 'user', content: text });
  c.updated = Date.now();
  save();
  el.input.value = '';
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
    el.voiceText.textContent = 'Parlez maintenant... Makasi AI vous écoute';
  };

  recognition.onresult = (e) => {
    const transcript = Array.from(e.results).map(r => r[0].transcript).join('');
    el.input.value = transcript;
    autosize();
    refreshSend();
    el.voiceText.textContent = `"${transcript}"`;
  };

  recognition.onerror = (e) => {
    isRecording = false;
    el.micBtn.classList.remove('active');
    el.voiceBar.hidden = true;
    toast('Écoute annulée ou micro indisponible.');
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
  el.input.style.height = Math.min(el.input.scrollHeight, 180) + 'px';
}

el.input.addEventListener('input', () => { autosize(); refreshSend(); });
el.input.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && innerWidth > 820) {
    e.preventDefault();
    send(el.input.value);
  }
});
el.form.addEventListener('submit', (e) => { e.preventDefault(); send(el.input.value); });
el.stop.addEventListener('click', () => controller && controller.abort());
$('newChat').onclick = () => { newChat(); closeSide(); };
el.search.addEventListener('input', renderHistory);
if (el.exportChatBtn) el.exportChatBtn.onclick = exportCurrentChat;

$('clearAll').onclick = () => {
  if (!chats.length) return;
  if (confirm('Voulez-vous supprimer toutes vos conversations ? Cette action est irréversible.')) {
    chats = [];
    activeId = null;
    save();
    renderHistory();
    renderMessages();
    toast('Toutes les conversations ont été effacées.');
  }
};

el.messages.addEventListener('click', async (e) => {
  // Copier bloc de code
  const copyCode = e.target.closest('[data-copy]');
  if (copyCode) {
    await navigator.clipboard.writeText(copyCode.closest('.codeblock').querySelector('code').textContent);
    copyCode.textContent = 'Copié ✓';
    setTimeout(() => (copyCode.textContent = 'Copier'), 1500);
    return;
  }

  const b = e.target.closest('[data-act]');
  if (!b || busy) return;
  const c = active();
  const idx = +b.closest('.msg').dataset.idx;

  if (b.dataset.act === 'copy') {
    await navigator.clipboard.writeText(c.messages[idx].content);
    toast('Réponse copiée dans le presse-papier !');
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
  const dark = (document.documentElement.dataset.theme || 'dark') === 'dark';
  $('themeIcon').textContent = dark ? '🌙' : '☀️';
  $('themeLabel').textContent = dark ? 'Sombre' : 'Clair';
}
$('themeBtn').onclick = () => {
  const current = document.documentElement.dataset.theme || 'dark';
  const next = current === 'dark' ? 'light' : 'dark';
  localStorage.setItem('makasi.theme', next);
  applyTheme(next);
};

/* ---------- Démarrage & Suggestions Clients ---------- */
(function init() {
  const h = new Date().getHours();
  el.greeting.textContent = h < 5 ? 'Bonne nuit !' : h < 18 ? 'Bonjour !' : 'Bonsoir !';

  // Suggestions orientées conversion client et productivité
  const suggestions = [
    { title: '💼 Devis création de site web', prompt: 'Je souhaite un devis pour la création d\'un site web moderne et professionnel avec Alphonse Design.' },
    { title: '🎨 Logo & Identité visuelle', prompt: 'Quelles sont les formules d\'Alphonse Design pour créer un logo et une identité de marque percutante ?' },
    { title: '🤖 Assistant IA sur-mesure', prompt: 'Comment Alphonse Design peut m\'aider à concevoir une solution d\'intelligence artificielle pour mon entreprise ?' },
    { title: '🚀 Stratégie marketing digital', prompt: 'Donne-moi 5 stratégies concrètes pour attirer plus de clients vers mon business cette semaine.' },
    { title: '📱 Contacter sur WhatsApp', prompt: 'Comment puis-je contacter Alphonse Design directement sur WhatsApp au 0971404824 ?' },
    { title: '💡 Améliorer mon texte de vente', prompt: 'Aide-moi à rédiger une proposition commerciale convaincante pour mes clients.' }
  ];

  el.chips.innerHTML = '';
  suggestions.forEach(({ title, prompt }) => {
    const b = document.createElement('button');
    b.className = 'chip';
    b.textContent = title;
    b.onclick = () => {
      el.input.value = prompt;
      autosize();
      refreshSend();
      send(prompt);
    };
    el.chips.appendChild(b);
  });

  chats = chats.filter((c) => c && Array.isArray(c.messages));
  if (!chats.find((c) => c.id === activeId)) activeId = null;

  applyTheme(localStorage.getItem('makasi.theme') || 'dark');
  renderHistory();
  renderMessages();
  refreshSend();
  initVoiceRecognition();
})();
