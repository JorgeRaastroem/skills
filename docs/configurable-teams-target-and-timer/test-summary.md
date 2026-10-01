# Test Summary — TEST-001: Static Skill Contract

**Task ID:** `test-skill-contract`
**Scope:** Paired static contract tests for the completed `SKILL.md` rewrite. No production
skill, run-state, or handoff YAML was modified by this task.

## Changed paths

- Added `enable-progress-in-teams/tests/SkillContract.Tests.ps1`.
- Added `docs/configurable-teams-target-and-timer/test-summary.md`.

## Test implementation

`SkillContract.Tests.ps1` resolves `SKILL.md` relative to its own `tests` directory, accumulates
named assertion failures, prints actionable `PASS`/`FAIL` output, and exits `1` if any contract
fails. It has no external dependencies, mocks, Teams calls, scheduler calls, or state writes.

Coverage mapping:

| Implementation contract | Static coverage |
|---|---|
| Dynamic frontmatter and version | Validates skill name, selectable destination description, and exact version `1.2.0`. |
| Target discovery and identity | Validates `ListTeams`, `ListChannels`, opaque slug semantics, canonical `team_id`/`channel_id`, confirmation, retarget, status, disable, terminal cleanup, and generation-specific root marker. |
| Unified schedule | Validates one 5-minute schedule owns route reconciliation and reply polling, the 288-ticks/day and about-5-minute disclosure, and no conflicting 2/10-minute cadence. |
| Authorization and persisted state | Validates separate sender-ID-only authorization, retained sender ID, `[ToAgent]` prefix, display-name rejection, authorization revision, schedule key/handle/lease, generation/root, cursor, ledger, and degraded state. |
| Tick and blocked behavior | Validates reload/ownership guards, five-page pagination, no watermark advance on exhaustion, three-tick degradation threshold, ledger-before-surface, safe-local-approval queue, no preemption/webhook guarantee, and blocked-state timer reuse. |
| Failure and regression behavior | Validates stale/deleted target, scheduler and persistence failure, duplicate schedules, pagination exhaustion, acknowledgement ambiguity, stop failure, disable, terminal cleanup, forbidden legacy IDs/terms, and blocked-only schedule instructions. |
| Completion format | Counts bullets in the fenced completion template (maximum seven) and validates destination, slug/generation/root, timer, listening, degraded/local fallback, and partial/blocked-only next action fields. |

## Commands and results

1. `& '.\tests\SkillContract.Tests.ps1'; exit $LASTEXITCODE`
   **Result:** exit `0`; `PASS: 73 static skill contract assertions passed.`
2. `git diff --check; exit $LASTEXITCODE`
   **Result:** exit `0`; no whitespace errors reported.

## Uncovered risks

These static checks cannot execute deferred Teams tools, scheduler reconciliation, session SQL
transactions, or live reply pagination. They validate that the Markdown skill contract specifies
those behaviors; runtime tool-schema compatibility and end-to-end operational behavior remain for
the next validation owner.

## Remediation Attempt 1 — Paired Static Contract Tests

**Task ID:** `remediation-tests-1`
**Workflow block:** dev-dude-feature-implementation Remediation attempt 1 — paired tests
**Scope:** Added direct static contract coverage for the remediated state-safety findings
SV-01 through SV-04. This task modified neither `SKILL.md`, run state, nor handoff YAML.

### Changed paths

- Modified `enable-progress-in-teams/tests/SkillContract.Tests.ps1`.
- Modified `docs/configurable-teams-target-and-timer/test-summary.md`.

### New direct assertions

| Finding | Static contract coverage |
|---|---|
| **SV-01** | Both durable watermark columns; exact lexicographic timestamp-and-message-ID disjunction; stable ordinal tie-break; common sort/qualification tuple; greatest-fully-processed advancement; retained watermark after exhaustion; rejection of timestamp-only qualification. |
| **SV-02** | Persisted `schedule_revision` and `schedule_intent_token`; exact five-dimension adoption CAS; index-ordered intent/create/adopt/revision/loser-stop lifecycle; baseline revision `0`; stale intent and unknown/failed stop visibility. |
| **SV-03** | Tick authorization-revision and sender snapshot capture; per-effect revision guard; claim/surface revalidation leaving stale replies unclaimed; acknowledgement revalidation that forbids stale authorization. |
| **SV-04** | Three-part transition primary key; index-ordered Phase 5 allocation, keyed `new_root_pending` persistence, root binding, atomic activation, and old-root handoff; transition-before-new-channel-write rule; old-route preservation with failed/degraded evidence; rejection of the former transition-before-allocation order. |

The ordering checks compare regex match indices inside the extracted Phase 5 retarget section;
they do not accept co-presence of terms as proof of execution order. The assertion harness retains
actionable named `PASS`/`FAIL` output and exits nonzero for any failure.

### Commands and results

1. `& '.\tests\SkillContract.Tests.ps1'; exit $LASTEXITCODE`
   **Result:** exit `0`; `PASS: 93 static skill contract assertions passed.`
2. `git diff --check; exit $LASTEXITCODE`
   **Result:** exit `0`; no whitespace errors reported.

### Remaining runtime risks

These tests are static Markdown-contract checks. They do not execute deferred Teams tool schemas,
the scheduler, session SQL transactions/CAS races, durable crash recovery, or live paginated reply
handling. Runtime compatibility and end-to-end behavior remain for the root orchestrator's next
validation stage; this paired-test task does not issue a final validation decision.
