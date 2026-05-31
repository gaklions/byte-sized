// graph.js — Cytoscape graph view for active/archive bites.

let cy = null;
const graphFilters = {
  domains: new Set(),     // empty = all
  statuses: new Set(["active", "deprecated"]),
  edges:   new Set(["relates_to", "depends_on", "supersedes", "conflicts_with"]),
};

const DOMAIN_PALETTE = [
  "#4f8cff", "#22d3ee", "#f9a826", "#a78bfa", "#4ade80",
  "#ec4899", "#facc15", "#fb923c", "#34d399", "#60a5fa",
];

function colorForDomain(d) {
  if (!d) return "#94a3b8";
  const idx = Math.abs(hash(d)) % DOMAIN_PALETTE.length;
  return DOMAIN_PALETTE[idx];
}
function hash(s) { let h = 0; for (const c of s) h = ((h << 5) - h) + c.charCodeAt(0) | 0; return h; }

function shapeForStatus(s) {
  if (s === "deprecated") return "rectangle";
  if (s === "superseded") return "triangle";
  return "ellipse";
}

const EDGE_COLOR = {
  relates_to:     "#64748b",
  depends_on:     "#22d3ee",
  supersedes:     "#f9a826",
  conflicts_with: "#ff5d6e",
};

function renderGraphFiltersInit() {
  const dHost = document.getElementById("graph-domains");
  if (!dHost) return;
  dHost.innerHTML = "";
  state.domains.forEach(d => {
    const id = `gd-${d}`;
    const label = document.createElement("label");
    label.innerHTML = `<input type="checkbox" id="${id}" value="${d}" checked /> <span style="color:${colorForDomain(d)}">●</span>${d}`;
    dHost.appendChild(label);
    label.querySelector("input").addEventListener("change", e => {
      if (e.target.checked) graphFilters.domains.delete(d);
      else graphFilters.domains.add(d);
      // Note: stored set holds EXCLUDED domains for simpler "all checked = all visible" semantics.
      renderGraph();
    });
  });
  document.querySelectorAll("#graph-status input").forEach(cb => {
    cb.checked ? graphFilters.statuses.add(cb.value) : graphFilters.statuses.delete(cb.value);
    cb.addEventListener("change", () => {
      cb.checked ? graphFilters.statuses.add(cb.value) : graphFilters.statuses.delete(cb.value);
      renderGraph();
    });
  });
  document.querySelectorAll("#graph-edges input").forEach(cb => {
    cb.checked ? graphFilters.edges.add(cb.value) : graphFilters.edges.delete(cb.value);
    cb.addEventListener("change", () => {
      cb.checked ? graphFilters.edges.add(cb.value) : graphFilters.edges.delete(cb.value);
      renderGraph();
    });
  });
  document.getElementById("graph-fit").addEventListener("click", () => cy && cy.fit(undefined, 40));
}

function renderGraph() {
  if (!state.index) return;
  const visible = state.index.bites.filter(r =>
    graphFilters.statuses.has(r.status) &&
    !graphFilters.domains.has(r.domain) // excluded set
  );
  const visibleIds = new Set(visible.map(r => r.id));

  const nodes = visible.map(r => ({
    data: {
      id: r.id, label: r.id, statement: r.statement || "",
      domain: r.domain, status: r.status, path: r.path,
      color: colorForDomain(r.domain), shape: shapeForStatus(r.status),
    },
  }));

  const seen = new Set();
  const edges = [];
  visible.forEach(r => {
    for (const rel of graphFilters.edges) {
      const targets = (r.edges && r.edges[rel]) || [];
      targets.forEach(t => {
        if (!visibleIds.has(t)) return;
        const k = `${r.id}|${rel}|${t}`;
        if (seen.has(k)) return;
        seen.add(k);
        edges.push({ data: { id: k, source: r.id, target: t, rel, color: EDGE_COLOR[rel] || "#64748b" } });
      });
    }
  });

  if (!cy) {
    cy = cytoscape({
      container: document.getElementById("cy"),
      elements: [...nodes, ...edges],
      style: [
        { selector: "node", style: {
            "background-color": "data(color)", "shape": "data(shape)",
            "label": "data(label)", "color": "#e6edf3",
            "font-size": 9, "text-valign": "center", "text-halign": "center",
            "text-outline-color": "#0f1115", "text-outline-width": 1,
            "width": 26, "height": 26, "border-color": "#0f1115", "border-width": 1.5,
        }},
        { selector: "node:selected", style: { "border-color": "#fff", "border-width": 3 } },
        { selector: "edge", style: {
            "width": 1.3, "line-color": "data(color)",
            "target-arrow-color": "data(color)", "target-arrow-shape": "triangle",
            "curve-style": "bezier", "arrow-scale": 0.8,
        }},
      ],
      layout: { name: "fcose", animate: false, randomize: true, nodeRepulsion: 4500, idealEdgeLength: 80 },
      wheelSensitivity: 0.2,
    });

    cy.on("tap", "node", (evt) => {
      const d = evt.target.data();
      const tip = document.getElementById("graph-tip");
      tip.classList.remove("hidden");
      tip.innerHTML = `
        <div><strong>${d.id}</strong> · <span style="color:${d.color}">${d.domain}</span> · ${d.status}</div>
        <div class="muted small" style="margin-top:4px">${escapeHtml(d.statement)}</div>
        <button class="ghost" style="margin-top:6px" onclick="openDetail('${d.id}')">Open in Bite detail →</button>
      `;
    });
    cy.on("tap", (evt) => { if (evt.target === cy) document.getElementById("graph-tip").classList.add("hidden"); });
  } else {
    cy.elements().remove();
    cy.add([...nodes, ...edges]);
    cy.layout({ name: "fcose", animate: false, randomize: false, nodeRepulsion: 4500, idealEdgeLength: 80 }).run();
  }
}

function openDetail(id) {
  state.currentBiteId = id;
  activateTab("detail");
  if (typeof loadBiteDetail === "function") loadBiteDetail(id);
}
window.openDetail = openDetail;
