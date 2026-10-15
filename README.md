# 2S Sales Hub

Internal Flutter sales companion for 2S Homewear. Uses the **real Odoo Online demo**, never an e-commerce or mock backend.

## Backend and configuration

| Setting | Verified value |
| --- | --- |
| HTTPS origin | https://2s-sales-demo.odoo.com |
| Database | `2s-sales-demo` (server-discovered) |
| Server version | `20.0+e` |
| API | XML-RPC over HTTPS |

Enter your dedicated Odoo database login and **local password** in the app. Defaults above are public configuration, not credentials. Expand Connection settings to change them. Do not use a company's production ERP for this assessment. No Docker setup is needed.

Real checks passed: authentication, customer domain read, internal membership, phone write/readback, Sales list/lines, and synthetic quotation confirmation with server-state readback. Temporary records were removed. Sanitized evidence: [connectivity](docs/online_connectivity_result.json), [Sales verification](docs/sales_verification.json). The original order list was empty; create a synthetic quotation in Odoo Sales before the company's manual confirmation demo.

## Features

- Branded gold/white login; validation, password visibility, secure storage, restoration, logout and guarded routes.
- Customers: `customer_rank > 0`, server pagination (20), debounced name search, refresh, loading/empty/error/retry states.
- Customer profile: phone/email/full address, phone-only editing with remote acknowledgement and fresh readback, copy and dial actions.
- Sales for internal users: pagination, state filters, customer/date/amount/status, product quantities/prices/subtotals and tax-inclusive total.
- Confirmation dialog, refreshed eligibility, `action_confirm`, and successful-state readback. Odoo enforces ACLs/record rules.
- SQLite offline customer reads and durable phone edits, automatic foreground synchronization, conflict feedback and Retry Sync. Queue/cache are isolated by account/database. Prior secure session can restore offline; a first login requires network.

Offline phone edits are saved atomically with a durable SQLite outbox. Pending edits survive restart and synchronize on reconnect, app resume and a 15-second foreground timer. Writes are verified by reading Odoo back; failures remain recoverable through Retry Sync. Normal sign-out retains pending edits for the original account; confirmed local-data removal deletes them. See [offline design and device test](docs/offline.md). There is no guaranteed sync while the app is terminated. The cache/outbox is private app storage, not independently encrypted; Android backup is disabled.

## Company installation and demo

1. Obtain `deliverables/2s-sales-hub-release.apk`. Transfer it to an Android device, open it and allow installation from that transfer app if Android requests it. This is a sideloaded assessment build, not a Play Store release.
2. Confirm internet access and sign in with a dedicated account authorized for this demo. Credentials are not bundled and should be shared through the company's approved secure channel.
3. Search/open a customer, edit a synthetic phone, and verify the value in Odoo.
4. With an Internal User who also has Sales rights, inspect a draft quotation and confirm it. Verify its state in Odoo.
5. Load customers, disable connectivity and refresh to inspect the cached list/profile. Edit a synthetic phone offline and restart to check durability. Reconnect/resume, wait for Synced, then verify Odoo. Normal sign-out clears credentials and retains pending edits for the original account.
6. Test a restricted account separately. Internal membership controls navigation; actual Sales permissions may still deny operations. Restricted-user live testing remains a manual acceptance item.

Demo availability depends on the Online trial lifetime and permissions. API success here does not guarantee future subscription access after trial expiry or plan changes.

## Development

Flutter 3.47.2 / Dart 3.13.2. Dependencies: flutter_bloc, get_it, go_router, Dio, XML, flutter_secure_storage, sqflite/SQLite, connectivity_plus, url_launcher; flutter_test/mocktail for tests. Immutable hand-written models avoid code generation.

```sh
flutter pub get
flutter run
flutter analyze
flutter test
```

Optional public defaults:

```sh
flutter run --dart-define=ODOO_URL=https://2s-sales-demo.odoo.com --dart-define=ODOO_DB=2s-sales-demo
```

Never pass passwords/API keys as dart-defines; they become part of the binary.

## Release build

```sh
python3 tool/prepare_release_signing.py
flutter build apk --release
```

Signing preparation creates a dedicated **assessment release key** outside the project at `~/.local/share/2s-sales-hub/signing/`; ignored `android/key.properties` points to it. It preserves an existing key. Keep a secure backup to sign later updates; a fresh key on another machine will require uninstalling the old APK. The assessment key is not the company's production/Play signing identity. No signing secrets belong in the repository.

Default output: `build/app/outputs/flutter-apk/app-release.apk`. The delivery copy includes a SHA-256 checksum. Android is the delivery target; iOS/macOS signing/entitlements and web CORS/SQLite are not validated.

## Architecture and security

See [architecture](docs/architecture.md), [Online setup](docs/odoo_demo_setup.md), [integration contract](docs/odoo_integration.md), [implementation status](IMPLEMENTATION_STATUS.md), and [primary specification](IMPLEMENTATION_PLAN.md).

Feature-first presentation/domain/data layers keep Odoo behavior in repositories and XML transport in one adapter. Credentials live in the OS secure store; HTTPS is mandatory, no TLS bypass or request-body logging. XML-RPC uses a reusable password rather than a bearer session; a production deployment should evaluate a backend gateway and the supported API lifecycle.

Tests use controlled fixtures solely to verify transport, business rules and UI. The release always targets real Odoo. The real Dart offline workflow passed against a synthetic Online customer, including SQLite reopen and server readback. Full Android radio/lifecycle flow still requires the documented manual acceptance steps; dedicated reviewer live ACL checks passed. This is an assessment build, not production certification.

## Delivery validation

- `flutter analyze`: passed, no issues.
- `flutter test`: passed, 41 tests.
- `flutter build apk --release`: passed, 54.0 MB universal APK.
- Signed release installed and launched on Pixel 9 Pro emulator; empty-field validation and real invalid-credential rejection passed. APK signature verification passed.
- [Login screenshot](docs/screenshots/login.png), [validation](docs/screenshots/login-validation.png), [real authentication error](docs/screenshots/login-error.png).
- Command output and checksum are included in `deliverables/`. Full Android radio/lifecycle acceptance remains manual; dedicated non-admin reviewer API checks passed.

## Offline bonus — v1.1.0
Durable latest-edit-wins phone queue, account isolation, automatic foreground synchronization, five-attempt exponential retry, explicit conflict handling, and manual Retry Sync are implemented. Normal sign-out retains unsynced edits; permanent local removal requires confirmation. [Offline architecture, limits and device checklist](docs/offline.md). Real backend evidence: [offline verification](docs/offline_live_verification.json). The signed APK is rebuilt for this version; consult IMPLEMENTATION_STATUS for final command results.

## Submission UI — v1.2.0
Premium off-white/gold surfaces, explicit Roboto typography, customer/order cards, refined phone dialog and semantic status pills. Mobile visual coverage and previews are documented in [UI review](docs/ui_review.md). Analysis and 43 tests pass; signed Android v1.2.0 is available in deliverables. Preview screenshots use synthetic data and are distinct from real backend verification.

[Reviewer access and demo setup](docs/reviewer_instructions.md) · [Submission progress](docs/submission_progress.md). The new GitHub repository is private and unpushed pending final confirmation; original history is preserved. Reviewer setup and actual Dart/Odoo offline verification passed; the dedicated account and retained 450 EGP draft S00002 are ready. Retrieve its password locally from Keychain as documented.
