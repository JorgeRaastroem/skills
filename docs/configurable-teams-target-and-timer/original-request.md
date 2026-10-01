# Original Feature Request

Update `enable-progress-in-teams` to:

1. Query the Microsoft Teams teams and channels available to the user and present them for selection instead of using a hard-coded destination.
2. Persist the selected destination as a session-scoped slug when progress reporting is enabled.
3. Support changing the target during the session, updating the persisted slug.
4. Create a recurring timer that:
   - idempotently reinforces notification routing; and
   - listens for operator messages continuously, including while the agent is working or waiting at a blocking command.
5. Remove the existing blocked-only listener because the new timer covers both continuous listening and blocked-state scenarios.

The exact interpretation of the destination slug, timer cadence, operator authorization, and message-consumption semantics must be resolved during design and explicitly approved before implementation.
