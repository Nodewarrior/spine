# Spine Conventions

## Vault Structure

```
{vault}/
  ├── Spine Architecture.md          ← meta doc (type/meta)
  ├── {repo}/                        ← one folder per repository
  │   └── {feature}/                 ← one folder per feature
  │       ├── {Feature}.md           ← spine note (type/spine)
  │       ├── Fix - {description}.md
  │       ├── Feature - {description}.md
  │       ├── Architecture - {description}.md
  │       ├── Plan - {description}.md
  │       └── Decision - {description}.md
  └── (more repos...)
```

## Naming Conventions

### Doc Prefixes

| Prefix | Use for | Tag | Date prefix? |
|--------|---------|-----|-------------|
| `Fix - ` | Bug fix with root cause and code snippets | `type/fix` | Yes: `YYYY-MM-DD Fix - ...` |
| `Feature - ` | New functionality | `type/feature` | Yes: `YYYY-MM-DD Feature - ...` |
| `Architecture - ` | Design doc, API structure, data flow | `type/architecture` | No |
| `Plan - ` | Implementation plan | `type/plan` | No |
| `Decision - ` | Decision record with context and trade-offs | `type/decision` | No |

### Spine Notes

Spine notes are named `{Feature}.md` (matching the folder name). They serve as hubs that link to all docs within the feature.

## Frontmatter

Every doc must have YAML frontmatter with:

```yaml
---
title: "{Type} - {Description}"
date: YYYY-MM-DD
tags:
  - {repo-name}
  - {feature-kebab-case}
  - type/{type}
status: resolved | in-progress | pending
---
```

Fix docs should also include `severity: sev1 | sev2 | sev3`.

## Type Tags

Tags drive the color-coded Obsidian graph:

| Tag | Color | Purpose |
|-----|-------|---------|
| `type/spine` | Blue | Feature spine notes |
| `type/fix` | Red | Bug fixes |
| `type/feature` | Green | New features |
| `type/architecture` | Purple | Architecture docs |
| `type/plan` | Orange | Implementation plans |
| `type/decision` | Yellow | Decision records |
| `type/meta` | Grey | Spine Architecture meta doc |

## Wikilinks

- Use Obsidian `[[wikilinks]]` to connect related notes
- Keep wikilinks relative (note name only, not full path)
- Every spine note should link to all its children
- Cross-repo features should link to each other's spine notes
- Every doc should have a `## See Also` section with related wikilinks

## Claude Memory Integration

Claude memory signposts are lightweight pointers — one per feature:

```markdown
**Spine note:** `~/path/to/vault/{repo}/{feature}/{Feature}.md`
```

The signpost contains critical gotchas for quick AI reference. The spine note has the full picture.

**Rule:** One memory signpost per feature, not per fix. New fixes under an existing feature don't need a new memory entry.
