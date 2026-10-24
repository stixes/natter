# Tasks

## 1. Add the design/UX guideline document

- [x] 1.1 Create `openspec/design-ux-guidelines.md` covering principles, interaction states (empty, loading/streaming, error, offline, cancel/retry), motion and scroll behavior, accessibility, copy tone, dark mode, and a review checklist. Verify: the file exists and `rg '^## ' openspec/design-ux-guidelines.md` lists every named section.
- [x] 1.2 Add a per-artifact checklist at the end of the guideline: proposal names UX impact; specs cover states in scenarios; design carries a `## UX and interaction` section; tasks verify states; apply runs a final check. Verify: the checklist has five entries whose names match those artifacts.

## 2. Wire the guideline into OpenSpec configuration

- [x] 2.1 Extend the existing `rules.proposal` and `rules.tasks` lists in `openspec/config.yaml` and add `rules.specs` and `rules.design`, each new rule citing `openspec/design-ux-guidelines.md` and stating the proof expected at that artifact. Verify: `openspec instructions design --change add-design-ux-guidelines --json` includes the design rule; repeat for proposal and tasks. For `specs`, inspect `openspec/config.yaml` directly because this change skips that artifact.
- [x] 2.2 Add `operations.apply.guidance` to `openspec/config.yaml` requiring a final design/UX check before a UI task is marked done. Verify: `openspec instructions apply --change add-design-ux-guidelines --json` includes the guidance text.

## 3. Integration verification

- [x] 3.1 Run `openspec validate add-design-ux-guidelines --strict` and confirm it is green. This also confirms the change's `skip_specs: true` marker and its artifacts.
- [x] 3.2 Run `flutter analyze && flutter test` and confirm both are green. No Dart changes are expected, so this is a regression check.
- [x] 3.3 Confirm the diff contains only `openspec/design-ux-guidelines.md` and `openspec/config.yaml`, plus this change's own planning artifacts, with no new dependencies, permissions, or network destinations. Verify with `git status --porcelain` and `git diff --stat`.

## Workflow follow-up

- Before committing, run the publishable scan over the commit and pushed tree per AGENTS.md "Publishing hygiene"; the new document and config must use placeholders only.
- Archive the change with `/opsx-archive` after validation and review are green.
