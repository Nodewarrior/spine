---
name: spine-dream
description: Synthesis curator. Reads accumulated vault docs, update sections, and episode logs, then derives NEW higher-level knowledge — reusable playbooks and gotcha docs — with evidence pointers back to every source. Human-gated writes, DREAMS.md audit diary. Spine's "dreaming" pass.
argument-hint: [optional: feature area or doc to synthesize from, e.g. "Trade-In"]
---

# Spine Dream — Derive Knowledge, Don't Just Store It

Capture and update record *what happened*. Dream reads many records and distills
*what we learned* — the gotchas, rules, and playbooks buried across update
sections and episodes — into `type/derived` docs a future session reads first.

Every derived claim must trace to a source. Nothing lands without human approval.

## Vault Path Resolution

Same config chain as all Spine skills:
1. `$SPINE_VAULT_PATH` environment variable
2. `~/.spine/config.json` → `vaultPath` field
3. Default: `~/Documents/SpineVault/`

## Phase 1: Gather (deterministic — no judgment yet)

1. Resolve repo name: `basename "$(git remote get-url origin 2>/dev/null)" .git` (fall back to directory name).
2. If `$ARGUMENTS` names a feature or doc, scope to it. Otherwise find the richest synthesis targets in `{vault}/{repo}/`:
   ```bash
   grep -rlc "^## Update\|^## 20" "{vault}/{repo}" | sort -t: -k2 -rn | head -5
   ```
   Living docs with 3+ dated update sections are the prime targets.
3. Also load, when present:
   - `{vault}/.spine/curator-log.md` entries mentioning the target docs
   - `{vault}/.spine/episodes/{repo}.md` episodes touching the same feature
   - Sibling docs sharing the feature folder or tags
4. If nothing has 3+ updates and no argument was given, report "nothing dense enough to dream about yet" and stop.

## Phase 2: Derive Candidates

Read the gathered material and extract **candidate lessons** — knowledge that is
*implied across* the sources but written down nowhere as a standalone fact:

- **Gotchas**: "X looks safe but does Y" traps hit more than once, or hit once at high cost
- **Rules**: "always/never" patterns that repeat across updates ("pin the CDN version", "fresh PR per commit")
- **Playbooks**: multi-step procedures reconstructable from repeated update sections
- **Contradictions**: places where a later update reverses an earlier doc (flag, don't resolve)

For each candidate record: the claim (1-3 sentences), the source quote(s) that
support it, and wikilinks to every source doc.

**Do NOT derive**: anything stated in only one place with no reinforcement (that's
already captured — dreaming adds nothing), speculation beyond what sources say,
or generic best practices the sources don't specifically evidence.

## Phase 3: Verify Against Source (the hallucination gate)

For EVERY candidate, before presenting, check:
1. Does the quoted source text actually say this, or did I infer beyond it?
2. Is the claim still current — does a later update section supersede it?
3. Are all wikilinked docs real files in the vault?

Drop any candidate that fails. Mark inference-but-well-supported claims with
`confidence: inferred` vs `confidence: stated` in the draft frontmatter.

## Phase 4: Present for Review

Show all surviving candidates at once:

```
🦴 Spine Dream: derived {N} candidate lessons from {sources}:

[1] {Gotcha|Rule|Playbook} — {claim, one line}
    Evidence: {source doc} — "{short quote}"

For each: (S)ave into the derived doc, (E)dit, or S(k)ip?
```

Group approved candidates into ONE doc per feature area (not one doc per lesson).

## Phase 5: Land

For each approved doc:

1. Write `{vault}/{repo}/{feature}/Derived - {Topic} Playbook.md`:
   ```markdown
   ---
   title: "Derived - {Topic} Playbook"
   date: {YYYY-MM-DD}
   tags:
     - {repo}
     - {feature}
     - type/derived
   derived_from:
     - "[[{source doc 1}]]"
     - "[[{source doc 2}]]"
   answers:
     - "{question this doc answers, as a future session would ask it}"
   ---

   # Derived - {Topic} Playbook

   > [!tip] Distilled from {N} update sections across {M} docs ({date range}).
   > Read this BEFORE working on {feature}.

   ## Gotchas
   - **{claim}** — evidence: [[{source}]] ({confidence: stated|inferred})

   ## Rules
   ...

   ## Playbook
   ...
   ```
2. Add a `[[wikilink]]` to the derived doc in the feature's spine note under a **Derived** section.
3. Append to `{vault}/.spine/DREAMS.md` (create if missing) — newest at top:
   ```markdown
   ## {YYYY-MM-DD} — Dream
   - **Derived:** `{filename}` from {N} sources — {M} lessons saved, {K} skipped
   ```
4. Log to `{vault}/.spine/curator-log.md` (same format as capture/update).

## Output Contract

```yaml
spine_dream_result:
  status: success | nothing_to_derive | skipped | error
  summary: "Derived 1 playbook (7 lessons) from Plan - DTC Onboarding SDK Migration + 3 episodes"
  derived:
    - { file: "Derived - Trade-In SDK Playbook.md", feature: "Trade-In", lessons: 7, sources: 4 }
  skipped_candidates: 2
  next_actions:
    - { action: "read before next Trade-In session", path: "{vault}/{repo}/Trade-In/" }
  recovery_hint: null
```

## Boundaries

- Never auto-land: every derived doc goes through Save/Edit/Skip.
- Never delete or rewrite source docs — dream only adds.
- Never derive across vault boundaries (one repo's docs per pass; cross-repo
  lessons require the user to ask explicitly).
- A dream pass that saves nothing is a valid outcome — say so and stop.
