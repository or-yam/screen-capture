# Issue tracker: Local Markdown

Issues and specs for this repo live as markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- New specs use `.scratch/<feature-slug>/spec.md`. Existing `PRD.md` files remain valid; read the referenced file without renaming it.
- Implementation issues are one file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01`.
- Triage state is recorded as a `Status:` line near the top of each implementation issue (see `triage-labels.md` for the role strings).
- Comments and conversation history append under a `## Comments` heading.

## When a skill says "publish to the issue tracker"

Write the appropriate spec or individual issue file using the paths above, creating directories if needed.

## When a skill says "fetch the relevant ticket"

Read the referenced file. If given only an issue number, resolve it within the specified feature; ask if ambiguous.

## Wayfinding operations

Used by `/wayfinder`. The map is a file with one child file per ticket.

- Map: `.scratch/<effort>/map.md` (Notes / Decisions-so-far / Fog).
- Child ticket: `.scratch/<effort>/issues/NN-<slug>.md`, numbered from `01`, with the question in the body.
- Type: a `Type:` line records `research`, `prototype`, `grilling`, or `task`.
- Lifecycle: wayfinding children use `Status: open`, `claimed`, or `resolved`, rather than implementation triage roles.
- Blocking: a `Blocked by: NN, NN` line lists dependencies. A ticket is unblocked when every listed ticket is `resolved`.
- Frontier: scan for open, unblocked, unclaimed tickets; first by number wins.
- Claim: set `Status: claimed` and save before work.
- Resolve: append the answer under `## Answer`, set `Status: resolved`, then append a gist and ticket link to Decisions-so-far in the map.
