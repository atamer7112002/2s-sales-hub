# Offline phone editing and foreground synchronization

## User behavior
Customers already fetched from Odoo remain available offline. Phone edits validate locally and immediately update the displayed customer after an atomic SQLite transaction. The profile/list displays **Pending Sync**, **Syncing**, **Synced**, or **Sync Failed**. Synced is shown only after an actual matching Odoo read. An offline banner is unobtrusive and does not block browsing or editing. Network errors never produce a false server-success message.

Sync runs after an edit, on a connectivity-restored event, every 15 seconds while the app is running, and on app resume. Connectivity is only a hint: the worker makes an authorized Odoo request before processing. It does not claim guaranteed delivery while the OS suspends or terminates the app. A first login requires network; a previously securely stored session can restore offline.

## Durable storage and ordering
SQLite schema version 2 migrates existing customers without resetting the database. `phone_outbox` contains scope, customer ID, random operation ID, phone, original remote baseline, creation time, status, attempt count, next attempt time, sanitized last error/kind, claim token/lease and explicit conflict-override flag. **No password or token is stored in this table.**

Scope is the exact HTTPS origin, database name and authenticated UID. Credentials are obtained from the existing secure session. A repository supplies its original scope when saving; the coordinator refuses a mismatched active account. Routes are keyed per account so stale screen state is not reused across accounts.

Enqueue and optimistic customer-cache update occur in one transaction. Multiple unsynchronized edits to a customer replace the operation with a new ID and the latest phone while preserving its original remote baseline. This gives deterministic latest-edit-wins behavior locally. Remote refreshes update the cached record but query-time overlays retain any unsynchronized phone/status.

One app coordinator serializes operations, ordered by creation time and customer ID. SQLite claims are atomic, with a unique claim token and a five-minute lease. Stale acknowledgements cannot complete a newer operation. If an edit supersedes an in-flight write, the completed older write advances the newer operation's baseline before the next attempt. Interrupted claims recover after lease expiry (up to five minutes after a crash); active claims are not stolen by manual retry.

## Verification, retry and conflicts
Each operation reads the current remote phone before writing. A matching value completes safely without repeating a write, covering a crash or timeout after server persistence but before local acknowledgement. Otherwise the worker compares the remote phone with the original baseline. A mismatch becomes **Sync Failed** with a conflict message, without overwriting Odoo automatically.

For an eligible operation the worker invokes `res.partner.write`, requires acknowledgement, then reads the phone back. A different readback is also a conflict. Only a matching remote read permits local completion. Network/timeouts and HTTP 5xx failures retry with exponential delays of 10, 20, 40 and 80 seconds after attempts 1–4; after attempt 5 the operation remains Failed. The delay formula is capped at 300 seconds. Actual attempts occur on the next worker wake at or after the persisted deadline.

When the reachability probe itself fails, no mutation is attempted and no operation retry budget is consumed; the foreground probe may retry every 15 seconds. An authentication/permission/validation failure stops automatic operation retries and keeps the edit. Authentication failures require the original account to sign in again; successful verified login releases authentication-blocked operations. Permission failures can be retried after the administrator corrects access.

**Retry Sync** resets failed transient/permanent operations for another bounded attempt cycle. Conflicts require an explicit dialog acknowledging that the saved local phone will overwrite the current Odoo phone; cancelling preserves the conflict. There is no silent conflict override. A five-minute interrupted lease must expire before an uncertain in-flight operation is retried.

This is not a distributed transaction or universal conflict-resolution engine. Baseline comparison and write/readback do not provide atomic compare-and-swap against concurrent edits from another client. Exactly-once network execution cannot be guaranteed. Reassigning an already-matching phone is avoided on recovery, reducing duplicate server side effects.

## Account and data removal policy
Normal **Sign out** waits for the active worker to finish its bounded request sequence, clears secure credentials, removes synchronized cache records and keeps only unsynchronized customer records/outbox entries. These remain hidden behind authentication and can synchronize only under the original server/database/UID. A failed login or an expired session never deletes pending edits.

**Remove local data and sign out** presents an explicit destructive confirmation. Confirming permanently removes this account's cached customers and all queue entries, including unsynchronized edits, then signs out. Other account/database scopes are untouched. This is the supported permanent-account-removal policy on this device. Uninstalling the app or clearing Android storage also removes pending data; there is no server backup of edits that never synced.

The cache/outbox is in the private app sandbox and is not independently encrypted. Android backup is disabled. Reusable Odoo credentials remain exclusively in OS secure storage and are never in the outbox, logs, APK or source archive.

## Validation and exact manual device check
Automated tests use temporary **real SQLite databases** with deterministic API doubles. They cover queue persistence, migration, offline edits, coalescing, reconnect, retry limits, auth/permission denial, scopes, atomic claims, acknowledgement failure/restart recovery, conflicts, refresh overlay, and in-flight supersession. Existing Login, customer and Sales tests remain in the suite.

`docs/offline_live_verification.json` records a successful real Online check using the same Dart repository, SQLite outbox, coordinator and XML-RPC adapter. It created one synthetic customer, cached it, simulated transport loss, edited offline, closed/reopened SQLite, restored the transport, synchronized, reread Odoo and removed the customer. The controlled offline gate blocks transport; it is not a substitute backend.

To repeat: open `tool/check_offline_odoo.command`, enter credentials in the hidden local Terminal prompt, and inspect the sanitized report. Credentials cross a private one-shot local Unix socket and remain in memory; no credential file/environment variable/command-line argument is used. The launcher runs only this opt-in test; normal `flutter test` never contacts Odoo.

Android radio/lifecycle acceptance still requires a manual signed-in device walkthrough:
1. An administrator creates a **dedicated synthetic customer** in the Online demo. Note its original phone; never use a real customer.
2. Install the v1.1.0 APK over the existing build, log in and open/cache that customer.
3. Disable Wi-Fi and mobile data (airplane mode alone may leave Wi-Fi enabled). Edit the phone. Confirm the local phone changes and Pending Sync appears.
4. Force-stop/reopen the app while still offline. Confirm the edit and status survive.
5. Restore connectivity and keep the app open/resume it. Confirm Syncing then Synced, and independently inspect the phone in Odoo.
6. Repeat with a revoked write permission and verify Sync Failed; restore rights and use Retry Sync.
7. Verify sign-out/sign-in preserves pending edits only for the original account; explicitly test another account/database without accessing the queued edit.
8. Delete the synthetic customer after the queue is Synced. Do not claim this device test passed from the desktop transport simulation alone.
