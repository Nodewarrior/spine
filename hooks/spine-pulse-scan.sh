#!/bin/bash
# Spine Pulse — stale-WIP detector
# Scans Claude Code activity (history.jsonl), local git branches, and Spine
# episode logs; writes {vault}/.spine/pulse.json listing work idle longer
# than the threshold. Deterministic — no LLM calls.
#
# Gated by `pulse.enabled` in ~/.spine/config.json (default: false).
# Silent-fail by design: any error exits 0 so hooks and launchd never break.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

VAULT_PATH=$(bash "$SCRIPT_DIR/spine-resolve-vault.sh" 2>/dev/null)
if [ -z "$VAULT_PATH" ] || [ ! -d "$VAULT_PATH" ]; then
  exit 0
fi
if ! command -v python3 &>/dev/null; then
  exit 0
fi

python3 - "$VAULT_PATH" <<'PYEOF' 2>/dev/null
import json, os, re, subprocess, sys, datetime, glob, tempfile, time

HOME = os.path.expanduser("~")
VAULT = sys.argv[1]
NOW = datetime.datetime.now(datetime.timezone.utc)
DEADLINE = time.monotonic() + 60  # global scan budget (seconds)

def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default

def days_ago(ts_utc):
    return (NOW - ts_utc).total_seconds() / 86400.0

def git(repo, *args, timeout=10):
    try:
        out = subprocess.run(["git", "-C", repo, *args], capture_output=True,
                             text=True, timeout=timeout)
        return out.stdout.strip() if out.returncode == 0 else ""
    except Exception:
        return ""

def claude_activity_by_project():
    """Latest prompt timestamp per project path from history.jsonl."""
    latest = {}
    path = os.path.join(HOME, ".claude", "history.jsonl")
    if not os.path.isfile(path):
        return latest
    with open(path, errors="replace") as f:
        for line in f:
            try:
                rec = json.loads(line)
            except Exception:
                continue
            proj = rec.get("project", "")
            ts = rec.get("timestamp", 0)
            if not proj or not isinstance(ts, (int, float)):
                continue
            # Normalize user-dir variants (e.g. email-suffixed home paths)
            proj = re.sub(r"^/Users/[^/]+", HOME, proj)
            if ts > latest.get(proj, 0):
                latest[proj] = ts
    return latest

def episode_recap(repo_name):
    """Last episode heading + last-prompt line for a repo, if episodes exist."""
    path = os.path.join(VAULT, ".spine", "episodes", f"{repo_name}.md")
    if not os.path.isfile(path):
        return "", ""
    title, last_prompt = "", ""
    try:
        with open(path, errors="replace") as f:
            for line in f:
                if line.startswith("## "):
                    title = line[3:].strip()
                    last_prompt = ""
                elif line.startswith("- **last prompt:**"):
                    last_prompt = line.split("**last prompt:**", 1)[1].strip()
    except Exception:
        pass
    return title, last_prompt

def default_branch(repo):
    """origin/HEAD if set, else local main/master."""
    ref = git(repo, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
    if ref and "/" in ref:
        cand = ref.split("/", 1)[1]
        if git(repo, "rev-parse", "--verify", "--quiet", cand):
            return cand
    for cand in ("main", "master"):
        if git(repo, "rev-parse", "--verify", "--quiet", cand):
            return cand
    return ""

def stale_branches(repo, threshold, max_age, ignore_branches):
    """Unmerged local branches idle between threshold and max_age days."""
    import fnmatch
    head = git(repo, "symbolic-ref", "--short", "HEAD") or "main"
    default = default_branch(repo)
    if not default:
        return []
    unmerged = set(
        b.strip().lstrip("* ").strip()
        for b in git(repo, "branch", "--no-merged", default).splitlines()
        if b.strip()
    )
    items = []
    refs = git(repo, "for-each-ref", "refs/heads",
               "--format=%(refname:short)\t%(committerdate:unix)")
    for line in refs.splitlines():
        try:
            branch, unix = line.split("\t")
            ts = datetime.datetime.fromtimestamp(int(unix), datetime.timezone.utc)
        except Exception:
            continue
        if branch not in unmerged or branch == default:
            continue
        if any(fnmatch.fnmatch(branch, pat) for pat in ignore_branches):
            continue
        idle = days_ago(ts)
        if threshold <= idle <= max_age:
            items.append({"branch": branch, "days_idle": round(idle, 1),
                          "is_checked_out": branch == head})
    return items

def main():
    config = load_json(os.path.join(HOME, ".spine", "config.json"), {})
    pulse = config.get("pulse", {})
    if not pulse.get("enabled", False):
        return
    threshold = float(pulse.get("thresholdDays", 3))
    max_age = float(pulse.get("maxAgeDays", 45))
    scan_roots = pulse.get("scanRoots", ["~/Documents/Git"])
    ignore = set(pulse.get("ignore", []))
    ignore_branches = pulse.get("ignoreBranches", ["release/*", "hotfix/*"])

    ack_path = os.path.join(VAULT, ".spine", "pulse-ack.json")
    acks = load_json(ack_path, {})
    # Local date, not UTC — a "snooze until Friday" should honor the user's day
    today = datetime.datetime.now().date().isoformat()

    activity = claude_activity_by_project()
    items = []
    partial = False

    for root in scan_roots:
        if partial:
            break
        root = os.path.expanduser(root)
        for repo in sorted(glob.glob(os.path.join(root, "*"))):
            if time.monotonic() > DEADLINE:
                partial = True
                break
            # .git DIRECTORY only — linked worktrees (.git file) share refs
            # with their parent repo and would double-report its branches.
            if not os.path.isdir(os.path.join(repo, ".git")):
                continue
            name = os.path.basename(repo)
            if name in ignore:
                continue
            ep_title, ep_prompt = episode_recap(name)
            claude_ts = activity.get(repo, 0)
            claude_idle = days_ago(datetime.datetime.fromtimestamp(
                claude_ts / 1000, datetime.timezone.utc)) if claude_ts else None

            # If Claude worked in this repo within the threshold, the user is
            # clearly around — don't nag about its branches.
            if claude_idle is not None and claude_idle < threshold:
                continue

            branch_candidates = stale_branches(repo, threshold, max_age, ignore_branches)
            for b in branch_candidates:
                key = f"{name}|{b['branch']}"
                if acks.get(key, "") >= today:
                    continue
                items.append({
                    "kind": "branch", "repo": name, "path": repo,
                    "branch": b["branch"], "days_idle": b["days_idle"],
                    "claude_days_idle": round(claude_idle, 1) if claude_idle is not None else None,
                    "episode_title": ep_title, "last_prompt": ep_prompt,
                })

            # Repo-level: Claude worked here recently, then went quiet, and
            # no stale branch covers it. Checked against pre-ack candidates so
            # snoozing a branch doesn't resurrect the repo as a session item.
            if claude_idle is not None and threshold <= claude_idle <= max_age \
                    and not branch_candidates:
                key = f"{name}|_session"
                if acks.get(key, "") >= today:
                    continue
                items.append({
                    "kind": "session", "repo": name, "path": repo,
                    "branch": git(repo, "symbolic-ref", "--short", "HEAD"),
                    "days_idle": round(claude_idle, 1),
                    "claude_days_idle": round(claude_idle, 1),
                    "episode_title": ep_title, "last_prompt": ep_prompt,
                })

    # Ascending: most recently stale first — likeliest to be truly forgotten
    # (long-idle items are usually deliberately parked).
    items.sort(key=lambda i: i["days_idle"])
    out = {
        "generated_at": NOW.isoformat(timespec="seconds"),
        "threshold_days": threshold,
        "partial": partial,
        "items": items,
    }
    out_path = os.path.join(VAULT, ".spine", "pulse.json")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(out_path), prefix=".pulse-")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(out, f, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, out_path)
    except Exception:
        try:
            os.unlink(tmp)
        except Exception:
            pass

main()
PYEOF

exit 0
