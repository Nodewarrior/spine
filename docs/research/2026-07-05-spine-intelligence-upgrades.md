# Spine Intelligence Upgrades — Research Synthesis

**Date:** 2026-07-05
**Method:** 4 parallel research agents — (1) hermes-agent internals (v0.18.0), (2) headroom internals (v0.30.0), (3) landscape sweep 2026-06-15→07-05, (4) local episodic-memory feasibility audit over `~/.claude/projects/`.
**Predecessor:** `2026-06-24-memory-landscape-and-spine-gaps.md` (hygiene track: legibility backfill → drift flagging → risk-gated review → session-end auto-draft). This doc is the **intelligence track** — what makes Spine *smarter*, not just cleaner.

---

## Bottom line

The industry converged on Spine's architecture bet in the last 6 weeks — **Letta moved memory to git-backed markdown ("MemFS"), Anthropic's Managed Agents "Dreaming" keeps all derived knowledge human-readable and review-gated.** Spine is not behind architecturally. What it's missing is the **intelligence loops on top of the files**: nothing in Spine ever *derives*, *remembers what happened*, or *learns from repetition*. Four tracks close that, and every one now has a proven, portable, file-native reference implementation.

**Recommended build order:** Episodic layer (Track 2) → Synthesis curator (Track 1) → Procedural learning (Track 3) → write-time anticipated queries (Track 4, trivial, fold in immediately). Rationale: episodic is cheapest (bash/jq, zero LLM cost), immediately useful, and is the **substrate** the other tracks consume (dream mines episodes; learn mines transcripts; demand-gated promotion needs recall logs).

---

## Track 1 — Synthesis curator (`/spine-dream`): derive new knowledge from existing docs

**The flagship.** Spine's own never-built Tier 3 vision (README cites Karpathy's autoResearch). Now massively validated:

| System | Evidence |
|---|---|
| Anthropic Managed Agents "Dreaming" (May 2026, research preview) | Scheduled background review of sessions + memory → extracts recurring mistakes/workflows/preferences → rewrites memory store. Review mode: auto-apply OR human approve/reject/edit. Harvey reports **~6x task completion**. |
| Letta `/sleeptime` (letta-code v0.27.25) | Client-side periodic dreaming; agent rewrites its own memory blocks; `/doctor` audits memory quality; memory synced to a GitHub repo. |
| OpenClaw Dreaming | **Most portable implementation found.** 3-phase, fully file-based, cron `0 3 * * *`: light sleep (ingest/stage, Jaccard dedup) → REM (7-day pattern extraction → "candidate truths") → deep sleep (promotion). **Only the last phase writes long-term.** |
| DCPM paper (arXiv 2606.09483) | "Nighttime engine" induces schemas + cross-domain patterns; +5.2 pts on synthesis-shaped queries, ~0 on span recall — derivation pays only where synthesis is needed. |
| Elastic Atlas (open-sourced 06-30) | Consolidation LLM derives semantic facts **with supporting evidence pointers**, flags superseded facts, maintains playbooks with success/failure counters. |

### Anti-hallucination gates (the hard part, all solved in the wild)
1. **Demand-gating (OpenClaw):** promote only what scored ≥0.8 AND was recalled ≥3 times across ≥3 distinct query contexts. Requires a tiny recall-log JSONL beside the vault. *Nothing enters long-term memory on LLM opinion alone.*
2. **Verify-against-source (Cloudflare Agent Memory):** 8-check pass per derived fact — "is the inferred fact actually supported by the source?" Prompt-level, zero infra.
3. **Evidence pointers (Atlas):** every derived claim carries wikilinks to its source docs/episodes.
4. **Review-before-land (Anthropic):** derived docs go through the existing risk-gated review (curator-log queue) — high-risk derivations keep the human gate.
5. **Diary (OpenClaw `DREAMS.md`):** human-readable log of what was derived and why; `promote --apply` vs preview.

### Spine design sketch
- New skill `/spine-dream` + optional cron/session-stop trigger (tier3-gated).
- **Inputs:** curator-log update entries, living Plan docs' update sections, episode index (Track 2), vault docs sharing tags/wikilinks.
- **Output:** `type/derived` docs — playbooks/gotchas with `derived_from:` wikilink lists — plus a `DREAMS.md` diary in `.spine/`.
- **LLM call via user's own CLI** (headroom trick: pipe digest to `claude -p` with idle watchdog) — no API key, no cost beyond subscription.
- **Concrete first target already in the vault:** the DTC Plan doc's 9+ update entries contain a derivable playbook ("branches merge-then-delete → fresh PR each commit"; "agent-browser needs `--ignore-https-errors`"; "1.3.x SDK requires explicit CSS import"; "container-query sticky gotchas"). One dream pass = one reusable gotchas doc the next session reads first.
- **Dependency:** quality depends on hygiene-track legibility backfill; sequence after Track 2.

---

## Track 2 — Episodic memory (`/spine-sessions`): remember what happened, not just what was written

**Feasibility proven on this machine** (agent 4, read-only audit):
- Corpus: 668MB, 166 jsonl (47 top-level sessions + 119 subagent), 13 projects, ~3 months. `rg` over ALL of it: **0.2–0.4s cold**. Speed is a non-issue.
- **~99% of bytes are machinery** (hook attachments 51–84%, tool dumps); human+assistant prose ≈0.3–1%. Raw grep works but noisy → thin extraction pass needed for *precision*, not speed.
- **Free material already exists:** per-session `ai-title` records, `last-prompt` records, 14 `isCompactSummary` compaction summaries, `stop_hook_summary`/`away_summary`, and `~/.claude/history.jsonl` (4,398 prompt records indexed by project+session).
- Claude Code changelog through July 2026: **still no native session search** — genuine gap; Definite's 150-line regex skill proves grep-scale suffices.

### Design (two pieces + hook injection)
1. **Stop-hook episode extraction.** `spine-session-stop.sh` already receives `transcript_path` on stdin — **currently ignored**. Add a pure bash/jq pass (~200ms even on 28MB transcripts), placed *before* the pending-commits early-exit: extract last `ai-title`, `last-prompt`, human prompts, timestamps, `gitBranch`, files touched, any compaction summary → append one episode record to `$VAULT/.spine/episodes/`. Indexing at Stop time **preserves episodes past transcript rotation**. Skip subagent transcripts by default.
2. **`/spine-sessions` search skill** — two-tier: grep the small episode index first; drop to type-filtered `rg` over raw jsonl only on miss. Steal hermes's June rebuild wholesale:
   - **No LLM in the loop** (hermes ripped LLM reranking out: $0.30/~30s → ~20ms).
   - Result shape: verbatim match window (±5 messages) + **bookends** (first/last 3 messages) + before/after counts for scroll follow-up.
   - Deterministic rerank: hide `subagent`/`tool` sources, demote `cron`, dedup by session lineage.
   - Mode inferred from args (query→discover, session-id→read, both→scroll, none→browse).
3. **SessionStart hook:** "Recent episodes for this repo" block (last N titles + dates) after the vault-index loop (~line 94) → session continuity at startup.

**Privacy note:** episodes inherit the vault's existing work/personal boundary — episodes land in the per-vault `.spine/`, never cross it.

### Why first in build order
Cheapest (no LLM, no new deps), immediately useful ("what did we decide about X three sessions ago"), and the substrate for Tracks 1 and 3 — plus the recall-log needed for demand-gated promotion starts here.

---

## Track 3 — Procedural learning (`/spine-learn`): learn rules from repetition and failure

Existing EPIC, now with a complete blueprint from three sources:

**From headroom `learn` (v0.30.0, implementation verified):**
- Mine **ALL sessions**, not just failures — same jsonl corpus as Track 2.
- **Loop detector is the crown jewel — measured, not LLM-guessed:** collapse every tool call to a canonical signature (strip pagination args, normalize ints → `bash::grep foo`); ≥3 same-signature occurrences in a session = loop; error-loops vs refetch-loops; waste measured in tokens; **measured evidence overrides the LLM's importance guess when ranking rules**.
- Digest → single LLM call → strict JSON rules, evidence bar 2+ occurrences, "no tautologies, no one-offs, 1–3 lines, actionable ('use X instead of Y')".
- **Marker-block merge semantics:** prior learned block fed back verbatim as baseline; same-heading sections replace, unmentioned sections carry forward → learnings accumulate, never reset. Write to gitignored personal file by default (their #1115 lesson: don't pollute team files).

**From hermes (v0.18.0):**
- Post-turn autonomous review with tool whitelist locked to memory+skill ops, iteration budget 16, "a pass that does nothing is a missed learning opportunity"; **preferential order: patch loaded skills → patch existing → add support files → create new** (bias against skill sprawl).
- Deterministic staleness tier free/always-on (ACTIVE→30d STALE→90d ARCHIVED, never hard-delete, provenance-gated); LLM consolidation opt-in.
- Capacity-rejection forced consolidation: over-budget write fails with "consolidate now" + entry inventory → the model merges/drops and retries (bounded 3 attempts).

**From arXiv 2606.23127 (June 2026 — skills stored as versioned SKILL.md, literally Spine's format):**
- Collect → Diagnose → Revise → Promote; **promotion only when validation improves by margin δ**; lineage via parent pointers in frontmatter; rejected candidates kept as inactive branches.
- **Warning: cross-role transfer is negative (−4.8 to −7.5 pts)** — never auto-promote a learned rule from one repo/workflow scope to global.

### Spine design sketch
`/spine-learn` = loop detector (deterministic, bash/jq/awk over episode transcripts) + mining prompt via `claude -p` + rules landed as marker-block in vault `type/learned` doc (or per-repo learned section), human-gated at first, demand-gated promotion later. Ships as EPIC #19.

---

## Track 4 — Proactive retrieval: right doc at the moment of action

- **MemoryArena anchor result stands:** models drop to 40–60% when memory must be *used* mid-task vs recalled on request. Passive index ≠ smart memory.
- **Cheapest win — write-time anticipated queries (Cloudflare):** every capture/update prepends 3–5 questions the doc answers (frontmatter `answers:` list or intro block). Plain grep then behaves like semantic search. **Zero infra — fold into spine-capture/spine-update templates immediately.**
- **headroom ContextTracker scoring** (for later): score tracked docs against the current user message — keyword overlap ×0.5 + exact-substring bonus +0.2 + original-context overlap ×0.3 + tool affinity +0.1, linear age discount, threshold 0.3, top-2 per turn, **fail-closed workspace scoping** (they had a real cross-project leak — directly relevant to the work/personal boundary). Natural home: extend the hygiene-track post-commit drift flagging from "docs referencing files you changed" to "docs relevant to what you're doing right now."
- **ProAct (arXiv 2605.25971):** idle-time compute forecasting next-session needs and pre-gathering evidence (−28% hallucination) — folds into the dream pass, not a separate feature.

---

## Cross-cutting steals (apply anywhere)

1. **Frozen-snapshot injection** (hermes): memory rendered into context once at session start; mid-session writes persist but appear next session → prompt-cache stable. Spine's autoLoad already does this — keep it; don't add mid-session index refresh.
2. **Deterministic-first, LLM-opt-in** (hermes curator, headroom verbosity): every feature ships a free deterministic tier; LLM tier is opt-in. Matches Spine's risk-gated review direction.
3. **Keyless LLM calls** via `claude -p --output-format stream-json` with idle watchdog (headroom) — all mining/dreaming runs on the user's subscription.
4. **Decay with counters, not vibes** (headroom traffic-learner): cap 15 entries, half-life 5 days, hard expiry 21 days, render-time re-validation — a working decay model if Spine ever needs one (currently: human curator is the decay mechanism, still valid).
5. **Never delete — archive with provenance** (hermes curator, supersession chains everywhere): matches Spine's mark-don't-delete supersession design from the 06-24 doc.

## Sequencing vs the hygiene track (06-24 doc)

Hygiene and intelligence interleave; they don't compete:

1. **Track 4a (anticipated queries)** — fold into capture/update templates now (one-line template change).
2. **Track 2 (episodic)** — build now; independent of hygiene; provides substrate + recall logging.
3. **Hygiene 1–2 (legibility backfill + drift flagging)** — unblocks Track 1 quality.
4. **Track 1 (`/spine-dream`)** — the flagship; first pass targets the DTC Plan doc playbook.
5. **Track 3 (`/spine-learn`)** — EPIC #19 with the headroom/hermes/2606.23127 blueprint.
6. **Track 4b (ContextTracker-style proactive surfacing)** — extends drift flagging once it exists.

## Source confidence
- hermes/headroom: implementation-verified against fresh repo clones (file paths cited in agent reports; headroom moved to `headroomlabs-ai/headroom`).
- Landscape: URLs + dates verified; "Claude Code AutoDream" articles identified as SEO conflation — excluded.
- Local feasibility: measured on this machine (timings, byte composition, record schemas).
