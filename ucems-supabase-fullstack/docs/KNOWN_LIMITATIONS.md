# Known limitations / release gate

This is an **in-progress SRS implementation**, not a verified production system. The user provided a development/staging Supabase target and approved reviewed migrations after validation, but no hosted changes have been made. The user explicitly requested no local Supabase integration. The CLI session in this workspace cannot access the user's authenticated profile, and the direct database route is unavailable over IPv6; do not infer that staging was inspected or modified.

## Implemented SRS-alignment slice

- Additive migrations map the existing five seat numbers to President, Vice President, Secretary, Vice Secretary, and Treasurer, and introduce per-club/per-position permissions. Per the user's latest policy choice, catalogued permissions are enabled by default; core proposal, publication, membership-decision, attendance-scan, external-registration verification, event cancellation, and refund-decision operations check permissions in PostgreSQL.
- Admin can configure Higher Authority routing rules by event category and LKR budget, with one or more eligible recipients per rule. Coordinator approval evaluates the matching rules, routes immediately, and snapshots rules and reviewers for that version. No active match produces a recoverable `routing_exception`, not approval.
- Existing organizer assignments remain intact until an Admin manually maps them into an available named position. The standalone Organizer role is no longer offered in web/mobile role switching or role assignment.
- Attendance scanning creates an attendance record and a pending badge candidate. A committee member with `badge.authorize` must approve or reject with a reason; previous unverified auto-issued rows are retained but are not shown to students as earned badges.
- Student web no longer issues attendance QR passes; mobile QR presentation and the committee scanner remain available.
- The web proposal workspace now shows saved versions, field-by-field differences, current approval progress, and a single ordered view of saved version snapshots, comments, and formal decisions.
- Student web now shows membership history and separates registration, latest payment, and attendance status; payment attempts have a read-only history.
- Admin web now exposes an RLS-protected, searchable audit view of the latest 100 records.
- The previous role-switch reliability fix remains in place.
- Auth creation and email changes now enforce an Admin-managed university email allow-list; `edu.lnbti.lk` is configured.
- The last published proposal version is kept separate from the version under review, so current public content is not replaced by unapproved values.
- Database events create recipient-scoped in-app notifications for proposal status/comments, membership, registration, payment settlement, and badge decisions.
- Proposal documents use a private Storage bucket, version-scoped object paths, access-checked signed links, MIME validation, and a 10 MB limit.
- Paid event/membership checkout is disabled in both the database RPC and Edge Function until a payment provider is selected and configured.
- Event registration now supports versioned internal form schemas, server-side answer validation, eligibility/deadline/capacity checks, external registration claims with manual verification, and confirmation codes.
- Published-event cancellation is audited, cancels registrations, and creates full-original-amount refund work items. Refund review is separate from provider processing; no refund is marked completed without a gateway confirmation.
- Separate Expo app with attendance camera scanner and student QR presentation.

## Not complete / needs user testing and decisions

- The prior database foundation had eight migrations and a 66-test pgTAP suite passed before the current changes. Operations, registration-lifecycle, and category/budget routing migrations plus updated SQL tests have **not** been applied or run. No local Supabase stack was started for this work, per the user's instruction; hosted migration state is also unverified.
- Web syntax checks, production build, and the static project check pass. Mobile runtime tests and device tests have not been performed.
- Stitch references are retained, but the new app is a consistent custom implementation of the approved workflows, **not pixel-for-pixel copies of every original HTML layout**. Preview and accessibility review needed.
- Calendar currently shows the current month; month navigation and timezone settings are future UI improvements.
- Admin-configurable event-category/LKR-budget authority rules and immutable per-version reviewer snapshots are implemented in SQL/UI, but remain unvalidated against PostgreSQL. Missing matches fail closed into a recoverable `routing_exception`.
- Per the user's latest decision, all catalogued committee permissions are enabled by default for all positions on new clubs, and existing clubs are seeded the same way. Admin can revoke grants. This differs from the SRS least-privilege default and requires institutional review before production.
- The permission matrix now includes draft editing, cancellation, external-registration verification, registration, badge-definition, and finance permissions. Participant export, full finance reconciliation, and badge-definition workflows remain incomplete.
- Existing standalone organizer assignments are not automatically placed into a position. If the account already has a position, or all five positions are occupied, the legacy assignment remains pending for Admin resolution.
- Device installation registration and Admin-approved transfer are explicitly excluded by user direction. The current QR flow remains time-limited and single-use, but is not device-bound and does not satisfy the SRS device rule.
- Event registration forms and external-claim verification now have database support and student UI. Committee participant search/export, membership eligibility/policy authoring, reopen/re-registration rules, and registration cancellation management remain incomplete.
- Private proposal document storage and upload UI are present, but external approval evidence verification, retention enforcement, document cleanup scheduling, and full thread/timeline integration remain outstanding.
- Notifications are durable and in-app, including proposal routing/decisions, external verification, cancellation, and refund decisions. Realtime delivery, email, and push are not implemented.
- Published content remains readable during reapproval, but a complete published-event revision/edit flow, minor-change classification, and general lifecycle automation remain outstanding.
- Category/budget authority rules fail closed when no active rule matches. Optional club-level review remains unimplemented; no zero-authority shortcut is enabled.
- Membership policy/form configuration by authorized committee/Admin, eligibility evaluation, member history/audit transitions, and configurable fee/payment policy remain incomplete.
- Manual badge authorization currently covers attendance-derived candidates only. Club-President badge definition/look management, goals, membership-based eligibility, repeatability, and revocation history remain outstanding.
- Paid checkout is disabled by the user's provider decision. Existing legacy fee/payment fields remain USD-test minor units; new event fee/budget fields are LKR. Per-club merchant onboarding, provider-backed refunds, settlement/reconciliation, and complete finance UI remain outstanding.
- Domain enforcement is active for `edu.lnbti.lk`; university SSO, bulk user import, and other institution domains require Admin configuration. Existing accounts are not automatically revoked when a domain is removed.
- Retention durations are intentionally unset; no automatic deletion/retention worker is implemented.
- The audit screen searches only the latest 100 records and has no export or scalable pagination.
- Staff role permissions must be revalidated against university policy (e.g. student eligibility, membership reviewer, account provisioning).

## Release checkpoints

1. Use the user's secure terminal authentication and an IPv4 Supabase pooler route to verify project ref `oyviblvnftfthczjtryy` and inspect migration state/drift before any write.
2. Review and validate the additive operations, registration-lifecycle, and category/budget routing migrations and updated SQL acceptance suite before applying them to the approved development/staging project.
3. Configure all five positions and review the current all-enabled permission defaults with the institution before using real accounts.
4. Configure authority routing criteria, matching roles/budgets/recipients, and confirm missing rules create a routing exception.
5. Test email-domain rejection/acceptance, notification privacy, private document upload/signed links, and historical published-version visibility.
6. Create role-specific accounts and run the acceptance scenarios against staging.
7. Implement and test club membership-policy authoring, badge definitions/goals, published-event revision policy, refund provider processing, and finance reconciliation before calling the SRS complete.
8. Device binding remains excluded unless the user changes that decision.
9. Select a payment provider and complete the LKR/per-club merchant/refund implementation before enabling paid checkout.
10. Obtain institutional and production approval before real university data or payment credentials are used.
