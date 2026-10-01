# UX Review — Configurable Teams Target and Unified Timer

**Stage:** dev-dude-feature-design, Step 1 Investigation
**Task ID:** `design-ux-review`
**Status:** Investigation only. No design selected, no implementation, no production or test edits.

---

## 1. UX Scope

This review covers the **operator-facing, text-only journey** of `enable-progress-in-teams` as it
would change under the feature request. Two surfaces are in scope:

| Surface | Description |
| --- | --- |
| **CLI surface** | What the operator reads and types in the Copilot CLI transcript: enablement, destination choice, confirmation, change-target, status, errors, completion block. |
| **Teams surface** | What a human reads in the Teams channel thread: root post, threaded replies, blocker posts, resumed/acknowledgement replies, terminal replies. |

### In scope

- Selecting a Teams destination (team, then channel) instead of a hard-coded pair.
- Confirming and persisting the selection as a session-scoped slug.
- Displaying the current target on demand and in routine status.
- Changing the target mid-session, including while a timer is running.
- Continuous operator-message listening replacing the blocked-only listener.
- Blocked-state feedback, authorization rejection, deduplication, timeout and failure messaging.

### Out of scope

- Slug encoding format, storage schema, timer cadence value, and message-consumption semantics.
  These are design-option decisions; this review constrains their **user-visible consequences** only.
- Any graphical rendering. Both surfaces are text; all layout maps below are text-only.
- Approving a design or recommending a single option.

### Evidence base

- `docs/configurable-teams-target-and-timer/original-request.md` — requested behavior.
- `enable-progress-in-teams/SKILL.md` v1.1.1 — current observed behavior.
- `.dev-dude-handoffs/000-root-to-feature-design.yaml` — verified facts F001–F005, assumptions
  A001–A002, constraints C001–C004, open questions Q001–Q003.

### Evidence strength

**Strong** for current behavior: `SKILL.md` specifies invariants, phases, failure handling, and a
completion block verbatim. **Weak** for intended behavior: the request defers slug semantics, cadence,
authorization, and consumption semantics to design. Every statement below is labelled either
*Observed* (current artifact) or *Proposed* (this review's guidance).

---

## 2. Guiding Principles — proposed, not pre-existing

**No project UX principles exist.** The repository contains exactly one skill
(`enable-progress-in-teams/SKILL.md`); there is no UX guideline document, no design system, and no
second skill to triangulate house style against. The rubric below is **derived from conventions
observable in that single artifact** and is offered as **proposed guidance** for the design stage to
accept, amend, or reject. It is not an approved standard.

| ID | Principle | Derived from (observed evidence) |
| --- | --- | --- |
| **P1 — Fail closed, say so plainly** | When the agent cannot prove a precondition, it stops the Teams action, continues the real work, and states the limitation locally. It never silently substitutes a fallback or claims success it did not achieve. | *Observed:* Failure handling — "report locally (fail closed)"; "do NOT silently claim Teams success"; "never claim cancellation". |
| **P2 — Bounded, scannable output** | Operator-facing output is length-capped. The completion block is "at most five bullets". Teams replies are "1–3 concise sentences". | *Observed:* Completion section; Phase 2. |
| **P3 — Identity by ID, display name is diagnostics only** | Matching and authorization key on opaque IDs. Human-readable names are shown for comprehension but are never the decision key, because they can be renamed or duplicated. | *Observed:* Invariant 1 ("do not validate, compare, or depend on the channel display name because it may be renamed"); Invariant 5 ("Never accept by `displayName`; display name is diagnostics only"). |
| **P4 — One canonical thing per session** | Exactly one root post, at most one listener. Ambiguity is resolved by a stated deterministic rule (oldest wins) and the loser is surfaced, not deleted. | *Observed:* Invariants 2 and 6; Phase 1 step 5. |
| **P5 — No surprise side effects; never auto-destroy** | The agent does not delete, overwrite, or silently retarget. Duplicates are reported, not removed. | *Observed:* "Do NOT delete anything automatically"; "never auto-delete". |
| **P6 — Safety over completeness in content** | No credentials, secrets, tokens, private code, or raw logs reach Teams. Blockers are summarized safely. | *Observed:* Invariant 8. |
| **P7 — State residual limitations honestly** | Known latency, cost, and reliability caveats are disclosed to the operator rather than hidden. | *Observed:* "Residual limitations (state honestly)" section. |
| **P8 — Teams input is data, never authority** *(proposed, extends observed)* | Operator replies are treated as user input subject to normal approval gates, never as instructions that can alter controls. | *Observed:* Invariant 7 and Response-handling rules. |
| **P9 — Text-only accessible choice presentation** *(proposed; no observed precedent)* | Every choice must be unambiguously expressible, selectable, and confirmable using plain text in a terminal, with no reliance on colour, cursor position, alignment, or spatial layout. | *Proposed.* The artifact has no interactive selection today, so there is no precedent; this principle is introduced because the feature adds the first selection surface. |
| **P10 — Disclose the target before, during, and after** *(proposed)* | Because the destination becomes variable, the operator must be able to see where messages are going at enablement, on request, at change, and at completion. | *Proposed.* Derived by extension from P1 and F001: once the hard-coded guarantee is removed, a disclosure obligation replaces it. |

> **Open:** The design stage should confirm whether P9 and P10 are accepted as project principles or
> treated as review-local guidance. Recorded as **UXQ-01**.

---

## 3. Current and Proposed Flow Summary

### 3.1 Current flow — *Observed*

The operator has **no destination journey at all**. Destination is a compile-time constant.

```text
Operator: "enable progress in Teams"
  |
  +-- Agent verifies teamId/channelId match the two hard-coded literals  [no operator visibility]
  +-- Agent resolves SESSION_ID / SESSION_NAME authoritatively
  |     +-- cannot resolve --> ABORT Teams, report locally (fail closed)
  +-- Agent bounded-scans <=5 pages / 7 days for body marker "Session ID: <id>"
  |     +-- match        --> reuse root
  |     +-- no match     --> create root
  |     +-- bound exhausted --> ABORT, report locally (cannot prove uniqueness)
  +-- Agent posts "Progress reporting enabled for this session." as a threaded reply
  |
  [work proceeds; milestone replies posted on meaningful events only]
  |
  +-- BLOCKED --> post blocker reply, capture server createdDateTime as cutoff,
  |               create (or reuse) ONE recurring listener, persist schedule_id
  |     +-- each tick: read replies, accept only (sender id == authorized) AND
  |     |              (body starts exactly "[ToAgent]") AND (newer than cutoff)
  |     +-- first qualifying reply --> stop schedule FIRST, then surface instruction,
  |     |                              post one resumed reply
  |     +-- 4h deadline reached     --> stop schedule, post timeout reply
  |
  +-- TERMINAL --> one terminal reply; reconcile and stop any active listener
```

**Key observed UX characteristics:**

- Zero operator decisions. The only input is the trigger phrase.
- No confirmation step, because there is nothing to confirm.
- Listening exists **only while blocked**. Outside a blocked state the operator cannot reach the
  agent through Teams at all.
- Latency and cost are disclosed honestly (~10 min detection latency; ~24 checks over 4 hours).
- The CLI completion block is a fixed five-bullet maximum.

### 3.2 Proposed flow — *Proposed*, structural shape only

The request introduces **three new operator decision points** and **one continuously-visible status**.

```text
Operator: "enable progress in Teams"
  |
  +-- [NEW] Discover teams available to the operator
  |     +-- zero teams            --> ERR-NO-TEAMS: state plainly, fall back to local reporting
  |     +-- one team              --> auto-advance, but DISCLOSE the auto-choice
  |     +-- many teams            --> SELECTION SURFACE A (paged, text-only)
  |
  +-- [NEW] Discover channels in the chosen team
  |     +-- include membershipType (standard / private / shared) on every row
  |     +-- zero postable channels --> ERR-NO-CHANNELS: offer back-to-teams or cancel
  |     +-- many channels          --> SELECTION SURFACE B (paged, text-only)
  |
  +-- [NEW] CONFIRMATION GATE
  |     +-- echo team + channel + membershipType + short ID fragment
  |     +-- operator confirms / re-picks / cancels
  |     +-- cancel --> NOTHING persisted, NOTHING posted, work continues locally
  |
  +-- [NEW] Persist session-scoped slug; disclose the slug to the operator
  |
  +-- Resolve SESSION_ID (unchanged, still fail-closed)
  +-- Bind root thread in the SELECTED channel (bounded scan, unchanged shape)
  +-- Post enabled reply, now including which destination was bound
  |
  +-- [NEW] Start the UNIFIED RECURRING TIMER (runs for the whole enabled period,
  |         not just while blocked)
  |     +-- reinforces routing idempotently
  |     +-- listens for operator messages ALWAYS: while working, while idle,
  |         and while parked at a blocking command
  |
  [work proceeds; milestone replies as before]
  |
  +-- [NEW] "where am I posting?"      --> STATUS SURFACE (target + timer + listening state)
  +-- [NEW] "change the Teams target"  --> re-enter selection, then CHANGE-TARGET
  |                                        CONFIRMATION (must disclose timer + thread impact)
  |
  +-- BLOCKED --> blocker reply; NO new listener is created (timer already listening)
  |
  +-- TERMINAL --> terminal reply; stop timer; report final destination in completion block
```

**What materially changes for the operator:**

| Dimension | Observed (today) | Proposed (after change) |
| --- | --- | --- |
| Destination | Invisible constant | Operator-selected, must be disclosed |
| Decisions | None | Team, channel, confirm, optionally change |
| Cancellation | Not applicable | Must exist at every step, must be side-effect-free |
| Listening | Only while blocked | Continuous while enabled |
| Listener creation | On first blocker | At enablement |
| "Where is this going?" | Answer is constant | Answer is session state and must be queryable |
| Trust basis | Hard-coded guarantee | Disclosure and confirmation |

---

## 4. Simple Layout Maps — text only

All maps are plain-text terminal output. No colour, box-drawing, cursor addressing, or alignment is
load-bearing.

### 4.1 Selection Surface A — team selection

```text
Surface: Select Teams team
- Heading line: purpose + scope ("Select the team to post session progress to.")
- Count line: "12 teams available — showing 1-10."
- Option rows (one per line, each self-contained):
    "[1] Contoso Platform Engineering  - id ...8cf98"
    "[2] Contoso Platform Engineering  - id ...4a21b   (duplicate name)"
    "[3] Field Readiness               - id ...77e03"
- Control row: "[m] more   [s] search by name   [c] cancel"
- Prompt line: "Reply with a number, or m / s / c."
```

### 4.2 Selection Surface B — channel selection

```text
Surface: Select channel in "Contoso Platform Engineering"
- Heading line: chosen team name + short id fragment
- Count line: "23 channels — showing 1-10."
- Option rows:
    "[1] General        standard  - id ...a9Ec1"
    "[2] Build Alerts   standard  - id ...b3F72"
    "[3] Release War Room  private  - id ...c1D05   (private: only members see posts)"
    "[4] Partner Sync      shared   - id ...d7A48   (shared: may include external members)"
- Control row: "[m] more   [s] search   [b] back to teams   [c] cancel"
- Prompt line: "Reply with a number, or m / s / b / c."
```

### 4.3 Confirmation Gate

```text
Surface: Confirm progress destination
- Line 1: Team    : Contoso Platform Engineering (...8cf98)
- Line 2: Channel : Build Alerts (...b3F72)
- Line 3: Type    : standard
- Line 4: Scope   : one root post per session; replies threaded under it
- Line 5: Listening: continuous while enabled
- Prompt: "[y] confirm   [r] re-pick   [c] cancel"
```

### 4.4 Status Surface — "where am I posting?"

```text
Surface: Teams progress status
- Target    : Contoso Platform Engineering > Build Alerts (standard)
- Slug      : <session-scoped slug>
- Root post : bound (reused | created) | not bound
- Timer     : running (every <cadence>) | stopped | failed to start
- Listening : active since <server timestamp> | inactive (reason)
- Last check: <server timestamp> | never
- Note      : detection latency up to one timer interval
```

### 4.5 Change-Target Confirmation

```text
Surface: Change progress destination
- From : Contoso Platform Engineering > Build Alerts (...b3F72)
- To   : Field Readiness > Release Notes (...e5C19)
- Effect on thread   : a new root post will be bound in the new channel;
                       the previous thread will receive one final hand-off reply
                       and will not be deleted
- Effect on listening: the timer continues; it will listen in the NEW thread only
- Effect on history  : earlier updates remain in the previous thread
- Prompt: "[y] change   [c] keep current target"
```

### 4.6 Teams-side root post and replies

```text
Surface: Teams channel thread
- Root subject: "Copilot progress - session <SESSION_ID> - <SESSION_NAME>"
- Root body line 1: "Session ID: <SESSION_ID>"        <- authoritative reuse marker
- Root body line 2: "Session name: <SESSION_NAME>"
- Root body line 3: short enabled-status line
- Replies (threaded, each 1-3 sentences):
    enabled | milestone | blocked | resumed/response-received | target-changed | terminal
```

### 4.7 CLI completion block — *Observed* shape, one proposed addition

```text
Surface: Completion (at most five bullets)
- Result line: SUCCESS | PARTIAL | BLOCKED
- Bullet: root thread bound (reused | created) for the exact session id
- Bullet: events posted
- Bullet: listener/timer state
- Bullet: local-only fallback used, when Teams was unavailable
- Bullet: exact next action, only for PARTIAL or BLOCKED
```

> **Tension:** the destination is now variable and P10 argues it must appear at completion, but P2
> caps the block at five bullets, which is already full. Options: fold the destination into the
> existing "root thread bound" bullet, or raise the cap. Recorded as **UXQ-02**.

---

## 5. Key UX Risks

Each risk is labelled with severity and the principle it threatens.

### R1 — Loss of the destination guarantee (High, P1/P3/P10)

*Observed:* the hard-coded pair makes mis-posting structurally impossible. *Proposed:* once the
destination is operator-selected, a mis-selection silently publishes session progress to the wrong
audience. The confirmation gate becomes the **only** protection. If confirmation is skipped for
convenience (for example auto-selecting when a name looks familiar), the feature trades a hard
safety property for a soft one.

### R2 — Long lists are unusable and unsafe when truncated (High, P9)

Operators may belong to dozens or hundreds of teams and channels. A single unpaged dump is
unreadable in a terminal; a silently truncated list is worse, because the operator cannot tell
whether the intended destination was omitted. Truncation must be **stated**, never implied.
This mirrors the artifact's existing treatment of bounded scans, which explicitly fail closed when
the bound is exhausted rather than guessing.

### R3 — Duplicate display names are indistinguishable (High, P3)

*Observed:* Invariant 1 already warns that display names are unreliable and renameable. Two teams or
two channels with identical display names are common in large tenants. A list showing names alone
gives the operator no basis to choose. Selecting the wrong one of two identically-named channels is
undetectable from the confirmation echo unless an ID fragment is shown.

### R4 — Private and shared channels have different audiences (High, P6)

A private channel is visible only to its members; a shared channel may include members from other
tenants. Posting session progress — even safely summarized — into a shared channel can expose work
context to an external audience. The operator may not remember a given channel's type. Membership
type must be visible **at selection and at confirmation**, not discovered afterwards.

### R5 — Stale or deleted target mid-session (High, P1)

The selected channel can be archived, deleted, renamed, or have the operator's access revoked after
selection. *Observed:* today this is impossible, so there is no recovery path. The proposed design
must define what the operator sees when a post fails because the target vanished: the current
artifact's doctrine (P1) says continue the work, report locally, never substitute another
destination. Silently re-selecting would be the most harmful possible behavior.

### R6 — Changing target while the timer is active (High, P4)

The request permits changing targets mid-session while the unified timer runs. Without clear
messaging the operator cannot predict: whether a new root post is created, whether prior updates
move, which thread the timer now listens in, and whether a reply already typed in the old thread is
lost. An operator who replies `[ToAgent]` in the old thread after a retarget would reasonably expect
it to be heard. It will not be.

### R7 — Invisible continuous listening (Medium-High, P7/P10)

*Observed:* listening is tightly scoped — it starts at a blocker and self-cancels. *Proposed:*
continuous listening means the agent is polling a channel for the whole session. Two opposite
failures are possible: the operator **over-trusts** it (assumes a reply is seen instantly, when
detection lag is up to one interval) or **under-trusts** it (does not know they can message at all).
Both are fixed by persistent, honest status rather than by a one-time enablement line.

### R8 — Cost and latency of a longer-running timer (Medium, P7)

*Observed:* the artifact already discloses ~24 checks over 4 hours as "non-trivial in runtime/cost"
for a **blocked-only** listener. A timer that runs for the entire enabled session is strictly more
expensive and longer-lived. The existing honesty obligation extends to it; the operator should see
the cadence and be able to stop it.

### R9 — Authorization rejection is invisible to the human (Medium-High, P3/P8)

*Observed:* a reply from a non-authorized sender is rejected and polling simply continues — silently,
from the replier's point of view. A colleague who replies `[ToAgent] go ahead` gets no feedback and
may wait indefinitely, or escalate. With continuous listening across a session this silent-rejection
window becomes much larger. Note the counter-pressure: acknowledging every rejected reply would both
spam the thread (against P2) and confirm to unauthorized parties that an agent is listening.

### R10 — Duplicate or re-processed instructions (Medium, P4)

*Observed:* duplication is bounded today because the listener stops on the first qualifying reply.
*Proposed:* a continuously-running timer may see the same qualifying reply on multiple ticks, or the
operator may post the same instruction twice believing the first was missed. Without a visible
"received" acknowledgement, the operator cannot tell which happened, and may act on the assumption
that nothing was received.

### R11 — Timeout and failure wording that overclaims (Medium, P1)

*Observed:* the artifact is careful never to claim cancellation it did not achieve
(`stop_failed` is surfaced rather than reported as stopped). A continuously-running timer has more
failure modes — failed to start, started but cannot be stopped, stopped unexpectedly, target gone —
and each needs distinct, non-overclaiming wording.

### R12 — Cancellation leaving partial state (Medium, P5)

If the operator cancels at the channel step after already choosing a team, or cancels at the
confirmation gate, the system must hold **no** persisted slug and must have made **no** Teams write.
Partial persistence would leave the session in a state the operator never agreed to.

### R13 — Accessibility of text-only choice (Medium, P9)

Terminal output is consumed by screen readers, in narrow windows, and in transcripts that strip
alignment. Any design relying on column alignment, colour to distinguish private channels, or
arrow-key navigation excludes those users. Every row must carry its meaning in its own words.

### R14 — Trigger-phrase ambiguity for change-target (Low-Medium, P10)

`SKILL.md` lists trigger phrases for enablement only. "Change the Teams target" has no defined
phrase set. Without one, the operator cannot discover that retargeting exists.

---

## 6. Recommendations

Guidance for the design stage. These are **UX constraints on any option**, plus differentiated notes
for two or three plausible option shapes. They are not a design selection.

### 6.1 Cross-cutting constraints — any option should satisfy these

**C-UX-1 — Always show an ID fragment beside every name.** Addresses R3 and reinforces P3. A short
trailing fragment of the opaque ID on every option row and in every confirmation echo lets the
operator disambiguate duplicates without reading a full GUID.

**C-UX-2 — Always show membership type on channel rows and in confirmation.** Addresses R4. Annotate
private and shared channels with a one-clause consequence (`private: only members see posts`;
`shared: may include external members`) rather than the bare keyword.

**C-UX-3 — State list bounds explicitly; never truncate silently.** Addresses R2 and matches the
artifact's observed bounded-scan doctrine. Always print total count and displayed range. Provide a
narrowing affordance (search by name) so large tenants do not require paging through everything.

**C-UX-4 — Cancellation is available at every step and is side-effect-free.** Addresses R12 and P5.
Cancelling must persist no slug, create no root post, start no timer, and must end with an explicit
line stating that nothing was changed and work continues with local reporting only.

**C-UX-5 — One confirmation gate before the first write.** Addresses R1. No Teams write and no slug
persistence occurs before explicit confirmation. The echo must contain team name, channel name,
membership type, and ID fragment — everything needed to catch a mis-selection.

**C-UX-6 — Disclose auto-advance.** If only one team or one channel exists, selecting it
automatically is reasonable, but the confirmation gate must still state that it was auto-selected so
the operator is never surprised by an unreviewed destination.

**C-UX-7 — A queryable status surface exists for the whole enabled period.** Addresses R7, R8, R10.
It must report target, slug, root-binding state, timer state, listening state, and last check time,
and must restate the detection-latency caveat (P7).

**C-UX-8 — Retarget messaging states thread, listening, and history effects before confirming.**
Addresses R6. The three effects in layout 4.5 are the minimum. Additionally, post one hand-off reply
in the old thread stating that updates have moved and replies there will no longer be read — this is
the only way a human watching the old thread learns to stop replying.

**C-UX-9 — Never auto-substitute a destination on failure.** Addresses R5 and preserves P1/P5. On a
stale or deleted target, state what failed, state that nothing was posted elsewhere, continue the
underlying work, and offer re-selection as an explicit operator action.

**C-UX-10 — Acknowledge accepted instructions exactly once; keep rejections quiet but locally
visible.** Addresses R9 and R10 while respecting P2 and the counter-pressure noted in R9. Proposed
split: post exactly one threaded acknowledgement per **accepted** instruction so the operator sees it
landed; surface **rejected** replies in the CLI transcript only (count and reason), not in Teams.
This gives the operator diagnosability without spamming the channel or signalling to unauthorized
repliers. The authorized-sender rule itself is a security decision, not a UX decision — flagged as
open below.

**C-UX-11 — Distinct, non-overclaiming wording per failure mode.** Addresses R11. Recommended
message skeletons:

```text
ERR-NO-TEAMS      "No Teams teams are available to this account. Teams progress reporting was not
                   enabled. Work continues; progress will be reported here only."
ERR-NO-CHANNELS   "No postable channels found in <team>. Choose another team [b] or cancel [c].
                   Nothing has been changed."
ERR-TARGET-GONE   "The selected channel is no longer reachable (<safe reason>). Nothing was posted
                   to any other destination. Work continues; reported here only.
                   Re-select with: change the Teams target."
ERR-DENIED        "Access to <channel> was denied. Nothing was posted elsewhere. Work continues;
                   reported here only."
ERR-TIMER-START   "The progress timer could not be started. Progress updates will still post, but
                   operator replies in Teams will not be read."
ERR-TIMER-STOP    "The progress timer could not be stopped (<safe reason>). It may still be running.
                   Do not assume it has stopped."
ERR-TIMEOUT       "No authorized reply was received within <window>. The timer has stopped listening.
                   Work continues; reported here only."
```

Note `ERR-TIMER-STOP` deliberately mirrors the observed `stop_failed` doctrine: never claim
cancellation that was not achieved.

**C-UX-12 — Text-only, screen-reader-safe presentation.** Addresses R13 and P9. Concretely: one
option per line; a bracketed token at line start (`[1]`, `[m]`, `[c]`); every row self-describing
without reference to a header row; no reliance on colour, alignment, box characters, or cursor
movement; accept both the number and an unambiguous name prefix as input.

**C-UX-13 — Define and document change-target trigger phrases.** Addresses R14. Add explicit phrases
to the skill description so retargeting is discoverable, for example "change the Teams target",
"post progress to a different channel", "where am I posting progress".

### 6.2 Differentiated guidance by option shape

These are **hypothetical option shapes** offered so the design stage can evaluate UX cost. None is
recommended.

#### Option shape I — Interactive paged selection at enablement

Operator is shown teams, then channels, then a confirmation gate.

- *UX strengths:* Highest mis-selection protection (R1); naturally supports membership-type and
  ID-fragment disclosure; cancellation is obvious.
- *UX costs:* Most turns before any work starts; worst experience in large tenants unless C-UX-3
  search is included; least usable in an unattended or autopilot context where no operator is present
  to answer.
- *Must-haves if chosen:* C-UX-3 (search + explicit bounds), C-UX-12, and a defined behavior when no
  operator responds to the prompt.

#### Option shape II — Declarative target in the trigger, with confirmation

Operator names the destination in the invocation; the agent resolves it and confirms.

- *UX strengths:* Fewest turns; works when the operator already knows the destination; repeatable.
- *UX costs:* Name-based resolution collides head-on with P3 and R3 — a typed name may match two
  teams or two channels. Resolution ambiguity becomes a new error state needing its own
  disambiguation surface, which partially reintroduces Option I's selection list.
- *Must-haves if chosen:* an explicit ambiguity surface (list the matches with ID fragments, never
  auto-pick); confirmation is non-optional; a clear "not found" message distinct from "ambiguous".

#### Option shape III — Remembered default with explicit override

A previously confirmed destination is reused; the operator may change it.

- *UX strengths:* Fastest for repeat use; least friction in a long-running workflow.
- *UX costs:* Highest silent-mis-post risk (R1). A remembered target may be stale (R5) or may no
  longer be appropriate for the current work. Conflicts with the request's "session-scoped" framing,
  which implies the selection does not outlive the session.
- *Must-haves if chosen:* the remembered target must be **restated and re-confirmed** at each
  enablement, never silently reused; staleness must be re-validated before the first post.

### 6.3 Guidance specific to the unified timer

- **Timer state is operator-visible state, not an internal detail.** It appears in the status surface
  (C-UX-7) and in the completion block's listener bullet.
- **Distinguish three states plainly:** `running`, `stopped`, `failed`. Do not merge "failed to start"
  with "stopped" — they have opposite implications for whether replies are being read.
- **Restate detection latency wherever listening is claimed.** P7 requires it; a continuous timer
  makes over-trust more likely (R7).
- **Make the timer's cost visible once, at enablement**, in one clause — consistent with the existing
  residual-limitations honesty without violating P2's brevity cap.
- **The timer must not be presented as a guaranteed webhook.** The observed artifact explicitly calls
  this out; the stronger "always listening" framing makes the misconception easier, so the caveat
  matters more, not less.

---

## 7. Open UX Decisions

These are **explicit open questions**, not recommendations. Each needs a design-stage answer.

| ID | Open question | Why it is open | Blocking? |
| --- | --- | --- | --- |
| **UXQ-01** | Are P9 and P10 accepted as project UX principles, or review-local guidance only? | No pre-existing UX principles exist in the repository; this review proposes them. | No |
| **UXQ-02** | How is the destination disclosed at completion given the observed five-bullet cap? Fold into an existing bullet, or raise the cap? | P2 (observed) and P10 (proposed) conflict directly. | No |
| **UXQ-03** | Is the slug operator-visible, and if so in what form? Opaque handle, or human-readable `team/channel`? | Request defers slug semantics (A001, Q001). Affects every status and confirmation surface. | No |
| **UXQ-04** | On retarget, does the agent bind a **new** root post in the new channel, or attempt to carry the session thread across? | Determines the entire change-target message set (4.5) and whether history appears split. | No |
| **UXQ-05** | Does the old thread receive a hand-off reply on retarget, and is a final terminal reply still posted there? | Humans watching the old thread otherwise keep replying into a dead listener (R6). | No |
| **UXQ-06** | Should rejected (unauthorized) replies be acknowledged in Teams at all, or only surfaced in the CLI? | C-UX-10 proposes CLI-only, but this trades repliers' feedback against thread noise and information disclosure. Security-adjacent. | No |
| **UXQ-07** | With the hard-coded authorized sender id removed or made configurable, who is authorized to send `[ToAgent]` instructions to a self-selected destination? | Invariant 5 is currently tied to one literal id. A selectable destination makes "the authorized operator" undefined. **Security decision with a large UX surface.** | Potentially |
| **UXQ-08** | Is the operator's reply still required to carry the `[ToAgent]` prefix under continuous listening? | Continuous listening in a shared channel means ordinary chatter is now read; the prefix is the only filter. Dropping it would be a major UX and safety change. | No |
| **UXQ-09** | What does the agent do when a selection prompt receives no response — in autopilot or unattended runs? | Option shape I assumes a present operator. Request does not address unattended enablement. | No |
| **UXQ-10** | Is there an operator-facing way to stop the timer or disable reporting mid-session without ending the session? | Request adds "change target" but not "turn off". Continuous listening makes an off-switch more expected. | No |
| **UXQ-11** | What is the timer cadence, and is it operator-visible or operator-adjustable? | Q002 defers cadence. Adjustability is a UX affordance with cost implications (R8). | No |
| **UXQ-12** | How are duplicate/re-seen instructions surfaced — silently deduplicated, or acknowledged once with a "already received" note? | Q003 defers consumption semantics; affects R10 directly. | No |
| **UXQ-13** | Does selection list **all** reachable channels, or filter to those the operator can post in? A visible-but-unpostable channel produces a confusing late failure. | Capability is a platform question this review did not verify. | No |
| **UXQ-14** | Does the status surface need its own trigger phrase, or is it folded into the change-target flow? | Related to R14 / C-UX-13. | No |

### Explicitly not decided here

- Slug format, storage schema, timer cadence value, authorization model, consumption semantics.
- Which option shape to adopt.
- Whether any observed invariant should be relaxed.

---

## 8. Document Handoff Notes for Investigation-Documenter

**Provenance.** Every claim is labelled *Observed* (traceable to `SKILL.md` v1.1.1 or
`original-request.md`) or *Proposed* (this review's guidance). Do not promote *Proposed* content to
*Observed* when consolidating.

**Carry forward verbatim where possible.**

1. **Section 2 principles table** — this is the only UX rubric that exists for this project. It must
   be carried with its "proposed, not pre-existing" caveat intact. Stripping that caveat would
   misrepresent an inferred rubric as an approved standard.
2. **Section 6.1 constraints C-UX-1 … C-UX-13** — these are the testable UX acceptance criteria and
   are the most directly reusable output of this lane.
3. **Section 6.1 C-UX-11 message skeletons** — reusable as draft copy, but they are *drafts*, not
   approved strings.
4. **Section 7 open questions UXQ-01 … UXQ-14** — must survive into the design stage unanswered.
   **UXQ-07 is the most consequential**: removing the hard-coded destination invalidates the premise
   of the hard-coded authorized-sender invariant, and it is security-adjacent, not purely UX.

**Relationship to the inbound handoff.**

| Inbound item | This lane's contribution |
| --- | --- |
| Q001 (slug format) | UXQ-03 adds the operator-visibility dimension. |
| Q002 (timer cadence) | UXQ-11 and Section 6.3 add visibility, adjustability, cost-disclosure dimensions. |
| Q003 (authorization / dedup / surfacing) | UXQ-06, UXQ-07, UXQ-08, UXQ-12 and C-UX-10 decompose it into distinct UX decisions. |
| F001 (hard-coded destination) | R1 identifies that this is a **safety property**, not merely a limitation; its removal needs a compensating control. |
| F002 / F003 (blocked-only listener) | R7, R8 and Section 6.3 cover the shift to continuous listening. |
| A002 (timer runs throughout) | Treated as *Proposed* throughout; all timer guidance is conditional on A002 holding. |

**Known gaps in this review.**

- No running application, no screenshots, no graphical UI — both surfaces are text, so inspection was
  limited to artifact reading. No browser or devtools tooling was applicable.
- Teams platform capabilities (whether postable-channel filtering is possible; exact list-paging
  behavior) were **not verified**. UXQ-13 depends on this; route it to the technical resource
  investigation lane rather than treating this review's assumption as fact.
- The repository contains exactly one skill, so no cross-skill house style could be triangulated.
  The rubric's evidence base is correspondingly narrow and should be treated as a starting point.

**Constraint compliance.** No production code or tests were modified. No design was selected. No
approval was granted or implied. This lane produced exactly one artifact: this file.
