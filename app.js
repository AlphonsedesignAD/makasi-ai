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
    toast('Audio non supporté sur ce navigateur.');
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
    let fileBadgeHtml = '';
    if (m.attachment) {
      fileBadgeHtml = `<div class="attached-file-badge">📎 ${esc(m.attachment.name)}</div>`;
    }
    d.innerHTML = `<div class="body">${fileBadgeHtml}<div class="user-text"></div></div>`;
    d.querySelector('.user-text').textContent = m.displayText || m.content || '';
  } else {
    d.innerHTML = `
      <div class="avatar">
        <svg viewBox="0 0 32 32" width="18" height="18" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
          <path d="M8 23V9l8 9 8-9v14"/>
        </svg>
      </div>
      <div class="content-wrap">
        <div class="body"></div>
        <div class="actions">
          <button data-act="copy" title="Copier le texte">📋 Copier</button>
          <button data-act="speak" title="Écouter la réponse">🔊 Écouter</button>
          <button data-act="retry" title="Régénérer">🔄 Relancer</button>
        </div>
      </div>
    `;
    d.querySelector('.body').innerHTML = md(m.content || '');
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
      it.innerHTML = '<button class="t"></button><button class="x" aria-label="Supprimer" title="Supprimer">✕</button>';
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
    mdContent += `### ${m.role === 'user' ? '👤 Utilisateur' : '🤖 Makasi AI'}\n\n${m.displayText || m.content}\n\n---\n\n`;
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
  if (type.startsWith('image/')) return '🖼️';
  if (name.endsWith('.pdf')) return '📕';
  if (name.match(/\.(js|ts|py|html|css|json|sql|php|cpp|c|java)$/i)) return '💻';
  if (name.endsWith('.csv') || name.endsWith('.xlsx')) return '📊';
  return '📄';
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
    el.fileIcon.textContent = getFileIcon(file.name, file.type);
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
}

function refreshSend() {
  const hasText = !!el.input.value.trim();
  const hasFile = !!currentAttachedFile;
  el.send.disabled = busy || (!hasText && !hasFile);
}

async function ask(c) {
  setBusy(true);

  const holder = document.createElement('div');
  holder.className = 'msg bot';
  holder.innerHTML = `
    <div class="avatar">
      <svg viewBox="0 0 32 32" width="18" height="18" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
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
    const history = c.messages.filter((m) => !m.error).slice(-CONFIG.MAX_HISTORY).map((m) => {
      // Construction des parts pour Gemini (support texte et images inline)
      if (m.parts) return { role: m.role, parts: m.parts };
      return { role: m.role, parts: [{ text: m.content || '' }] };
    });

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
      c.messages.push({ role: 'assistant', content: 'Désolé, je n\'ai pas pu répondre (' + e.message + '). Vérifiez votre connexion.', error: true });
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

/* ---------- Démarrage & Suggestions Normales ---------- */
(function init() {
  const h = new Date().getHours();
  el.greeting.textContent = h < 5 ? 'Bonne nuit !' : h < 18 ? 'Bonjour !' : 'Bonsoir !';

  const suggestions = [
    { title: '📝 Corriger ou améliorer un texte', prompt: 'Corrige et améliore la structure et l\'orthographe de ce texte :' },
    { title: '💻 Déboguer ou écrire du code', prompt: 'Aide-moi à écrire une fonction en JavaScript pour :' },
    { title: '💡 Trouver des idées innovantes', prompt: 'Donne-moi 5 idées créatives de projets web pour débuter cette année.' },
    { title: '📊 Résumer un document ou fichier', prompt: 'Résume de manière claire et concise les points clés suivants :' }
  ];

  el.chips.innerHTML = '';
  suggestions.forEach(({ title, prompt }) => {
    const b = document.createElement('button');
    b.className = 'chip';
    b.textContent = title;
    b.onclick = () => {
      el.input.value = prompt + ' ';
      autosize();
      refreshSend();
      el.input.focus();
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
