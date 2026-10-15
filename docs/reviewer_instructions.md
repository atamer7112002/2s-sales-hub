# Company reviewer access

The designated reviewer login is `reviewer@2s-sales-demo.example` on https://2s-sales-demo.odoo.com, database `2s-sales-demo`.

Do not use the project owner's administrator credentials for assessment review. The account is created and its verified permissions are recorded in `reviewer_setup.json`. The password is generated randomly and stored in the owner's **macOS login Keychain**, service **2S Sales Hub Odoo Reviewer**, account **reviewer@2s-sales-demo.example**. It is never included in the repository, APK, report, or archive.

To retrieve the password locally, open **Keychain Access**, select the login keychain, search for **2S Sales Hub Odoo Reviewer**, open that item, and choose **Show password**. macOS may ask for local authentication. Share it with the company only using an approved secure channel; do not paste it into README, GitHub, screenshots, or chat. No invitations or password emails are sent by the setup tool.

The setup grants the standard Internal User, Sales own-document, and Contacts creation/edit groups. Contacts access was required by the verified phone-write ACL. It verifies that the reviewer has neither Settings administrator nor access-rights administrator membership. Quotations are assigned to the reviewer, keeping Sales visibility within own-document permissions.

The retained synthetic data is:
- Customer: 2S Demo Customer / 01012345678 / Cairo / demo.customer@example.com.
- Saleable consumable product: 2S Demo Cotton T-Shirt, 450 EGP.
- One quantity-one, tax-free synthetic quotation totalling 450 EGP, left in Draft.

No global currency or accounting configuration is changed. The setup stops if the company currency differs from EGP. A separate quotation is used to verify confirmation permissions and then cancelled/deleted; the main review quotation remains Draft. Verified retained IDs: customer 13, product 2, quotation 2 / S00002. Setup and actual Dart app checks passed; see `reviewer_setup.json` and `reviewer_app_verification.json`.

`tool/verify_reviewer.py` uses the private Keychain password to exercise the actual Dart authentication repository, real Odoo customer search/details, Sales list/details, and durable offline synchronization on the dedicated synthetic customer. It restores that customer's original demo phone afterward and checks the main quotation remains Draft. On desktop only the secure-storage platform plugin is replaced with test storage; all HTTP/XML-RPC calls use real Odoo and the production adapter. Reports omit credentials.

For Android acceptance, install the final APK, enter the reviewer login and locally retrieved password, inspect/edit the synthetic customer, and confirm the main quotation when ready. Confirmation changes the retained draft; use a separate synthetic draft if the main one must remain available for another reviewer. Test airplane-mode/restart/reconnect using the steps in offline.md.
