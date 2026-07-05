# Memory-Layer Landscape & Spine Gaps — Research Synthesis

**Date:** 2026-06-24
**Method:** 3 parallel research agents — (1) competitive (headroom, hermes-agent), (2) landscape (mem0/Letta/Zep/Graphiti/cognee/Claude native memory/LangMem), (3) community pain (HN/Reddit verbatim). Findings triangulated.

## Bottom line / robust goal (FINAL — grounded in live-vault evidence, iteration 3)

**Story:** "the auditable memory that doesn't rot." The #1 is curation burden — but live-vault evidence (iteration 3) **relocated** it: the bottleneck is **UPDATE / staleness + automation enablement**, NOT capture/coverage.

**The hard blocker — the legibility ceiling.** In the real vault, only **14/90 docs** have a `**Files changed:**` section and **46/89 have neither `date` nor `last_updated`**. ~84% of docs are structurally **invisible** to every auto-update/staleness mechanism Spine ships. Even the heavily-updated flagship Plan doc lacks `Files changed:` — its 8 manual updates could never have been auto-triggered. **Nothing else works until this is backfilled.**

**Two more empirical facts that reframe everything:**
- **`tier3: false` on the author's own machine** — the autonomous loop (silent tracking, batch capture, auto-scan) is OFF, ~3 weeks after it shipped. The likely cause: the all-or-nothing Save/Edit/Skip approval wall is too heavy (the exact "approve every write" anti-pattern 2026 SOTA rejects).
- **The vault is NOT git-versioned** (`git rev-parse` fails in `~/Documents/Lennar/`). Only audit trail = `.spine/curator-log.md`. Any "git-inspectable review queue" design must account for this.

**Evidence of the real labor:** the curator-log shows 8 manual `/spine-update` runs in June, all on one living Plan doc — hand-enriching long-lived docs as code evolves. That *is* the recurring burden, and it's update-enrichment, which iteration 2 wrongly demoted to "fast-follow."

**Final ranked plan (evidence-ordered):**
1. **Legibility backfill** (unblocks everything) — infer `Files changed:` + `last_updated` for the ~76 blind docs.
2. **Swimm-style drift flagging** in the post-commit hook — cross-ref changed files vs docs' `Files changed:` → "doc X references files you just changed — `/spine-update X`?"
3. **Replace the all-or-nothing Tier 3 wall with risk-gated review** — low-risk writes (Fix/Feature/wikilink/tag) auto-commit to the curator-log (async review queue); high-risk (Decision/Architecture/hub/ADR) keep the gate.
4. **Auto-draft update sections at session end** for living docs the session's commits touched.

**Dropped:** `valid_until` (premature formalization). **Kept:** `superseded_by`/`supersedes` + recall demotion (folds into the update loop, not a separate fast-follow). **Prerequisite to proving any of this:** a benchmark vs plain markdown.

**🔑 Pivotal question — RESOLVED (2026-06-25):** *why* is `tier3: false`? **Neither trust nor the approval wall — it's an onboarding gap in `spine-init`.** The "Enable Tier 3?" prompt exists only in Fresh Vault Mode (Step 2a); this vault was **adopted** (pre-existing Obsidian vault), and Adopt Mode (Step 2b) writes the default `tier3:false` and never asks. The author was never offered the choice. Evidence: commit `c52bd33` ("tier3 opt-in, defaults off"); `spine-init` SKILL.md Step 2a line 29 (prompt) vs Step 2b line 138 (silent default); config has only ever been `false`. **Implication:** the iter-3 "approval wall too heavy" hypothesis is likely wrong; the immediate unblock is flipping the flag, and the product fix is adopt-mode offering the toggle (or risk-gated autonomy removing the all-or-nothing flag).

> Provenance: iter-1 ranked temporal awareness #1; iter-2 reframed to curation-burden + demoted temporal to fast-follow; **iter-3 (live vault) relocated #1 to update/staleness+enablement and surfaced the legibility ceiling + disabled-tier3 + non-git-vault facts.** Earlier framings preserved below.

---

## (Iteration 1) Original framing — temporal awareness as #1

**Make Spine temporally aware so it never serves stale knowledge with false confidence.**

This was the single best-supported direction from the broad sweep: simultaneously the #1 community pain, the #1 landscape gap with no existing Spine roadmap slot, and where competitors are actively racing — 100% file-native, preserving Spine's no-DB / inspectable / human-in-loop identity. (Reframed in iteration 2; see top.)

## Evidence triangulation

| Theme | Competitive | Landscape | Community |
|---|---|---|---|
| **Staleness / temporal rot** | (implicit in CCR/consolidation) | #1 true gap, NO roadmap slot; Zep/Graphiti/cognee do temporal supersession | **#1 pain, most recurrent across all communities** |
| Learn from failures | headroom `learn` mines failed sessions → playbooks; hermes auto skill-gen | high-value gap | #3 pain ("brand-new hire every session") |
| Scored retrieval | hermes SQLite FTS5; headroom BM25-IDF | high gap — BM25 + recency + access-freq, explicitly NOT vectors | #5 vector/RAG disappointment (similarity ≠ relevance) |
| Curation burden | hermes hard caps force consolidation | conflict/consolidation gap | #4 pain — **Spine's most-exposed weakness** |
| Inspectable / portable / local / no-blackbox | — | Anthropic native memory tool chose files over vector DB (validates Spine) | Spine ALREADY WINS these |

## What Spine already wins (keep as differentiators)
- Inspectable, git-versionable, roll-back-able memory (plain markdown + wikilinks + audit skills).
- No setup friction, no proprietary memory server (answers the "black box" complaint).
- Portable / tool-neutral / local-first (answers lock-in + privacy fears).
- Human-approved writes + no auto-fact-extraction → dodges hallucinated-memory failure mode.
- No vectors → dodges similarity≠relevance retrieval misses.

## What Spine still suffers (honest)
- **Manual-curation burden** — the biggest file-based complaint; people skip notes exactly when busy.
- **Staleness** — `spine-scan`/`spine-health` *detect* stale docs but markdown still rots; no notion of one fact superseding another.
- **Doesn't auto-learn from mistakes** — human-gated capture learns only when told.
- **Auto-load index tension** — index is signposts not payload (good), but it grows with the vault, and recall quality depends on the agent picking the right doc (retrieval-selection problem).
- **Unproven** — no benchmark showing it beats plain markdown.

## Off the table by design (NOT gaps)
- Vector / embedding retrieval — files + nav + BM25 cover Spine's scope; Anthropic's own file-based memory validates the bet.
- Fully autonomous self-editing memory — conflicts with the human-approval gate (a deliberate tension, not a deficiency).
- Auto-forgetting/decay — the human curator IS the decay mechanism; auto-deletion risks discarding curated knowledge.

## Steal list (file-native, ranked)
1. **Temporal supersession / staleness** [HIGH, no roadmap slot] — frontmatter `valid_until` + `superseded-by` wikilink; health-audit goes detection → active supersession; auto-load/recall demote or hide superseded docs.
2. **Scored retrieval** [HIGH] — BM25 + recency + access-frequency ranking (maps to planned `/spine-search` + "formalized retrieval / CCR"). NOT vectors.
3. **Learn-from-failures** [HIGH] — `type/failure` doc class (symptom → wrong path → root cause → guard), agent-drafted, human-approved. (Existing epic `/spine-learn`.)
4. **Conflict resolution / consolidation** [MED-HIGH] — extend health-audit to dedup/merge contradictory docs (addresses curation burden).
5. **CCR-style pointer/retrieve as a tool** [MED] — expose recall-as-tool so full doc bodies load only on demand (cuts auto-load growth).
6. **Forced-consolidation capacity budget** [MED] — token cap on signpost layer that forces curation when exceeded (from hermes).

## How it sequences with existing epics
- Existing roadmap epics: `/spine-learn` (failures), token/cache opt, formalize retrieval (CCR), cross-agent vault.
- **New, unslotted, highest-signal:** temporal staleness layer. Recommend it as the next brainstorm target; it composes with scored retrieval (CCR) and learn-from-failures to form a coherent "trustworthy, non-rotting memory" story.

## Source confidence
- Competitive: versions/stars/dates verified via GitHub API.
- Landscape: approaches search-confirmed; vendor benchmark scores conflict — not comparable.
- Community: direct verbatim quotes with URLs+dates; founder pitches excluded from ranking; X/Twitter weak (auth-walled).

---

# Iteration 2 — Hardening pass (adversarial + mechanics)

Two agents: a red-team of the iteration-1 goal, and a source-grounded mechanics deep-dive. Both ran against the actual Spine skills/hooks.

## Red-team verdict: REFRAME, not crown
- **Two failure modes split the goal.** (A) doc never written/updated = curation burden → *fixed* by auto-capture. (B) doc was right, reality moved, contradictory docs compete at recall → *not* fixed by auto-capture; **worsened** by it. B is the only thing that justifies a temporal layer.
- **For Spine today** (sparse, single-user, git-versioned): coverage is the binding constraint → **curation-burden reduction is the higher-ROI #1**; temporal demotion is a fast-follow that becomes #1 once the vault is mature/high-coverage.
- **Everything Spine does is report-only.** `spine-health` Check 2, `spine-update` auto-detect, and `spine-scan` (which already writes `stale:`/`obsolete:` flags) all surface findings *to the human*. None acts when **Claude** auto-loads the index or recalls. The consumer-side gap is genuine even single-user.
- **`valid_until` = premature formalization → drop.** **`superseded_by` + recall-demotion = the crown jewel → keep.**
- **Benchmark is a prerequisite** to ranking any feature #1 (Spine has no proof it beats plain markdown).

## Mechanics (source-read, steal-ready)
- **Zep/Graphiti** — bi-temporal: 4 timestamps/edge (transaction time `created_at`/`expired_at`; valid time `valid_at`/`invalid_at`). LLM flags contradictions, a **deterministic gate** invalidates only on validity-window overlap; `old.invalid_at = new.valid_at`. **Mark, never delete; exclusion at retrieval is opt-in (annotate, don't hide).**
- **Letta sleep-time** — background agent rewrites shared blocks; `rethink` (wholesale) vs `replace` (surgical); turn-cadence trigger (default every 5).
- **LangMem** — LLM tool-choice: `PatchDoc` (supersede in place) vs new-schema (keep both) vs `RemoveDoc`; conservative default keeps unmentioned memories; consolidation runs debounced in background.
- **cognee** — `memify` is extraction/enrichment, **not** decay; consolidates entity descriptions in place; **no time-decay anywhere** → independently validates Spine's "human curator is the decay mechanism."

## File-native design for the temporal fast-follow
- **Git is the transaction axis (T′) for free** → frontmatter only carries valid-time + chain pointer. No `created_at`/`expired_at` table needed.
- **Schema:** extend existing `status` enum with `superseded`; add `superseded_by: "[[successor]]"` + `superseded_at: YYYY-MM-DD` on the stale doc; reciprocal `supersedes: "[[old]]"` on the successor. Current truth = tail of the chain (no `superseded_by`).
- **Reciprocal wikilinks** render as a visible directed edge in the Obsidian graph + a discrete git diff — the differentiators over silent in-place edits.
- **Index discovery (verified):** `spine-session-start.sh` greps only `type/spine` hubs and emits hub + child-count — superseded **child** docs never appear in the index. So index-level handling is needed **only for superseded hubs**; child demotion lives in the **hub's child-wikilink list** and **`/spine-recall`**.
- **Fires by extending existing hooks** (not one new trigger): capture Step 6 (already detects contradictions → propose mark in Step 4 review), scan Phase 1d (detection-only flag, never auto-write `superseded`), health Check 3 (consolidate contradictory clusters), manual `/spine-update`.
- **Human is the deterministic gate** (replaces Graphiti's temporal-overlap check): LLM only *flags*; human approves before any frontmatter write. Mark-don't-delete; recall still loads superseded docs but loads current tail first and tags them `[SUPERSEDED → successor]`; log to `curator-log.md`.

## Lead open questions for the brainstorm
1. Major-contradiction → new-doc-+-chain vs minor → in-place edit: adopt the magnitude split or pick one?
2. `status: superseded` enum vs scan's `superseded: true` boolean (a doc can be `stale` but not yet `superseded` — does the enum collapse orthogonal cases)?
3. Partial supersession — a Spine doc holds many facts; supersede whole doc, split, or annotate a section?
4. `superseded_at` semantics — successor date, contradicting-commit date, or human-entered?
5. Should scan ever auto-mark, or always flag-only (human-gate vs review burden)?
6. Cross-repo supersession (recall is per-repo today).

## Recommended sequencing
1. **Benchmark harness** (prerequisite) — prove Spine improves outputs vs plain markdown.
2. **Curation-burden reduction** (#1) — strengthen auto-capture/auto-update so coverage stops depending on discipline.
3. **Recall-time supersession** (fast-follow) — `superseded_by`/`supersedes` + recall/hub demotion, human-gated, git-inspectable.
4. Then the existing epics: `/spine-learn`, token/cache opt, formalized retrieval (CCR), cross-agent vault.

---

# Iteration 3 — Live-vault validation of the #1 goal (the decisive pass)

One agent pressure-tested the reframed #1 against the **actual vault and config**, not just the web. It overturned iteration 2's location of the bottleneck.

## SOTA (2026) for reducing curation burden — the dominant pattern: **autonomous capture by default, gated by RISK not by WRITE**
- **Auto-capture:** git-cliff, release-please (deterministic changelog); Mintlify docs-on-autopilot, Ellipsis, Greptile, Devin Knowledge, Claude Code memory (LLM, mostly no pre-approval gate).
- **Docs-derived-from-code / drift detection (the strand Spine most lacks):** **Swimm Auto-sync** (docs reference live code; auto-update on small change, flag a human task on large change — canonical design), Driver.ai (DAG reprocessing on commit), oasdiff/cog/embedme `--verify` (CI fails on drift). Academic: DocPrism (2025, 94%), Panthaplackel JIT inconsistency, CoCC.
- **AI ADRs:** Lore (2026) makes the git commit message itself the decision record via trailers.
- **Approval tax = anti-pattern for routine writes (2026 consensus):** Anthropic autonomy telemetry ("oversight ≠ approving every action; be positioned to intervene when it matters"; experienced users move 20%→40%+ full-auto), Redis/Augment tiered risk-gated review + async queues. Shared caveat: confidence-gating alone is unsafe (models confidently wrong) — route on trust **and** risk.

## Empirical findings (live vault `~/Documents/Lennar/` + `~/.spine/config.json`)
- **A — autonomous loop is OFF:** `tier3: false`. Silent tracking, batch capture, auto-scan don't run; post-commit hook only nudges. ~3 weeks after Tier 3 shipped. The author hasn't enabled their own flagship feature.
- **B — capture works; coverage is NOT the bottleneck:** 26 docs created/touched in last 30 days, good multi-type coverage (8 for one new feature alone).
- **C — real burden is UPDATE:** curator-log shows 8 manual `/spine-update` runs in June, all on one living Plan doc — hand-enriching as code evolves.
- **D — legibility ceiling (hard constraint):** only 14/90 docs have `Files changed:`; 46/89 have neither `date` nor `last_updated`; ~84% of vault is invisible to every auto-update/staleness mechanism. The flagship Plan doc itself lacks `Files changed:`.
- **E — vault not git-versioned:** `git rev-parse` fails; only audit trail is `.spine/curator-log.md`.

## Verdict
Curation burden **is** the right #1 — but it lives in **UPDATE/STALENESS + AUTOMATION ENABLEMENT**, not capture/coverage. Iteration 2's "coverage gap" was an artifact of (i) half the docs predating metadata conventions (tooling-blind) and (ii) the autonomous features being disabled. Update-enrichment — which iter-2 demoted to fast-follow — is the actual recurring labor. Rejected alternatives (learn-from-failures, scored search, benchmark-as-#1): no usage signal supports them; `autoLoad:true` shows no retrieval pain, no failure-capture signal anywhere.

## Design directions (ROI-ranked) — see top "Final ranked plan"
Legibility backfill → Swimm-style drift flagging in post-commit hook → replace all-or-nothing Tier 3 wall with risk-gated review (curator-log as async queue) → session-end auto-draft of update sections.

## Open questions
1. **Why `tier3:false`?** (trust / approval-wall-too-heavy / never-flipped) — highest-value to confirm; verdict pivots on it.
2. git-init the vault so a "git-inspectable review queue" is real (not curator-log-only)?
3. Risk-tier taxonomy: auto-accept Fix/Feature/wikilink/tag; gate Decision/Architecture/hub/ADR (SOTA caveat: models fabricate the "why" on decision records)?
4. Legibility backfill: opportunistic (on next touch) vs one-shot bulk (unblocks tooling now, but one large unreviewed write)?
