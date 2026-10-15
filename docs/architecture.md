# Architecture

Feature-first layers: presentation widgets/Cubits → domain contracts → Odoo repositories → isolated XML-RPC adapter and SQLite cache. `get_it` composes dependencies at startup. `go_router` guards authenticated routes and internal-user Sales navigation; server ACLs remain authoritative. Domain models normalize Odoo false/relational fields before UI access. Simple immutable classes avoid unnecessary code generation.

`AuthCubit` controls secure session restoration, login and logout. Only the OS secure store contains reusable RPC credentials. On online restoration the app authenticates again and rechecks `res.users.has_group([[uid], 'base.group_user'])`, as required by Odoo 20's record method. On a network timeout/unreachable server it may restore the last securely saved session for offline customer reads. Revocation cannot be detected while offline; no API write succeeds without server authorization.

`PagedCubit` handles immutable result states, 350 ms search debounce, pagination, stale response suppression and cancellation of debounce timers. Widgets own only transient form/dialog state and call repositories for domain operations. Confirm logic rereads eligibility, calls action_confirm and verifies resulting state. No automatic mutation retries.

Customer cache uses sqflite transactions, scoped by server/database/UID. Only already-fetched customers are available offline. Cached search uses literal substring matching, while online search uses Odoo ilike. A successful network request refreshes cached records; a permissions failure never falls back to cached records. Normal logout removes the secure session and synchronized cache while retaining unsynced customer/outbox records for the original scope. Confirmed permanent removal clears both cache and outbox. SQLite uses the app's private OS sandbox and is not independently encrypted. Android backup is disabled.

Offline phone writes use the version-2 SQLite outbox and `PhoneSync`. The cache update and outbox replacement are transactional; reads overlay unsynced values over server refreshes. One foreground worker uses atomic claims/leases, read-before-write, baseline checks, remote write/readback, bounded exponential retries and explicit conflicts. Connectivity events, periodic foreground checks and resume wake the worker. Scope and lease-token checks prevent cross-account processing and stale acknowledgements. See [complete offline design](offline.md) for crash recovery, account removal and concurrency limits.

The opt-in real integration tool ran the Dart repository/worker with real SQLite and the Online instance; its sanitized report is `offline_live_verification.json`. Normal tests use deterministic transport doubles and real temporary SQLite.

Known scope: Android is the validated delivery platform. Web cross-origin RPC and web SQLite are unsupported. iOS/macOS platform entitlements and deployment signing have not been validated.
