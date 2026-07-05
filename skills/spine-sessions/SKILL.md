---
name: spine-sessions
description: Search past Claude Code sessions (episodic memory). Two-tier — grep the Spine episode log first, then targeted ripgrep over raw session transcripts. Deterministic, no LLM calls, returns verbatim excerpts with resume commands.
argument-hint: [query, or a session id to read, or nothing to browse recent sessions]
---

# Spine Sessions — Episodic Memory Search

Answer "what did we do / decide / try in a past session?" from two sources:

1. **Episode log** (fast, curated): `{vault}/.spine/episodes/{repo}.md` — one record per session (title, date, branch, last prompt, asks, files touched), written by the Stop hook.
2. **Raw transcripts** (deep, verbatim): `~/.claude/projects/{escaped-cwd}/*.jsonl` — full session history, searched with type-filtered ripgrep.

No LLM calls in the search loop — this skill is deterministic recipes. Speed: full-corpus ripgrep is sub-second; never summarize results with extra model passes unless the user asks.

## Vault Path Resolution

Same config chain as all Spine skills:
1. `$SPINE_VAULT_PATH` environment variable
2. `~/.spine/config.json` → `vaultPath` field
3. Default: `~/Documents/SpineVault/`

## Mode Selection (inferred from `$ARGUMENTS`)

| Arguments | Mode |
|---|---|
| empty | **Browse** — list recent sessions |
| a UUID-looking token | **Read** — open that session's episode / transcript |
| anything else | **Discover** — search episodes, then transcripts |

## Mode: Browse

1. Resolve repo name: `basename "$(git remote get-url origin 2>/dev/null)" .git` (fall back to directory name).
2. Show the tail of the episode log:
   ```bash
   grep -E '^## |^- \*\*session' "{vault}/.spine/episodes/{repo}.md" | tail -20
   ```
3. If no episode log exists, fall back to transcript listing:
   ```bash
   ls -t ~/.claude/projects/{escaped-cwd}/*.jsonl | head -10
   ```
   where `{escaped-cwd}` is the current working directory with `/` and `.` replaced by `-` (e.g. `/Users/jane/Git/spine` → `-Users-jane-Git-spine`).
4. Present: date — title — session id — resume command.

## Mode: Discover

### Tier 1 — episode log (always first)

```bash
grep -n -i -F -B2 -A8 -e "{query}" "{vault}/.spine/episodes/{repo}.md"
```

**Query hygiene (all modes):** treat `{query}` as literal text — use `-F` and pass it after `-e` (or `--`) so queries starting with `-` or containing regex metacharacters can't be misread as flags or patterns. Drop `-F` only when the user explicitly gives a regex.

If this answers the question, stop here — report the matching episode(s) with their `claude --resume {session_id}` commands.

### Tier 2 — raw transcripts (on miss, or when the user wants verbatim detail)

Raw transcripts are ~99% machinery (hook attachments, tool dumps). ALWAYS type-filter; never dump raw matching lines into the conversation.

1. Find candidate sessions:
   ```bash
   rg -l -i -F -e "{query}" ~/.claude/projects/{escaped-cwd}/*.jsonl
   ```
   Exclude `subagents/` transcripts by default (redundant with parents).
2. For each candidate (newest first, cap 5), pull only human/assistant prose hits:
   ```bash
   rg -i '"type":"(user|assistant)"' {file} | rg -v '"isMeta":true' | rg -i -F -e "{query}" | head -5
   ```
3. Extract orientation for each hit file (the "bookends"):
   ```bash
   rg '"type":"ai-title"' {file} | tail -1   # session title
   rg '"type":"last-prompt"' {file} | tail -1 # how it ended
   ```
4. If a session looks right, offer a targeted deep read: parse the matching lines' JSON and quote the relevant `message.content` verbatim (±2 surrounding conversation records for context), not the raw JSONL.

### Ranking (deterministic)

- Interactive sessions beat automation: demote hits from cron/headless sessions.
- Hide subagent transcripts entirely unless the user asks.
- Dedup: if a compaction-continuation session and its parent both hit, report the parent once.
- Newest first within equal relevance.

## Mode: Read

Given a session id:
1. Check the episode log for its record (fast summary).
2. Offer `claude --resume {session_id}` to reopen it.
3. For an in-place read, extract prose only:
   ```bash
   rg '"type":"(user|assistant)"' ~/.claude/projects/{escaped-cwd}/{session_id}.jsonl | rg -v '"isMeta":true'
   ```
   then quote the relevant `message.content` fields — never the raw JSON lines.

## Output Contract

```yaml
spine_sessions_result:
  status: success | no_match | error
  mode: browse | discover | read
  summary: "2 sessions matched 'OAuth PKCE' — most relevant: 2026-06-01 spine-agent-oauth"
  matches:
    - { session: "abc-123", date: "2026-06-01", title: "spine-agent-oauth", source: "episode-log", resume: "claude --resume abc-123" }
  next_actions:
    - { action: "resume session", command: "claude --resume abc-123" }
    - { action: "deep read", detail: "quote verbatim excerpts from the matched turns" }
  recovery_hint: null
```

**Status values:**
- `success` — at least one match presented
- `no_match` — both tiers empty; suggest broadening the query or checking another repo's episode log
- `error` — vault or transcript directory missing; include `recovery_hint`

## Privacy Boundary

Episodes and transcripts contain work content. Results stay within the current vault's boundary — never copy episode content into another vault, repo, or external service. If the query clearly targets a different vault/workspace, say so instead of searching across.
