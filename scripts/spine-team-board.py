#!/usr/bin/env python3
"""Spine Team Board: one view of every live Claude Code session on this machine.

Joins two local sources, read-only, no LLM calls:
  - ~/.claude/sessions/<pid>.json   Claude Code's live session registry (name, cwd, busy/idle)
  - {vault}/.spine/episodes/*.md    Spine's per-session episode records (asks, branch, files)

and flags what no single session can see: two sessions on the same branch, two sessions
editing the same files, and sessions idle for a long time.

Usage: spine-team-board.py [--json]
Only *.json files in the registry are read; the per-session *.key files are never opened.
"""
import glob
import json
import os
import re
import subprocess
import sys
import time

IDLE_HOURS = 24  # an idle session older than this is flagged as stale
ACTIVE_HOURS = 2  # overlaps only matter between sessions busy or active this recently
ASK_CHARS = 100  # last-ask preview length
FILES_SHOWN = 4


def vault_path():
    if os.environ.get("SPINE_VAULT_PATH"):
        return os.path.expanduser(os.environ["SPINE_VAULT_PATH"])
    try:
        cfg = json.load(open(os.path.expanduser("~/.spine/config.json")))
        if isinstance(cfg.get("vaultPath"), str) and cfg["vaultPath"].strip():
            return os.path.expanduser(cfg["vaultPath"])
    except Exception:
        pass
    return os.path.expanduser("~/Documents/SpineVault")


def alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except PermissionError:
        return True  # exists, owned by someone else
    except (ProcessLookupError, ValueError, OverflowError):
        return False


def live_sessions(registry_dir):
    out = []
    for path in glob.glob(os.path.join(registry_dir, "*.json")):
        try:
            s = json.load(open(path))
        except Exception:
            continue
        if not s.get("sessionId") or not alive(s.get("pid", path.rsplit("/", 1)[-1].split(".")[0])):
            continue
        out.append(s)
    return out


EP_SESSION = re.compile(r"^- \*\*session:\*\* `([^`]+)`", re.M)
EP_FIELD = re.compile(r"^- \*\*(branch|last prompt|files touched|span):\*\* (.*)$", re.M)


def episodes(vault):
    """session id -> episode fields, from every repo's episode log."""
    found = {}
    for path in glob.glob(os.path.join(vault, ".spine", "episodes", "*.md")):
        repo = os.path.basename(path)[:-3]
        try:
            text = open(path, errors="replace").read()
        except Exception:
            continue
        for block in re.split(r"(?m)^(?=## )", text):
            m = EP_SESSION.search(block)
            if not m:
                continue
            fields = {k: v.strip() for k, v in EP_FIELD.findall(block)}
            title = block.split("\n", 1)[0].split(" — ", 1)[-1].strip()
            files = re.findall(r"`([^`]+)`", fields.get("files touched", ""))
            found[m.group(1)] = {
                "repo": repo,
                "title": title,
                "branch": fields.get("branch", "").strip("`") or None,
                "last_ask": fields.get("last prompt") or None,
                "files": list(dict.fromkeys(files)),
            }
    return found


def git(cwd, *args):
    try:
        r = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=3)
        return r.stdout.strip() if r.returncode == 0 else None
    except Exception:
        return None


def ago(ms, now):
    secs = max(0, now - int(ms) / 1000)
    if secs < 90:
        return "just now"
    if secs < 5400:
        return f"{round(secs / 60)}m ago"
    if secs < 172800:
        return f"{round(secs / 3600)}h ago"
    return f"{round(secs / 86400)}d ago"


def build(registry_dir, vault, now=None):
    now = now or time.time()
    eps = episodes(vault)
    rows = []
    for s in live_sessions(registry_dir):
        cwd = s.get("cwd") or ""
        ep = eps.get(s["sessionId"], {})
        top = git(cwd, "rev-parse", "--show-toplevel") if cwd else None
        repo = ep.get("repo") or (os.path.basename(top) if top else os.path.basename(cwd) or "?")
        rows.append({
            "name": s.get("name") or s["sessionId"][:8],
            "session_id": s["sessionId"],
            "status": s.get("status") or "unknown",
            "updated_ms": int(s.get("updatedAt") or s.get("startedAt") or 0),
            "cwd": cwd,
            "root": top or cwd,
            "repo": repo,
            "branch": (git(cwd, "rev-parse", "--abbrev-ref", "HEAD") if cwd else None) or ep.get("branch"),
            "last_ask": ep.get("last_ask"),
            "files": ep.get("files", []),
            "flags": [],
        })

    # Overlaps between sessions active at the same time: one checkout, one branch across
    # worktrees, or the same files. Idle-for-hours sessions sharing a checkout is normal.
    def active(r):
        return r["status"] == "busy" or (r["updated_ms"] and now - r["updated_ms"] / 1000 < ACTIVE_HOURS * 3600)

    for r in rows:
        partners = {"same checkout as": [], "same branch (other worktree) as": [], "also editing": []}
        for o in rows:
            if o is r or not (active(r) and active(o)):
                continue
            real_branch = r["branch"] and r["branch"] != "HEAD" and r["branch"] == o["branch"]
            if r["root"] == o["root"] and real_branch:
                partners["same checkout as"].append(o["name"])
            elif real_branch and r["repo"] == o["repo"]:
                partners["same branch (other worktree) as"].append(o["name"])
            if r["repo"] == o["repo"]:
                shared = [f for f in r["files"] if f in o["files"]]
                if shared:
                    partners["also editing"].append(f"{', '.join(shared[:2])} with {o['name']}")
        for label, names in partners.items():
            if names:
                r["flags"].append(f"{label} {'; '.join(names[:3])}{' …' if len(names) > 3 else ''}")
    for r in rows:
        if r["status"] != "busy" and r["updated_ms"] and now - r["updated_ms"] / 1000 > IDLE_HOURS * 3600:
            r["flags"].append(f"idle {ago(r['updated_ms'], now).replace(' ago', '')}")
        r["active"] = ago(r["updated_ms"], now) if r["updated_ms"] else "?"

    rows.sort(key=lambda r: (r["status"] != "busy", -r["updated_ms"]))
    return rows


def clean(s, n):
    s = re.sub(r"\s+", " ", str(s or "")).strip()
    return s if len(s) <= n else s[: n - 1] + "…"


def render(rows):
    if not rows:
        return "No live Claude Code sessions found."
    busy = sum(r["status"] == "busy" for r in rows)
    flagged = sum(bool(r["flags"]) for r in rows)
    lines = [f"# Team board · {len(rows)} sessions · {busy} busy · {flagged} flagged", ""]
    by_repo = {}
    for r in rows:
        by_repo.setdefault(r["repo"], []).append(r)
    for repo, group in by_repo.items():
        lines.append(f"## {repo}")
        for r in group:
            state = "● busy" if r["status"] == "busy" else f"○ {r['status']} · {r['active']}"
            head = f"- **{clean(r['name'], 40)}** · {state}"
            if r["branch"] and r["branch"] != "HEAD":  # HEAD = not on a branch (or not a repo)
                head += f" · `{clean(r['branch'], 60)}`"
            lines.append(head)
            if r["last_ask"]:
                lines.append(f"  - last ask: {clean(r['last_ask'], ASK_CHARS)}")
            if r["files"]:
                lines.append(f"  - files: {', '.join(clean(f, 40) for f in r['files'][-FILES_SHOWN:])}")
            for f in r["flags"]:
                lines.append(f"  - ⚠ {clean(f, 120)}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main():
    rows = build(os.path.expanduser("~/.claude/sessions"), vault_path())
    if "--json" in sys.argv:
        print(json.dumps(rows, indent=2))
    else:
        sys.stdout.write(render(rows))


if __name__ == "__main__":
    main()
