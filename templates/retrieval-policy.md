# Spine Retrieval Policy

When you need context on a feature, component, or past decision in this repo, follow these steps:

## Auto-Loaded Context

At session start, Spine injected a **vault index** listing all spine notes (feature hubs) for this repo. Use it as your map.

## Three-Hop Navigation

1. **Scan the index** — find the spine note matching the feature area you need
2. **Read the spine note** — it's the hub with wikilinks to all child docs (fixes, features, architecture, plans, decisions)
3. **Read the specific doc** — follow the wikilink to the doc with the detail you need

## When to Pull Vault Docs

- Before making changes to a feature area — check if architecture docs or decisions exist
- When debugging — check if a fix doc covers this area (root cause, code snippets)
- When planning — check if a plan doc already exists for this feature
- When you see a `[[wikilink]]` in any spine doc — you can read it from the vault

## On-Demand Deep Pull

Use `/spine-recall <feature>` to load all docs for a specific feature area into context at once.

## Do NOT

- Create duplicate docs — check the index first
- Ignore spine docs when they exist — they contain institutional knowledge
- Modify vault docs directly — use `/spine-update` or `/spine-capture`
