"""Offline structural checks; cannot replace live database or end-to-end tests."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
required=['web/index.html','web/package.json','web/src/main.js','web/src/ui.js','web/src/main.jsx','web/src/App.jsx','web/src/admin.css','web/src/demo-login.css','web/src/demo-preview.dev.js','web/src/loading.css','web/src/club-cards.css','web/src/style.css','web/src/client.js','web/src/data.js','mobile/App.js','mobile/app.json','supabase/migrations/202611220001_ucems.sql','supabase/migrations/202611220002_club_logos.sql','supabase/migrations/202611220003_admin_club_management.sql','supabase/migrations/202611220004_role_based_proposal_review.sql','supabase/migrations/202611220005_admin_account_role_management.sql','supabase/migrations/202611220006_prevent_self_role_management.sql','supabase/migrations/202611230001_admin_self_role_grants.sql','supabase/migrations/202611230002_srs_foundations.sql','supabase/migrations/202611230003_srs_operations.sql','supabase/migrations/202611230004_registration_lifecycle.sql','supabase/migrations/202611230005_authority_routing_rules.sql','supabase/functions/create-checkout/index.ts','supabase/functions/stripe-webhook/index.ts']
for f in required: assert (root/f).is_file(),f
sql=(root/'supabase/migrations/202611220001_ucems.sql').read_text()
for s in ['create policy','enable row level security','create function public.resubmit_proposal','create function public.publish_proposal','create function public.lecturer_decide','create function public.authority_decide','create function public.scan_attendance_token','create function public.issue_attendance_token','create function public.complete_checkout','create function public.decide_membership']:
 assert s in sql,s
assert "p.current_version" in sql
assert "p.status='published' and p.current_version=version" in sql
assert "auth.role()<>'service_role'" in sql
assert 'revoke all on all functions' in sql
assert 'STRIPE_TEST_SECRET_KEY' in (root/'supabase/functions/create-checkout/index.ts').read_text()
assert 'validSignature' in (root/'supabase/functions/stripe-webhook/index.ts').read_text()
logos=(root/'supabase/migrations/202611220002_club_logos.sql').read_text()
for s in ['add column logo_path','storage.buckets','club_logos_admin_upload','private.has_role(\'admin\')','admin_create_club_with_logo']:
 assert s in logos,s
admin_management=(root/'supabase/migrations/202611220003_admin_club_management.sql').read_text()
for s in ['admin_update_club','admin_clear_club_lecturer','admin_remove_committee_seat','admin_remove_club_organizer','admin_replace_club_organizer']:
 assert s in admin_management,s
review_policy=(root/'supabase/migrations/202611220004_role_based_proposal_review.sql').read_text()
for s in ['create or replace function public.submit_proposal','r.role = \'authority\'','revoke all on function public.admin_assign_reviewer']:
 assert s in review_policy,s
assert 'admin_assign_reviewer' not in (root/'web/src/App.jsx').read_text()
role_management=(root/'supabase/migrations/202611220005_admin_account_role_management.sql').read_text()
for s in ['admin_update_user_role','admin_remove_user_role','Cannot remove the last administrator','grant execute on function public.admin_update_user_role','grant execute on function public.admin_remove_user_role']:
 assert s in role_management,s
app=(root/'web/src/App.jsx').read_text()
for s in ['AccountRoleManager','admin_update_user_role','admin_remove_user_role','Name, account ID, or role']:
 assert s in app,s
for s in ['My memberships','Payment history','Shared proposal activity','Changes from Version','Audit history','Latest 100 records','resetPasswordForEmail','PasswordRecovery']:
 assert s in app,s
for s in ['aria-label="Active club"','clubIds={scopedClubIds}','const mine=clubIds.includes(p.club_id)','setClubContextId(event.target.value);setModal(null)','const data=store.memberships.filter(m=>scopedClubIds.includes(m.club_id))']:
 assert s in app,s
assert "get('audit_log'" in (root/'web/src/data.js').read_text()
self_role_policy=(root/'supabase/migrations/202611220006_prevent_self_role_management.sql').read_text()
for s in ['admin_assign_role','admin_update_user_role','admin_remove_user_role','p_user = auth.uid()','Admins cannot']:
 assert s in self_role_policy,s
for s in ['currentUserId={store.user.id}','disabled={busy||isSelf}','Your existing roles cannot be changed or removed here.']:
 assert s in app,s
self_role_grants=(root/'supabase/migrations/202611230001_admin_self_role_grants.sql').read_text()
for s in ['admin_assign_role','if not private.has_role(\'admin\')','p_user is null','p_role is null','grant execute on function public.admin_assign_role']:
 assert s in self_role_grants,s
assert 'p_user = auth.uid()' not in self_role_grants
assert 'available.length>0?<form' in app
assert 'if(account.id===store.user?.id)await loadSession();' in app
for s in ["!import.meta.env.DEV","Quick role preview","loadDemoPreview","Demo preview only — no changes were saved."]:
 assert s in app,s
demo_preview=(root/'web/src/demo-preview.dev.js').read_text()
for s in ['demo-admin','demo-student','demo-committee','demo-coordinator','demo-authority','demo-published']:
 assert s in demo_preview,s
assert 'current_version: 2' in demo_preview
assert 'auditLogs: role===\'admin\'' in demo_preview
assert 'demo-organizer' not in demo_preview
assert 'supabase' not in demo_preview.lower()
foundations=(root/'supabase/migrations/202611230002_srs_foundations.sql').read_text()
for s in ['President','Vice President','Secretary','Vice Secretary','Treasurer','committee_position_permissions','private.has_club_permission','admin_set_authority_routing','routing_exception','proposal_authority_assignments','badge_candidates','decide_badge_candidate','admin_migrate_organizer_assignment']:
 assert s in foundations,s
assert 'enabled boolean not null default false' in foundations
assert "where p.status in ('authority_pending','approved_unpublished','published')" in foundations
assert "'badge_issued',false" in foundations
assert "insert into public.badges(proposal_id,user_id,authorized_by,authorization_reason,candidate_id)" in foundations
assert 'revoke insert,update,delete,truncate,references,trigger on table' in foundations
operations=(root/'supabase/migrations/202611230003_srs_operations.sql').read_text()
for s in ['allowed_email_domains','require_university_email','published_version','notifications','mark_notification_read','proposal_documents','proposal_document_access','Paid checkout is disabled until a payment provider is configured']:
 assert s in operations,s
assert "values ('edu.lnbti.lk')" in operations
assert 'do update set enabled=true' in operations
assert 'notifications' in (root/'web/src/App.jsx').read_text()
assert 'proposal-documents' in (root/'web/src/App.jsx').read_text()
registration=(root/'supabase/migrations/202611230004_registration_lifecycle.sql').read_text()
for s in ['register_event_with_answers','private.validate_registration_answers','claim_external_registration','verify_external_registration','registration.verify_external','cancel_event','decide_refund_request','provider_status']:
 assert s in registration,s
assert 'Verified event registration required for attendance' in registration
assert 'Paid checkout is disabled until a payment provider is configured' in registration
for s in ['register_event_with_answers','claim_external_registration','registration_form_schema','verification_status']:
 assert s in app,s
authority_rules=(root/'supabase/migrations/202611230005_authority_routing_rules.sql').read_text()
for s in ['authority_routing_rules','admin_save_authority_rule','private.assign_authority_tasks','rule_snapshot','routing_exception']:
 assert s in authority_rules,s
for s in ['AdminAuthorityRules','admin_save_authority_rule','Event registrations','registration.verify_external']:
 assert s in app,s
assert 'Publishing records the public event version' in (root/'supabase/tests/rls_rpc_flows.test.sql').read_text()
assert 'outside@example.com' in (root/'supabase/tests/rls_rpc_flows.test.sql').read_text()
scan_function=foundations.split('create or replace function public.scan_attendance_token',1)[1].split('create or replace function public.decide_badge_candidate',1)[0]
assert 'insert into public.badges' not in scan_function
assert 'onChange={event=>switchRole(event.target.value)}' in app
for f in ['web/src/main.js','web/src/ui.js','web/src/client.js','mobile/App.js']:
 s=(root/f).read_text();assert 'SUPABASE_SERVICE_ROLE_KEY' not in s,f
print('PASS: required files, SQL control points, no frontend service-role key. This is a static check, not a live deployment test.')
