# UI review — v1.2.0

The shared design system uses warm off-white canvas, white bordered surfaces, muted gold accents, explicit Roboto typography, compact section labels, consistent 14–18 px corner radii, restrained order/sync status colors, and 160 ms sync-status transitions respecting reduced-motion preferences.

Updated screens: Login/connection settings, customer search/list, customer profile, edit-phone dialog, Sales filters/order cards, order details/total, offline/pending/failed sync, empty/error/loading states. Domain repositories, authorization rules, synchronization algorithm is unchanged. The transport additionally recognizes verified Odoo 20 numeric fault codes.

`test/ui_review_test.dart` renders the actual presentation widgets at a 390×844 logical mobile viewport and checks for layout/runtime errors across these states. `docs/screenshots/design-preview/` contains **synthetic visual previews**, not authenticated backend evidence. Preview type uses a system font loaded into the test engine; Android uses its Roboto system font. No mock repository is wired into the release app.

Reviewed all preview images. Corrected a small-width brand-row overflow, ensured Material ink is visible on card taps, and allowed edit-phone helper text to wrap instead of truncating. Loading blocks are intentionally static; only purposeful, brief status/Material navigation transitions animate.

Validation: flutter analyze clean; 43 tests pass (41 existing plus mobile visual coverage and numeric XML-RPC fault regression coverage). Signed Android build and native screenshot inspection are recorded in IMPLEMENTATION_STATUS when complete.

Native signed-in Android acceptance: final release upgrade preserved the reviewer session. Customer search/profile/edit dialog and Sales list/details were captured and visually inspected in docs/screenshots/reviewer-*.png. Main quotation S00002 remains Draft. Full device airplane-mode/restart acceptance remains manual; real Dart/SQLite/Odoo offline synchronization passed.
