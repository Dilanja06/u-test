# UCEMS V1 — Supabase acceptance scenarios

**Status:** The prior eight-migration baseline and its 66-test pgTAP suite passed before the current additions. The operations, registration-lifecycle, and category/budget routing migrations and updated SQL tests have not been run. Per user instruction, no local Supabase stack is to be used. Hosted staging state and acceptance scenarios remain unverified.

| ID | Scenario | Expected result |
|---|---|---|
| AT-01 | Student tries `admin_create_club` via RPC | Rejected by DB |
| AT-02 | Club A committee tries to create Club B proposal | Rejected by DB |
| AT-03 | Club submission with no assigned lecturer | Rejected |
| AT-04 | Club submission with zero authorities | Rejected |
| AT-05 | Assigned lecturer approves V1 | Proposal enters authority stage |
| AT-06 | Authority approves before lecturer | Rejected |
| AT-07 | Of 3 configured authority recipients routed after Coordinator approval, only 2 approve | No publication eligibility |
| AT-08 | Assigned authority requests corrections | Status changes_requested |
| AT-09 | Committee resubmits V2 after corrections | New version, lecturer_pending |
| AT-10 | Try to publish V2 using V1 approvals | Rejected |
| AT-11 | V2 lecturer approves + all V2 authorities approve | approved_unpublished |
| AT-12 | Committee explicitly publishes V2 | visible to students and calendar |
| AT-13 | Published event viewed by unrelated student | Only the last published proposal version is visible; preservation during a newer review is pending the user-facing event-revision workflow |
| AT-14 | Student tries to create draft for a club | Rejected |
| AT-15 | Student requests paid membership | pending review, not paid |
| AT-16 | Committee approves paid membership | payment_due, not active |
| AT-17 | Free membership approved | active |
| AT-18 | Free event student registration | registered |
| AT-19 | Student attempts to register for a paid event while no provider is configured | Rejected; no registration or payment is created |
| AT-20 | Browser manually claims Stripe success | Does not activate payment |
| AT-21 | Fake Stripe webhook signature | Rejected |
| AT-22 | Valid signed Stripe TEST completion | Updates order and related status |
| AT-23 | Student requests check-in token outside event time | Rejected |
| AT-24 | Eligible registered student requests token in time | 90-second token issued |
| AT-25 | Committee member without `attendance.scan` attempts a scan | Rejected |
| AT-26 | Committee member with `attendance.scan` scans token | Attendance and pending badge candidate created; no badge issued |
| AT-27 | Same QR reused | Rejected |
| AT-28 | Expired QR | Rejected |
| AT-29 | Student attempts to read another student's private payment orders | RLS blocks |
| AT-30 | Old reviewer decision on V1 after resubmit V2 | Audit remains but no V2 clearance |

| AT-31 | Assigned reviewer comments without casting a decision | Comment visible to stakeholders on that version |
| AT-32 | Unrelated student tries to read proposal comments | RLS blocks |
| AT-33 | Admin updates an existing club profile | Updated details are visible in the club directory |
| AT-34 | Admin replaces or removes a club staff assignment | Assignment reflects the new staff member or vacant position |
| AT-35 | Non-admin calls club update or staff removal RPC | Rejected by the database |
| AT-36 | Admin uploads an unsupported or oversized club logo | Upload is rejected; no club change is applied |
| AT-37 | Coordinator approves with matching category/budget authority rules | All active recipients from matching rules are assigned to the current proposal version automatically |
| AT-38 | Admin tries to manually select a proposal reviewer | Per-proposal reviewer RPC is unavailable to authenticated users |
| AT-39 | Admin changes a matching routing rule before Coordinator approval | The rules and recipients active at approval time are snapshotted when the current version is routed |
| AT-40 | Admin searches and pages through account roles | Matching accounts and current role assignments are shown |
| AT-41 | Admin grants, changes, or removes an account role | The account-role list reflects the saved assignment |
| AT-42 | Non-admin calls role update or removal RPC | Rejected by the database |
| AT-43 | Admin attempts to remove/change the final admin role | Rejected; at least one administrator remains |
| AT-44 | Admin grants an additional role to their own account | Allowed after the self-grant migration; the role is available after refresh |
| AT-45 | Admin attempts to change or remove their own existing role | Rejected by the UI and database; existing roles and the last-admin safeguard remain protected |
| AT-46 | Admin assigns a committee position | UI shows one of President, Vice President, Secretary, Vice Secretary, or Treasurer |
| AT-47 | Newly assigned committee position on a new club | All catalogued permissions are enabled by the currently selected policy |
| AT-48 | Admin revokes `event.publish` for Club A President | Club A President cannot publish; other club/position grants remain independently scoped |
| AT-49 | Coordinator approves when no enabled category/budget rule matches | Proposal enters `routing_exception`; it cannot be published |
| AT-50 | Admin configures a matching rule with active authority recipients and retries routing | Current version becomes actionable for the configured recipients; all required approvals remain necessary |
| AT-51 | A legacy organizer assignment is migrated by Admin | The selected vacant named position is assigned; the legacy assignment is removed only after success |
| AT-52 | Attendance scan completes for an eligible event | Student sees no earned badge until an authorized committee member records an approval decision |
| AT-53 | Committee member without `badge.authorize` attempts to approve a candidate | Database rejects the decision |
| AT-54 | Authorized committee member approves a badge candidate with a reason | Award is recorded with authorizer and reason; it appears in the student's earned badge list |
| AT-55 | Authorized proposal participant opens a proposal with multiple versions | The shared workspace shows version selection, field differences, current approval progress, and one chronological thread of version snapshots, comments, and formal decisions |
| AT-56 | Student opens My Events after registration/payment/attendance changes | Registration, latest payment state, and verified attendance appear as separate statuses |
| AT-57 | Student opens My Memberships | Current and historical membership requests show their club, request date, and status |
| AT-58 | Admin opens Audit history | The latest 100 RLS-authorized audit records can be searched and paged; resource links open proposal records where applicable |
| AT-59 | User requests a password reset and follows a valid Supabase recovery link | User can set and confirm a new password; invalid/expired links or mismatched passwords do not change the account |
| AT-60 | Committee member assigned to multiple clubs switches the active club | The top bar identifies the selected club and position; committee data, permission checks, proposal actions, and proposal forms are limited to that club; changing context closes any open modal |
| AT-61 | New account uses an email domain outside the Admin allow-list | Auth insert/email change is rejected by the database trigger |
| AT-62 | User reads or marks another user's notification as read | RLS/RPC deny access; own inbox and read receipts remain available |
| AT-63 | Authorized proposal participant uploads a supported document to a draft version | Private object and metadata are stored with proposal/version context; authorized users can obtain a short-lived signed URL; unrelated users cannot read it |
| AT-64 | Account uploads an unsupported or over-10-MB proposal document | Client and Storage reject it; no document metadata is created |
| AT-65 | A user attempts paid checkout while no provider is selected | Database RPC and Edge Function keep checkout disabled |
| AT-66 | Published event has a newer proposal version pending review | **Pending feature:** once the user-facing revision workflow exists, student discovery/detail must remain on `published_version`, never on unapproved `current_version` |
| AT-67 | Student submits an internal event registration with missing required answers or forged fields | Server rejects invalid/missing/unknown answers; valid answers are stored with the published version and confirmation code |
| AT-68 | Student claims registration for an external-form event | A pending-verification record is created; opening the external URL alone does not confirm registration |
| AT-69 | Authorized verifier accepts or rejects an external claim | Decision, reviewer, timestamp, and reason are persisted; student receives a durable notification; pending claims cannot pass attendance checks |
| AT-70 | Student registers after deadline, without required club membership, or after capacity is reached | Database RPC rejects the attempt; row locking prevents concurrent over-capacity registration |
| AT-71 | Authorized committee member cancels a published event with paid registrations | Registrations are cancelled and full-amount refund work items are created; approval remains separate from gateway processing and completion |
| AT-72 | Coordinator approves a proposal with no enabled category/budget routing match | Proposal enters `routing_exception`; it cannot be published, and Admin must configure a rule and retry |
| AT-73 | Multiple enabled rules match one proposal version | Distinct assigned authorities each receive an independent task; the matched rule/reviewer snapshot is preserved if Admin later edits routing |

AT-74 onward (club membership-policy authoring, goal/membership badge definitions, retention enforcement, finance reconciliation, and provider-backed refunds) remain pending implementation.
