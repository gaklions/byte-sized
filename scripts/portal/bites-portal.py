#!/usr/bin/env python3
"""bites-portal.py — local review portal for byte-sized.

A single-file HTTP server (stdlib only) that serves a static SPA and exposes
JSON APIs which delegate every mutation to the existing bash/pwsh lifecycle
scripts. No business logic is duplicated here — Python is just an RPC layer.

Run via the platform wrapper:
  bash scripts/bash/bites-portal.sh
  pwsh -NoProfile -File scripts/powershell/bites-portal.ps1

Or directly:
  python3 scripts/portal/bites-portal.py --port 7821 --no-open

The server binds to 127.0.0.1 only; non-loopback hosts are refused at startup.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

# ----- Constants & path resolution -----------------------------------------------

IS_WINDOWS = os.name == "nt"
SCRIPT_DIR = Path(__file__).resolve().parent
WEB_DIR = SCRIPT_DIR / "web"
EXT_ROOT = SCRIPT_DIR.parent.parent  # repo root of the byte-sized extension itself
BASH_DIR = EXT_ROOT / "scripts" / "bash"
PWSH_DIR = EXT_ROOT / "scripts" / "powershell"


# ----- Repo + config discovery ---------------------------------------------------


def find_repo_root(start: Path) -> Path:
    """Walk upward from `start` until a `.specify/` directory is found."""
    cur = start.resolve()
    while True:
        if (cur / ".specify").is_dir():
            return cur
        if cur.parent == cur:
            raise RuntimeError(
                "byte-sized portal: not inside a spec-kit project (.specify/ not found)"
            )
        cur = cur.parent


def config_path(repo_root: Path) -> Path:
    candidates = [
        repo_root / ".specify/extensions/byte-sized/byte-sized-config.yml",
        repo_root / ".specify/extensions/byte-sized/config-template.yml",
    ]
    for c in candidates:
        if c.is_file():
            return c
    raise RuntimeError(
        "byte-sized portal: no config file under .specify/extensions/byte-sized/"
    )


def yq_to_json(yaml_path: Path) -> Any:
    """Use yq (already a required dep) to convert YAML to a Python object."""
    proc = subprocess.run(
        ["yq", "eval", "-o=json", ".", str(yaml_path)],
        capture_output=True, text=True, check=False,
    )
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def read_config(cfg_file: Path) -> dict[str, Any]:
    data = yq_to_json(cfg_file) or {}
    return data if isinstance(data, dict) else {}


def cfg_get(cfg: dict[str, Any], dotted: str, default: Any = None) -> Any:
    cur: Any = cfg
    for part in dotted.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return default
    return cur if cur is not None else default


# ----- Helper script dispatcher --------------------------------------------------


def _run(cmd: list[str], cwd: Path, stdin_str: str | None = None) -> tuple[int, str, str]:
    proc = subprocess.run(
        cmd, cwd=str(cwd), input=stdin_str,
        capture_output=True, text=True, check=False,
    )
    return proc.returncode, proc.stdout, proc.stderr


def _bash(name: str, args: list[str], cwd: Path) -> tuple[int, str, str]:
    return _run(["bash", str(BASH_DIR / f"{name}.sh"), *args], cwd)


def _pwsh(name: str, args: list[str], cwd: Path) -> tuple[int, str, str]:
    cmd = ["pwsh", "-NoProfile", "-File", str(PWSH_DIR / f"{name}.ps1"), *args]
    return _run(cmd, cwd)


# Each helper is a (bash_argv, pwsh_argv) builder pair so we don't leak
# shell-specific arg names into the route handlers.

def call_promote(cwd: Path, from_file: str, index: int, overrides_json: str = "{}") -> tuple[int, str, str]:
    if IS_WINDOWS:
        return _pwsh("bites-promote", ["-FromFile", from_file, "-Index", str(index), "-OverridesJson", overrides_json], cwd)
    return _bash("bites-promote", ["--from-file", from_file, "--index", str(index), "--overrides-json", overrides_json], cwd)


def call_reject(cwd: Path, from_file: str, index: int, reason: str = "") -> tuple[int, str, str]:
    if IS_WINDOWS:
        return _pwsh("bites-reject", ["-FromFile", from_file, "-Index", str(index), "-Reason", reason], cwd)
    return _bash("bites-reject", ["--from-file", from_file, "--index", str(index), "--reason", reason], cwd)


def call_status(cwd: Path, bite_id: str, status: str, reason: str = "") -> tuple[int, str, str]:
    if IS_WINDOWS:
        return _pwsh("bites-status", ["-Id", bite_id, "-Status", status, "-Reason", reason], cwd)
    return _bash("bites-status", ["--id", bite_id, "--status", status, "--reason", reason], cwd)


def call_edit(cwd: Path, bite_id: str, **fields: str) -> tuple[int, str, str]:
    args_pwsh: list[str] = ["-Id", bite_id]
    args_bash: list[str] = ["--id", bite_id]
    if "statement" in fields:
        args_pwsh += ["-Statement", fields["statement"]]
        args_bash += ["--statement", fields["statement"]]
    if "domain" in fields:
        args_pwsh += ["-Domain", fields["domain"]]
        args_bash += ["--domain", fields["domain"]]
    if "tags_csv" in fields:
        args_pwsh += ["-TagsCsv", fields["tags_csv"]]
        args_bash += ["--tags-csv", fields["tags_csv"]]
    if "rationale_file" in fields:
        args_pwsh += ["-RationaleFile", fields["rationale_file"]]
        args_bash += ["--rationale-file", fields["rationale_file"]]
    if IS_WINDOWS:
        return _pwsh("bites-edit", args_pwsh, cwd)
    return _bash("bites-edit", args_bash, cwd)


def call_link(cwd: Path, frm: str, relation: str, to: str, remove: bool = False) -> tuple[int, str, str]:
    if IS_WINDOWS:
        args = ["-From", frm, "-Relation", relation, "-To", to]
        if remove:
            args.append("-Remove")
        return _pwsh("bites-link", args, cwd)
    args = [frm, relation, to]
    if remove:
        args.append("--remove")
    return _bash("bites-link", args, cwd)


# ----- Domain helpers (closest-active scoring, drafts walk) ----------------------


_TOKEN_RE = re.compile(r"[^a-z0-9]+")


def tokens(text: str | None) -> list[str]:
    if not text:
        return []
    return [t for t in _TOKEN_RE.split(text.lower()) if len(t) >= 3]


def overlap(a: list[str], b: list[str]) -> float:
    sa, sb = set(a), set(b)
    if not sa and not sb:
        return 0.0
    inter = len(sa & sb)
    union = len(sa | sb)
    return inter / union if union else 0.0


def closest_active(stub_statement: str, active_bites: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not stub_statement or not active_bites:
        return None
    st = tokens(stub_statement)
    if not st:
        return None
    best: dict[str, Any] | None = None
    for r in active_bites:
        sc = overlap(st, tokens(r.get("statement", "")))
        if best is None or sc > best["overlap"]:
            best = {
                "id": r.get("id"),
                "statement": r.get("statement"),
                "domain": r.get("domain"),
                "overlap": round(sc, 4),
            }
    return best


def list_drafts(repo_root: Path, bites_dir: Path, drafts_subdir: str, active_bites: list[dict[str, Any]]) -> list[dict[str, Any]]:
    drafts_dir = bites_dir / drafts_subdir
    if not drafts_dir.is_dir():
        return []
    files: list[dict[str, Any]] = []
    repo_root_resolved = repo_root.resolve()
    for entry in sorted(drafts_dir.iterdir()):
        if entry.is_dir():
            continue  # skip _rejected/ and any other subdirs
        if entry.suffix.lower() not in (".yml", ".yaml"):
            continue
        data = yq_to_json(entry)
        if not isinstance(data, list):
            continue
        stubs: list[dict[str, Any]] = []
        for idx, stub in enumerate(data):
            if not isinstance(stub, dict):
                continue
            statement = stub.get("statement") or ""
            stubs.append({
                "idx": idx,
                "statement": statement,
                "rationale": stub.get("rationale") or "",
                "domain": stub.get("domain") or "",
                "tags": stub.get("tags") or [],
                "status": stub.get("status") or "draft",
                "source": stub.get("source") or {},
                "edges": stub.get("edges") or {},
                "closest_active": closest_active(statement, active_bites),
            })
        rel = entry.resolve().relative_to(repo_root_resolved).as_posix()
        files.append({"file": rel, "stub_count": len(stubs), "stubs": stubs})
    return files


def list_rejected(repo_root: Path, bites_dir: Path, drafts_subdir: str) -> list[dict[str, Any]]:
    rejected_dir = bites_dir / drafts_subdir / "_rejected"
    if not rejected_dir.is_dir():
        return []
    out: list[dict[str, Any]] = []
    repo_root_resolved = repo_root.resolve()
    for entry in sorted(rejected_dir.iterdir()):
        if entry.suffix.lower() not in (".yml", ".yaml"):
            continue
        data = yq_to_json(entry) or []
        rel = entry.resolve().relative_to(repo_root_resolved).as_posix()
        out.append({"file": rel, "stub_count": len(data) if isinstance(data, list) else 0})
    return out


def read_bite_markdown(bite_path: Path) -> dict[str, Any]:
    text = bite_path.read_text(encoding="utf-8")
    # Split frontmatter and body on the second `---` line.
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {"frontmatter": None, "body": text}
    fm_end = -1
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            fm_end = i
            break
    if fm_end < 0:
        return {"frontmatter": None, "body": text}
    fm_yaml = "\n".join(lines[1:fm_end])
    body = "\n".join(lines[fm_end + 1:]).lstrip("\n")
    # Convert frontmatter to a dict via yq.
    proc = subprocess.run(
        ["yq", "eval", "-o=json", "-I=0", ".", "-"],
        input=fm_yaml, capture_output=True, text=True, check=False,
    )
    fm_obj: Any = None
    if proc.returncode == 0 and proc.stdout.strip():
        try:
            fm_obj = json.loads(proc.stdout)
        except json.JSONDecodeError:
            fm_obj = None
    return {"frontmatter": fm_obj, "body": body}


# ----- Server context ------------------------------------------------------------


class PortalCtx:
    def __init__(self, repo_root: Path, cfg: dict[str, Any]) -> None:
        self.repo_root = repo_root
        self.cfg = cfg
        bites_rel = cfg_get(cfg, "storage.bites_dir", ".specify/bites")
        self.bites_dir = (repo_root / bites_rel).resolve()
        self.drafts_subdir = cfg_get(cfg, "extraction.drafts_dir", "_drafts")
        self.portal_cfg = cfg_get(cfg, "portal", {}) or {}
        self.host = cfg_get(self.portal_cfg, "host", "127.0.0.1")
        self.port = int(cfg_get(self.portal_cfg, "port", 7821))
        self.open_browser = bool(cfg_get(self.portal_cfg, "open_browser", True))

    def index(self) -> dict[str, Any]:
        idx = self.bites_dir / "index.json"
        if not idx.is_file():
            return {"schema_version": "1.0", "generated_at": "", "bites": []}
        return json.loads(idx.read_text(encoding="utf-8"))

    def active_bites(self) -> list[dict[str, Any]]:
        return [r for r in self.index().get("bites", []) if r.get("status") == "active"]


# ----- Request handler -----------------------------------------------------------


JSON_HEADERS = {"Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store"}
ALLOWED_MIME = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".ico": "image/x-icon",
    ".map": "application/json",
}


def make_handler(ctx: PortalCtx) -> type[BaseHTTPRequestHandler]:

    class Handler(BaseHTTPRequestHandler):
        # quiet down the default access log
        def log_message(self, fmt: str, *args: Any) -> None:
            sys.stderr.write("portal: " + (fmt % args) + "\n")

        # -- response helpers --
        def _send_json(self, code: int, payload: Any) -> None:
            body = json.dumps(payload).encode("utf-8")
            self.send_response(code)
            for k, v in JSON_HEADERS.items():
                self.send_header(k, v)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _send_static(self, path: Path) -> None:
            if not path.is_file():
                self._send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return
            data = path.read_bytes()
            mime = ALLOWED_MIME.get(path.suffix.lower(), "application/octet-stream")
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def _read_json_body(self) -> Any:
            length = int(self.headers.get("Content-Length", "0") or 0)
            if length <= 0:
                return {}
            raw = self.rfile.read(length).decode("utf-8")
            if not raw:
                return {}
            try:
                return json.loads(raw)
            except json.JSONDecodeError as e:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": f"invalid JSON body: {e}"})
                return None

        def _refresh_response(self, result_stdout: str, stderr: str, status: int = HTTPStatus.OK) -> None:
            try:
                result = json.loads(result_stdout) if result_stdout.strip() else {}
            except json.JSONDecodeError:
                result = {"raw": result_stdout.strip()}
            payload = {
                "result": result,
                "index": ctx.index(),
                "warnings": [ln for ln in (stderr or "").splitlines() if ln.strip()],
            }
            self._send_json(status, payload)

        # -- routing --
        def do_GET(self) -> None:  # noqa: N802 (stdlib API)
            url = urlparse(self.path)
            path = unquote(url.path)
            if path == "/" or path == "/index.html":
                self._send_static(WEB_DIR / "index.html")
                return
            if path.startswith("/assets/"):
                rel = path[len("/assets/"):]
                # prevent path traversal
                target = (WEB_DIR / rel).resolve()
                if WEB_DIR.resolve() not in target.parents and target != WEB_DIR.resolve():
                    self._send_json(HTTPStatus.FORBIDDEN, {"error": "forbidden"})
                    return
                self._send_static(target)
                return
            if path == "/api/config":
                self._send_json(HTTPStatus.OK, {
                    "repo_root": str(ctx.repo_root),
                    "bites_dir": str(ctx.bites_dir.relative_to(ctx.repo_root)),
                    "drafts_subdir": ctx.drafts_subdir,
                    "portal": ctx.portal_cfg,
                    "domains": ctx.cfg.get("domains", []),
                    "edge_relations": ["relates_to", "supersedes", "depends_on", "conflicts_with"],
                    "statuses": ["active", "deprecated", "superseded"],
                })
                return
            if path == "/api/index":
                self._send_json(HTTPStatus.OK, ctx.index())
                return
            if path == "/api/drafts":
                drafts = list_drafts(ctx.repo_root, ctx.bites_dir, ctx.drafts_subdir, ctx.active_bites())
                rejected = list_rejected(ctx.repo_root, ctx.bites_dir, ctx.drafts_subdir)
                self._send_json(HTTPStatus.OK, {"drafts": drafts, "rejected_files": rejected})
                return
            m = re.match(r"^/api/bite/([^/]+)$", path)
            if m:
                bite_id = m.group(1)
                entry = next((r for r in ctx.index().get("bites", []) if r.get("id") == bite_id), None)
                if not entry:
                    self._send_json(HTTPStatus.NOT_FOUND, {"error": f"bite {bite_id} not found"})
                    return
                abs_path = (ctx.repo_root / entry["path"]).resolve()
                if not abs_path.is_file():
                    self._send_json(HTTPStatus.NOT_FOUND, {"error": f"file missing: {entry['path']}"})
                    return
                doc = read_bite_markdown(abs_path)
                self._send_json(HTTPStatus.OK, {
                    "entry": entry,
                    "frontmatter": doc["frontmatter"],
                    "body": doc["body"],
                    "abs_path": str(abs_path),
                })
                return
            self._send_json(HTTPStatus.NOT_FOUND, {"error": f"unknown route {path}"})

        def do_POST(self) -> None:  # noqa: N802
            url = urlparse(self.path)
            path = unquote(url.path)
            body = self._read_json_body()
            if body is None:
                return

            if path == "/api/drafts/promote":
                file = body.get("file")
                idx = body.get("idx")
                overrides = body.get("overrides") or {}
                if not file or idx is None:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "file + idx required"})
                    return
                code, out, err = call_promote(ctx.repo_root, file, int(idx), json.dumps(overrides))
                if code != 0:
                    self._send_json(HTTPStatus.UNPROCESSABLE_ENTITY, {"error": err.strip() or out.strip()})
                    return
                self._refresh_response(out, err)
                return

            if path == "/api/drafts/reject":
                file = body.get("file")
                idx = body.get("idx")
                reason = body.get("reason") or ""
                if not file or idx is None:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "file + idx required"})
                    return
                code, out, err = call_reject(ctx.repo_root, file, int(idx), reason)
                if code != 0:
                    self._send_json(HTTPStatus.UNPROCESSABLE_ENTITY, {"error": err.strip() or out.strip()})
                    return
                self._refresh_response(out, err)
                return

            if path == "/api/drafts/bulk":
                action = body.get("action")
                items = body.get("items") or []
                if action not in ("promote", "reject") or not isinstance(items, list):
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "action in {promote,reject} + items[] required"})
                    return
                # Process items in reverse so per-file indexes stay valid as stubs are popped.
                grouped: dict[str, list[dict[str, Any]]] = {}
                for it in items:
                    grouped.setdefault(it["file"], []).append(it)
                for f in grouped:
                    grouped[f].sort(key=lambda x: int(x["idx"]), reverse=True)
                results: list[dict[str, Any]] = []
                for f, group in grouped.items():
                    for it in group:
                        if action == "promote":
                            overrides = it.get("overrides") or {}
                            code, out, err = call_promote(ctx.repo_root, f, int(it["idx"]), json.dumps(overrides))
                        else:
                            code, out, err = call_reject(ctx.repo_root, f, int(it["idx"]), it.get("reason") or "")
                        try:
                            parsed = json.loads(out) if out.strip() else {}
                        except json.JSONDecodeError:
                            parsed = {"raw": out.strip()}
                        results.append({
                            "file": f, "idx": it["idx"], "ok": code == 0,
                            "result": parsed, "error": err.strip() if code != 0 else "",
                        })
                self._send_json(HTTPStatus.OK, {"results": results, "index": ctx.index()})
                return

            m = re.match(r"^/api/bite/([^/]+)/status$", path)
            if m:
                bite_id = m.group(1)
                status = body.get("status")
                reason = body.get("reason") or ""
                if status not in ("active", "deprecated", "superseded"):
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "status must be active|deprecated|superseded"})
                    return
                code, out, err = call_status(ctx.repo_root, bite_id, status, reason)
                if code != 0:
                    self._send_json(HTTPStatus.UNPROCESSABLE_ENTITY, {"error": err.strip() or out.strip()})
                    return
                self._refresh_response(out, err)
                return

            m = re.match(r"^/api/bite/([^/]+)/edit$", path)
            if m:
                bite_id = m.group(1)
                fields: dict[str, str] = {}
                if "statement" in body:
                    fields["statement"] = str(body["statement"])
                if "domain" in body:
                    fields["domain"] = str(body["domain"])
                if "tags" in body:
                    tags = body["tags"]
                    if isinstance(tags, list):
                        fields["tags_csv"] = ",".join(str(t).strip() for t in tags if str(t).strip())
                    else:
                        fields["tags_csv"] = str(tags)
                if "rationale" in body:
                    # Write rationale to a temp file (preserves newlines).
                    fd, tmp_path = tempfile.mkstemp(prefix="bs-rationale-", suffix=".txt")
                    try:
                        with os.fdopen(fd, "w", encoding="utf-8") as fh:
                            fh.write(str(body["rationale"]))
                        fields["rationale_file"] = tmp_path
                        code, out, err = call_edit(ctx.repo_root, bite_id, **fields)
                    finally:
                        try:
                            os.unlink(tmp_path)
                        except OSError:
                            pass
                else:
                    code, out, err = call_edit(ctx.repo_root, bite_id, **fields)
                if code != 0:
                    self._send_json(HTTPStatus.UNPROCESSABLE_ENTITY, {"error": err.strip() or out.strip()})
                    return
                self._refresh_response(out, err)
                return

            m = re.match(r"^/api/bite/([^/]+)/edges$", path)
            if m:
                bite_id = m.group(1)
                add_list = body.get("add") or []
                remove_list = body.get("remove") or []
                results: list[dict[str, Any]] = []
                for entry in remove_list:
                    code, out, err = call_link(ctx.repo_root, bite_id, entry["rel"], entry["target"], remove=True)
                    results.append({"op": "remove", **entry, "ok": code == 0, "error": err.strip() if code != 0 else ""})
                for entry in add_list:
                    code, out, err = call_link(ctx.repo_root, bite_id, entry["rel"], entry["target"], remove=False)
                    results.append({"op": "add", **entry, "ok": code == 0, "error": err.strip() if code != 0 else ""})
                self._send_json(HTTPStatus.OK, {"results": results, "index": ctx.index()})
                return

            self._send_json(HTTPStatus.NOT_FOUND, {"error": f"unknown route {path}"})

    return Handler


# ----- Entrypoint ----------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description="byte-sized review portal")
    parser.add_argument("--port", type=int, default=None)
    parser.add_argument("--host", type=str, default=None, help="Loopback host; non-loopback is refused.")
    parser.add_argument("--no-open", action="store_true", help="Don't open the browser.")
    parser.add_argument("--repo", type=str, default=None, help="Override repo root (default: discover from cwd).")
    args = parser.parse_args()

    repo_root = Path(args.repo).resolve() if args.repo else find_repo_root(Path.cwd())
    cfg = read_config(config_path(repo_root))
    ctx = PortalCtx(repo_root, cfg)
    if args.port is not None:
        ctx.port = args.port
    if args.host is not None:
        ctx.host = args.host

    if ctx.host not in ("127.0.0.1", "localhost", "::1"):
        sys.stderr.write(
            f"portal: refusing non-loopback host '{ctx.host}'. Only 127.0.0.1 / localhost / ::1 allowed.\n"
        )
        return 2

    handler_cls = make_handler(ctx)
    server = ThreadingHTTPServer((ctx.host, ctx.port), handler_cls)
    url = f"http://{ctx.host}:{ctx.port}/"
    sys.stderr.write(f"portal: serving {url} (repo: {ctx.repo_root})\n")
    sys.stderr.write("portal: Ctrl-C to stop.\n")

    if ctx.open_browser and not args.no_open:
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.stderr.write("portal: shutting down.\n")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
