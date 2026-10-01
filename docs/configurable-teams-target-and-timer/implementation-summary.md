# Implementation Summary — IMP-001: Configurable Teams Target and Unified Routing Timer

**Task ID:** `implementation-skill-rewrite`
**Workflow block:** dev-dude-feature-implementation Step 3 Implementation
**Date:** 2026-10-01
**Scope:** IMP-001 only. Production skill rewrite plus this summary. No tests were added (paired
Test-Implementer owns TEST-001). No run-state or handoff YAML was modified.

## Changed paths

- Modified: `enable-progress-in-teams/SKILL.md` (full rewrite).
- Added: `docs/configurable-teams-target-and-timer/implementation-summary.md` (this file).

No other files were created, modified, or deleted.

## What changed, mapped to the approved design

The rewrite implements the normative core of `design-options.md` with the policy selections in
`approved-design.md` (Profile A+B, retained fixed sender ID, 5-minute cadence, enabled-until-disable
lifetime, queue-at-safe-point delivery, 3-tick backlog threshold, standard/private/shared channels,
50-row selection bound, ≤7-bullet completion, sanitized root preview, no-history-migration retarget).

| Approved-design requirement | Implementation in `SKILL.md` |
|---|---|
| No hard-coded destination; canonical IDs only (§2.3, boundaries 6–7) | Frontmatter rewritten; Hard invariants 1–2; all phases resolve exact `team_id`/`channel_id`/`root_message_id` from the confirmed route row. Old `teamId`/`channelId` constants removed. |
| Frontmatter description + version bump | `description` now describes interactive destination, slug, per-generation root, 5-minute polling; `metadata.version` incremented `1.1.1` → `1.2.0`. |
| ListTeams/ListChannels at enablement; A+B text-only selection (§4.1–§4.2) | Phase 1 steps 2–4: remembered-target (Profile B) branch, interactive `ListTeams`/`ListChannels` selection (Profile A), duplicate-name ID fragments, membership type, ≤50 returned-item bound with completeness disclosure, cancellation, and a single confirmation gate. |
| Opaque session slug → exact IDs + display metadata; status shows slug; change-target via new generation (§2.2, §3.1) | `teams_progress_session.slug` + display columns; Phase 6 status reports slug; Phase 5 retarget allocates a new generation and slug on confirmation only. |
| Globally monotonic `route_generation`; generation in root marker; generation-specific root; no history migration; one guarded handoff (§3.2, §3.8) | Hard invariants 3–4, 6; `teams_progress_generation` counter; `ROOT_BODY_MARKER` = `Session ID` + `Route generation`; Phase 5 retarget creates a fresh generation root and posts at most one guarded old-root handoff. |
| Separate id-only authorization; retain sender ID; empty ⇒ listening disabled, posting may stay enabled (§3.3) | Hard invariant 7; separate `teams_progress_authorization` table seeded with `6e507591-b016-4741-8543-11b3e2ff8e29`, revisioned; retarget never writes it; empty/unresolved ⇒ listening disabled, no empty-set fail-open. Match by id + exact leading `[ToAgent]`. |
| One unified session route/timer state model replacing the listener table (§3.1) | `teams_progress_session` holds IDs, slug, generation, root, `logical_schedule_key`/`schedule_id`, lease/owner, enabled/terminal, watermark, backlog/degraded; plus `teams_progress_generation`, `_generation_history`, `_authorization`, `_reply_ledger`, `_transition`. The `teams_progress_listener`/`listener_key` table is removed. |
| Exactly one 5-minute schedule owning reconciliation + polling in active and blocked states (§3.5, boundary 2) | Hard invariant 8; Schedule ownership contract; Phase 3 explicitly creates no second schedule; Phase 4 tick polls in both states. |
| Intent/CAS/lease ownership; adopt handle only if current; stop extras; retain stop_failed/unknown (§3.6) | Schedule ownership contract (intent→create→persist→adopt-if-current, reconcile extras by logical key/handle, visible `stop_failed`/`unknown`). |
| Tick reloads state, verifies enabled/not-terminal/generation/key/lease before every external effect; bounded pages; process only newer unledgered replies; no watermark past unprocessed/exhausted pages; `listening_degraded` after 3 exhausted ticks (§3.7) | Phase 4 steps 1–10, including lease CAS, per-effect ownership re-check, 5-page bound, ledger-before-surface, watermark discipline, and `bound_exhausted_ticks` → `listening_degraded`. |
| Ledger-before-surface + queue at next safe local approval point; no preemptive interruption; Teams text cannot retarget/mutate controls without trusted local confirmation (§3.3, §3.7) | Phase 4 steps 7, 9; Response-handling rules; Hard invariant 9 (`teams-origin` provenance, immutable controls). |
| Blocked posts a concise blocker under the current root; existing timer covers both states (§3) | Phase 3. |
| Enable, remembered target, status, change target, disable, terminal, stale/deleted target, authorization mismatch, scheduler unavailable, schedule persistence failure, duplicate schedule, pagination exhaustion, ack ambiguity, stop failure defined (§6) | Phases 1–7 plus the Failure handling table. |
| Remove hard-coded IDs, blocked-only/4-hour listener, listener_key table, contradictory 2/10-minute cadence (investigation gaps) | All removed; cadence is consistently 5-minute throughout. |
| Latency ~5 min; ~288 ticks/day; bounded retries/pages; best-effort, not webhook/durable (§7) | Residual limitations section. |
| Completion ≤7 bullets incl. destination, slug/generation/root, timer, listening, degraded/local fallback, next action for partial/blocked (§5) | Completion section (7 bullets). |
| Preserve fail-closed identity resolution and safe-content protections | Hard invariants 5, 10; Session identity contract + ordered resolution algorithm retained. |

## Targeted self-checks performed

1. `git diff --check` — clean (exit 0, no whitespace/conflict errors).
2. Stale-term search over `SKILL.md` for `cf0bc7fc-3957-47ab-a270-de8cab08cf98`,
   `3uz38MVu2jWGdYNcs9OVJNCks4`, `4-hour`/`4h`, `listener_key`, `teams_progress_listener`,
   `blocked-only`, `2-minute`, `10 minutes`, `24 scheduled` — **no matches**.
3. Residual `listener` mentions are intentional and non-normative: a vocabulary note ("do not
   reintroduce 'listener' for the schedule"), a migration note ("replaces the old blocker-only
   listener table"), and instructions to NOT create a separate listener. No listener is used as the
   schedule abstraction.
4. Cadence consistency — every cadence/latency mention is 5-minute / ~5 minutes / ~288 ticks/day.
5. Retained authorization sender id `6e507591-b016-4741-8543-11b3e2ff8e29` present in Hard invariant
   7, the authorization table comment, and the Phase 1 seed.
6. `metadata.version` is `1.2.0`.
7. File coherence reviewed: canonical vocabulary, state schema, Phases 1–7, Schedule ownership
   contract, Failure handling, Residual limitations, Examples, and Completion agree on generations,
   roots, the single 5-minute schedule, authorization separation, and best-effort semantics.

These are targeted implementation self-checks, not a final validation decision.

## Notes and assumptions

- Logical table/field names (`teams_progress_session`, etc.) are an implementation choice permitted
  by §3.1; the required uniqueness, revisions, and transitions are preserved.
- `logical_schedule_key` is `enable-progress-in-teams|<SESSION_ID>`, satisfying "stable per-session
  key"; the scheduled prompt carries only `session_id` and this key (boundary §2.3).
- Profile C (declarative selector) was intentionally excluded per `approved-design.md` and rejected
  approach R102 in the input handoff.

## Test Specifications for Test-Implementer

These specifications drive TEST-001 (owner: `test-implementer-copilot`). The artifact under test is
a Markdown skill, so tests are **static contract checks** over
`enable-progress-in-teams/SKILL.md`. Implement them as a repository-local PowerShell script under
`enable-progress-in-teams/tests/` that exits non-zero with an actionable message when any assertion
fails. No runtime Teams/scheduler calls are in scope.

### Files to test

- `enable-progress-in-teams/SKILL.md` (modified — primary target).
- `docs/configurable-teams-target-and-timer/implementation-summary.md` (reference only; not a test
  target).

### Suite A — Frontmatter and metadata

1. YAML frontmatter parses and contains `name: enable-progress-in-teams`.
2. `metadata.version` equals exactly `1.2.0` (and is not `1.1.1`).
3. The `description` references dynamic/interactive destination selection (e.g. "selected",
   "interactively", or "change the Teams progress target") and does NOT contain "hard-coded".

### Suite B — Required dynamic-destination and core terms present

Assert each of these literals/terms appears at least once (case-sensitive unless noted):
`ListTeams`, `ListChannels`, `route_generation`, `logical_schedule_key`, `authorized_sender_ids`,
`authorization_revision`, `watermark`, `reply_ledger`, `transition`, `listening_degraded`,
`stop_failed`, `teams-origin`, `slug`, and the retained sender id
`6e507591-b016-4741-8543-11b3e2ff8e29`.

### Suite C — Forbidden / removed terms absent

Assert NONE of the following appear anywhere in the file:
`cf0bc7fc-3957-47ab-a270-de8cab08cf98`, `3uz38MVu2jWGdYNcs9OVJNCks4`, `listener_key`,
`teams_progress_listener`, `4-hour`, `4h` (as a duration), `blocked-only`, `2-minute`,
`every 10 minutes`. (The word "listener" may appear only in negative/explanatory context; a lenient
check should allow it but assert the schedule abstraction is never called a "listener" — e.g. no
"create a listener" as an active instruction.)

### Suite D — Cadence consistency

1. At least one occurrence of `5-minute` / `5 minutes`.
2. No occurrence of `2 minutes`/`2-minute`, `10 minutes`/`10-minute`, or `every 10 minutes`.
3. Cost disclosure mentions `288` ticks/day and latency "about 5 minutes".

### Suite E — Invariant and structural coverage

Assert the presence of sections/phrases proving each contract:
1. "No hard-coded destination" invariant.
2. "Canonical IDs are the only routing identity".
3. Root marker includes both `Session ID:` and `Route generation:`.
4. Globally monotonic generation statement (never reset/reused across disable/re-enable/retarget).
5. Separate authorization table/record and "retarget never writes" authorization.
6. Exactly one 5-minute schedule per session owning reconciliation and polling.
7. Schedule ownership contract with intent/CAS/lease and `stop_failed`/`unknown` retention.
8. Tick reloads state and guards generation/lease before external effects; watermark not advanced
   past unprocessed/exhausted pages; `listening_degraded` after 3 consecutive bound-exhausted ticks.
9. Blocked state posts under the current root and creates no separate schedule.
10. Phases/flows for enable, remembered target, status, change target, disable, and terminal cleanup.
11. Completion block has at most 7 bullets and includes destination, slug/generation/root, timer,
    and listening fields.
12. Fail-closed `SESSION_ID` resolution and safe-content ("never include credentials, secrets")
    language retained.

### Edge cases / negative assertions

- The failed-build/forbidden-term checks must fail loudly (non-zero exit, named offending term and
  line) if reintroduced, to catch regressions.
- The completion-bullet check must count bullet lines inside the completion fenced block and fail if
  the count exceeds 7.
- The version check must fail if the version regresses or is a non-`1.2.0` value.

### Mocking / dependencies

None. All assertions are file-content checks; no Teams MCP, scheduler, or SQL mocks are required.
Use `Select-String`/regex against the file content; prefer exact-literal matches for IDs and terms.

## Remediation Attempt 1

**Task ID:** `remediation-production-1`
**Workflow block:** dev-dude-feature-implementation Remediation attempt 1
**Date:** 2026-10-01
**Scope:** Production remediation of the four semantic findings SV-01…SV-04 from validation attempt 1
(`verification.md`, `semantic-verification.md`). Only `enable-progress-in-teams/SKILL.md` and this
summary were changed. No tests were edited (paired Test-Implementer owns them). No run-state or
handoff YAML was modified. `metadata.version` left at `1.2.0` (no version change requested; existing
version assertion preserved).

### SV-01 — Composite watermark comparison

Exact changed sections/fields in `SKILL.md`:

- **Canonical vocabulary → `watermark`:** redefined as the durable tuple
  `(watermark_created_at, watermark_message_id)`; a reply is *newer than the watermark* iff
  `createdDateTime > watermark_created_at OR (createdDateTime = watermark_created_at AND message_id > watermark_message_id)`,
  with the id tie-break a **stable ordinal (byte/code-unit) string comparison**. Sorting and
  advancement use the same tuple.
- **Phase 4 step 6 (Order and filter):** sorts by the tuple `(createdDateTime, message_id)` with the
  ordinal id tie-break and applies the composite "newer than watermark" rule as a qualification
  condition.
- **Phase 4 step 8 (Advance the watermark carefully):** advances only to the **greatest fully
  processed `(createdDateTime, message_id)` tuple**; never past unprocessed/unledgered/deferred
  replies and never on page-bound/time-budget/read-failure/pagination exhaustion (retains prior
  tuple + continuation state).
- **Phase 4 success criteria:** restated in terms of the greatest fully processed tuple.
- **State schema:** already persisted both `watermark_created_at` and `watermark_message_id`
  (columns retained with clarifying comments); no schema change required.

Self-check: a same-timestamp pair now orders deterministically by id (ordinal), and a reply equal to
the watermark timestamp with a lexicographically-smaller/equal id is **not** newer — closing the
monotonic-timestamp-collision gap flagged by SV-01.

### SV-02 — Durable schedule CAS identity

Exact changed sections/fields in `SKILL.md`:

- **State schema (`teams_progress_session`):** added `schedule_revision INTEGER` (incremented only on
  CAS adoption) and `schedule_intent_token TEXT` (unique per create/replace intent; cleared only when
  its handle is adopted or reconciled).
- **Canonical vocabulary:** added `schedule_revision` / `schedule_intent_token` entry describing the
  adopt-only-by-CAS rule and revision increment on adoption.
- **Phase 1 commit (step 5.3):** initializes `schedule_revision = 0` as the baseline for the first
  schedule CAS.
- **Schedule ownership contract:** rewritten to CAS on the 5-tuple
  `(session_id, logical_schedule_key, expected_schedule_revision, schedule_intent_token, route_generation)`:
  capture expected revision + mint/persist unique intent token **before** create; create exactly one
  5-minute schedule; adopt the returned handle **only** when the CAS still matches the captured
  tuple, **incrementing `schedule_revision`** and clearing the consumed token on success; CAS losers
  **stop their extra external handles and reconcile**; stale intent tokens and `stop_failed`/`unknown`
  stop outcomes remain visible for reconciliation.
- **Failure handling → Duplicate schedule creation:** restated around the intent-token + revision CAS
  tuple, adoption-increments-revision, and losers-stop-and-reconcile.

Self-check: two concurrent creators capturing the same `expected_schedule_revision` cannot both
adopt — the first adoption increments the revision, so the second's CAS fails and it stops its handle;
lost/uncertain handles stay visible. Closes the "adopt handle only if current" ambiguity in SV-02.

### SV-03 — Authorization revision guards

Exact changed sections/fields in `SKILL.md`:

- **Phase 4 step 2 (Reload and guard):** reloads the separate `teams_progress_authorization` record
  and captures this tick's initial `authorization_revision` and `authorized_sender_ids` snapshot.
- **Phase 4 step 3 (Verify ownership before every external effect):** adds the current
  `authorization_revision` to the per-effect re-check; a changed revision discards the pending effect
  with no Teams read/write and reloads next tick.
- **Phase 4 step 6 (filter):** qualifies replies against this tick's captured `authorized_sender_ids`
  snapshot.
- **Phase 4 step 7 (Ledger before surface, under a fresh authorization guard):** before ledgering
  `claimed`/surfacing/acknowledging, reloads authorization and requires the **same** captured
  `authorization_revision` and that the sender id is **still** authorized (plus generation/key/lease
  guards); on mismatch aborts acceptance, leaves the reply unclaimed, and reloads next tick.
- **Phase 4 step 9 (acknowledgement):** re-applies the step 7 authorization guard before any
  acknowledgement write; never acknowledges under a stale/changed authorization revision.
- **Phase 4 success criteria + Failure handling:** added the stale/changed-authorization abort path
  ("Authorization revision changed mid-tick").

Self-check: a de-authorization committed after a tick starts (revision bump) blocks claim, surface,
and acknowledgement for that sender for the rest of the tick; no acknowledgement is emitted under the
stale revision. Closes the TOCTOU authorization gap in SV-03.

### SV-04 — Retarget transition ordering

Exact changed sections/fields in `SKILL.md`:

- **State schema (`teams_progress_transition`):** primary key changed to
  `(session_id, from_generation, to_generation)` to match the required transition key.
- **Phase 5 step 2:** reordered — **allocate the next monotonic `route_generation` FIRST**, then
  persist the keyed `teams_progress_transition` row in state `new_root_pending` **before any
  new-channel write** (the allocated generation is `to_generation`, which must exist before the keyed
  row can be written).
- **Phase 5 step 3:** old route stays authoritative while the new generation-specific root is
  created/bound; atomic CAS-commit of the new current generation + route activation + transition
  `committed`/`complete` happens **only after** durable root binding (`root_bound`).
- **Phase 5 step 4:** guarded old-root handoff posts **only after** commit.
- **Phase 5 step 5:** on any failure before durable root binding, retain the old route, do **not**
  update slug/current route, and mark the transition `failed`/`degraded` with enough root evidence
  (`new_root_id` if created) for reconciliation.
- **Change-destination example:** restated to "newly allocated generation → keyed `new_root_pending`
  row → old route authoritative → atomic cutover only after durable root binding".

Self-check: the keyed transition row can never be written before its `to_generation` exists; a crash
between generation allocation and commit leaves the old route current and a discoverable
`new_root_pending`/`degraded` transition; the new root is never treated as current before durable
binding. Closes the ordering/foreign-key gap in SV-04.

### Cross-section consistency

State schema, canonical vocabulary, schedule ownership contract, Phase 1 commit, Phase 4 tick phases,
Phase 5 retarget phase, the Failure handling table, and the change-destination example were all
updated together and re-read for coherence. Targeted searches confirm no stale single-key schedule
CAS (`(session_id, logical_schedule_key)` alone), no "allocate generation after the transition row",
and no "adopt handle only if generation/owner is still current" wording remain. `git diff --check`
reports no whitespace errors.

## Test Specifications for Test-Implementer (Remediation Attempt 1)

These extend the existing static `SkillContract.Tests.ps1` suites (A–E) and the base Suites above.
All assertions are file-content checks against `enable-progress-in-teams/SKILL.md` using
`Select-String`/regex; no Teams MCP, scheduler, or SQL mocks are required. Do not weaken existing
assertions — add the following.

### Suite F — SV-01 Composite watermark semantics

1. Vocabulary/`watermark` defines the tuple `(watermark_created_at, watermark_message_id)` AND
   contains the exact disjunction
   `createdDateTime > watermark_created_at OR (createdDateTime = watermark_created_at AND message_id > watermark_message_id)`.
2. The id tie-break is described as a **stable ordinal** (byte/code-unit) comparison (assert the words
   `ordinal` and `tie-break`/`tie break`).
3. Phase 4 ordering step sorts by `(createdDateTime, message_id)` (assert both field names appear in
   the sort/order instruction) with the ordinal tie-break.
4. Phase 4 advancement step advances only to the **greatest fully processed** tuple and explicitly
   forbids advancing on page/pagination exhaustion (assert `greatest fully processed` and a
   never-advance-on-exhaustion clause).
5. State schema retains BOTH `watermark_created_at` and `watermark_message_id` columns.
6. Negative: no instruction advances the watermark using `createdDateTime` alone (no timestamp-only
   comparison that ignores `message_id`).

### Suite G — SV-02 Schedule CAS identity

1. `teams_progress_session` schema declares `schedule_revision` and `schedule_intent_token` columns.
2. Vocabulary defines `schedule_revision`/`schedule_intent_token` with "adopt … only by … CAS" and
   "increment … revision" semantics.
3. Schedule ownership contract contains the exact 5-tuple
   `(session_id, logical_schedule_key, expected_schedule_revision, schedule_intent_token, route_generation)`.
4. Contract orders: capture `expected_schedule_revision` + mint/persist `schedule_intent_token`
   **before** create; adopt handle **only** on matching CAS; **increment `schedule_revision`** on
   adoption; CAS losers **stop** their extra handle and **reconcile**.
5. Contract retains `stop_failed`/`unknown` and unconsumed `schedule_intent_token` visibly for
   reconciliation.
6. Phase 1 commit initializes `schedule_revision = 0`.
7. Failure-handling "Duplicate schedule creation" row references the revision/intent-token CAS and
   losers-stop-and-reconcile.
8. Negative: no remaining schedule CAS keyed on `(session_id, logical_schedule_key)` alone, and no
   "adopt handle only if the generation/owner is still current" wording.

### Suite H — SV-03 Authorization revision guards

1. Phase 4 reload step captures the tick's initial `authorization_revision` and
   `authorized_sender_ids` snapshot from the separate `teams_progress_authorization` record.
2. Phase 4 per-effect ownership re-check includes the current `authorization_revision`; a changed
   revision discards the pending effect with no Teams read/write.
3. Phase 4 ledger-before-surface step requires the **same** captured `authorization_revision` and the
   sender **still** authorized before ledgering `claimed`/surfacing; on mismatch leaves the reply
   unclaimed.
4. Phase 4 acknowledgement step re-applies the authorization guard and never acknowledges under a
   stale/changed authorization revision (assert a never-acknowledge-under-stale clause).
5. Failure-handling table has an "Authorization revision changed mid-tick" row with abort/leave-
   unclaimed/do-not-acknowledge/reload-next-tick behavior.
6. Negative: no instruction surfaces or acknowledges a reply using only the start-of-tick snapshot
   without a pre-effect authorization recheck.

### Suite I — SV-04 Retarget transition ordering

1. `teams_progress_transition` primary key is `(session_id, from_generation, to_generation)`.
2. Phase 5 allocates the next monotonic `route_generation` **FIRST**, then writes the keyed
   `new_root_pending` transition row **before any new-channel write** (assert ordering words: FIRST /
   before any … write).
3. Phase 5 keeps the old route authoritative until durable root binding (`root_bound`) and performs
   the atomic cutover/CAS-commit of the new current generation **only after** binding.
4. Phase 5 posts the guarded old-root handoff **only after** commit.
5. Phase 5 failure path: on failure before durable binding, retain old route, do **not** update
   slug/current route, mark transition `failed`/`degraded` with `new_root_id` evidence.
6. Change-destination example reflects generation-before-transition-before-new-channel-write ordering.
7. Negative: no remaining "Write a `teams_progress_transition` row … BEFORE any write … Allocate the
   next monotonic generation" (transition-before-allocation) wording.

### Edge cases / negative assertions (shared)

- Each negative assertion must fail loudly (non-zero exit, named offending term + line) if the stale
  pre-remediation wording is reintroduced, to catch regressions.
- Ordering assertions (Suites G step 4, I steps 2–4) should verify relative position (e.g., the
  generation-allocation instruction appears before the transition-row instruction; capture/mint
  appears before create; CAS adopt appears before revision increment) using line-index comparison,
  not mere co-presence.

### Mocking / dependencies

None. File-content assertions only; reuse the existing `SkillContract.Tests.ps1` harness and helpers.
