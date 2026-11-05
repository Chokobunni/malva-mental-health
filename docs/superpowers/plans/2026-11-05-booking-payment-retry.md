# Booking and payment retry repair

**Design approved in task coordination:** reuse the same pending purchase and payment; bind the selected care package through the existing `care_packages.booking_id`. Keep the legacy `bookings.package_id` reference to service packages unchanged. No new database columns, routes, or wire fields are needed for purchase linkage.

**Impact:** backend booking, care package and payment stores/handlers; Flutter purchase, resume and MyCare; Android payment return. Medium scope, backward compatible for ordinary bookings. Legacy package bookings may be adopted only when their relationship is unambiguous. Concurrent operations must serialize, and paid/cancelled state must never be reopened by a retry.

1. Add failing integration tests for package-only booking payloads, duplicate package/payment retries, activation replay and payment amount/terminal status reconciliation. Run against the isolated local test database supplied by the parent task.
2. Reuse matching pending packages under the existing pair lock. Atomically create/reuse and bind package bookings; reject ownership or changed intent. Reuse pending payments under a booking row lock, including tokenless rows; initialize the gateway under payment lock with the same reference. Atomically cancel linked pending entities.
3. Resolve exact package linkage before activation, including merged replay; only use unambiguous legacy fallback. Verify amount before status reconciliation and persist terminal gateway payment states without reviving cancelled packages.
4. Add Flutter regressions for exact package booking resume, no overlapping status checks, package filters and lifecycle refresh. Parse the already-existing package booking ID, use it for resume/cancellation, and preserve package context through payment success.
5. Open Midtrans in an embedded browser session where supported; close it only after authoritative paid status. Configure a finish callback and Android URI filter, and route callback references through authenticated backend status checks. Sandbox simulator pages can be separate browser tabs and cannot be forcibly closed by Malva.
6. Run focused backend/Flutter tests, full build/vet/tests and API document checks through parent coordination. Update payment/care module guidance. No deployment, commits or edits to existing migrations.

## Follow-up: legacy continuation before deployment

The user authorized push/deployment and a new APK in the parent task. The parent handles release actions. The previous APK used the new package-only booking payload while the old backend remained deployed, which still required `professional_id`; the resulting English validation was hidden by the generic friendly-error fallback.

Local inspection also found that resuming an unbound legacy package bypassed the existing package-booking bind endpoint. With duplicate pending packages this could make paid activation ambiguous. Parse the existing booking slot/type/duration fields and bind the selected package to its single eligible legacy booking before opening payment. Exclude bookings already owned by another package. Keep database and HTTP schemas unchanged; cover the legacy path in Flutter and synthetic PostgreSQL tests before release.

The parent also approved the directly related expired-session repair in `MalvaApiClient`: return fresh credentials to all concurrent refresh waiters, retry with that credential, reuse it for follow-on calls still carrying the captured expired token, disable recursive refresh of the refresh endpoint, and reject stale account generations before refresh/retry. Regression coverage must include successful payment resume, concurrent requests, revoked refresh termination, and account changes during an outstanding request/refresh. No authentication provider refactor is planned.
