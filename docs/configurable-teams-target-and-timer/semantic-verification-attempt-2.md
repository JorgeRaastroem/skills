# Semantic Verification — Attempt 2

## Scope and method

Task `validation-semantic-flow-2` reverified the current feature from the authorized artifacts only.
The current `enable-progress-in-teams/SKILL.md` and
`enable-progress-in-teams/tests/SkillContract.Tests.ps1` were read directly; the attempt-1 report
was used only to identify findings SV-01 through SV-04 that required fresh closure checks.

Completion criteria for this stage:

1. Trace the original request and approved normative design to the current production skill.
2. Explicitly close or reopen SV-01 through SV-04 using current text.
3. Check state-transition consistency and current test alignment.
4. Determine whether the 93 assertions semantically cover the four remediations sufficiently for
   a Markdown skill contract.
5. Provide validator-ready evidence without issuing the final validation-gate verdict.

## Current requirement trace

| Requirement | Current production evidence | Current test evidence | Result |
|---|---|---|---|
| Dynamically discover and select a Teams destination | `SKILL.md` Phase 1 calls `ListTeams`, then `ListChannels`, presents bounded numbered results, discloses membership type and incomplete adapter coverage, handles duplicate names by canonical-ID fragment, and requires an explicit confirmation gate before persistence or Teams writes. | Assertions cover the selectable-destination frontmatter, `ListTeams`, `ListChannels`, confirmation, canonical-ID routing, and absence of the former hard-coded team/channel IDs. | Implemented and aligned. |
| Persist the selected destination as a session-scoped slug | Canonical vocabulary defines `slug` as an opaque session-scoped alias, never a routing or authorization identity. Phase 1 allocates and persists a fresh slug with the canonical route generation. | Assertions require opaque/non-canonical slug semantics and canonical `team_id`/`channel_id` routing. | Implemented and aligned. |
| Change the target and update the slug | Phase 5 performs trusted local reselection and confirmation, allocates a new generation, binds a new root while retaining the old authoritative route, and atomically commits the new IDs, root, generation, and slug only after durable binding. | Assertions require retargeting, a new generation, ordered transition/cutover semantics, old-route preservation, and no pre-allocation transition write. | Implemented and aligned. |
| One recurring timer reinforces routing idempotently | The hard invariant and schedule contract define exactly one logical 5-minute session schedule. Phase 4 routing reinforcement is state-only when healthy and performs bounded repair only after enable/retarget or recorded uncertainty, avoiding periodic post spam. | Assertions require one 5-minute schedule owning reconciliation and polling, validate cadence/cost disclosure, and reject contradictory 2- or 10-minute cadence text. | Implemented and aligned. |
| The same timer listens during active and blocked states | Phase 4 polls authorized replies and queues accepted input for the next safe local approval point. Phase 3 explicitly reuses the same timer while blocked and does not promise preemptive interruption of active work or a blocking command. | Assertions require safe-point queuing, truthful non-webhook/non-preemption language, blocked-flow timer reuse, and absence of blocked-only schedule creation. | Implemented and aligned. |
| Remove the old blocked-only listener | The state model replaces the listener table with unified route/timer state; canonical vocabulary forbids reintroducing “listener” as a blocker-owned schedule. Phase 3 prohibits a separate listener or schedule. | Negative assertions reject `teams_progress_listener`, `listener_key`, and blocked-only schedule instructions. | Implemented and aligned. |
| Approved A+B selection profile and policies | Phase 1 implements explicit selection plus an optional remembered-target shortcut with exact-ID revalidation and confirmation. It uses the retained fixed sender ID, 5-minute cadence, session-lifetime schedule reconciliation, safe-point queueing, three-exhausted-tick degradation, all approved channel membership types, a 50-item display bound, sanitized literal preview, no history migration, and a generation-specific retarget root. | Broad contract assertions cover these core fields and behaviors; the remediation assertions cover the safety-critical ordering and concurrency rules. | Implemented and aligned. |

## Prior-finding closure

### SV-01 — Composite reply watermark

**Status: CLOSED in the current artifacts.**

Current production evidence:

- Canonical vocabulary defines the durable watermark as
  `(watermark_created_at, watermark_message_id)`.
- “Newer” uses the exact lexicographic disjunction:
  `createdDateTime > watermark_created_at OR (createdDateTime = watermark_created_at AND message_id > watermark_message_id)`.
- The message-ID tie-break is explicitly a stable ordinal string comparison.
- Phase 4 step 6 sorts and qualifies using the same `(createdDateTime, message_id)` tuple.
- Phase 4 step 8 advances only to the greatest fully processed tuple and retains the prior tuple on
  an incomplete scan, page/time bound, read failure, or pagination exhaustion.
- No current instruction authorizes timestamp-only qualification or advancement.

State transition:

`prior watermark` → bounded tuple-ordered scan → fully processed tuple set → `greatest fully
processed tuple`; an incomplete/exhausted scan instead transitions to continuation/degraded state
while retaining the prior watermark.

Current test alignment:

- Six direct SV-01 assertions require both persisted columns, the exact disjunction, stable ordinal
  ordering, common sort/qualification tuple, greatest-fully-processed advancement, and the absence
  of a timestamp-only qualification path.
- These checks are scoped to the relevant Phase 4 text where ordering semantics matter.

The same-timestamp skip path identified in attempt 1 is no longer present.

### SV-02 — Durable schedule creation/adoption CAS

**Status: CLOSED in the current artifacts.**

Current production evidence:

- `teams_progress_session` durably persists `schedule_revision` and
  `schedule_intent_token`, in addition to logical key, external handle, status, route generation,
  and lease state.
- Phase 1 initializes `schedule_revision = 0` as the baseline.
- The schedule contract captures `expected_schedule_revision`, mints and persists a unique intent
  token before the external create, and adopts the returned handle only with a CAS matching:
  `(session_id, logical_schedule_key, expected_schedule_revision, schedule_intent_token, route_generation)`.
- Successful adoption increments `schedule_revision` and clears the consumed token.
- A CAS loser stops its newly created external schedule and reconciles rather than adopting it.
- Failed/unknown stop outcomes, stale intent tokens, and unconsumed tokens remain visible for later
  reconciliation.

State transition:

`baseline/active revision N` → persisted `intent/creating` with unique token → external create →
five-dimensional CAS → either `active revision N+1` or loser cleanup with
`stop_failed`/`unknown`/visible stale intent evidence.

Current test alignment:

- Five direct SV-02 assertions require the durable fields, the exact five-dimensional CAS tuple,
  and index-ordered intent-before-create, CAS-adopt, revision-increment, and loser-stop lifecycle.
- The tests separately require revision baseline zero and visible stale/uncertain outcomes.

The ambiguous concurrent-handle adoption path identified in attempt 1 is no longer present.

### SV-03 — Authorization snapshot and revision guards

**Status: CLOSED in the current artifacts.**

Current production evidence:

- Phase 4 step 2 loads the separate authorization record and captures the tick’s initial
  `authorization_revision` and `authorized_sender_ids`.
- Step 3 requires a fresh current `authorization_revision` check before every external Teams read
  or write, together with enabled, terminal, route-generation, logical-key, and lease guards. A
  revision mismatch discards the pending effect with no Teams read/write.
- Step 6 qualifies candidates against the captured sender snapshot.
- Step 7 reloads authorization before claiming, ledgering acceptance, surfacing, or acknowledging;
  it requires the same captured revision and that the sender remains authorized. A mismatch leaves
  the reply unclaimed and unacknowledged, with no `claimed` ledger row or surface.
- Step 9 repeats the authorization guard before acknowledgement and explicitly forbids
  acknowledgement under a stale or changed revision.
- Failure handling restates that a mid-tick revision or sender mismatch aborts acceptance and
  leaves the reply unclaimed for a later tick.

State transition:

`captured authorization revision R` → per-effect revision check → candidate qualification →
fresh claim/surface guard at R → `claimed`/`surfaced`; any revision or sender mismatch instead
returns to the next-tick reload path without claim, surface, or acknowledgement.

Current test alignment:

- Four direct SV-03 assertions require snapshot capture, per-external-effect revision validation,
  fresh claim/surface validation with unclaimed mismatch behavior, and acknowledgement
  revalidation.
- The assertions are scoped to Phase 4 and test the relevant negative outcome, not only the
  presence of `authorization_revision`.

The stale-authorization TOCTOU path identified in attempt 1 is no longer present.

### SV-04 — Retarget generation and transition ordering

**Status: CLOSED in the current artifacts.**

Current production evidence:

- The transition primary key is
  `(session_id, from_generation, to_generation)`.
- Phase 5 allocates the next monotonic generation first, then persists the keyed
  `new_root_pending` transition before any write to the new channel.
- The exact new target is validated and the generation-specific root is created/bound while the
  old route remains authoritative.
- Only after the new root identity is durable (`root_bound`) may one atomic CAS commit activate
  the new route, slug, generation, IDs, and root.
- The old-root handoff occurs only after activation, is guarded, and is limited to at most one
  attempt.
- Before durable root binding, failure retains the old current route and slug and records
  failed/degraded transition evidence. If root creation succeeds but commit fails, the persisted
  transition is the reconciliation record and the orphan is not treated as current.

State transition:

`old route authoritative` → allocate `to_generation` → persist keyed `new_root_pending` →
create/bind new root → `root_bound` → atomic current-route activation
(`committed`/`complete`) → optional guarded old-root handoff. Any pre-binding failure preserves the
old route and records degraded failure evidence; post-root/pre-commit failure remains
transition-backed and non-current.

Current test alignment:

- Five direct SV-04 assertions require the three-part key, index-ordered allocation → transition →
  root → activation → handoff sequence, transition persistence before the first new-channel write,
  old-route/slug preservation on failure, and absence of the former transition-before-allocation
  wording.
- The principal ordering assertion operates on the extracted Phase 5 section, preventing unrelated
  occurrences elsewhere in the document from satisfying the cutover order.

The unexecutable pre-allocation transition order identified in attempt 1 is no longer present.

## State-transition consistency

The current skill is internally consistent across the safety-critical states:

- **Session lifecycle:** confirmation precedes route persistence; disable sets disabled before stop;
  terminal cleanup sets disabled/terminal before schedule reconciliation; restored disabled or
  terminal ticks perform no Teams operation.
- **Generation/root:** generations are globally monotonic and never reused; roots are generation
  specific; stale generations fail guards; retarget activation waits for durable new-root binding.
- **Schedule:** intent is durable before create; adoption is revisioned CAS; losers clean up; leases
  prevent concurrent side-effecting ticks; unknown outcomes remain visible.
- **Reply consumption:** tuple ordering, dedup ledger, authorization revalidation, safe-point
  surfacing, acknowledgement uncertainty, and watermark advancement form one consistent sequence.
- **Retarget:** the old route remains authoritative through allocation, transition persistence, and
  root binding; activation is atomic; post-activation handoff cannot make the old route current.

Non-material wording note: the transition schema’s state comment lists `degraded` but not
`failed`, while Phase 5 permits marking a failed pre-binding transition as `failed`/`degraded`.
Using the declared `degraded` state satisfies the required failure semantics, so this does not
reopen SV-04; a future editorial pass could choose one canonical label.

## Test adequacy for the Markdown contract

Fresh command evidence:

```text
PASS: 93 static skill contract assertions passed.
TEST_EXIT=0
DIFF_CHECK_EXIT=0
```

The 20 remediation assertions are semantically sufficient for this repository’s Markdown contract,
not merely vocabulary checks:

| Finding | Direct assertions | Semantic strength |
|---|---:|---|
| SV-01 | 6 | Requires persisted tuple fields, exact comparator, stable tie-break, common tuple use, safe advancement, and a negative timestamp-only check. |
| SV-02 | 5 | Requires durable CAS identity, the exact five dimensions, ordered intent/create/adopt/revision/loser cleanup, baseline revision, and visible uncertain state. |
| SV-03 | 4 | Requires snapshot capture, per-effect revision guards, unclaimed mismatch behavior at acceptance/surface, and fresh acknowledgement guards. |
| SV-04 | 5 | Requires the complete Phase 5 order, pre-write transition durability, failure preservation, exact key, and a negative old-order check. |

The remaining assertions align the remediations with the broader feature contract: dynamic
selection, canonical IDs, opaque slug, unified cadence, authorization separation, blocked-state
reuse, pagination/degradation, failure visibility, cleanup, removal of legacy listener state, and
bounded completion output.

These tests cannot execute Teams APIs, scheduler races, SQL transactions, crash recovery, or live
pagination. That is an inherent runtime risk of an instructional Markdown skill with static
contract tests, not evidence of a current contradiction in the production contract. The tests are
adequate to establish that the required semantics are explicitly and consistently specified in the
current Markdown artifact.

## New material findings

No new material semantic finding was identified in the current authorized artifacts. The
transition-state naming note above is editorial/non-blocking because the declared `degraded` state
fully represents the required preserved-old-route failure path.

## Validator-ready conclusion

Current artifact evidence supports treating SV-01, SV-02, SV-03, and SV-04 as closed. The original
dynamic destination selection, session slug persistence and retarget update, unified 5-minute
routing/listening schedule, active/blocked safe-point listening, and removal of the old blocked-only
listener are all represented consistently in the current production skill and aligned static
contract tests. The fresh 93-assertion run and diff check pass, and the remediation assertions
verify the safety-critical comparators, guards, negative paths, and execution order with sufficient
specificity for a Markdown contract.

The final validation-gate decision is intentionally left to the next validation owner.
