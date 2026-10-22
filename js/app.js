(() => {

"use strict";

/* ========================================
   CONFIGURATION
======================================== */

const config = window.MAKASI_CONFIG;

if (!config?.SUPABASE_URL || !config?.SUPABASE_ANON_KEY) {

  console.error("Configuration Supabase manquante.");

  alert("Configuration Makasi AI manquante.");

  return;

}

const sb = supabase.createClient(
  config.SUPABASE_URL,
  config.SUPABASE_ANON_KEY
);

const $ = selector => document.querySelector(selector);

const $$ = selector => document.querySelectorAll(selector);

const esc = value => String(value ?? "").replace(
  /[&<>"']/g,
  character => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;"
  })[character]
);


/* ========================================
   STATE
======================================== */

let user = null;

let convId = null;

let history = [];

let pending = [];

let mode = "chat";

let busy = false;

let signup = false;

let abortController = null;

let conversations = [];

let toastTimer = null;

let chatVersion = 0;

const MAX_FILE_SIZE = 8 * 1024 * 1024;

const welcomeEl = $("#welcome");

const input = $("#input");


/* ========================================
   UTILITIES
======================================== */

function toast(message) {

  const element = $("#toast");

  element.textContent = message;

  element.classList.add("show");

  clearTimeout(toastTimer);

  toastTimer = setTimeout(() => {

    element.classList.remove("show");

  }, 3000);

}

function getError(error) {

  return error?.message || "Une erreur est survenue.";

}

function closeSidebar() {

  $("#app").classList.remove("sidebar-open");

}

function scrollBottom() {

  const thread = $("#thread");

  thread.scrollTop = thread.scrollHeight;

}

function updateSendButton() {

  $("#send").disabled = busy || (
    !input.value.trim() &&
    pending.length === 0
  );

}

async function copyText(text) {

  try {

    await navigator.clipboard.writeText(text);

    toast("Copié dans le presse-papiers.");

  } catch {

    toast("Impossible de copier le contenu.");

  }

}

function download(blob, filename) {

  const url = URL.createObjectURL(blob);

  const link = document.createElement("a");

  link.href = url;

  link.download = filename;

  document.body.appendChild(link);

  link.click();

  link.remove();

  setTimeout(() => {

    URL.revokeObjectURL(url);

  }, 10000);

}


/* ========================================
   THEME
======================================== */

function applyTheme(theme) {

  const selected = ["dark", "light", "system"].includes(theme)
    ? theme
    : "dark";

  const actual = selected === "system"
    ? (
      matchMedia("(prefers-color-scheme: light)").matches
        ? "light"
        : "dark"
    )
    : selected;

  document.documentElement.dataset.theme = actual;

  localStorage.setItem("makasi-theme", selected);

  $("#theme-select").value = selected;

  $("#theme-toggle").innerHTML = actual === "dark"
    ? '<i class="fa-solid fa-sun"></i>'
    : '<i class="fa-solid fa-moon"></i>';

}

applyTheme(localStorage.getItem("makasi-theme") || "dark");

$("#theme-toggle").onclick = () => {

  const current = document.documentElement.dataset.theme;

  applyTheme(current === "dark" ? "light" : "dark");

};

$("#theme-select").onchange = event => {

  applyTheme(event.target.value);

};

matchMedia("(prefers-color-scheme: light)")
  .addEventListener("change", () => {

    if (localStorage.getItem("makasi-theme") === "system") {

      applyTheme("system");

    }

  });


/* ========================================
   ANIMATIONS
======================================== */

const animationsEnabled =
  localStorage.getItem("makasi-animations") !== "false";

$("#animations-toggle").checked = animationsEnabled;

document.body.classList.toggle(
  "no-animations",
  !animationsEnabled
);

$("#animations-toggle").onchange = event => {

  const enabled = event.target.checked;

  localStorage.setItem(
    "makasi-animations",
    String(enabled)
  );

  document.body.classList.toggle(
    "no-animations",
    !enabled
  );

};


/* ========================================
   AUTHENTICATION
======================================== */

function authMsg(message = "", success = false) {

  const element = $("#auth-msg");

  element.textContent = message;

  element.className = success
    ? "auth-message success"
    : "auth-message";

}

function setAuthMode(isSignup) {

  signup = isSignup;

  $("#auth-title").textContent = signup
    ? "Créez votre compte"
    : "Heureux de vous revoir";

  $("#auth-subtitle").textContent = signup
    ? "Rejoignez Makasi AI et commencez à explorer."
    : "Connectez-vous pour accéder à votre espace intelligent.";

  $("#auth-submit span").textContent = signup
    ? "Créer mon compte"
    : "Se connecter";

  $("#auth-switch").textContent = signup
    ? "Se connecter"
    : "Créer un compte";

  $("#auth-switch-label").textContent = signup
    ? "Vous avez déjà un compte ?"
    : "Vous n'avez pas encore de compte ?";

  $("#password").autocomplete = signup
    ? "new-password"
    : "current-password";

  authMsg();

}

$("#auth-switch").onclick = event => {

  event.preventDefault();

  setAuthMode(!signup);

};

$("#toggle-password").onclick = () => {

  const password = $("#password");

  const visible = password.type === "password";

  password.type = visible ? "text" : "password";

  $("#toggle-password").innerHTML = visible
    ? '<i class="fa-regular fa-eye-slash"></i>'
    : '<i class="fa-regular fa-eye"></i>';

  $("#toggle-password").setAttribute(
    "aria-label",
    visible ? "Masquer le mot de passe" : "Afficher le mot de passe"
  );

};

$("#auth-form").onsubmit = async event => {

  event.preventDefault();

  const email = $("#email").value.trim();

  const password = $("#password").value;

  if (!email || password.length < 6) {

    authMsg(
      "Entrez un e-mail valide et un mot de passe d'au moins 6 caractères."
    );

    return;

  }

  const button = $("#auth-submit");

  button.disabled = true;

  authMsg("Connexion en cours...", true);

  try {

    const result = signup
      ? await sb.auth.signUp({ email, password })
      : await sb.auth.signInWithPassword({ email, password });

    if (result.error) {

      throw result.error;

    }

    if (signup) {

      authMsg(
        "Compte créé. Vérifiez votre e-mail si une confirmation est nécessaire.",
        true
      );

    } else {

      authMsg("Connexion réussie.", true);

    }

  } catch (error) {

    authMsg(getError(error));

  } finally {

    button.disabled = false;

  }

};

$("#auth-google").onclick = async () => {

  const { error } = await sb.auth.signInWithOAuth({

    provider: "google",

    options: {

      redirectTo: location.origin + location.pathname

    }

  });

  if (error) {

    authMsg(error.message);

  }

};

$("#auth-reset").onclick = async event => {

  event.preventDefault();

  const email = $("#email").value.trim();

  if (!email) {

    authMsg("Saisissez d'abord votre adresse e-mail.");

    return;

  }

  const { error } = await sb.auth.resetPasswordForEmail(
    email,
    {
      redirectTo: location.origin + location.pathname
    }
  );

  authMsg(
    error
      ? error.message
      : "Un e-mail de réinitialisation vous a été envoyé.",
    !error
  );

};

$("#logout").onclick = async () => {

  const { error } = await sb.auth.signOut();

  if (error) {

    toast(error.message);

  }

};


/* ========================================
   AUTH STATE
======================================== */

sb.auth.onAuthStateChange((_event, session) => {

  const previousId = user?.id;

  user = session?.user || null;

  $("#auth").hidden = Boolean(user);

  $("#app").hidden = !user;

  if (!user) {

    stopGeneration();

    convId = null;

    history = [];

    conversations = [];

    pending = [];

    renderChips();

    $("#convs").replaceChildren();

    newChat();

    return;

  }

  if (previousId === user.id) {

    return;

  }

  const email = user.email || "";

  const displayName =
    user.user_metadata?.full_name ||
    user.user_metadata?.name ||
    email.split("@")[0] ||
    "Utilisateur";

  $("#user-name").textContent = displayName;

  $("#user-email").textContent = email;

  $("#user-avatar").textContent =
    displayName.charAt(0).toUpperCase();

  $("#welcome-name").textContent =
    displayName.split(" ")[0];

  newChat();

  loadConvs();

});


/* ========================================
   CONVERSATIONS
======================================== */

async function loadConvs() {

  if (!user) return;

  const currentUserId = user.id;

  const { data, error } = await sb
    .from("conversations")
    .select("id,title")
    .eq("user_id", currentUserId)
    .order("created_at", { ascending: false });

  if (currentUserId !== user?.id) return;

  if (error) {

    toast("Impossible de charger les conversations.");

    return;

  }

  conversations = data || [];

  renderConvs();

}

function renderConvs() {

  const search = $("#search-convs").value
    .trim()
    .toLowerCase();

  const list = $("#convs");

  list.replaceChildren();

  const filtered = conversations.filter(item =>

    (item.title || "")
      .toLowerCase()
      .includes(search)

  );

  if (!filtered.length) {

    const empty = document.createElement("p");

    empty.style.cssText =
      "padding:12px;color:var(--text-muted);font-size:12px;";

    empty.textContent = search
      ? "Aucune discussion trouvée."
      : "Aucune discussion pour le moment.";

    list.appendChild(empty);

    return;

  }

  filtered.forEach(conversation => {

    const row = document.createElement("div");

    row.className =
      "conv" +
      (conversation.id === convId ? " on" : "");

    row.tabIndex = 0;

    const title = document.createElement("span");

    title.textContent =
      conversation.title || "Nouvelle discussion";

    const actions = document.createElement("div");

    actions.className = "conv-actions";

    const rename = document.createElement("button");

    rename.innerHTML =
      '<i class="fa-solid fa-pen"></i>';

    rename.title = "Renommer";

    rename.setAttribute("aria-label", "Renommer");

    const remove = document.createElement("button");

    remove.innerHTML =
      '<i class="fa-solid fa-trash"></i>';

    remove.title = "Supprimer";

    remove.setAttribute("aria-label", "Supprimer");

    row.onclick = () => {

      openConv(conversation.id);

    };

    row.onkeydown = event => {

      if (event.target !== row) return;

      if (event.key === "Enter" || event.key === " ") {

        event.preventDefault();

        openConv(conversation.id);

      }

    };

    rename.onclick = async event => {

      event.stopPropagation();

      const value = prompt(
        "Nouveau titre :",
        conversation.title
      );

      if (!value?.trim()) return;

      const { error } = await sb
        .from("conversations")
        .update({
          title: value.trim().slice(0, 100)
        })
        .eq("id", conversation.id)
        .eq("user_id", user.id);

      if (error) {

        toast(error.message);

        return;

      }

      toast("Discussion renommée.");

      loadConvs();

    };

    remove.onclick = async event => {

      event.stopPropagation();

      if (!confirm("Supprimer cette discussion ?")) {

        return;

      }

      const { error } = await sb
        .from("conversations")
        .delete()
        .eq("id", conversation.id)
        .eq("user_id", user.id);

      if (error) {

        toast(error.message);

        return;

      }

      if (conversation.id === convId) {

        newChat();

      }

      toast("Discussion supprimée.");

      loadConvs();

    };

    actions.append(rename, remove);

    row.append(title, actions);

    list.appendChild(row);

  });

}

$("#search-convs").oninput = renderConvs;


/* ========================================
   NEW CHAT
======================================== */

function newChat() {

  stopGeneration();

  chatVersion++;

  convId = null;

  history = [];

  pending = [];

  renderChips();

  $("#thread").replaceChildren();

  $("#thread").appendChild(welcomeEl);

  input.value = "";

  resizeInput();

  updateSendButton();

  closeSidebar();

  renderConvs();

}

$("#new-chat").onclick = newChat;

$("#top-new-chat").onclick = newChat;

$("#nav-chat").onclick = () => {

  newChat();

};


/* ========================================
   OPEN CONVERSATION
======================================== */

async function openConv(id) {

  stopGeneration();

  const version = ++chatVersion;

  convId = id;

  history = [];

  $("#thread").replaceChildren();

  closeSidebar();

  renderConvs();

  const { data, error } = await sb
    .from("messages")
    .select("role,content")
    .eq("conversation_id", id)
    .order("created_at", { ascending: true });

  if (version !== chatVersion) return;

  if (error) {

    toast("Impossible de charger cette discussion.");

    return;

  }

  (data || []).forEach(message => {

    history.push(message);

    addMsg(message.role, message.content);

  });

  scrollBottom();

}


/* ========================================
   MARKDOWN
======================================== */

function renderMarkdown(text) {

  const html = marked.parse(String(text || ""));

  return DOMPurify.sanitize(html);

}


/* ========================================
   MESSAGES
======================================== */

function addMsg(role, text, images = []) {

  welcomeEl.remove();

  const message = document.createElement("div");

  message.className =
    "m " + (role === "user" ? "user" : "ai");

  const bubble = document.createElement("div");

  bubble.className = "bubble";

  if (role === "user") {

    if (images.length) {

      const gallery = document.createElement("div");

      gallery.className = "imgs";

      images.forEach(url => {

        const image = document.createElement("img");

        image.src = url;

        image.alt = "Image jointe";

        gallery.appendChild(image);

      });

      message.appendChild(gallery);

    }

    bubble.textContent = text;

  } else {

    bubble.innerHTML = renderMarkdown(text);

    bubble.querySelectorAll("pre").forEach(pre => {

      const button = document.createElement("button");

      button.className = "copy";

      button.textContent = "Copier";

      button.onclick = () => {

        const code = pre.querySelector("code");

        copyText(
          code?.textContent || pre.textContent
        );

      };

      pre.appendChild(button);

    });

  }

  message.appendChild(bubble);

  if (role !== "user" && text) {

    const tools = document.createElement("div");

    tools.className = "tools";

    const actions = [

      ["copy", "Copier", "fa-copy"],

      ["word", "Word", "fa-file-word"],

      ["pdf", "PDF", "fa-file-pdf"],

      ["xlsx", "Excel", "fa-file-excel"],

      ["retry", "Régénérer", "fa-rotate"]

    ];

    actions.forEach(([action, label, icon]) => {

      const button = document.createElement("button");

      button.dataset.action = action;

      button.innerHTML =
        `<i class="fa-solid ${icon}"></i> ${label}`;

      button.onclick = () => {

        if (action === "retry") {

          regenerate();

        } else {

          exportAs(action, text, bubble);

        }

      };

      tools.appendChild(button);

    });

    message.appendChild(tools);

  }

  $("#thread").appendChild(message);

  scrollBottom();

  return message;

}


/* ========================================
   TYPING ANIMATION
======================================== */

function addTyping() {

  const message = addMsg("assistant", "");

  message.querySelector(".bubble").innerHTML = `
    <div class="typing" aria-label="Makasi AI réfléchit">
      <i></i>
      <i></i>
      <i></i>
    </div>
  `;

  return message;

}


/* ========================================
   INPUT
======================================== */

function resizeInput() {

  input.style.height = "auto";

  input.style.height =
    Math.min(input.scrollHeight, 190) + "px";

  const length = input.value.length;

  $("#char-counter").textContent =
    length > 0 ? `${length}/30000` : "";

  updateSendButton();

}

input.oninput = resizeInput;

input.onkeydown = event => {

  if (
    event.key === "Enter" &&
    !event.shiftKey &&
    !event.isComposing &&
    !matchMedia("(max-width:850px)").matches
  ) {

    event.preventDefault();

    send();

  }

};

$("#send").onclick = send;


/* ========================================
   MODES
======================================== */

$("#modes").onclick = event => {

  const button = event.target.closest(".mode-chip");

  if (!button) return;

  mode = button.dataset.mode;

  $$(".mode-chip").forEach(chip => {

    chip.classList.toggle(
      "active",
      chip === button
    );

  });

  const placeholders = {

    chat: "Demandez ce que vous voulez à Makasi AI...",

    doc: "Quel document souhaitez-vous créer ?",

    code: "Décrivez votre projet de programmation...",

    files: "Que souhaitez-vous analyser ?"

  };

  input.placeholder = placeholders[mode];

};


/* ========================================
   SUGGESTIONS
======================================== */

$$(".suggestion-card").forEach(button => {

  button.onclick = () => {

    input.value = button.dataset.s;

    resizeInput();

    send();

  };

});

const quickPrompts = [

  "Explique-moi un concept complexe avec des exemples simples.",

  "Aide-moi à créer un projet professionnel.",

  "Rédige un e-mail professionnel.",

  "Propose-moi des idées de business innovantes.",

  "Aide-moi à améliorer mon code JavaScript.",

  "Crée un plan de formation structuré."

];

$("#quick-prompt").onclick = () => {

  const promptText = quickPrompts[
    Math.floor(Math.random() * quickPrompts.length)
  ];

  input.value = promptText;

  resizeInput();

  input.focus();

};


/* ========================================
   GENERATION STATE
======================================== */

function setBusy(value) {

  busy = value;

  $("#send").hidden = value;

  $("#stop").hidden = !value;

  updateSendButton();

}

function stopGeneration() {

  if (abortController) {

    abortController.abort();

    abortController = null;

  }

  setBusy(false);

}

$("#stop").onclick = () => {

  stopGeneration();

  toast("Génération arrêtée.");

};


/* ========================================
   SEND MESSAGE
======================================== */

async function send() {

  const text = input.value.trim();

  if ((!text && !pending.length) || busy || !user) {

    return;

  }

  const version = chatVersion;

  const currentUser = user;

  const files = [...pending];

  pending = [];

  renderChips();

  input.value = "";

  resizeInput();

  setBusy(true);

  const images = files
    .filter(file => file.type === "image")
    .map(file => file.data);

  let fullText = text;

  files
    .filter(file => file.type === "text")
    .forEach(file => {

      fullText += `

[Fichier : ${file.name}]

${file.data.slice(0,30000)}
`;

    });

  const content = images.length
    ? [

        {
          type: "text",
          text: fullText || "Analyse cette image."
        },

        ...images.map(url => ({

          type: "image_url",

          image_url: { url }

        }))

      ]
    : fullText;

  const shown = text ||
    files.map(file => file.name).join(", ");

  addMsg("user", shown, images);

  const waiting = addTyping();

  const controller = new AbortController();

  abortController = controller;

  try {

    if (!convId) {

      const { data, error } = await sb
        .from("conversations")
        .insert({

          user_id: currentUser.id,

          title: (
            shown || "Nouvelle discussion"
          ).slice(0, 80)

        })
        .select()
        .single();

      if (error) throw error;

      if (version !== chatVersion) return;

      convId = data.id;

      loadConvs();

    }

    const activeConvId = convId;

    const { error: messageError } = await sb
      .from("messages")
      .insert({

        conversation_id: activeConvId,

        role: "user",

        content: fullText || shown

      });

    if (messageError) throw messageError;

    files.forEach(file => {

      uploadFile(file).catch(error => {

        console.warn("Upload:", error);

      });

    });

    const { data, error: sessionError } =
      await sb.auth.getSession();

    if (sessionError) throw sessionError;

    const token = data.session?.access_token;

    if (!token) {

      throw new Error("Votre session a expiré.");

    }

    const response = await fetch("/api/chat", {

      method: "POST",

      signal: controller.signal,

      headers: {

        "Content-Type": "application/json",

        "Authorization": `Bearer ${token}`

      },

      body: JSON.stringify({

        mode,

        messages: [

          ...history.slice(-18),

          {
            role: "user",
            content
          }

        ]

      })

    });

    let result = await response.json();

    if (result.fallback) {
      // Vercel est bloqué par Cloudflare WAF, requête directe exécutée depuis le navigateur
      const directResponse = await fetch(result.apiUrl, {
        method: "POST",
        signal: controller.signal,
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${result.key}`
        },
        body: JSON.stringify(result.body)
      });
      if (!directResponse.ok) {
        const errorData = await directResponse.json().catch(() => ({}));
        throw new Error(
          errorData.error?.message ||
          errorData.error ||
          `Erreur IA (${directResponse.status})`
        );
      }
      const directData = await directResponse.json();
      result = {
        reply: directData.choices?.[0]?.message?.content ?? directData.content?.[0]?.text ?? ""
      };
    } else if (!response.ok) {

      throw new Error(
        result.error || "Erreur du serveur."
      );

    }

    if (version !== chatVersion) return;

    const reply = result.reply;

    if (typeof reply !== "string" || !reply.trim()) {

      throw new Error("La réponse de l'IA est vide.");

    }

    history.push(

      {
        role: "user",
        content: fullText || shown
      },

      {
        role: "assistant",
        content: reply
      }

    );

    waiting.remove();

    addMsg("assistant", reply);

    const { error: saveError } = await sb
      .from("messages")
      .insert({

        conversation_id: activeConvId,

        role: "assistant",

        content: reply

      });

    if (saveError) {

      toast("Réponse reçue, mais sauvegarde impossible.");

    }

  } catch (error) {

    if (version !== chatVersion) return;

    waiting.remove();

    if (error.name === "AbortError") {

      addMsg(
        "assistant",
        "Génération interrompue."
      );

    } else {

      addMsg(
        "assistant",
        `Une erreur est survenue : ${getError(error)}`
      );

      toast(getError(error));

    }

  } finally {

    if (abortController === controller) {

      abortController = null;

      setBusy(false);

    }

  }

}


/* ========================================
   REGENERATE
======================================== */

async function regenerate() {

  if (busy) return;

  if (!history.length) {

    toast("Aucun message à régénérer.");

    return;

  }

  const lastUser = [...history]
    .reverse()
    .find(message => message.role === "user");

  if (!lastUser) return;

  input.value = typeof lastUser.content === "string"
    ? lastUser.content
    : "Analyse le contenu précédent.";

  resizeInput();

  toast(
    "Message préparé. Modifiez-le ou envoyez-le."
  );

  input.focus();

}


/* ========================================
   FILE ATTACHMENTS
======================================== */

const allowedTextExtensions = new Set([

  "txt", "md", "csv", "json",

  "js", "ts", "py", "html",

  "css", "sql", "xml", "log"

]);

$("#file-input").onchange = async event => {

  for (const file of event.target.files) {

    if (file.size > MAX_FILE_SIZE) {

      toast(`${file.name} dépasse 8 Mo.`);

      continue;

    }

    const extension = file.name
      .split(".")
      .pop()
      .toLowerCase();

    const isImage =
      file.type.startsWith("image/");

    if (
      !isImage &&
      !allowedTextExtensions.has(extension)
    ) {

      toast(`Format non pris en charge : ${file.name}`);

      continue;

    }

    try {

      const data = await new Promise(
        (resolve, reject) => {

          const reader = new FileReader();

          reader.onload = () => {

            resolve(reader.result);

          };

          reader.onerror = reject;

          if (isImage) {

            reader.readAsDataURL(file);

          } else {

            reader.readAsText(file);

          }

        }
      );

      pending.push({

        name: file.name,

        type: isImage ? "image" : "text",

        data,

        file

      });

    } catch {

      toast(`Impossible de lire ${file.name}.`);

    }

  }

  event.target.value = "";

  renderChips();

};

function renderChips() {

  const container = $("#chips");

  container.replaceChildren();

  pending.forEach((file, index) => {

    const chip = document.createElement("span");

    const label = document.createElement("span");

    label.textContent = file.name;

    label.style.padding = "0";

    label.style.border = "0";

    label.style.background = "transparent";

    const remove = document.createElement("b");

    remove.textContent = "✕";

    remove.title = "Retirer";

    remove.onclick = () => {

      pending.splice(index, 1);

      renderChips();

    };

    chip.append(label, remove);

    container.appendChild(chip);

  });

  updateSendButton();

}


/* ========================================
   UPLOAD
======================================== */

async function uploadFile(file) {

  if (!user) return;

  const ownerId = user.id;

  const safeName = file.name.replace(
    /[^\w.-]/g,
    "_"
  );

  const uniqueId = crypto.randomUUID();

  const path =
    `${ownerId}/${uniqueId}-${safeName}`;

  const { error } = await sb.storage
    .from("files")
    .upload(path, file.file);

  if (error) throw error;

  const { error: dbError } = await sb
    .from("files")
    .insert({

      user_id: ownerId,

      name: file.name,

      path,

      mime: file.file.type,

      size: file.file.size

    });

  if (dbError) {

    console.warn(dbError.message);

  }

}


/* ========================================
   FILE MANAGER
======================================== */

$("#open-files").onclick = async () => {

  closeSidebar();

  $("#files-dlg").showModal();

  const container = $("#files-list");

  container.textContent = "Chargement...";

  const { data, error } = await sb
    .from("files")
    .select("*")
    .eq("user_id", user.id)
    .order("created_at", {
      ascending: false
    });

  if (error) {

    container.textContent = error.message;

    return;

  }

  container.replaceChildren();

  if (!data?.length) {

    container.innerHTML = `
      <p style="
        text-align:center;
        color:var(--text-muted);
        padding:30px 0;
      ">
        Aucun fichier pour le moment.
      </p>
    `;

    return;

  }

  data.forEach(file => {

    const row = document.createElement("div");

    row.className = "f";

    const name = document.createElement("span");

    name.textContent = file.name;

    const actions = document.createElement("span");

    const open = document.createElement("button");

    open.textContent = "Ouvrir";

    const remove = document.createElement("button");

    remove.textContent = "Supprimer";

    open.onclick = async () => {

      const { data: result, error } =
        await sb.storage
          .from("files")
          .createSignedUrl(file.path, 60);

      if (error) {

        toast(error.message);

        return;

      }

      window.open(
        result.signedUrl,
        "_blank",
        "noopener,noreferrer"
      );

    };

    remove.onclick = async () => {

      if (!confirm("Supprimer ce fichier ?")) {

        return;

      }

      const { error: storageError } =
        await sb.storage
          .from("files")
          .remove([file.path]);

      if (storageError) {

        toast(storageError.message);

        return;

      }

      const { error: dbError } = await sb
        .from("files")
        .delete()
        .eq("id", file.id)
        .eq("user_id", user.id);

      if (dbError) {

        toast(dbError.message);

        return;

      }

      row.remove();

      toast("Fichier supprimé.");

    };

    actions.append(open, remove);

    row.append(name, actions);

    container.appendChild(row);

  });

};

$("#close-files").onclick = () => {

  $("#files-dlg").close();

};


/* ========================================
   SETTINGS
======================================== */

$("#open-settings").onclick = () => {

  closeSidebar();

  $("#settings-dlg").showModal();

};

$("#close-settings").onclick = () => {

  $("#settings-dlg").close();

};


/* ========================================
   EXPORT
======================================== */

async function exportAs(kind, text, bubble) {

  const date = new Date()
    .toISOString()
    .slice(0,10);

  const filename = `makasi-ai-${date}`;

  if (kind === "copy") {

    await copyText(text);

    return;

  }

  if (kind === "word") {

    const safeHtml = DOMPurify.sanitize(
      bubble.innerHTML
    );

    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <style>
          body {
            font-family: Arial, sans-serif;
            font-size: 11pt;
            line-height: 1.6;
          }
          table {
            border-collapse: collapse;
            width: 100%;
          }
          td, th {
            border: 1px solid #999;
            padding: 7px;
          }
          button {
            display: none;
          }
        </style>
      </head>
      <body>
        ${safeHtml}
      </body>
      </html>
    `;

    download(
      new Blob(
        ["\ufeff", html],
        { type: "application/msword" }
      ),
      `${filename}.doc`
    );

    toast("Document Word téléchargé.");

    return;

  }

  if (kind === "pdf") {

    const { jsPDF } = window.jspdf;

    const pdf = new jsPDF({

      unit: "pt",

      format: "a4"

    });

    const pageWidth =
      pdf.internal.pageSize.getWidth();

    const pageHeight =
      pdf.internal.pageSize.getHeight();

    const margin = 45;

    const cleanText = bubble.innerText
      .replace(/\bCopier\b/g, "")
      .trim();

    const lines = pdf.splitTextToSize(
      cleanText,
      pageWidth - margin * 2
    );

    let y = 55;

    pdf.setFont("helvetica", "normal");

    pdf.setFontSize(10);

    lines.forEach(line => {

      if (y > pageHeight - 50) {

        pdf.addPage();

        y = 55;

      }

      pdf.text(line, margin, y);

      y += 15;

    });

    pdf.save(`${filename}.pdf`);

    toast("PDF téléchargé.");

    return;

  }

  if (kind === "xlsx") {

    const workbook = XLSX.utils.book_new();

    const tables = bubble.querySelectorAll("table");

    if (tables.length) {

      tables.forEach((table, index) => {

        const sheet = XLSX.utils.table_to_sheet(
          table
        );

        XLSX.utils.book_append_sheet(
          workbook,
          sheet,
          `Tableau ${index + 1}`
        );

      });

    } else {

      const rows = text
        .split("\n")
        .map(line => [line]);

      const sheet = XLSX.utils.aoa_to_sheet(
        rows
      );

      XLSX.utils.book_append_sheet(
        workbook,
        sheet,
        "Contenu"
      );

    }

    XLSX.writeFile(
      workbook,
      `${filename}.xlsx`
    );

    toast("Fichier Excel téléchargé.");

  }

}


/* ========================================
   MOBILE
======================================== */

$("#burger").onclick = () => {

  $("#app").classList.add("sidebar-open");

};

$("#close-sidebar").onclick = closeSidebar;

$("#scrim").onclick = closeSidebar;


/* ========================================
   KEYBOARD SHORTCUTS
======================================== */

document.addEventListener("keydown", event => {

  if (
    (event.ctrlKey || event.metaKey) &&
    event.key.toLowerCase() === "k"
  ) {

    event.preventDefault();

    if (user) {

      newChat();

      input.focus();

    }

  }

  if (
    event.key === "Escape" &&
    $("#app").classList.contains("sidebar-open")
  ) {

    closeSidebar();

  }

});


/* ========================================
   INITIALIZATION
======================================== */

resizeInput();

renderChips();

})();