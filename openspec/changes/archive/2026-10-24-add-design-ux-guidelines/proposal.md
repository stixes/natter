# Proposal

## Why

Natter's stated bar is "ChatGPT-quality conversation feel", but OpenSpec currently carries only technical and process rules. The design/UX expectation lives in one sentence in AGENTS.md ("Tone and polish bar"), so a proposal, spec, design, or task can drift toward "cheap on Android" without any artifact naming interaction states, motion, accessibility, copy, or dark mode. This change gives design/UX guidance a durable home in OpenSpec and makes every relevant artifact prove it was consulted.

## What Changes

- Add `openspec/design-ux-guidelines.md`: a narrative guideline covering principles, interaction states (empty, loading/streaming, error, offline, cancel/retry), motion and scroll behavior, accessibility, copy tone, dark mode, and a review checklist.
- Add per-artifact rules in `openspec/config.yaml` for `proposal`, `specs`, `design`, and `tasks`, plus `operations.apply.guidance`, so each artifact must consult the guideline and produce a specific proof.
- No app code, dependencies, permissions, or network changes. This is workflow, tooling, and documentation only.
- Out of scope: forking the schema (option C), creating a design-language spec capability (option D), and making AGENTS.md the primary home (option E). AGENTS.md keeps its product-principles role; the new document is the design/UX source of truth.

## Capabilities

### New Capabilities

None. This change declares `skip_specs: true` in `.openspec.yaml`: the design/UX guideline changes workflow guidance, not app behavior, so no spec-level behavior changes.

### Modified Capabilities

None. No non-goal is touched; this operationalizes the existing "Tone and polish bar" rather than altering it.

## Impact

- `openspec/design-ux-guidelines.md` (new)
- `openspec/config.yaml` (per-artifact rules and apply guidance)
- No `lib/`, `android/`, `test/`, `integration_test/`, or `pubspec.yaml` changes
- No new dependencies, permissions, or network destinations
- Changelog: no entry; this is not user-facing app behavior
- On-device rounds: not applicable; no network path is touched
