/* ============================================================
   MAKASI AI — Cloud (comptes + mémoire partagée)
   Client Supabase REST minimal, sans dépendance externe.

   • Le site et l'app Flutter lisent la même configuration
     publique via /api/config.
   • Les discussions sont stockées dans la table `chats`.
   • Aucune clé de l’IA ne transite ici.
   ============================================================ */
(() => {
  'use strict';

  const CONFIG_URL = '/api/config';
  const SESSION_KEY = 'makasi.session';
  const LAST_SYNC_KEY = 'makasi.lastSync';
  const PROFILE_KEY = 'makasi.profile';

  let config = { supabaseUrl: '', supabaseAnonKey: '' };
  let session = readSession();
  let user = null;
  let profile = readJson(PROFILE_KEY);
  let ready = false;
  let known = new Map(); // id de discussion -> updated (ms)

  const listeners = { auth: new Set(), sync: new Set() };

  /* ---------- Outils ---------- */
  function readJson(key) {
    try { return JSON.parse(localStorage.getItem(key) || 'null'); } catch (_) { return null; }
  }
  function readSession() { return readJson(SESSION_KEY); }
  function writeSession(s) {
    session = s;
    try {
      if (s) localStorage.setItem(SESSION_KEY, JSON.stringify(s));
      else localStorage.removeItem(SESSION_KEY);
    } catch (_) { /* stockage indisponible */ }
  }
  function emit(kind, value) {
    listeners[kind].forEach((fn) => { try { fn(value); } catch (e) { console.error('[MakasiCloud]', e); } });
  }
  function configured() {
    return !!(config.supabaseUrl && config.supabaseAnonKey);
  }
  function base() { return config.supabaseUrl.replace(/\/+$/, ''); }

  async function parseError(res) {
    let text = '';
    try { text = await res.text(); } catch (_) { /* ignore */ }
    let data = null;
    try { data = JSON.parse(text); } catch (_) { /* ignore */ }
    const msg =
      data?.error_description || data?.msg || data?.message ||
      data?.error || (res.status === 429 ? 'Trop de tentatives. Réessayez dans un instant.' : '') ||
      `Erreur ${res.status}`;
    const err = new Error(String(msg));
    err.status = res.status;
    return err;
  }

  /* ---------- Session ---------- */
  function storeToken(data) {
    if (!data?.access_token) return;
    writeSession({
      access_token: data.access_token,
      refresh_token: data.refresh_token || session?.refresh_token || '',
      expires_at: Math.floor(Date.now() / 1000) + Number(data.expires_in || 3600),
    });
  }

  async function refreshToken() {
    if (!configured() || !session?.refresh_token) return false;
    try {
      const res = await fetch(`${base()}/auth/v1/token?grant_type=refresh_token`, {
        method: 'POST',
        headers: { apikey: config.supabaseAnonKey, 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh_token: session.refresh_token }),
      });
      if (!res.ok) {
        writeSession(null);
        setUser(null);
        return false;
      }
      storeToken(await res.json());
      return true;
    } catch (_) {
      return false;
    }
  }

  async function ensureToken() {
    if (!session?.access_token) return;
    if (Number(session.expires_at || 0) * 1000 - Date.now() < 60_000) {
      await refreshToken();
    }
  }

  async function request(path, options = {}) {
    const { method = 'GET', body, headers = {}, auth = true, retry = true } = options;
    if (!configured()) throw new Error('Le service de comptes n’est pas configuré sur le serveur.');
    if (auth) await ensureToken();

    const h = { apikey: config.supabaseAnonKey, ...headers };
    if (body !== undefined) h['Content-Type'] = 'application/json';
    if (auth && session?.access_token) h.Authorization = `Bearer ${session.access_token}`;

    let res;
    try {
      res = await fetch(base() + path, {
        method,
        headers: h,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch (e) {
      const err = new Error('Connexion impossible. Vérifiez votre réseau.');
      err.offline = true;
      throw err;
    }

    if (res.status === 401 && auth && retry && session?.refresh_token) {
      if (await refreshToken()) return request(path, { ...options, retry: false });
    }
    return res;
  }

  function setUser(u) {
    user = u;
    if (!u) {
      profile = null;
      known = new Map();
      try {
        localStorage.removeItem(PROFILE_KEY);
        localStorage.removeItem(LAST_SYNC_KEY);
      } catch (_) { /* ignore */ }
    }
    emit('auth', u);
  }

  async function fetchUser() {
    if (!session?.access_token) return null;
    const res = await request('/auth/v1/user');
    if (!res.ok) return null;
    return res.json();
  }

  async function fetchProfile() {
    if (!user) return null;
    try {
      const res = await request(`/rest/v1/profiles?select=display_name&id=eq.${encodeURIComponent(user.id)}`);
      if (!res.ok) return null;
      const rows = await res.json();
      const name = rows?.[0]?.display_name || null;
      if (name) {
        profile = { display_name: name };
        try { localStorage.setItem(PROFILE_KEY, JSON.stringify(profile)); } catch (_) { /* ignore */ }
      }
      return name;
    } catch (_) {
      return profile?.display_name || null;
    }
  }

  /* ---------- Authentification ---------- */
  async function signUp({ email, password, name }) {
    if (!configured()) throw new Error('Le service de comptes n’est pas configuré sur le serveur.');
    const res = await fetch(`${base()}/auth/v1/signup`, {
      method: 'POST',
      headers: { apikey: config.supabaseAnonKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: String(email).trim(),
        password,
        data: { display_name: String(name || '').trim() || String(email).split('@')[0] },
      }),
    });
    if (!res.ok) throw await parseError(res);

    const data = await res.json();
    if (data?.access_token) {
      storeToken(data);
      setUser(data.user || (await fetchUser()));
      await fetchProfile();
      return { user, needsConfirmation: false };
    }
    // Confirmation e-mail activée côté Supabase
    return { user: null, needsConfirmation: true, email: String(email).trim() };
  }

  async function signIn({ email, password }) {
    if (!configured()) throw new Error('Le service de comptes n’est pas configuré sur le serveur.');
    const res = await fetch(`${base()}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: { apikey: config.supabaseAnonKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: String(email).trim(), password }),
    });
    if (!res.ok) throw await parseError(res);

    const data = await res.json();
    storeToken(data);
    setUser(data.user || (await fetchUser()));
    await fetchProfile();
    return { user };
  }

  async function signOut() {
    try {
      if (configured() && session?.access_token) {
        await fetch(`${base()}/auth/v1/logout`, {
          method: 'POST',
          headers: {
            apikey: config.supabaseAnonKey,
            Authorization: `Bearer ${session.access_token}`,
          },
        });
      }
    } catch (_) { /* déconnexion locale dans tous les cas */ }
    writeSession(null);
    setUser(null);
  }

  async function resetPassword(email) {
    if (!configured()) throw new Error('Le service de comptes n’est pas configuré sur le serveur.');
    const res = await fetch(`${base()}/auth/v1/recover`, {
      method: 'POST',
      headers: { apikey: config.supabaseAnonKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: String(email).trim() }),
    });
    if (!res.ok) throw await parseError(res);
    return true;
  }

  /* ---------- Mémoire (chats) ---------- */
  function rowToChat(row) {
    return {
      id: row.id,
      title: row.title || '',
      messages: Array.isArray(row.messages) ? row.messages : [],
      updated: Date.parse(row.updated_at) || Date.now(),
    };
  }

  async function pullChats() {
    const res = await request(
      '/rest/v1/chats?select=id,title,messages,updated_at&order=updated_at.desc&limit=500'
    );
    if (!res.ok) throw await parseError(res);
    const rows = await res.json();
    return (rows || []).map(rowToChat);
  }

  async function upsertChats(chats) {
    if (!user || !chats.length) return;
    const rows = chats.map((c) => ({
      id: String(c.id),
      user_id: user.id,
      title: String(c.title || '').slice(0, 200),
      messages: Array.isArray(c.messages) ? c.messages : [],
      updated_at: new Date(Number(c.updated) || Date.now()).toISOString(),
    }));
    const res = await request('/rest/v1/chats?on_conflict=id', {
      method: 'POST',
      headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: rows,
    });
    if (!res.ok) throw await parseError(res);
  }

  async function deleteChat(id) {
    if (!user) return;
    const res = await request(`/rest/v1/chats?id=eq.${encodeURIComponent(id)}`, { method: 'DELETE' });
    if (!res.ok) throw await parseError(res);
  }

  async function clearRemote() {
    if (!user) return;
    const res = await request(`/rest/v1/chats?user_id=eq.${encodeURIComponent(user.id)}`, {
      method: 'DELETE',
    });
    if (!res.ok) throw await parseError(res);
    known = new Map();
  }

  function prime(chats) {
    known = new Map((chats || []).map((c) => [c.id, Number(c.updated) || Date.now()]));
  }

  /* Envoie uniquement les discussions modifiées + supprime les disparues. */
  async function pushChats(chats) {
    if (!user) return { pushed: 0, removed: 0 };
    const list = Array.isArray(chats) ? chats : [];
    const current = new Map(list.map((c) => [c.id, c]));
    const changed = list.filter((c) => known.get(c.id) !== Number(c.updated));
    const removed = [...known.keys()].filter((id) => !current.has(id));

    if (!changed.length && !removed.length) return { pushed: 0, removed: 0 };

    emit('sync', { state: 'saving' });
    try {
      if (changed.length) await upsertChats(changed);
      for (const id of removed) await deleteChat(id);
      prime(list);
      emit('sync', { state: 'saved', at: Date.now() });
      return { pushed: changed.length, removed: removed.length };
    } catch (e) {
      emit('sync', { state: 'error', error: e.message });
      throw e;
    }
  }

  function sortChats(list) {
    return list.sort((a, b) => (b.updated || 0) - (a.updated || 0));
  }

  /* Fusion locale <-> cloud ; importe les discussions invité au premier passage. */
  async function pullAndMerge(localChats, lastSync) {
    const local = Array.isArray(localChats) ? localChats : [];
    const since = Number(lastSync) || 0;
    const remote = await pullChats();
    const remoteMap = new Map(remote.map((c) => [c.id, c]));
    const merged = new Map(remoteMap);
    const toPush = [];

    for (const c of local) {
      const r = remoteMap.get(c.id);
      if (!r) {
        if (!since || Number(c.updated) > since) toPush.push(c);
      } else if (Number(c.updated) > Number(r.updated)) {
        merged.set(c.id, c);
        toPush.push(c);
      }
    }

    if (toPush.length) await upsertChats(toPush);
    const chats = sortChats([...merged.values()]);
    prime(chats);
    return { chats, pushed: toPush.length, total: chats.length };
  }

  /* ---------- Initialisation ---------- */
  async function init() {
    try {
      const r = await fetch(CONFIG_URL, { headers: { Accept: 'application/json' } });
      if (r.ok) {
        const data = await r.json();
        config.supabaseUrl = data.supabaseUrl || '';
        config.supabaseAnonKey = data.supabaseAnonKey || '';
      }
    } catch (_) {
      // Hors ligne : le mode invité continue de fonctionner.
    }

    if (configured() && session) {
      try {
        await ensureToken();
        const u = await fetchUser();
        if (u) {
          setUser(u);
          await fetchProfile();
        } else {
          writeSession(null);
        }
      } catch (_) {
        // On garde la session en cache : elle sera réessayée plus tard.
      }
    }

    ready = true;
    emit('ready', { configured: configured(), user });
    return { configured: configured(), user };
  }

  function on(kind, fn) {
    if (!listeners[kind]) return () => {};
    listeners[kind].add(fn);
    return () => listeners[kind].delete(fn);
  }

  window.MakasiCloud = {
    init,
    on,
    isConfigured: configured,
    isReady: () => ready,
    user: () => user,
    displayName: () =>
      profile?.display_name || user?.user_metadata?.display_name ||
      (user?.email ? user.email.split('@')[0] : ''),
    signUp,
    signIn,
    signOut,
    resetPassword,
    pullChats,
    pullAndMerge,
    pushChats,
    clearRemote,
    prime,
    lastSyncKey: LAST_SYNC_KEY,
  };
})();
