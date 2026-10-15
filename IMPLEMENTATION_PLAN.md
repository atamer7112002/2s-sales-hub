# 2S Sales Hub — Implementation Plan & Engineering Specification

> **Project:** 2S Homewear — Flutter Sales Companion  
> **Backend:** Verified Odoo Online demo — https://2s-sales-demo.odoo.com, database `2s-sales-demo`, version `20.0+e`, XML-RPC (not the company's production ERP)  
> **Timebox:** 2 days / approximately 16 focused engineering hours  
> **Status:** Implementation specification — verify API behavior against the chosen Odoo version.

## 1. Objective
Build a working, demonstrable Flutter mobile application for a sales team that integrates with an Odoo demo database. Deliver all mandatory features first, then offline capabilities and production-quality polish. Do not represent a demo build as production-deployed or claim compatibility with the company's ERP without testing it.

## 2. Scope and priority

### P0 — Mandatory acceptance criteria

#### Authentication
- [ ] Sign in with an Odoo username and password against the configured demo database.
- [ ] Prefer a supported REST interface **if it actually supports the required username/password flow**; otherwise use a supported XML-RPC/RPC interface. Do not assume JSON-2 API keys are equivalent to password login.
- [ ] Navigate to Customer List after successful authentication.
- [ ] Display actionable error messages on invalid credentials, permission errors, network failures, and server failures.
- [ ] Provide logout and clear local authentication material on logout.

#### Customers
- [ ] Read `res.partner` records with domain `[['customer_rank', '>', 0]]`.
- [ ] Display customer **name, phone, city**.
- [ ] Search customers by name (prefer server-side `ilike`, debounced input).
- [ ] Show details: **name, phone, email, address**.
- [ ] Edit **phone only**, validate input sensibly, and persist via Odoo `write` or the supported API equivalent.
- [ ] Show success only after the remote write is acknowledged; clearly distinguish queued offline edits.

#### Sales Orders — internal users
- [ ] Determine whether the signed-in user belongs to `base.group_user` using a supported, authorized group check.
- [ ] Show Sales Orders navigation only for internal users; do not treat client-side visibility as authorization.
- [ ] Read `sale.order`: **order number, customer, order date, status**.
- [ ] Open order details showing **products, quantities/prices where available, totals, and status**.
- [ ] Confirm eligible draft/quotation orders using Odoo's `action_confirm` business method or supported equivalent, **not** a direct state write.
- [ ] Respect Odoo ACLs and record rules; display permission errors without exposing data.
- [ ] Refresh the order from Odoo after confirmation; handle concurrent state changes.

### P1 — Bonus
- [x] Cache successfully fetched customers for offline reading.
- [x] Queue offline phone edits durably; sync when connectivity **and server reachability** return.
- [x] Surface `Pending`, `Synced`, and `Failed` states.
- [x] Avoid duplicate/reordered writes; document conflict behavior and retry limits.

### P2 — Polish (only after P0 works)
- [ ] Pull-to-refresh, pagination, skeleton/loading/empty/error states.
- [ ] Status filters on Sales Orders, tap-to-call, copy phone.
- [ ] Responsive Material 3 design with a restrained 2S-inspired visual identity.
- [ ] Additional tests, screenshots, and short demo video.

## 3. Non-goals
- No integration with the company's live production ERP without authorization.
- No payment, inventory, invoice, or customer creation flows.
- No hard-coded real customer records or secrets in Git.
- No promise of guaranteed background sync when the OS suspends or terminates the app.
- No full conflict-resolution engine or universal Odoo-version compatibility in two days.

## 4. Verified integration — first implementation gate
The existing official Online database is already provisioned and activated. Do not recreate it or set up Docker.

- HTTPS origin: `https://2s-sales-demo.odoo.com`.
- Database: `2s-sales-demo`, obtained from POST `/web/database/list`, not assumed from hostname.
- Version: `20.0+e`, obtained from XML-RPC POST `version()`.
- Password authentication and customer domain reads passed; see `docs/online_connectivity_result.json`.
- Internal membership, synthetic customer phone write/readback, Sales list/lines and business-method confirmation passed; see `docs/sales_verification.json`.
- Credentials are entered locally and are never hardcoded or committed.
- For Odoo 20, `res.users.has_group` is a record method: `[[uid], 'base.group_user']`.
- Use the existing Online instance for the final application. No mock or local Docker backend.
- A second restricted account still needs manual acceptance testing; server ACLs remain authoritative.

### Odoo concepts and mapping
| Requirement | Model / method | Notes |
|---|---|---|
| Login | `common.authenticate` on legacy XML-RPC, or verified supported alternative | Legacy XML-RPC uses database, username, password and returns `uid`; `uid` alone is not a token. |
| Customer list/search | `res.partner.search_read` | Domain `customer_rank > 0`; `name ilike` for search; fields, limit, offset. |
| Customer details | `res.partner.read` | Address may use `street`, `street2`, `city`, `state_id`, `zip`, `country_id`; handle absent fields. |
| Phone update | `res.partner.write` | Send record IDs and `{'phone': value}`; re-read after success. |
| Internal user check | Authorized group membership check, e.g. supported `has_group` | Verify method signature for chosen version; never infer from a role label alone. |
| Sales list | `sale.order.search_read` | Fields such as `name`, `partner_id`, `date_order`, `state`, `amount_total`, `currency_id`. |
| Sales line items | `sale.order.line` reads | Fetch lines for selected order, including product, quantity, unit price, subtotal. |
| Confirm quotation | `sale.order.action_confirm` | Validate eligible state; server is authority; refresh after success. |

**Compatibility:** Odoo 19's JSON-2 interface uses API-key authentication, so it does not by itself implement the assignment's username/password login. XML-RPC is verified on this Odoo 20.0+e Online demo. It remains a legacy transport; revalidate availability before any server upgrade. Do not invent REST endpoints.

**Parsing:** Odoo may serialize unset fields as `false`; many2one values may be `[id, display_name]`. Normalize these in the data layer; never expose raw Odoo payloads to widgets. Confirm field names and permissions through the selected instance.

## 5. Architecture
Use pragmatic **feature-first Clean Architecture**. Avoid boilerplate-only use cases; include them where business rules benefit from isolation.

```text
lib/
  app/
    app.dart
    router/
    theme/
    di/
  core/
    network/        # OdooApi interface, concrete RPC adapter, error mapping
    database/       # local customer cache + durable pending operations
    security/       # credential/session handling
    sync/           # foreground sync coordinator
    errors/
    ui/             # shared widgets
  features/
    auth/{data,domain,presentation}/
    customers/{data,domain,presentation}/
    sales_orders/{data,domain,presentation}/
  main.dart

test/
  core/
  features/
```

**Dependency direction:** UI → Cubit/BLoC → domain repository contract → data repository → Odoo adapter / local store. Keep API request details out of widgets. Use dependency injection to swap real and fake repositories in tests.

### Recommended stack
- Flutter / Dart; `flutter_bloc` for state management.
- `get_it` for dependency injection; `go_router` for navigation and guards.
- `dio` for HTTP transport, with XML-RPC serialization/parsing when required (Dio alone is not an XML-RPC implementation).
- `drift` + SQLite for persistent offline storage, or another well-tested SQLite layer if setup cost is excessive.
- `flutter_secure_storage` for sensitive authentication material; never commit passwords or API keys.
- `freezed` / `json_serializable` only if code generation setup is stable; simple immutable Dart models are acceptable.
- `flutter_test` and `mocktail` for tests.

### Key interfaces (conceptual)
```dart
abstract interface class AuthRepository {
  Future<AuthenticatedUser> signIn(String username, String password);
  Future<void> signOut();
}

abstract interface class CustomerRepository {
  Future<CustomerPage> getCustomers({String? query, int offset = 0, int limit = 20});
  Future<Customer> getCustomer(int id);
  Future<PhoneUpdateResult> updatePhone(int id, String phone);
}

abstract interface class SalesOrderRepository {
  Future<List<SalesOrder>> getOrders({int offset = 0, int limit = 20});
  Future<SalesOrderDetails> getOrder(int id);
  Future<SalesOrderDetails> confirmOrder(int id);
}
```

## 6. Screen specification
1. **Splash/session check:** restore a valid authorized session or navigate to Login; no indefinite spinner.
2. **Login:** username, password, show/hide, validation, loading, errors; no secret in logs.
3. **Customers:** searchable list with name/phone/city, pagination, refresh, offline banner and states.
4. **Customer details:** name/phone/email/address; edit phone; show queued vs synced outcome.
5. **Sales Orders:** visible to internal users only, number/customer/date/status, filters if time permits.
6. **Order details:** line items, totals, status, eligible confirm button and confirmation dialog.
7. **Profile/logout:** basic account identity and explicit sign-out.

## 7. Offline behavior
- **Reads:** show cached customers immediately; refresh from server when possible; label stale/offline data.
- **Writes:** store the new phone and an operation in a single local transaction. Mark pending; do not claim server success.
- **Sync:** attempt on app resume, manual retry, and regained connectivity; connectivity is only a hint, so handle failed requests.
- **Queue:** operation ID, user/database scope, entity ID, intended phone, creation time, attempts, status, and last error.
- **Ordering:** serialize changes to the same customer; coalesce unsent phone edits when safe.
- **Retries:** bounded exponential backoff for transient errors; do not retry authentication/permission/validation failures indefinitely.
- **Conflicts:** if the remote record changed after the cached version, show a conflict/review state or document a carefully scoped last-write-wins demo policy. Never silently claim conflict-safe sync.
- **Security:** isolate cache and pending operations per account/database; clear credentials and synchronized cache on logout; retain unsynced edits only for the original account, with explicit confirmed permanent removal; avoid logging PII.
- **Limitations:** guaranteed background delivery and cross-device conflict resolution are out of scope for this timebox.

## 8. Security & reliability
- Require HTTPS for remote connections; never disable TLS certificate verification in release builds.
- Do not embed demo credentials in the APK, README, screenshots, or repository. Provide setup instructions separately.
- If legacy RPC requires reusable credentials, store them securely and explain that the demo's mobile-direct approach is **not** a complete production security architecture. A production backend gateway may be needed for credential/session management.
- Treat server ACLs/record rules as authoritative; group-based UI hiding is only UX.
- Avoid printing passwords, authentication headers, raw customer data, or tokens.
- Use typed error mapping and user-friendly retry behavior.
- Handle timeouts, empty results, malformed/optional fields, session invalidation, and duplicate confirmation attempts.
- Make request cancellation/debouncing safe during search and navigation.

## 9. Two-day execution plan

### Day 1 — Integration and customer journey (P0)
| Slot | Task | Exit criteria |
|---|---|---|
| 1 | Provision demo Odoo; seed synthetic data | API works and test users exist |
| 2 | Verify auth, partner reads/writes, sales methods via test client | Sanitized request/response samples saved |
| 3 | Flutter scaffold, DI, router, theme, error types | App launches cleanly |
| 4 | Auth repository + Login UI | Real demo login works; bad login fails clearly |
| 5 | Customer models + repository + list | Filter `customer_rank > 0` verified |
| 6 | Debounced search, paging, loading/empty/error states | Search and list stable |
| 7 | Customer details + phone edit | Write persists and re-read matches |
| 8 | Fix integration edge cases; smoke tests | P0 customer journey demonstrable |

### Day 2 — Orders, bonus, delivery
| Slot | Task | Exit criteria |
|---|---|---|
| 1 | Internal-user group check and order repository | Authorized order access verified |
| 2 | Sales Orders list | Number, customer, date, status correct |
| 3 | Order details and lines | Products and totals render correctly |
| 4 | Confirm order + error/concurrency handling | Draft → confirmed via Odoo method |
| 5 | SQLite customer cache | Previously fetched customers available offline |
| 6 | Persistent offline phone edit queue + foreground sync | Offline edit syncs after reconnect |
| 7 | Tests, accessibility/error-state review, manual QA | Critical tests and smoke flows pass |
| 8 | Release build, README, screenshots, short video | Reproducible demo package ready |

**Timebox rule:** P0 correctness > P1 offline > P2 polish. If the backend setup takes longer, cut optional filters/animations before core requirements. Do not mark unfinished items complete.

## 10. Test matrix
| Area | Minimum tests |
|---|---|
| Auth | Valid/invalid login; offline/server error; logout clears sensitive state |
| Customers | Domain filtering; pagination/search; `false`/missing field parsing; successful/failed phone write |
| Permissions | Internal user sees orders; restricted user does not; server denial handled |
| Orders | Order list/details parsing; eligible confirmation; already-confirmed and permission-failure cases |
| Offline | Cached list without network; queue survives restart; successful retry clears pending; failed retry remains visible |
| UI | Loading, empty, error, retry, keyboard, small-screen layout |

**Manual smoke script:** Login → search customer → view/edit phone → verify Odoo change → view orders as internal user → inspect products/totals → confirm draft order → verify new state → disable network → view cached customers → edit phone offline → reconnect → verify sync.

## 11. Delivery checklist
- [ ] Git repository with clear commits and no secrets.
- [ ] `README.md`: setup, supported Odoo version, demo provisioning, configuration, run/build/test commands, screenshots, architecture, limitations.
- [ ] `docs/odoo_integration.md`: tested endpoint/method mapping and sanitized payload examples.
- [ ] `docs/architecture.md`: dependency flow and offline design.
- [ ] Release APK tested on a device/emulator.
- [ ] Short screen recording showing real demo backend integration.
- [ ] Test output (`flutter analyze`, `flutter test`) and known failures documented.
- [ ] Explicit note that the demo is not connected to 2S production ERP.
- [ ] If the demo expires, document how reviewers can recreate the database and sample data.

## 12. Definition of Done
**Core complete:** a reviewer can configure a working demo instance, sign in, list/search eligible customers, view/edit a customer phone, see orders only with internal-user access, view order lines/totals, and confirm an eligible quotation; errors are handled safely.

**Bonus complete:** previously loaded customers remain visible offline and offline phone edits persist and synchronize with truthful status reporting.

**Production-style, not production-certified:** clean boundaries, security hygiene, critical tests, reproducible setup, documented assumptions and limitations. A real production deployment would require security review, operational monitoring, lifecycle management, and compatibility testing against the target ERP.

## 13. Risks and mitigations
| Risk | Mitigation |
|---|---|
| Hosted free demo blocks external API | Validate immediately; fall back to self-hosted Community demo |
| Demo expires before review | Document recreation and seed data; use stable environment if feasible |
| Odoo version/API mismatch | Adapter interface; verify calls before Flutter implementation |
| Missing Sales/permission configuration | Install Sales, seed orders, verify internal/restricted test users |
| Login credentials exposure | Secure storage, HTTPS, sanitized logs; production gateway recommendation |
| Offline write conflict | Detect when feasible; otherwise disclose policy and limitations |
| Two-day deadline | P0-first gates; defer nonessential UI extras |

## 14. Official references
- Odoo 19 external API / JSON-2: https://www.odoo.com/documentation/19.0/developer/reference/external_api.html
- Odoo 19 external RPC API: https://www.odoo.com/documentation/19.0/developer/reference/external_rpc_api.html
- Odoo 18 external API: https://www.odoo.com/documentation/18.0/developer/reference/external_api.html

---
**Engineering principle:** Demonstrate real, verified functionality and explain trade-offs. Do not trade core correctness for architectural complexity or cosmetic polish.
