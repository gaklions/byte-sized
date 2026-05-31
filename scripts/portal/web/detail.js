// detail.js — Bite detail tab: view + edit + status + edges + body preview.

let detailLoaded = null;

function renderDetailEmpty() {
  document.getElementById("detail-empty").classList.remove("hidden");
  document.getElementById("detail-view").classList.add("hidden");
  renderDetailSearch();
}

function renderDetailSearch() {
  const q = (document.getElementById("detail-search").value || "").toLowerCase();
  const ul = document.getElementById("detail-search-results");
  if (!state.index) { ul.innerHTML = ""; return; }
  const matches = state.index.bites
    .filter(r => !q || r.id.toLowerCase().includes(q) || (r.statement || "").toLowerCase().includes(q))
    .slice(0, 30);
  ul.innerHTML = matches.map(r =>
    `<li data-id="${r.id}"><span class="id">${r.id}</span>${escapeHtml(r.statement || "")}<br>
       <span class="muted small">${r.domain} · ${r.status}</span></li>`).join("");
  ul.querySelectorAll("li").forEach(li => li.addEventListener("click", () => loadBiteDetail(li.dataset.id)));
}

async function loadBiteDetail(id) {
  try {
    const data = await api("GET", `/api/bite/${encodeURIComponent(id)}`);
    detailLoaded = data;
    state.currentBiteId = id;
    document.getElementById("detail-empty").classList.add("hidden");
    document.getElementById("detail-view").classList.remove("hidden");

    const e = data.entry, fm = data.frontmatter || {};
    document.getElementById("detail-id").textContent = e.id;
    document.getElementById("detail-statement").textContent = e.statement || "";
    document.getElementById("detail-meta").textContent =
      `${e.domain} · status: ${e.status} · ${e.path} · created: ${(e.source||{}).created || "—"}`;

    document.getElementById("detail-open-vscode").href = `vscode://file/${data.abs_path}`;
    document.getElementById("detail-edit-statement").value = fm.statement || "";
    const dsel = document.getElementById("detail-edit-domain");
    if (fm.domain && !Array.from(dsel.options).some(o => o.value === fm.domain)) {
      const opt = document.createElement("option");
      opt.value = fm.domain; opt.textContent = fm.domain + " (custom)";
      dsel.appendChild(opt);
    }
    dsel.value = fm.domain || (state.domains[0] || "");
    document.getElementById("detail-edit-tags").value = (fm.tags || []).join(", ");
    document.getElementById("detail-edit-status").value = fm.status || "active";
    document.getElementById("detail-edit-rationale").value = fm.rationale || "";
    document.getElementById("detail-body").textContent = data.body || "";

    renderEdges(e);
    renderInverseEdges(e);
  } catch (err) {
    toast("err", `load detail failed: ${err.message}`);
  }
}

function renderEdges(entry) {
  const host = document.getElementById("detail-edges");
  host.innerHTML = "";
  ["relates_to", "depends_on", "supersedes", "conflicts_with"].forEach(rel => {
    const targets = (entry.edges && entry.edges[rel]) || [];
    targets.forEach(t => {
      const row = document.createElement("div");
      row.className = "edge-row";
      row.innerHTML = `<span class="rel">${rel}</span>
                       <span class="target">${t}</span>
                       <button title="Remove edge">×</button>`;
      row.querySelector("button").addEventListener("click", () => removeEdge(rel, t));
      host.appendChild(row);
    });
  });
  if (!host.children.length) {
    host.innerHTML = `<p class="muted small">No outgoing edges. Add one below.</p>`;
  }
}

function renderInverseEdges(entry) {
  const host = document.getElementById("detail-inverse");
  const e = entry.edges || {};
  const inv = [
    ["related_by_others",     "related by"],
    ["depended_on_by",        "depended on by"],
    ["superseded_by_others",  "superseded by"],
    ["conflicts_with_others", "conflicts with (inv)"],
  ];
  const lines = inv
    .map(([k, label]) => ({ label, ids: e[k] || [] }))
    .filter(x => x.ids.length)
    .map(x => `<div><strong>${x.label}:</strong> ${x.ids.join(", ")}</div>`)
    .join("");
  host.innerHTML = lines || "<em>No inverse edges.</em>";
}

async function removeEdge(rel, target) {
  if (!state.currentBiteId) return;
  try {
    const payload = await api("POST", `/api/bite/${encodeURIComponent(state.currentBiteId)}/edges`,
      { remove: [{ rel, target }] });
    if (payload.index) state.index = payload.index;
    toast("ok", `removed ${rel} → ${target}`);
    await loadBiteDetail(state.currentBiteId);
  } catch (e) { toast("err", `remove edge failed: ${e.message}`); }
}

async function addEdge() {
  if (!state.currentBiteId) return;
  const rel = document.getElementById("edge-add-rel").value;
  const target = document.getElementById("edge-add-target").value.trim();
  if (!target) return;
  if (rel === "supersedes") {
    if (!confirm(`Adding a supersedes edge will auto-flip ${target} to status=superseded and move it to _archive/. Proceed?`)) return;
  }
  try {
    const payload = await api("POST", `/api/bite/${encodeURIComponent(state.currentBiteId)}/edges`,
      { add: [{ rel, target }] });
    if (payload.index) state.index = payload.index;
    document.getElementById("edge-add-target").value = "";
    toast("ok", `added ${rel} → ${target}`);
    await loadBiteDetail(state.currentBiteId);
  } catch (e) { toast("err", `add edge failed: ${e.message}`); }
}

async function saveDetail() {
  if (!state.currentBiteId) return;
  const fm = detailLoaded?.frontmatter || {};
  const body = {};
  const newStatement = document.getElementById("detail-edit-statement").value;
  if (newStatement !== (fm.statement || "")) body.statement = newStatement;
  const newDomain = document.getElementById("detail-edit-domain").value;
  if (newDomain !== (fm.domain || "")) body.domain = newDomain;
  const newTags = document.getElementById("detail-edit-tags").value.split(",").map(s => s.trim()).filter(Boolean);
  if (JSON.stringify(newTags) !== JSON.stringify(fm.tags || [])) body.tags = newTags;
  const newRationale = document.getElementById("detail-edit-rationale").value;
  if (newRationale !== (fm.rationale || "")) body.rationale = newRationale;

  const newStatus = document.getElementById("detail-edit-status").value;
  const statusChanged = newStatus !== (fm.status || "active");

  try {
    if (Object.keys(body).length) {
      const p = await api("POST", `/api/bite/${encodeURIComponent(state.currentBiteId)}/edit`, body);
      if (p.index) state.index = p.index;
      toast("ok", "bite edited");
    }
    if (statusChanged) {
      if (newStatus === "superseded" || newStatus === "deprecated") {
        if (!confirm(`Change status to ${newStatus}? This will ${newStatus === "superseded" ? "move the file to _archive/" : "keep it in place but exclude from default queries"}.`)) return;
      }
      const p = await api("POST", `/api/bite/${encodeURIComponent(state.currentBiteId)}/status`, { status: newStatus });
      if (p.index) state.index = p.index;
      toast("ok", `status → ${newStatus}`);
    }
    await loadBiteDetail(state.currentBiteId);
  } catch (e) { toast("err", `save failed: ${e.message}`); }
}

document.addEventListener("DOMContentLoaded", () => {
  document.getElementById("detail-search").addEventListener("input", renderDetailSearch);
  document.getElementById("detail-save").addEventListener("click", saveDetail);
  document.getElementById("edge-add-btn").addEventListener("click", addEdge);
});
