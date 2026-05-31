// drafts.js — Drafts tab: list, filter, multi-select, edit, approve/reject, bulk, shortcuts.

function renderDomainFilter() {
  const sel = document.getElementById("filter-domain");
  if (!sel) return;
  sel.innerHTML = '<option value="">All domains</option>' +
    state.domains.map(d => `<option value="${d}">${d}</option>`).join("");
  const editSel = document.getElementById("edit-domain");
  if (editSel) {
    editSel.innerHTML = state.domains.map(d => `<option value="${d}">${d}</option>`).join("");
  }
  const detailSel = document.getElementById("detail-edit-domain");
  if (detailSel) {
    detailSel.innerHTML = state.domains.map(d => `<option value="${d}">${d}</option>`).join("");
  }
}

function flattenStubs() {
  const text = ($("#filter-text").value || "").toLowerCase();
  const domain = $("#filter-domain").value || "";
  const tag = ($("#filter-tag").value || "").toLowerCase();
  const overlapMax = Number($("#filter-overlap").value || 100) / 100;
  $("#filter-overlap-val").textContent = overlapMax.toFixed(2);

  const flat = [];
  state.drafts.forEach(file => {
    file.stubs.forEach(stub => {
      if (text && !(stub.statement || "").toLowerCase().includes(text)) return;
      if (domain && stub.domain !== domain) return;
      if (tag && !(stub.tags || []).some(t => String(t).toLowerCase().includes(tag))) return;
      const sc = stub.closest_active?.overlap ?? 0;
      if (sc > overlapMax) return;
      flat.push({ file: file.file, stub });
    });
  });
  state.flatStubs = flat;
}

function renderDrafts() {
  flattenStubs();
  $("#drafts-count").textContent = String(state.flatStubs.length);
  $("#drafts-total").textContent = `${state.flatStubs.length} stub${state.flatStubs.length === 1 ? "" : "s"}`;

  // Group flat stubs back by file for the list rendering.
  const byFile = new Map();
  state.flatStubs.forEach(({ file, stub }) => {
    if (!byFile.has(file)) byFile.set(file, []);
    byFile.get(file).push(stub);
  });

  const ul = $("#drafts-list");
  ul.innerHTML = "";
  for (const [file, stubs] of byFile.entries()) {
    const li = document.createElement("li");
    li.className = "file";
    li.textContent = `${file} (${stubs.length})`;
    ul.appendChild(li);

    const inner = document.createElement("ul");
    inner.className = "stubs";
    stubs.forEach(stub => {
      const key = stubKey(file, stub.idx);
      const item = document.createElement("li");
      item.className = "stub";
      if (state.currentKey === key) item.classList.add("is-current");
      item.dataset.key = key;

      const cb = document.createElement("input");
      cb.type = "checkbox";
      cb.checked = state.selectedKeys.has(key);
      cb.addEventListener("click", (e) => {
        e.stopPropagation();
        if (cb.checked) state.selectedKeys.add(key); else state.selectedKeys.delete(key);
        updateBulkCount();
      });
      item.appendChild(cb);

      const text = document.createElement("div");
      text.className = "stmt";
      text.textContent = stub.statement || "(no statement)";
      item.appendChild(text);

      const score = stub.closest_active?.overlap ?? 0;
      const badge = document.createElement("span");
      badge.className = "badge " + (score >= 0.5 ? "dup" : score === 0 ? "novel" : "");
      badge.textContent = score ? score.toFixed(2) : "new";
      item.appendChild(badge);

      item.addEventListener("click", () => selectStub(key));
      inner.appendChild(item);
    });
    ul.appendChild(inner);
  }
  updateBulkCount();
  if (state.currentKey && !state.flatStubs.find(s => stubKey(s.file, s.stub.idx) === state.currentKey)) {
    state.currentKey = null;
    showStubEditor(null);
  }
}

function updateBulkCount() {
  $("#bulk-count").textContent = `${state.selectedKeys.size} selected`;
  $("#bulk-approve").disabled = state.selectedKeys.size === 0;
  $("#bulk-reject").disabled  = state.selectedKeys.size === 0;
}

function findStubByKey(key) {
  const { file, idx } = parseKey(key);
  const f = state.drafts.find(d => d.file === file);
  if (!f) return null;
  const stub = f.stubs.find(s => s.idx === idx);
  return stub ? { file, stub } : null;
}

function selectStub(key) {
  state.currentKey = key;
  const found = findStubByKey(key);
  showStubEditor(found);
  $$("#drafts-list .stub").forEach(li => li.classList.toggle("is-current", li.dataset.key === key));
}

function showStubEditor(entry) {
  if (!entry) {
    $("#stub-empty").classList.remove("hidden");
    $("#stub-editor").classList.add("hidden");
    return;
  }
  $("#stub-empty").classList.add("hidden");
  $("#stub-editor").classList.remove("hidden");
  const { file, stub } = entry;
  $("#stub-title").textContent = stub.statement || "(no statement)";
  const src = stub.source || {};
  $("#stub-source").textContent = `${file} · feature: ${src.feature || "—"} · spec: ${src.spec || "—"}`;
  $("#edit-statement").value = stub.statement || "";
  $("#edit-rationale").value = stub.rationale || "";
  const domainSel = $("#edit-domain");
  if (stub.domain && !Array.from(domainSel.options).some(o => o.value === stub.domain)) {
    const opt = document.createElement("option");
    opt.value = stub.domain; opt.textContent = stub.domain + " (custom)";
    domainSel.appendChild(opt);
  }
  domainSel.value = stub.domain || (state.domains[0] || "");
  $("#edit-tags").value = (stub.tags || []).join(", ");
  const edges = stub.edges || {};
  $("#edit-relates").value     = (edges.relates_to || []).join(", ");
  $("#edit-depends").value     = (edges.depends_on || []).join(", ");
  $("#edit-supersedes").value  = (edges.supersedes || []).join(", ");
  $("#edit-conflicts").value   = (edges.conflicts_with || []).join(", ");

  const closest = stub.closest_active;
  const block = $("#closest-block");
  if (!closest || !closest.id) {
    block.className = "muted";
    block.textContent = "No similar active bite (this stub looks novel).";
  } else {
    const cls = closest.overlap >= 0.5 ? "dup" : closest.overlap > 0 ? "" : "novel";
    block.className = "closest-card";
    block.innerHTML = `
      <div><span class="id">${closest.id}</span>
           <span class="score ${cls}">overlap ${closest.overlap.toFixed(2)}</span></div>
      <p style="margin:6px 0 0 0">${escapeHtml(closest.statement || "")}</p>
      <p class="muted small" style="margin:6px 0 0 0">domain: ${closest.domain || "—"}</p>
    `;
  }
}

function readStubOverrides() {
  const tagsCsv = $("#edit-tags").value.trim();
  const tags = tagsCsv ? tagsCsv.split(",").map(s => s.trim()).filter(Boolean) : undefined;
  const overrides = {
    statement: $("#edit-statement").value,
    rationale: $("#edit-rationale").value,
    domain:    $("#edit-domain").value,
  };
  if (tags !== undefined) overrides.tags = tags;
  const edgesIn = (id) => {
    const v = $(id).value.trim();
    return v ? v.split(",").map(s => s.trim()).filter(Boolean) : [];
  };
  const edges = {
    relates_to:     edgesIn("#edit-relates"),
    depends_on:     edgesIn("#edit-depends"),
    supersedes:     edgesIn("#edit-supersedes"),
    conflicts_with: edgesIn("#edit-conflicts"),
  };
  if (Object.values(edges).some(a => a.length)) overrides.edges = edges;
  return overrides;
}

async function approveCurrent() {
  if (!state.currentKey) return;
  const { file, idx } = parseKey(state.currentKey);
  try {
    const payload = await api("POST", "/api/drafts/promote", { file, idx, overrides: readStubOverrides() });
    applyIndexPayload(payload);
    toast("ok", `Approved → ${payload?.result?.id || "ok"}`);
    state.selectedKeys.delete(state.currentKey);
    await reloadDraftsAndIndex({ advance: true });
  } catch (e) {
    toast("err", `approve failed: ${e.message}`);
  }
}

async function rejectCurrent() {
  if (!state.currentKey) return;
  const { file, idx } = parseKey(state.currentKey);
  const reason = prompt("Reason for rejecting (optional):") ?? "";
  try {
    const payload = await api("POST", "/api/drafts/reject", { file, idx, reason });
    applyIndexPayload(payload);
    toast("ok", `Rejected → ${payload?.result?.rejected_into || "ok"}`);
    state.selectedKeys.delete(state.currentKey);
    await reloadDraftsAndIndex({ advance: true });
  } catch (e) {
    toast("err", `reject failed: ${e.message}`);
  }
}

async function bulkAction(action) {
  if (state.selectedKeys.size === 0) return;
  let reason = "";
  if (action === "reject") {
    reason = prompt(`Reason for rejecting ${state.selectedKeys.size} stub(s) (optional):`) ?? "";
  } else if (action === "promote") {
    if (!confirm(`Approve ${state.selectedKeys.size} stub(s) as-is (no per-stub overrides)?`)) return;
  }
  const items = Array.from(state.selectedKeys).map(k => {
    const { file, idx } = parseKey(k);
    return action === "reject" ? { file, idx, reason } : { file, idx };
  });
  try {
    const payload = await api("POST", "/api/drafts/bulk", { action, items });
    if (payload.index) state.index = payload.index;
    const okCount = (payload.results || []).filter(r => r.ok).length;
    const errs = (payload.results || []).filter(r => !r.ok);
    toast(errs.length ? "warn" : "ok",
      `${action === "promote" ? "Approved" : "Rejected"} ${okCount}/${items.length}` +
      (errs.length ? ` · ${errs.length} error(s)` : ""));
    errs.slice(0, 3).forEach(r => toast("err", `${r.file}#${r.idx}: ${r.error}`));
    state.selectedKeys.clear();
    await reloadDraftsAndIndex({ advance: false });
  } catch (e) {
    toast("err", `bulk ${action} failed: ${e.message}`);
  }
}

async function reloadDraftsAndIndex({ advance }) {
  const prevIdxInFlat = advance
    ? state.flatStubs.findIndex(s => stubKey(s.file, s.stub.idx) === state.currentKey)
    : -1;
  const d = await api("GET", "/api/drafts");
  state.drafts = d.drafts || [];
  state.rejectedFiles = d.rejected_files || [];
  state.index = await api("GET", "/api/index");
  renderDrafts();
  if (advance && prevIdxInFlat >= 0) {
    const next = state.flatStubs[Math.min(prevIdxInFlat, state.flatStubs.length - 1)];
    if (next) selectStub(stubKey(next.file, next.stub.idx));
    else { state.currentKey = null; showStubEditor(null); }
  }
}

function moveSelection(delta) {
  if (state.flatStubs.length === 0) return;
  let cur = state.flatStubs.findIndex(s => stubKey(s.file, s.stub.idx) === state.currentKey);
  if (cur < 0) cur = -1;
  const next = (cur + delta + state.flatStubs.length) % state.flatStubs.length;
  const s = state.flatStubs[next];
  selectStub(stubKey(s.file, s.stub.idx));
  const el = document.querySelector(`.stub[data-key="${CSS.escape(stubKey(s.file, s.stub.idx))}"]`);
  if (el) el.scrollIntoView({ block: "nearest" });
}

function draftsKeydown(ev) {
  if (ev.key === "j") { ev.preventDefault(); moveSelection(1); }
  else if (ev.key === "k") { ev.preventDefault(); moveSelection(-1); }
  else if (ev.key === "a") { ev.preventDefault(); approveCurrent(); }
  else if (ev.key === "r") { ev.preventDefault(); rejectCurrent(); }
  else if (ev.key === "x" && state.currentKey) {
    ev.preventDefault();
    if (state.selectedKeys.has(state.currentKey)) state.selectedKeys.delete(state.currentKey);
    else state.selectedKeys.add(state.currentKey);
    renderDrafts();
    if (state.currentKey) selectStub(state.currentKey);
  } else if (ev.key === "e") { ev.preventDefault(); $("#edit-statement").focus(); }
}

async function autoHandle() {
  const ah = state.config?.portal?.auto_handle || {};
  const novelBelow = Number(ah.novel_below || 0);
  const dupAbove   = Number(ah.duplicate_above || 0);
  if (!novelBelow && !dupAbove) {
    alert("Set portal.auto_handle.novel_below and/or .duplicate_above in byte-sized-config.yml first.");
    return;
  }
  const allFlat = [];
  state.drafts.forEach(f => f.stubs.forEach(stub => allFlat.push({ file: f.file, stub })));
  const promoteItems = [], rejectItems = [];
  for (const { file, stub } of allFlat) {
    const sc = stub.closest_active?.overlap ?? 0;
    if (dupAbove   && sc >= dupAbove) rejectItems.push({ file, idx: stub.idx, reason: `auto: overlap ${sc.toFixed(2)} ≥ ${dupAbove}` });
    else if (novelBelow && sc <= novelBelow) promoteItems.push({ file, idx: stub.idx });
  }
  if (!promoteItems.length && !rejectItems.length) { toast("warn", "No stubs match auto-handle thresholds."); return; }
  if (!confirm(`Auto-approve ${promoteItems.length} novel stub(s) and auto-reject ${rejectItems.length} duplicate(s)?`)) return;
  if (rejectItems.length) {
    const p = await api("POST", "/api/drafts/bulk", { action: "reject", items: rejectItems });
    toast("ok", `Auto-rejected ${(p.results || []).filter(r => r.ok).length}/${rejectItems.length}`);
  }
  if (promoteItems.length) {
    const p = await api("POST", "/api/drafts/bulk", { action: "promote", items: promoteItems });
    toast("ok", `Auto-approved ${(p.results || []).filter(r => r.ok).length}/${promoteItems.length}`);
  }
  await reloadDraftsAndIndex({ advance: false });
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

document.addEventListener("DOMContentLoaded", () => {
  $("#filter-text").addEventListener("input",   () => renderDrafts());
  $("#filter-domain").addEventListener("change", () => renderDrafts());
  $("#filter-tag").addEventListener("input",    () => renderDrafts());
  $("#filter-overlap").addEventListener("input", () => renderDrafts());
  $("#stub-approve").addEventListener("click", approveCurrent);
  $("#stub-reject").addEventListener("click",  rejectCurrent);
  $("#bulk-approve").addEventListener("click", () => bulkAction("promote"));
  $("#bulk-reject").addEventListener("click",  () => bulkAction("reject"));
  $("#bulk-auto").addEventListener("click",    autoHandle);
});
