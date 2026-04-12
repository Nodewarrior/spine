---
tags:
  - type/meta
---

# Spine Architecture

A knowledge management system that bridges Claude Code's memory with this Obsidian vault, organizing project knowledge as a navigable graph tree.

## Structure

```
{vault}/
  └─ {repo}/
       └─ {feature}/
            ├─ {Feature}.md           ← spine note (overview, wikilinks to all children)
            ├─ Fix - {description}.md
            ├─ Feature - {description}.md
            ├─ Architecture - {description}.md
            ├─ Plan - {description}.md
            └─ Decision - {description}.md
```

## Navigation

Claude Memory → Feature Signpost → Spine Note → Specific Doc

## Conventions

- **Repo-first** hierarchy separates concerns across codebases
- **Feature-first** grouping within each repo keeps related knowledge together
- **Spine notes** are the entry point — read the spine to understand a feature before diving in
- **Naming convention** (`Fix -`, `Feature -`, `Architecture -`, `Plan -`, `Decision -`) keeps the tree shallow
- **Type tags** (`type/spine`, `type/fix`, `type/feature`, `type/architecture`, `type/plan`, `type/decision`) drive graph coloring
- **Cross-repo features** link to each other via `[[wikilinks]]`
- **Date prefixes** on Fix and Feature docs (`YYYY-MM-DD Fix - ...`), none on Architecture/Plan/Decision
