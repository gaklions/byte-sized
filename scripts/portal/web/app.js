// app.js — shared state, router, fetch helpers, toasts.

const state = {
  config: null,
  index: null,
  drafts: [],
  rejectedFiles: [],
  domains: [],
  // Drafts tab state:
  flatStubs: [],         // [{file, stub}, …] in display order, filtered
  selectedKeys: new Set(),// "<file>::<idx>"
  currentKey: null,
  // Detail tab state:
  currentBiteId: null,
};

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

function stubKey(file, idx)  { return `${file}::${idx}`; }
function parseKey(k)         { const i = k.lastIndexOf("::"); return { file: k.slice(0, i), idx: Number(k.slice(i + 2)) }; }

async function api(method, path, body) {
  const opts = { method, headers: { "Content-Type": "application/json" } };
  if (body !== undefined) opts.body = JSON.stringify(body);
  const res = await fetch(path, opts);
  let payload;
  try { payload = await res.json(); } catch { payload = { error: await res.text() }; }
  if (!res.ok) {
    const msg = (payload && payload.error) || `HTTP ${res.status}`;
    throw new Error(msg);
  }
  return payload;
}

function toast(kind, message, ms = 3500) {
  const root = $("#toast-root");
  const el = document.createElement("div");
  el.className = `toast ${kind}`;
  el.textContent = message;
  root.appendChild(el);
  setTimeout(() => el.remove(), ms);
}

function applyIndexPayload(payload) {
  if (payload && payload.index) state.index = payload.index;
  (payload?.warnings || []).forEach(w => toast("warn", w));
}

// ---------- routing ----------

function activateTab(name) {
  $$(".tab").forEach(b => b.classList.toggle("is-active", b.dataset.tab === name));
  $$(".tab-panel").forEach(p => p.classList.toggle("is-active", p.id === `tab-${name}`));
  if (name === "graph"  && typeof renderGraph === "function") renderGraph();
  if (name === "detail" && typeof renderDetailEmpty === "function" && !state.currentBiteId) renderDetailEmpty();
}

// ---------- initial load ----------

async function loadAll() {
  try {
    state.config = await api("GET", "/api/config");
    state.domains = state.config.domains || [];
    state.index   = await api("GET", "/api/index");
    const d = await api("GET", "/api/drafts");
    state.drafts = d.drafts || [];
    state.rejectedFiles = d.rejected_files || [];

    const repoLabel = $("#repo-label");
    if (repoLabel) repoLabel.textContent = state.config.repo_root;

    renderDrafts();
    renderDomainFilter();
    renderGraphFiltersInit();
  } catch (e) {
    toast("err", `load failed: ${e.message}`);
  }
}

// ---------- shortcuts ----------

let gPrefix = false;

document.addEventListener("keydown", (ev) => {
  const tag = (ev.target.tagName || "").toLowerCase();
  if (["input", "textarea", "select"].includes(tag)) {
    if (ev.key === "Escape") ev.target.blur();
    return;
  }
  if (ev.key === "?") { $("#help-modal").classList.remove("hidden"); return; }
  if (ev.key === "Escape") { $("#help-modal").classList.add("hidden"); return; }

  if (gPrefix) {
    gPrefix = false;
    if (ev.key === "d") activateTab("drafts");
    else if (ev.key === "g") activateTab("graph");
    else if (ev.key === "r") activateTab("detail");
    return;
  }
  if (ev.key === "g") { gPrefix = true; setTimeout(() => (gPrefix = false), 800); return; }

  // Tab-specific shortcuts dispatched to drafts module
  if ($("#tab-drafts").classList.contains("is-active") && typeof draftsKeydown === "function") {
    draftsKeydown(ev);
  }
});

document.addEventListener("DOMContentLoaded", () => {
  $$(".tab").forEach(b => b.addEventListener("click", () => activateTab(b.dataset.tab)));
  $("#refresh-btn").addEventListener("click", loadAll);
  $("#help-btn").addEventListener("click", () => $("#help-modal").classList.remove("hidden"));
  loadAll();
});
