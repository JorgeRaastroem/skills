# Implementation Plan

## Approved scope

Rewrite `enable-progress-in-teams/SKILL.md` to replace the hard-coded destination and blocked-only listener with:

- interactive team/channel discovery and confirmation;
- an opaque session target slug mapped to canonical IDs;
- target status and change-target flows;
- globally monotonic route generations and generation-specific root posts;
- one session-owned 5-minute timer for route reconciliation and operator-message polling;
- separate explicit sender-ID authorization;
- reply cursor, deduplication ledger, queued safe-point delivery, and bounded degraded states;
- disable, terminal, stale-target, schedule-race, and stop-failure reconciliation;
- updated examples, tool preconditions, limitations, and completion format.

## Ordered tasks

### IMP-001 — Rewrite the production skill

**Owner:** `feature-implementer-copilot`

**Files:**

- Modify `enable-progress-in-teams/SKILL.md`.
- Write `docs/configurable-teams-target-and-timer/implementation-summary.md`.

**Required invariants:**

1. No hard-coded team/channel destination remains.
2. Team/channel lists use actual Teams schemas and disclose bounded completeness.
3. Slugs/display names are non-canonical; writes use exact team/channel IDs.
4. Profile A+B always confirms the resolved target before writes.
5. `route_generation` never resets or reuses a prior value.
6. Root identity includes the generation.
7. Authorization is stored separately and retains sender ID `6e507591-b016-4741-8543-11b3e2ff8e29`.
8. Exactly one logical schedule per session performs reconciliation and polling every 5 minutes.
9. Every tick reloads current state and rejects stale generation/lease ownership before external effects.
10. Reply pagination, watermark, and ledger semantics prevent skipping or replaying accepted messages.
11. Teams-originated input cannot retarget or mutate controls without the normal local confirmation path.
12. The old blocked-only listener and its 4-hour lifecycle are removed.
13. Polling is described as best effort, not a webhook or guaranteed preemption.

### TEST-001 — Implement static contract tests

**Owner:** `test-implementer-copilot`

**Files:**

- Add a repository-local PowerShell test script under `enable-progress-in-teams/tests/`.
- Write `docs/configurable-teams-target-and-timer/test-summary.md`.

**Validation criteria:**

- YAML frontmatter has the expected skill name and updated description/version.
- Required dynamic destination, slug, retarget, generation, schedule, cursor/ledger, authorization, failure, and completion terms are present.
- Hard-coded team/channel IDs and blocked-only/4-hour listener semantics are absent.
- Cadence is consistently 5 minutes.
- The test script exits nonzero with actionable messages when any contract fails.

## Dependencies

`TEST-001` depends on `IMP-001`.

## Targeted checks

1. Run the static contract test script.
2. Run `git diff --check`.
3. Search for stale hard-coded IDs, `4-hour`, `blocked-only`, contradictory timer cadence, and old listener table terminology.
4. Review the changed file list.

## Remediation attempt

One bounded implementation/test correction pass is authorized before final validation if targeted checks fail.
