# Domain Docs

This repo uses a single-context layout: root `GLOSSARY.md` and `docs/adr/`.

## Before exploring

- Read `GLOSSARY.md` if present.
- Read ADRs in `docs/adr/` relevant to the area you're working in.

If these files are absent, proceed silently. `/domain-modeling` creates them lazily when terms or decisions are resolved.

## File structure

```text
/
├── GLOSSARY.md
├── docs/adr/
│   └── 0001-<decision-slug>.md
└── Sources/
```

## Use the glossary's vocabulary

When naming domain concepts in issues, proposals, hypotheses, or tests, use the terms defined in `GLOSSARY.md`, rather than synonyms it explicitly avoids.

If a needed concept is missing, reconsider whether it belongs to the domain; note genuine gaps for `/domain-modeling`.

## Flag ADR conflicts

Explicitly surface contradictions with existing ADRs, naming the ADR and explaining why reopening the decision may be warranted.
