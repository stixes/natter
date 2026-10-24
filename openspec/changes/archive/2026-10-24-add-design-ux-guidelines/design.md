# Design

## Context

See proposal.md - Why. OpenSpec exposes five places to inject guidance: `context` (every artifact), `rules.<artifact>` (one artifact), `operations.<op>.guidance` (apply/archive), schema/templates (structural), and `specs/` (behavioral truth). Natter's current config uses `context` and `rules.proposal` / `rules.tasks`; there is no design/UX guidance anywhere in OpenSpec. The tone bar lives in AGENTS.md as one sentence. The constraint is to add a durable guideline without forking the schema or turning design taste into a behavioral spec.

## Goals / Non-Goals

**Goals:**
- One narrative source of truth for design/UX in OpenSpec, with enough detail to guide a proposal and a task.
- Enforce consultation at the artifact where each concern belongs: proposal names UX impact, specs cover states, design carries a UX section, tasks verify states, apply runs a final check.
- Keep prompts lean: the document carries the detail; config only points at it and states the proof.

**Non-Goals:**
- No schema fork or new artifact. The workflow stays `proposal -> specs -> design -> tasks`.
- No design-language spec capability. Design/UX stays guidance, not a behavior contract.
- No AGENTS.md rewrite. It keeps product principles and non-goals; the new document owns design/UX detail.
- No app code, dependencies, permissions, or network changes.

## Decisions

- **Guideline document + thin rules ring.** Add `openspec/design-ux-guidelines.md` and point at it from per-artifact rules. Chosen because the bar is subjective ("ChatGPT-quality feel"): a narrative doc with examples and a checklist guides better than encoded rules, while the rules ring makes consultation mandatory. Alternatives: config-only rules (rejected: no room for examples, long rules bloat every artifact's instructions), forked schema (rejected: maintenance burden and upstream divergence for a small project), design-language spec (rejected: too rigid for aesthetic guidance and noisy at archive time).

- **Document at `openspec/design-ux-guidelines.md`.** Root-level, beside `config.yaml` and `specs/`, so it is discoverable without a new directory convention. OpenSpec ignores extra files at the root; validation only scans `specs/` and `changes/`. Alternative: `openspec/docs/design-ux-guidelines.md` (rejected: adds a directory with no precedent).

- **Enforcement ring per artifact.** Extend the existing `rules.proposal` and `rules.tasks` lists; add `rules.specs` and `rules.design`. `rules.proposal`: name the user-facing surface and UX impact, or state none. `rules.specs`: user-facing scenarios cover loading, empty, error, and cancellation where relevant. `rules.design`: include a `## UX and interaction` section covering states, motion, accessibility, copy, dark mode; cite the guideline; state when it does not apply. `rules.tasks`: UI tasks name the states they implement and how to verify them; visual changes owe an on-device look. `operations.apply.guidance`: final check against the guideline before a UI task is marked done. Chosen because each artifact's instruction is read at the moment the artifact is written; a single global pointer would be easy to ignore and would also hit archive. Alternative: `context` only (rejected: applies everywhere but enforces nothing specific).

- **Rules are advisory, not hard validation.** OpenSpec injects rules into instructions; it does not fail a change for missing a UX section. Accepted: hard validation would require a schema fork or custom validator, which is more than this change needs. Mitigation: the design rule names the exact section and the task rule requires a verification. If drift persists after a few changes, graduate to a forked schema or a design-language spec.

- **No AGENTS.md edit.** The config already treats AGENTS.md as the single source of truth for product principles and non-goals. Design/UX operational detail belongs in the OpenSpec document, not in AGENTS.md. A one-line pointer can be added later if discoverability proves weak.

## Risks / Trade-offs

- Advisory rules can be skipped -> mitigation: explicit `## UX and interaction` requirement, task-level verification, and a review after the next few UI changes; escalate to a schema fork or design spec if drift continues.
- Guideline doc and config rules drift apart -> mitigation: the rules point at the document by path and repeat only the proof, not the content; keep the document's checklist aligned with the rule text.
- Extra instructions on every artifact add prompt weight -> mitigation: one or two lines per artifact; the document carries the detail and is read only when the artifact touches a user-facing surface.
- Config `context` bloat -> mitigation: the document is referenced, not copied into `context`; `context` stays short.
- Non-UI changes get noise -> mitigation: each rule explicitly allows "state none" or "does not apply", so a backend or tooling change closes the loop in one sentence.

## Migration Plan

1. Add `openspec/design-ux-guidelines.md`.
2. Add the per-artifact rules and `operations.apply.guidance` to `openspec/config.yaml`.
3. Run `openspec validate add-design-ux-guidelines --strict` and `flutter analyze && flutter test` to confirm no regression.
4. Rollback is a revert of the commit; no data or runtime migration.

## UX and interaction

Not applicable: this change adds design/UX guidance for future changes and
touches no user-facing surface. There are no interaction states, motion,
accessibility, copy, or dark-mode changes to assess, and no app code changes.
