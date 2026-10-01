# Approved Design

Approval evidence: User input on 2026-10-01: "If you were planning, stop planning and start implementing."

The approved design is the normative shared core in `design-options.md` with these policy selections:

- **Selection profile:** A+B — explicit team/channel selection with an optional remembered session alias.
- **Authorization:** retain the current fixed authorized sender ID; authorization remains separate from destination state.
- **Timer cadence:** every 5 minutes.
- **Timer lifetime:** enabled until explicit disable or terminal cleanup, with restored schedule reconciliation.
- **Messages observed during active work:** queue and surface at the next safe local approval point.
- **Backlog degradation threshold:** 3 consecutive pagination-bound-exhausted ticks.
- **Eligible channels:** standard, private, and shared channels, with membership type disclosure and explicit confirmation.
- **Selection display bound:** at most 50 returned teams or channels per selection surface; never claim tenant-wide completeness.
- **Completion format:** at most 7 bullets.
- **Root preview:** use a sanitized literal preview before confirmation.
- **History on retarget:** do not migrate history; post a guarded handoff in the old root and create a generation-specific root for the new destination.

All canonical routing uses exact `team_id` and `channel_id`. The slug is an opaque session alias only. Route generations are globally monotonic for the session, and one recurring schedule owns both route reconciliation and operator-message polling.
