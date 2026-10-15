# Verified Odoo Online environment

Use the existing database; do not recreate it or set up Docker.

- Server: https://2s-sales-demo.odoo.com
- Database: `2s-sales-demo`, discovered through POST `/web/database/list`.
- Version: `20.0+e`, returned by XML-RPC POST `version()`.
- Transport: XML-RPC `/xmlrpc/2/common` and `/xmlrpc/2/object`.
- Authentication and customer-domain read: verified (`online_connectivity_result.json`).
- Internal membership, phone write/readback, order retrieval, lines, and confirmation: verified (`sales_verification.json`). Synthetic test records were cleaned up.

The company tester needs a dedicated database account with a local Odoo password. Odoo.com SSO credentials may differ. Enter credentials only in the app or the hidden local verification prompt; none are embedded in the APK. Connection settings are editable on login and default to this verified server/database.

Contacts and Sales are already available. As the instance administrator, configure test users under Settings → Users. Use an Internal User and suitable Sales access for order tests; use a separate restricted account to exercise ACL failures. The app's Sales navigation follows base.group_user membership; this does not grant record access or confirmation permissions. Do not bypass server ACLs.

For another verification run, open `tool/check_online_odoo.command` (read-only auth/customer test) or `tool/check_sales_odoo.command` (synthetic records with cleanup). Both prompt locally and do not retain passwords. No Docker is involved.

Online demo expiration, subscription changes and account permissions may affect later tests. API access has been demonstrated for the tested account and operations; it is not a guarantee of access for every user or future plan state.
