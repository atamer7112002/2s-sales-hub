# Odoo Online integration

## Verified server
- Origin: https://2s-sales-demo.odoo.com
- Database: `2s-sales-demo`, discovered from actual POST `/web/database/list`.
- Version: `20.0+e`, actual XML-RPC POST `version()`.
- Authentication and customer `customer_rank > 0` reads passed; see `online_connectivity_result.json`.
- Internal membership, Sales retrieval, synthetic phone write/readback, lines and confirmation passed; see `sales_verification.json`. All synthetic records were cleaned up.

External API access is available for the tested account and operations on the current Online demo. Neither a GET response nor a public version response was used to claim authenticated access. No Docker/local substitute is used. A second restricted account has not been live-verified; ACL failures have automated coverage and require manual acceptance.

## Contract
- `/xmlrpc/2/common`: `authenticate(db, username, password, {})` → positive UID, false for rejected credentials.
- `/xmlrpc/2/object`: `execute_kw(db, uid, password, model, method, args, kwargs)`.
- Odoo 20 membership: `res.users.has_group([[uid], 'base.group_user'])`. This is a record method, not the older assumed model-only signature.
- `res.partner.search_read`: domain `[['customer_rank','>',0]]`, optional name ilike, requested fields, limit 20/offset, name/id ordering. Detail includes the customer domain.
- Phone `write([[id], {'phone': value}])`: require true, then read directly from server. Offline cache cannot satisfy write verification.
- `sale.order.search_read/read`; line search by `order_id` excluding display sections. Read quantities, unit price, subtotal, order total and currency.
- Confirm: reread eligible draft/sent order, invoke `action_confirm([[id]])`, reread and require sale/done. Never write `state` directly. Sales confirmation is never automatically retried. Phone outbox retries use bounded backoff and remote reconciliation/readback; see offline.md.

## Data and errors
Empty Odoo fields can be false; many2one values can be `[id, display_name]`. Data-layer parsers normalize these. Faults are sanitized before presentation. Network timeouts allow customer read-cache fallback and durable phone queueing; authentication/permission errors never do. Server ACLs remain authoritative even when navigation is visible.

Passwords are entered locally and stored only in the OS secure store for mobile restoration. CLI verification uses hidden terminal input and memory only, without logging raw RPC faults/customer payloads. HTTPS and certificate verification are required. No hardcoded credentials, passwords in dart-defines, or external mail actions.

## Verification tools
`tool/check_online_odoo.command`: version, actual database discovery, local credential input, customer domain read.
`tool/check_sales_odoo.command`: local credential input, internal check, Sales list, own synthetic customer/product/quotation, phone write/readback, lines, confirmation and cleanup. Only run on the assignment demo.

The legacy `verify_odoo.py` supports private external configuration and older demo checks; use the Online-specific tools above for this project.

## Lifecycle
XML-RPC is verified on this instance today, but it is a legacy API. Revalidate before server upgrades or trial/plan changes. JSON-2 uses API keys and is not a drop-in password-login replacement. Official references: [external RPC](https://www.odoo.com/documentation/19.0/developer/reference/external_rpc_api.html), [current external API](https://www.odoo.com/documentation/master/developer/api/external_api.html), [Odoo 20 user model](https://github.com/odoo/odoo/blob/20.0/odoo/addons/base/models/res_users.py).

Offline writes and real reconnection verification are documented in [offline.md](offline.md) and `offline_live_verification.json`.

## Verified Odoo 20 reviewer compatibility
Odoo 20 XML-RPC numeric fault codes 3 (authentication), 4 (access), and 2 (validation) are classified even when no Python exception class appears in the message. Official source: https://github.com/odoo/odoo/blob/20.0/addons/rpc/controllers/xmlrpc.py. Real reviewer phone updates required the standard Contacts edit group in addition to Internal User and Sales own-document access. No administrator privilege was needed.
