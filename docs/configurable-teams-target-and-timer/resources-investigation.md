# Resources Investigation: Configurable Teams Target and Unified Timer

**Feature**: Discover and select a Microsoft Teams destination, persist it for the session, support
retargeting, and replace the blocked-only listener with one unified recurring routing/listening timer.
**Date**: 2026-10-01
**Investigator**: Technical-Resource-Investigator agent
**Based on**: [Investigation](./investigation.md) and [UX review](./ux-review.md)
**Source policy**: governed by `C:\Users\jrastrom\.copilot\skills\dev-dude\references\trusted-source-policy.md`

## Research Tools

| Tool | Status |
|------|--------|
| Documentation MCP | available; Microsoft Learn MCP used |
| GitHub / registry lookup | available; no external package was needed |
| WebFetch / WebSearch | available; official GitHub documentation used for scheduler semantics |
| Teams runtime schemas | available; loaded `ListTeams`, `ListChannels`, `GetTeam`, `GetChannel`, `ListChannelMessages`, `ListChannelMessageReplies`, `SendMessageToChannel`, and `ReplyToChannelMessage` schemas |
| Serena | available and onboarding complete; no production code changes were permitted |

No `docs\ArchOverview` artifacts exist. This is noted for downstream design review and does not block
resource discovery.

## Candidate Resources

### Internal Reuse Candidates (validated from investigation.md)

| Resource | Location | Fit | Notes |
|----------|----------|-----|-------|
| Authoritative session identity resolution with ambiguity fail-closed behavior | `enable-progress-in-teams/SKILL.md` | High | Retain the runtime-first/session-store fallback and never invent a session ID. The selected destination and timer rows must key to this identity. |
| Exact session body marker and bounded root reuse | `enable-progress-in-teams/SKILL.md` | High | Reuse ID-based root matching, bounded scans, oldest-wins duplicate handling, and no-write behavior when absence cannot be proven. Apply the same rules independently for a new root after retargeting. |
| Canonical opaque Teams IDs, with display names for diagnostics only | `enable-progress-in-teams/SKILL.md`; `investigation.md` | High | Team and channel IDs are the stable routing values. Names and membership labels are presentation metadata and must not be identity keys. |
| Session `sql` durable state | Existing `teams_progress_listener` pattern in `enable-progress-in-teams/SKILL.md` | High | Extend the same session-scoped SQLite mechanism for destination, root binding, timer ownership, cursor/deduplication, and cleanup state rather than adding a dependency. |
| Persisted scheduler handle plus create-compensation | `enable-progress-in-teams/SKILL.md` | High | Persist the returned schedule ID immediately; if persistence fails, stop the newly created schedule and report the failure locally. |
| Schedule reconciliation by ID | `enable-progress-in-teams/SKILL.md` | High | Reconcile live schedules by `schedule_id`, never by prompt text. This is the appropriate ownership/idempotency guard for one timer per session. |
| Stop-before-act and explicit stop-failure states | `enable-progress-in-teams/SKILL.md` | High | Preserve stop-before-processing of an accepted operator message, truthful `stop_failed` handling, and terminal cleanup. |
| Bounded pagination and server timestamps | `enable-progress-in-teams/SKILL.md` | High | Continue bounded page traversal and compare Teams server timestamps, but add a durable cursor or message-ID ledger for continuous operation. |
| Safe content and normal approval gates | `enable-progress-in-teams/SKILL.md`; `ux-review.md` | High | Teams content remains untrusted input. Keep safe summaries, prefix filtering, sender-ID authorization, and normal approval gates. |

### External Candidates

| Candidate | Type | Citation (allowlisted) | Status |
|-----------|------|------------------------|--------|
| Microsoft Teams MCP runtime tools | platform/API adapter | Runtime schemas loaded in this session: `teams-ListTeams`, `teams-ListChannels`, `teams-GetTeam`, `teams-GetChannel`, `teams-ListChannelMessages`, `teams-ListChannelMessageReplies`, `teams-SendMessageToChannel`, `teams-ReplyToChannelMessage` | recommended |
| Microsoft Graph Teams APIs underlying the adapter | platform/API | [List joined teams](https://learn.microsoft.com/en-us/graph/api/user-list-joinedteams?view=graph-rest-1.0), [List channels](https://learn.microsoft.com/graph/api/channel-list?view=graph-rest-1.0), [List channel messages](https://learn.microsoft.com/graph/api/channel-list-messages?view=graph-rest-1.0), [List replies](https://learn.microsoft.com/en-us/graph/api/chatmessage-list-replies?view=graph-rest-1.0), [chatMessage resource](https://learn.microsoft.com/en-us/graph/api/resources/chatmessage?view=graph-rest-1.0) | recommended as capability reference, not a new dependency |
| GitHub Copilot CLI recurring prompts | platform/runtime capability | [Scheduling prompts in GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/schedule-prompts) | recommended through existing `manage_schedule`; not a new dependency |
| Microsoft Graph change notifications | platform/API alternative | [Change notifications for Teams messages](https://learn.microsoft.com/graph/teams-changenotifications-chatmessage) | unverified for this skill/runtime; no webhook/subscription tool is available in the authorized runtime |

## Runtime Capability Findings

The loaded Teams schemas provide the following concrete shapes and constraints:

- `ListTeams` returns the signed-in user's teams with `id` (GUID), `displayName`, `description`, and
  `webUrl`. The runtime schema exposes no `nextLink` or `hasMoreResults`; treat the returned set as
  the complete adapter result and do not invent client pagination.
- `ListChannels` requires a verified team GUID and returns `id`, `displayName`, `description`,
  `createdDateTime`, `webUrl`, and `membershipType`. It accepts `filter` and `select`, but exposes
  no pagination fields. The available membership types are `standard`, `private`, and `shared`.
- `GetTeam` returns selected team metadata; `GetChannel` returns selected channel metadata including
  membership type. These are useful for confirmation and stale-target checks, not for proving that a
  future post will succeed.
- `ListChannelMessages` returns root messages only, ordered most-recent-first, with message IDs,
  timestamps, sender `displayName` and `id`, and body content. It accepts `top` from 1 to 50,
  returns `hasMoreResults` and `nextLink`, and uses `nextLink` for subsequent pages.
- `ListChannelMessageReplies` returns reply IDs, sender `displayName` and `id`, body, and timestamp.
  It accepts `maxReplies` from 1 to 50 and returns `hasMoreResults` and `nextLink`.
- `SendMessageToChannel` requires canonical `teamId` and `channelId`, accepts text or HTML and
  optional subject/importance/mentions/cards, and returns message identity plus creation time.
- `ReplyToChannelMessage` requires canonical team, channel, and parent message IDs, accepts text or
  HTML and optional rich content, and returns reply identity, parent identity, and creation time.

The adapter therefore exposes the fields needed for selection, confirmation, root binding, sender-ID
authorization, timestamp cutoffs, and durable message IDs. It does not expose a postability probe,
channel membership for the signed-in user, sender UPN, or a server-side filter for “channels this
user can post to”.

Microsoft Learn adds two important platform facts. `GET /me/joinedTeams` returns teams where the
user is a direct member and currently does not support OData customization; shared-channel host
teams may require a separate associated-team operation
([joined teams](https://learn.microsoft.com/en-us/graph/api/user-list-joinedteams?view=graph-rest-1.0)).
The channel-list API says users cannot see private or shared channels they are not members of, and
supports filtering by `membershipType`
([list channels](https://learn.microsoft.com/graph/api/channel-list?view=graph-rest-1.0)).
Consequently, discovery can be scoped to returned channels, but a returned channel is not proof that
the eventual write will succeed.

## Facts vs Recommendations

- **Fact**: The runtime can return opaque team/channel IDs, display metadata, membership type,
  message IDs, sender IDs, timestamps, and body content; the exact fields and pagination parameters
  are in the loaded Teams schemas.
- **Fact**: Microsoft Graph channel message and reply reads have a maximum page size of 50 and use
  collection pagination; the channel message API documents a default page size of 20 and maximum of
  50 ([channel messages](https://learn.microsoft.com/graph/api/channel-list-messages?view=graph-rest-1.0);
  [replies](https://learn.microsoft.com/en-us/graph/api/chatmessage-list-replies?view=graph-rest-1.0)).
- **Fact**: A Teams message contains `id`, `createdDateTime`, `from`, `body`, and `replyToId`
  properties ([chatMessage](https://learn.microsoft.com/en-us/graph/api/resources/chatmessage?view=graph-rest-1.0)).
- **Fact**: Microsoft Graph supports change notifications for channel messages and replies, but the
  feature requires a subscription endpoint and permissions not exposed by the authorized Teams
  runtime ([change notifications](https://learn.microsoft.com/graph/teams-changenotifications-chatmessage)).
- **Fact**: Copilot CLI fixed recurring prompts run only while the interactive session is running;
  schedules are restored when a session is reopened, and fixed intervals range from 10 seconds to
  one day ([GitHub Copilot CLI scheduling](https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/schedule-prompts)).
- **Recommendation**: Use the existing Teams MCP tools and session SQLite state. Do not add a Graph
  SDK, webhook service, or scheduler package; the authorized runtime already supplies the required
  operations for a best-effort polling design.
- **Recommendation**: Represent the selected destination as an opaque, session-scoped slug that
  indexes a durable row containing canonical `team_id` and `channel_id`. Do not encode display names
  or rely on a reversible slug; names can change and IDs are the routing authority.
- **Recommendation**: Store the current root ID with the destination row and maintain a generation or
  revision so a retarget operation can invalidate stale timer prompts and old cursors atomically.
- **Recommendation**: Use one timer row per session with a unique session constraint and a stable
  logical schedule key. A tick should load current state from SQLite, verify that its schedule handle
  and destination generation are still current, then reinforce routing and poll only the current
  root.

## Advisory / Security Notes

- No external package is proposed, so no package advisory lookup is applicable.
- Teams authorization must continue to use sender `id`, never display name. The runtime exposes sender
  IDs in both root messages and replies.
- Membership type is security-relevant presentation metadata. `private` and `shared` destinations
  should require explicit confirmation and should not be silently downgraded to another channel.
- A successful discovery read must not be treated as authorization to post. Send failures must remain
  explicit and fail closed for Teams reporting.
- Change notifications are not a safe shortcut here: the source documents subscription requirements,
  and the authorized runtime has no subscription creation, renewal, validation endpoint, or callback
  receiver. Keep polling semantics bounded and honestly best-effort.

## License

| Candidate | License | Obligations / compatibility |
|-----------|---------|-----------------------------|
| Microsoft Teams MCP runtime tools | Runtime-provided capability; no third-party dependency introduced | No new package license obligation identified. |
| Microsoft Graph APIs | Microsoft platform service | No package is added; use remains subject to tenant permissions and service terms. |
| Copilot CLI scheduler | GitHub Copilot CLI capability | No package is added; schedules remain session-scoped. |

No license fact for an external package was needed or asserted.

## Maintenance Signals

- The recommended path has no added dependency maintenance surface.
- Teams and Graph schemas are service contracts and can evolve; the runtime schema should be treated
  as authoritative for actual callable fields. Microsoft Learn documents the current API behavior,
  including known limitations and permissions ([list channels](https://learn.microsoft.com/graph/api/channel-list?view=graph-rest-1.0);
  [joined teams](https://learn.microsoft.com/en-us/graph/api/user-list-joinedteams?view=graph-rest-1.0)).
- The scheduler is an existing CLI capability rather than a separately versioned package. Its
  session-running constraint is material and documented by GitHub
  ([scheduling prompts](https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/schedule-prompts)).

## Reliability / Operational Notes

- **Selection**: `ListTeams` and `ListChannels` are sufficient for a text-only paged selection
  surface at the adapter level, but the current `ListTeams`/`ListChannels` schemas lack pagination
  fields. The UX must not promise pagination beyond what the adapter returns; if the result is too
  large, selection needs a bounded display/search rule or an explicit fail-closed limitation.
- **Postability**: There is no postability check. The first root write remains the authoritative
  validation, and stale/revoked targets must fail locally without fallback posting.
- **Root binding**: Reuse the current bounded body-marker scan and oldest-wins race handling. For a
  retarget, bind a new root in the new channel rather than attempting to move a Teams thread.
- **Timer ownership**: One durable row keyed by session, containing schedule ID, destination slug,
  root ID, generation, status, and timestamps, supports idempotent create/reconcile/stop operations.
  A unique session constraint prevents duplicate active timer ownership.
- **Message cursor/deduplication**: The current listener table has no cursor. Add a durable
  `last_observed_message_id`/timestamp plus a consumed-message ledger or equivalent idempotency key.
  Because list results are most-recent-first and reply ordering should not be assumed, each tick must
  examine a bounded window, sort by server timestamp plus message ID, and retain state when the bound
  is exhausted.
- **Routing reinforcement**: A tick should verify that the current destination generation, root ID,
  and enabled state still match the persisted session row. It should not recreate a root or schedule
  merely because a prompt is retried; create/reconcile must be guarded by the unique session key.
- **Timer lifetime**: Keep the timer alive for the enabled session and stop it on disable/terminal
  cleanup. This is a best-effort polling loop, not a durable webhook or an always-on service.
- **Operator-message surfacing**: Scheduled prompts can submit work to the active Copilot session, but
  the available documentation does not establish a durable external queue or guaranteed delivery
  while the session is suspended. The design must specify local persistence and retry behavior and
  must not claim webhook semantics.

## Decision Matrix

| Criterion | Teams MCP + existing session SQL | Direct Microsoft Graph SDK | New webhook/subscription service |
|-----------|----------------------------------|----------------------------|----------------------------------|
| Fit | High: exact runtime operations already exist | Medium: broader API surface but not an authorized runtime dependency | Low for this skill: no callback service or subscription tool |
| Security | High if canonical IDs, sender IDs, and fail-closed writes remain mandatory | Medium: expands permission and credential surface | Low/Medium: adds externally reachable callback and renewal surface |
| Maintenance | High: no new package | Low/Medium: SDK and auth lifecycle would be added | Low: service, renewal, delivery, and storage operations required |
| License | High: no added package | Unneeded package obligations | Unneeded service obligations |
| Supply-chain risk | High: no new dependency | Lower than a custom service but non-zero if packaged | High relative to current design surface |
| Operational cost | Medium: recurring session polling | Medium/High: same polling plus new integration | High: endpoint, renewal, and durable delivery infrastructure |
| Pagination/cursor support | Sufficient, but application must persist cursor/dedup state | Potentially broader, but not needed for current adapter | Potentially lower latency, but unavailable and unverified here |

## Recommended Resources

- **Existing Teams MCP runtime tools** — use `ListTeams` then `ListChannels` for discovery, the
  canonical ID fields for storage and writes, `GetChannel` for confirmation/revalidation, and the
  existing message/reply operations for root binding and polling. This is an architecture-facing
  reuse recommendation grounded in the loaded runtime schemas and Microsoft Graph capability
  references ([list channels](https://learn.microsoft.com/graph/api/channel-list?view=graph-rest-1.0);
  [channel messages](https://learn.microsoft.com/graph/api/channel-list-messages?view=graph-rest-1.0)).
- **Session `sql`** — extend the existing listener persistence into one destination/timer state
  model with unique session ownership, generation-based retargeting, cursors, and consumed-message
  records. This reuses the current skill's durable state and compensation behavior.
- **Existing `manage_schedule`** — retain one fixed recurring schedule per session, persist its
  handle, reconcile by handle, and stop it on terminal cleanup. The scheduler is session-scoped and
  must be described as best-effort polling, not durable delivery
  ([GitHub scheduling](https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/schedule-prompts)).
- **Opaque session slug** — use a non-reversible, session-local slug mapped to canonical IDs in
  SQLite. Show display names, membership type, and a short ID fragment for confirmation, but never
  use those display values as routing or authorization keys.

## Rejected / Unverified Resources

- **Direct Graph SDK dependency** — **rejected for this stage**: the existing runtime adapter already
  exposes the needed read/write operations; adding an SDK would expand permissions and maintenance
  without a demonstrated requirement.
- **Graph change-notification webhook** — **unverified/rejected for this feature surface**: official
  documentation confirms the platform capability, but the authorized runtime exposes no subscription
  creation, callback endpoint, renewal, or resource-data validation. It cannot be selected as the
  implementation resource based on current evidence
  ([change notifications](https://learn.microsoft.com/graph/teams-changenotifications-chatmessage)).
- **Display-name or human-readable `team/channel` slug** — **rejected**: names are mutable and
  non-unique; this would violate the existing ID-authoritative safety model.
- **External durable queue or scheduler service** — **unverified/rejected**: no authorized,
  allowlisted, repository-integrated candidate was identified or needed.

## Critique & Amendments (Step 1.6 — append-only)

The critique-and-amend pass is **architecturally material: yes**. Destination identity,
membership/privacy handling, operator authorization, and the lifetime/reliability of the unified
timer affect the design materially. It was **not executed** because this invocation is explicitly
limited to discovery mode and must stop after writing this artifact.

## Revised Recommendations (Step 1.6 — append-only)

- No revised recommendations were produced because the critique pass was not authorized in this
  discovery-only stage. The discovery recommendations above remain conditional on the later design
  and architecture review resolving postability, retarget cutover, cursor semantics, and operator
  authorization.

## Unresolved Risks

- `ListTeams` and `ListChannels` expose no adapter pagination metadata; large result sets may need a
  bounded selection/search behavior that is not yet defined.
- Discovery does not prove write permission. A channel can become stale, inaccessible, archived, or
  otherwise unwritable between selection and a later tick.
- The runtime exposes sender ID but not an independently resolved operator UPN or tenant identity;
  the authorization source and how it is bound to the session remain design decisions.
- Retargeting requires an atomic destination-generation cutover so an old scheduled prompt cannot
  post to or consume from the old root.
- A single cursor is insufficient if pages are bounded and messages arrive while a tick is running;
  the design must define overlap windows and idempotent message consumption.
- Scheduled prompts are restored with the session, but official documentation does not promise
  durable delivery while the session is closed or blocked in every runtime state.
- Private/shared channel exposure and shared-channel host-team behavior need explicit UX and safety
  policy; do not silently broaden discovery to channels outside the direct membership result.

## Inputs for Architecture-Reviewer

- Prefer the existing Teams MCP and session SQL surfaces; do not introduce a Graph SDK or webhook
  service unless a later option demonstrates a concrete capability gap.
- Treat team/channel IDs as canonical, display names as diagnostics, and the slug as a
  non-reversible session-local mapping.
- Require one session-owned timer with persisted schedule handle, generation-aware target state,
  idempotent reconciliation, and explicit cleanup/stop-failure states.
- Require durable message observation/consumption state; a timestamp-only cutoff is insufficient
  for continuous listening.
- Preserve sender-ID authorization, safe-content rules, stop-before-act, bounded pagination, and
  fail-closed behavior on missing identity, stale target, ambiguous root, or unproven write.
- Bound claims about operator-message delivery: the available scheduler is recurring
  session-scoped polling, not a durable webhook or guaranteed external queue.
- Resolve whether the first post is the write-time postability check, whether private/shared
  channels are allowed, and what trusted session mechanism authorizes retargeting.

---

## Critique & Amendments — Step 2 critique-and-amend pass (2026-10-01)

**Provenance:** This appendix supplements, but does not replace, the discovery report above.
In particular, its earlier "not executed" placeholder records the status *at discovery time*;
this section is the subsequent authorized critique. Risk rankings below are design constraints,
not approved behavior. Internal evidence: `original-request.md`, `investigation.md`,
`ux-review.md`, and `enable-progress-in-teams/SKILL.md`. External claims were checked against
the cited official documentation and the Teams MCP tool schemas loaded for this pass. The
[trusted-source policy](C:/Users/jrastrom/.copilot/skills/dev-dude/references/trusted-source-policy.md)
requires an allowlisted citation for every external claim/recommendation.

### Material risks, ranked

| Rank | Risk / discovery correction | Design constraint or uncertainty |
|------|-----------------------------|----------------------------------|
| **Critical — destination data exposure / confused deputy** | Replacing one hard-coded destination with any discovered channel permits progress, blocker details, and acknowledgements to reach a broader or different audience. A returned channel is not evidence that its audience is appropriate or that a write will succeed: the Graph channel-list API can be called with admin permissions and explicitly notes that admins can access teams they do not belong to ([channel-list permissions](https://learn.microsoft.com/en-us/graph/api/channel-list?view=graph-rest-1.0)). The adapter's `ListTeams` description says "signed-in user is a member", but its identity, permission scope, and audience are not independently verified here. | Treat discovery as *candidate display*, never consent to publish. Require a trusted local/session-origin selection and explicit target disclosure/confirmation before any new-destination write; do not let a Teams reply or stale scheduled prompt change routing or authorization. Keep safe-content minimization and local-only failure on inaccessible/uncertain targets. Private/shared-channel type deserves disclosure, not an assumption of confidentiality. |
| **Critical — retarget cutover is not atomically achievable by one SQL write** | The discovery recommendation that a generation can invalidate stale prompts "atomically" overstates what session SQL can guarantee. Database state can be committed together, but Teams posts, schedule create/stop, and already-running ticks are separate side effects. A tick or progress post may have read the old route before the commit; scheduler stop may fail. | Define a single authoritative session route revision covering slug mapping, canonical IDs, root binding, timer ownership, cursor epoch, and acknowledgement destination. Serialize/guard writers; recheck revision **immediately before each external write and before accepting a reply**, and suppress stale work. Stage/verify a new root before publishing the new route, or explicitly define a no-routing transition; keep old-route cleanup/compensation and uncertain-write states visible. No claim of strict atomicity or zero race window without an enforceable in-flight exclusion mechanism. |
| **High — slug alias / stale mapping** | An "opaque slug" is useful only as a reference, not an authorization token or Teams destination. A slug reused after retarget, a cached mapping, a missing row, or a name-derived slug could route to an old or unintended channel. | Scope an unpredictable/non-reused reference to the authoritative session and revision; resolve to persisted `team_id`/`channel_id` and bound root on every operation. Reject missing, stale, conflicting, inaccessible, or ambiguously mapped targets; never reconstruct IDs from the slug or choose a fallback by name. Persist/disclose mapping lifecycle and define behavior for rename, removal, or loss of access. Exact slug format remains a design decision. |
| **High — duplicate timers and side effects** | A UNIQUE `session_id` row establishes one *database owner*, not one live external schedule. Concurrent create-before-persist calls can create two schedules; persistence compensation or stop can fail; retried/overlapping ticks can double-post, double-consume, or double-acknowledge. The runtime `manage_schedule` interface supports create/list/stop by schedule ID but exposes no atomic create-if-absent or tick exclusivity contract (runtime tool schema; [CLI scheduling](https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/schedule-prompts)). | Require serialized schedule creation/ownership with recoverable in-progress and `stop_failed` states, a persisted handle, reconciliation by handle, and safe behavior for unknown/orphan handles; do not equate row uniqueness with a proven single live schedule. Each tick checks session, handle, enabled state, and route revision; use exclusive or transactional claims for message consumption and acknowledgement, with reconciliation after ambiguous Teams responses. "Exactly once" cannot be promised from these APIs alone. An accepted reply must not terminate the unified timer if listening is to remain continuous; transfer only the safety intent of the old stop-before-act rule. |
| **High — reply traversal, replay, and loss across cutover** | `ListChannelMessageReplies` exposes pages of up to 50 and a `nextLink` but no delta cursor, server filter, or documented stable ordering in its schema ([Graph replies](https://learn.microsoft.com/en-us/graph/api/chatmessage-list-replies?view=graph-rest-1.0)). Timestamp-only or single `last_observed_message_id` cursors cannot safely advance past an incomplete five-page scan, equal timestamps, or late-arriving pages. Blindly persisting a `nextLink` across ticks has no proven snapshot/expiry semantics. | Bind cutoff, paging progress and a durable `(session, route revision, team, channel, root, reply ID)` consumption record. Do not advance a high-water mark beyond unread pages; use bounded overlap and dedup, process deterministic `(createdDateTime, id)` order only after the relevant bounded set is established, and surface backlog/exhaustion rather than silently dropping messages. On retarget, retire the old cursor/acceptance epoch; never accept old-root replies into the new route, including those created before cutover but first seen afterward. Distinguish observed, claimed, delivered, and acknowledged states; specify retry for crashes and ambiguous acknowledgement writes. |
| **High — continuous polling cost and no delivery guarantee** | The existing skill contradicts itself: Phase 3 requests 10-minute scheduling while invariant/examples say two minutes; its 24 checks/four-hour and ~10-minute figures describe a *10-minute, four-hour* listener only. At fixed intervals, two minutes means 30 ticks/hour, 120 per four hours, 720 per 24 hours; ten minutes means 6, 24, 144 respectively, *per enabled session*, before retries or extra pages. Five pages at 50 replies can read up to 250 replies per tick, i.e. 36,000 reply records/day at ten minutes or 180,000/day at two minutes if every tick fills all pages; these are illustrative upper-bound reads, not measured traffic, spend, or delivery SLAs ([Graph replies](https://learn.microsoft.com/en-us/graph/api/chatmessage-list-replies?view=graph-rest-1.0)). Graph cautions that continuous polling increases throttling risk and documents 429/`Retry-After` behavior ([throttling](https://learn.microsoft.com/en-us/graph/throttling)). | Choose cadence and lifetime explicitly in design, cap requests/pages/backlog and concurrency, respect exposed retry/backoff signals, and disclose the idle-session overhead. Nominal detection waits up to one interval *only if ticks run on time, pages are reachable, and the session stays running*; processing, throttle, backlog, blocking, and suspension can make it longer or unbounded. No verified dollar-cost estimate or guaranteed 10-minute response. |
| **High — scheduled prompts cannot guarantee interrupting active work** | GitHub documents `/every` as **experimental**, available only with experimental CLI enabled, and scoped to a running interactive session; fixed schedules are restored when reopening, with their wait measured from reopening ([scheduling prompts](https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/schedule-prompts)). That page says prompts are *submitted*, not that they preempt a currently executing agent turn or a blocking command, serialize with other work, or provide durable message delivery. The runtime `manage_schedule` tool exists here, but that does not prove universal availability or delivery semantics for this feature. | Downgrade the discovery phrase "submit work to the active Copilot session" to best-effort invocation during supported interactive operation. State listening while actively working/blocked as an unverified requirement, not a demonstrated runtime guarantee; define honest status and local recovery if a tick is delayed, queued, missed, or unable to surface instructions to the active workflow. Do not imply a background service or webhook. |
| **Medium — root-order and root-age assumptions** | The Teams `ListChannelMessages` adapter describes "most recent first", but the underlying Graph endpoint **sorts root messages by last modification of the whole reply chain**, not by root creation time ([channel messages response](https://learn.microsoft.com/en-us/graph/api/channel-list-messages?view=graph-rest-1.0)). The discovery wording "ordered most-recent-first" must not be read as creation order. Its claim that `ListTeams`/`ListChannels` return the "complete adapter result" is also too strong: Graph channel-list results explicitly include `@odata.nextLink` when paginated, while this adapter's `ListChannels` schema exposes no continuation parameter ([channel-list response](https://learn.microsoft.com/en-us/graph/api/channel-list?view=graph-rest-1.0); Teams MCP `ListChannels` schema). | Do not terminate a bounded root scan by assuming creation-time order; a root older than seven days can still have recent replies. Where lookup completeness cannot be proven, refuse duplicate root creation rather than treating an adapter page as all channels or roots. Text-only UX can page *locally within returned items*, not promise exhaustive Teams discovery; disclose adapter limitations. |
| **Medium — independent operator authorization** | Discovery preserves sender-ID filtering but never proves where an authorized operator ID comes from after selection. Channel or team membership and display name are not a delegation of control over the active session; the current skill's fixed ID is a distinct control (`SKILL.md`, invariant 5). | Retain an explicitly trusted, independently bound sender-ID policy, validate ID presence and exact prefix/root/revision/time, and keep normal approval gates. Never silently derive operator identity from selected team/channel, recipient membership, or message text. Whether the fixed ID is retained or a separately authorized session allowlist is required remains open. |

### Citation audit and resource correction

- **Verified:** The discovery links to official `learn.microsoft.com` pages for joined teams,
  channel-list visibility, channel message/reply pagination, chatMessage fields, and Graph change
  notifications; `docs.github.com` supports the session-scoped, experimental schedule claim.
  The relevant MCP tool descriptions/schemas were loaded again in this pass. These are allowlisted
  vendor references, not evidence of an end-to-end delivery guarantee.
- **Corrected:** Graph channel-list *does* paginate, while the Teams adapter exposes no channel
  `nextLink` parameter. Therefore "sufficient for a paged selection surface" means only
  client-side paging of whatever the adapter returns; completeness is **unverified**, not
  established ([Graph channel-list](https://learn.microsoft.com/en-us/graph/api/channel-list?view=graph-rest-1.0);
  Teams MCP `ListChannels` schema). The Graph root sort is reply-chain modification time, not
  root creation time ([Graph channel messages](https://learn.microsoft.com/en-us/graph/api/channel-list-messages?view=graph-rest-1.0)).
- **Downgraded:** Discovery matrix ratings "High" for security/maintenance and "Sufficient"
  pagination, its "one timer row ... supports idempotent create" assertion, and its suggestion
  that a generation atomically invalidates old work are *conditional design judgments*, not
  verified guarantees. The existing session SQL is suitable for coordination, but cannot make
  external writes transactional. The absence of package-advisory results means **no new package
  exposure was introduced**, not that the pre-existing Teams MCP or CLI supply chain was audited.
  Adapter provenance, service contractual stability, effective permissions, and retry semantics
  have not been established here.
- **Clarified:** Microsoft documents a maximum Graph reply page size of 50; the runtime adapter
  `maxReplies` also accepts 1–50. Neither source establishes a durable pagination snapshot,
  exactly-once acknowledgement, a per-session message queue, or scheduler preemption
  ([Graph replies](https://learn.microsoft.com/en-us/graph/api/chatmessage-list-replies?view=graph-rest-1.0);
  [Graph paging](https://learn.microsoft.com/en-us/graph/paging);
  [CLI scheduling](https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/schedule-prompts)).
- **Advisories, license, maintenance, supply chain:** No external library/package is proposed, so
  no new dependency license or version-specific GHSA/OSV advisory applies; this is **not** a
  clean-bill-of-health assessment for the runtime adapter or its transitive implementation.
  No independent release cadence, provenance, installed version, or advisory inventory for
  Teams MCP was supplied. A direct Graph SDK would add an auth and dependency surface without
  solving scheduler preemption, routing cutover, or exactly-once delivery; a webhook would add a
  callback/renewal/permissions surface not exposed here. Their relative operating costs remain
  qualitative, not measured.

### Revised Recommendations — resource inputs, not a selected design

1. **No new external dependency is justified by the verified requirements.** Retain the
   runtime-provided Teams MCP read/write tools, session SQL, and existing schedule interface as
   *conditional* design inputs, not as evidence that continuous delivery or exhaustive discovery
   already works. Vendor references: [Graph channel list](https://learn.microsoft.com/en-us/graph/api/channel-list?view=graph-rest-1.0),
   [Graph replies](https://learn.microsoft.com/en-us/graph/api/chatmessage-list-replies?view=graph-rest-1.0),
   [CLI scheduling](https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/schedule-prompts).
2. Preserve session-bound opaque slug-to-canonical-ID mapping and a *separate* sender-ID
   authorization boundary; treat target selection as an explicit, trusted publication decision.
   Revise the discovery "High security" rating to **conditional on audience confirmation and
   fail-closed route validation**.
3. Treat route, root, cursor, schedule ownership, and acknowledgement state as one
   revision-scoped logical contract, with explicit transitions and stale-work guards; do not
   promise a cross-system atomic transaction, one physical schedule solely from a UNIQUE row, or
   exactly-once Teams delivery.
4. Keep polling bounded and best-effort, with an explicit cadence/cost/error budget and honest
   degraded status. Graph recommends avoiding continuous collection scans because of throttling
   ([Graph throttling](https://learn.microsoft.com/en-us/graph/throttling)); its change-notification
   alternative remains **unverified/unavailable** in the authorized runtime
   ([Teams change notifications](https://learn.microsoft.com/en-us/graph/teams-changenotifications-chatmessage)).

**Unresolved for the Architecture-Reviewer / user design gate:** What trusted action can
authorize retargeting and which audiences (including private/shared channels) are eligible?
What is the slug format/lifetime and who can inspect or change its mapping? How are in-flight
posts, schedule-creation races, ambiguous send/acknowledgement results, and cutover messages
handled? What cursor policy has a proven bound on missed replies under high volume or unstable
pagination? Does this CLI/runtime actually execute scheduled prompts concurrently with work or
while waiting at a blocking command? Which explicit sender ID(s) are authorized, what cadence and
session lifetime are acceptable, and what degraded-mode latency/cost disclosure is required?
None of these questions is answered or approved by this appendix.
