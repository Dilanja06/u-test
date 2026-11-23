begin;

select extensions.no_plan();

insert into public.allowed_email_domains(domain) values ('ucems.test')
on conflict(domain) do nothing;

insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_user_meta_data) values
 ('11110000-0000-0000-0000-000000000001','authenticated','authenticated','admin@ucems.test','',now(),'{"full_name":"Admin"}'),
 ('11110000-0000-0000-0000-000000000002','authenticated','authenticated','committee@ucems.test','',now(),'{"full_name":"Committee"}'),
 ('11110000-0000-0000-0000-000000000003','authenticated','authenticated','lecturer@ucems.test','',now(),'{"full_name":"Lecturer"}'),
 ('11110000-0000-0000-0000-000000000004','authenticated','authenticated','authority1@ucems.test','',now(),'{"full_name":"Authority One"}'),
 ('11110000-0000-0000-0000-000000000005','authenticated','authenticated','authority2@ucems.test','',now(),'{"full_name":"Authority Two"}'),
 ('11110000-0000-0000-0000-000000000006','authenticated','authenticated','student@ucems.test','',now(),'{"full_name":"Student"}'),
 ('11110000-0000-0000-0000-000000000007','authenticated','authenticated','student2@ucems.test','',now(),'{"full_name":"Other Student"}');
select extensions.throws_ok(
 $$insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_user_meta_data)
 values('11110000-0000-0000-0000-000000000008','authenticated','authenticated','outside@example.com','',now(),'{}')$$,
 'P0001','Use an email address from an approved university domain',
 'Auth rejects addresses outside the configured university domains'
);

insert into public.user_roles(user_id,role) values
 ('11110000-0000-0000-0000-000000000001','admin'),
 ('11110000-0000-0000-0000-000000000002','committee'),
 ('11110000-0000-0000-0000-000000000003','lecturer'),
 ('11110000-0000-0000-0000-000000000004','authority'),
 ('11110000-0000-0000-0000-000000000005','authority')
on conflict do nothing;

insert into public.clubs(id,name,lecturer_id,membership_fee_cents) values
 ('22220000-0000-0000-0000-000000000001','Flow Test Club','11110000-0000-0000-0000-000000000003',0),
 ('22220000-0000-0000-0000-000000000002','Other Club',null,500);

insert into public.committee_seats(club_id,seat,position_name,user_id) values
 ('22220000-0000-0000-0000-000000000001',1,'President','11110000-0000-0000-0000-000000000002');

insert into public.memberships(id,club_id,user_id,status) values
 ('33330000-0000-0000-0000-000000000001','22220000-0000-0000-0000-000000000002','11110000-0000-0000-0000-000000000007','payment_due');
insert into public.payment_orders(id,user_id,kind,reference_id,amount_cents) values
 ('44440000-0000-0000-0000-000000000001','11110000-0000-0000-0000-000000000007','membership','33330000-0000-0000-0000-000000000001',500);

insert into public.proposals(id,club_id,created_by,status) values
 ('55550000-0000-0000-0000-000000000001','22220000-0000-0000-0000-000000000002','11110000-0000-0000-0000-000000000002','draft');
insert into public.proposal_versions(proposal_id,version,title,description,starts_at,ends_at,venue,capacity,fee_cents) values
 ('55550000-0000-0000-0000-000000000001',1,'Private Club Event','RLS fixture',now()+interval '1 day',now()+interval '1 day 1 hour','Test Hall',20,0);

create temporary table ucems_flow_state(
 name text primary key,
 id uuid,
 token text,
 payload jsonb
);
grant select,insert,update on ucems_flow_state to authenticated,service_role;

create function pg_temp.assume_user(p_user uuid) returns void
language plpgsql
as $$
begin
 perform set_config('request.jwt.claim.sub',p_user::text,true);
 perform set_config('request.jwt.claim.role','authenticated',true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_user::text,'role','authenticated')::text,true);
end;
$$;
grant execute on function pg_temp.assume_user(uuid) to authenticated;

set local role authenticated;
select pg_temp.assume_user('11110000-0000-0000-0000-000000000006');

select extensions.ok(
 not exists(select 1 from public.committee_position_permissions
  where club_id='22220000-0000-0000-0000-000000000001' and not enabled),
 'Every catalogued committee permission is enabled by default'
);
select extensions.throws_ok(
 $$select public.admin_set_committee_permission('22220000-0000-0000-0000-000000000001','President','event.create',true)$$,
 'P0001','Admin required','Student cannot grant committee permissions'
);
select extensions.throws_ok(
 $$select public.admin_set_email_domains(array['example.com'])$$,
 'P0001','Admin required','Student cannot change university email domains'
);
select extensions.throws_ok(
 $$select public.create_proposal('22220000-0000-0000-0000-000000000001','Denied proposal','',now()+interval '1 day',now()+interval '1 day 1 hour','Hall',20,0)$$,
 'P0001','event.create permission required for this club','Student cannot create a committee proposal'
);
select extensions.lives_ok(
 $$insert into pg_temp.ucems_flow_state(name,id) values('membership',public.apply_membership('22220000-0000-0000-0000-000000000001'))$$,
 'Student can submit a membership request'
);
select extensions.is(
 (select status from public.memberships where id=(select id from pg_temp.ucems_flow_state where name='membership')),
 'pending','Membership request starts pending'
);

select pg_temp.assume_user('11110000-0000-0000-0000-000000000001');
select extensions.lives_ok(
 $$select public.admin_set_committee_permission('22220000-0000-0000-0000-000000000001','President','club.members.manage',false)$$,
 'Admin can disable a default committee permission'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000002');
select extensions.throws_ok(
 $$select public.decide_membership((select id from pg_temp.ucems_flow_state where name='membership'),true)$$,
 'P0001','club.members.manage permission required or application is not pending','Committee cannot decide membership without the permission'
);
select extensions.is(
 (select count(*) from public.memberships where user_id='11110000-0000-0000-0000-000000000007'),
 0::bigint,'RLS hides another club member record'
);

select pg_temp.assume_user('11110000-0000-0000-0000-000000000001');
select extensions.lives_ok(
 $$select public.admin_set_committee_permission('22220000-0000-0000-0000-000000000001','President','event.create',true)$$,
 'Admin can grant a club-scoped permission'
);
select extensions.lives_ok(
 $$select public.admin_set_email_domains(array['@EDU.LNBTI.LK','ucems.test'])$$,
 'Admin can manage approved university email domains'
);
select extensions.ok(
 exists(select 1 from public.allowed_email_domains where domain='edu.lnbti.lk'),
 'Configured email domains are normalized'
);
select extensions.lives_ok(
 $$select public.admin_set_committee_permission('22220000-0000-0000-0000-000000000001','President','club.members.manage',true)$$,
 'Admin can grant membership review permission'
);

select pg_temp.assume_user('11110000-0000-0000-0000-000000000002');
select extensions.lives_ok(
 $$select public.decide_membership((select id from pg_temp.ucems_flow_state where name='membership'),true)$$,
 'Committee with permission can approve a free membership'
);
select extensions.is(
 (select status from public.memberships where id=(select id from pg_temp.ucems_flow_state where name='membership')),
 'active','Free approved membership becomes active'
);
select extensions.throws_ok(
 $$select public.decide_membership('33330000-0000-0000-0000-000000000001',true)$$,
 'P0001','club.members.manage permission required or application is not pending','Club A permission cannot decide Club B membership'
);
select extensions.lives_ok(
 $$insert into pg_temp.ucems_flow_state(name,id) values('proposal1',public.create_proposal('22220000-0000-0000-0000-000000000001','Approval flow event','Database flow test',now()-interval '15 minutes',now()+interval '1 hour','Test Hall',20,0))$$,
 'Committee with event.create can create a club proposal'
);
select extensions.lives_ok(
 $$select public.configure_proposal_registration((select id from pg_temp.ucems_flow_state where name='proposal1'),'Workshop','Flow test','all_students',true,'internal',null,null,'[{"key":"diet","label":"Dietary needs","type":"text","required":true}]'::jsonb,0,0)$$,
 'Committee can configure a server-validated internal registration form'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000001');
select extensions.lives_ok(
 $$select public.admin_set_committee_permission('22220000-0000-0000-0000-000000000001','President','event.proposal.submit',false)$$,
 'Admin can disable proposal submission for an explicit permission test'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000002');
select extensions.throws_ok(
 $$select public.submit_proposal((select id from pg_temp.ucems_flow_state where name='proposal1'))$$,
 'P0001','event.proposal.submit permission required or proposal is not a draft','Proposal submission requires its separate permission'
);

select pg_temp.assume_user('11110000-0000-0000-0000-000000000001');
select extensions.lives_ok(
 $$select public.admin_set_committee_permission('22220000-0000-0000-0000-000000000001','President','event.proposal.submit',true)$$,
 'Admin can grant proposal submission permission'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000002');
select extensions.lives_ok(
 $$select public.submit_proposal((select id from pg_temp.ucems_flow_state where name='proposal1'))$$,
 'Committee can submit after the permission is granted'
);

select pg_temp.assume_user('11110000-0000-0000-0000-000000000003');
select extensions.lives_ok(
 $$select public.lecturer_decide((select id from pg_temp.ucems_flow_state where name='proposal1'),'approved','')$$,
 'Lecturer can approve a submitted proposal'
);
select extensions.is(
 (select status from public.proposals where id=(select id from pg_temp.ucems_flow_state where name='proposal1')),
 'routing_exception','No configured authorities creates a routing exception, not approval'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000002');
select extensions.ok(
 exists(select 1 from public.notifications
  where recipient_id='11110000-0000-0000-0000-000000000002'
   and entity_type='proposal' and entity_id=(select id from pg_temp.ucems_flow_state where name='proposal1')),
 'Proposal status changes create a durable notification for the committee'
);
select extensions.lives_ok(
 $$select public.mark_notification_read((select id from public.notifications
  where recipient_id='11110000-0000-0000-0000-000000000002'
   and entity_type='proposal' and entity_id=(select id from pg_temp.ucems_flow_state where name='proposal1')
  order by created_at desc limit 1))$$,
 'A recipient can mark their own notification as read'
);

select pg_temp.assume_user('11110000-0000-0000-0000-000000000001');
select extensions.lives_ok(
 $$select public.admin_save_authority_rule(null,'All categories, zero budget',null,0,null,array['11110000-0000-0000-0000-000000000004'::uuid,'11110000-0000-0000-0000-000000000005'::uuid])$$,
 'Admin can configure a matching category and budget rule'
);
select extensions.lives_ok(
 $$select public.admin_retry_authority_routing((select id from pg_temp.ucems_flow_state where name='proposal1'))$$,
 'Admin can recover a routing exception'
);
select extensions.ok(
 exists(select 1 from public.proposal_authority_assignments
  where proposal_id=(select id from pg_temp.ucems_flow_state where name='proposal1')
   and version=1 and jsonb_array_length(rule_snapshot)>0),
 'Routed proposal records the applied rule snapshot'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000004');
select extensions.lives_ok(
 $$select public.authority_decide((select id from pg_temp.ucems_flow_state where name='proposal1'),'approved','')$$,
 'Assigned authority can approve'
);
select extensions.is(
 (select status from public.proposals where id=(select id from pg_temp.ucems_flow_state where name='proposal1')),
 'authority_pending','One of two approvals does not clear authority review'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000005');
select extensions.lives_ok(
 $$select public.authority_decide((select id from pg_temp.ucems_flow_state where name='proposal1'),'approved','')$$,
 'Second assigned authority can approve'
);
select extensions.is(
 (select status from public.proposals where id=(select id from pg_temp.ucems_flow_state where name='proposal1')),
 'approved_unpublished','All current-version approvals make the event eligible, not yet published'
);

select pg_temp.assume_user('11110000-0000-0000-0000-000000000001');
select extensions.lives_ok(
 $$select public.admin_set_committee_permission('22220000-0000-0000-0000-000000000001','President','event.publish',false)$$,
 'Admin can disable publication for an explicit permission test'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000002');
select extensions.throws_ok(
 $$select public.publish_proposal((select id from pg_temp.ucems_flow_state where name='proposal1'))$$,
 'P0001','event.publish permission required or proposal is not fully approved','Approval does not grant committee publication permission'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000001');
select extensions.lives_ok(
 $$select public.admin_set_committee_permission('22220000-0000-0000-0000-000000000001','President','event.publish',true)$$,
 'Admin can grant event publication permission'
);
select extensions.lives_ok(
 $$select public.admin_set_committee_permission('22220000-0000-0000-0000-000000000001','President','attendance.scan',true)$$,
 'Admin can grant attendance scanning permission'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000002');
select extensions.lives_ok(
 $$select public.publish_proposal((select id from pg_temp.ucems_flow_state where name='proposal1'))$$,
 'Committee can publish after approvals and permission grant'
);
select extensions.is(
 (select status from public.proposals where id=(select id from pg_temp.ucems_flow_state where name='proposal1')),
 'published','Publication status is visible to the club committee'
);
select extensions.is(
 (select published_version from public.proposals where id=(select id from pg_temp.ucems_flow_state where name='proposal1')),
 1,'Publishing records the public event version'
);

select pg_temp.assume_user('11110000-0000-0000-0000-000000000006');
select extensions.throws_ok(
 $$select public.register_event_with_answers((select id from pg_temp.ucems_flow_state where name='proposal1'),'{}'::jsonb)$$,
 'P0001','Required registration field "Dietary needs" is missing',
 'Required form answers are enforced by the database'
);
select extensions.lives_ok(
 $$insert into pg_temp.ucems_flow_state(name,id) values('registration1',public.register_event_with_answers((select id from pg_temp.ucems_flow_state where name='proposal1'),'{"diet":"Vegetarian"}'::jsonb))$$,
 'Student can submit valid answers for a published free event'
);
select extensions.is(
 (select form_answers->>'diet' from public.registrations where id=(select id from pg_temp.ucems_flow_state where name='registration1')),
 'Vegetarian','Registration answers are persisted with the registration'
);
select extensions.is(
 (select version from public.registrations where id=(select id from pg_temp.ucems_flow_state where name='registration1')),
 1,'Registration is bound to the published version'
);
select extensions.lives_ok(
 $$insert into pg_temp.ucems_flow_state(name,token) values('attendance_token',public.issue_attendance_token((select id from pg_temp.ucems_flow_state where name='proposal1')))$$,
 'Registered student can request a time-limited attendance token'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000002');
select extensions.lives_ok(
 $$update pg_temp.ucems_flow_state set payload=public.scan_attendance_token(token) where name='attendance_token'$$,
 'Authorized scanner can verify a valid attendance token'
);
select extensions.ok(
 (select payload->>'badge_issued'='false' from pg_temp.ucems_flow_state where name='attendance_token'),
 'Attendance scan creates eligibility without issuing a badge'
);
select extensions.throws_ok(
 $$select public.scan_attendance_token((select token from pg_temp.ucems_flow_state where name='attendance_token'))$$,
 'P0001','QR expired or already used','Attendance token is single use'
);
reset role;
select extensions.is(
 (select count(*) from public.attendance where proposal_id=(select id from pg_temp.ucems_flow_state where name='proposal1')),
 1::bigint,'Successful scan records attendance'
);
select extensions.is(
 (select status from public.badge_candidates where proposal_id=(select id from pg_temp.ucems_flow_state where name='proposal1') and user_id='11110000-0000-0000-0000-000000000006'),
 'pending','Successful scan creates a pending badge candidate'
);
select extensions.is(
 (select count(*) from public.badges where proposal_id=(select id from pg_temp.ucems_flow_state where name='proposal1')),
 0::bigint,'Attendance scan does not directly create an earned badge'
);

insert into public.proposals(id,club_id,created_by,current_version,status,published_version,published_at)
values('55550000-0000-0000-0000-000000000003','22220000-0000-0000-0000-000000000001',
 '11110000-0000-0000-0000-000000000002',1,'published',1,now());
insert into public.proposal_versions(
 proposal_id,version,title,description,starts_at,ends_at,venue,capacity,fee_cents,
 registration_method,external_registration_url
) values(
 '55550000-0000-0000-0000-000000000003',1,'External registration event','Manual verification flow',
 now()-interval '15 minutes',now()+interval '1 hour','Test Hall',20,0,
 'external','https://forms.example.edu/external'
);
insert into pg_temp.ucems_flow_state(name,id)
values('proposal_external','55550000-0000-0000-0000-000000000003');
set local role authenticated;
select pg_temp.assume_user('11110000-0000-0000-0000-000000000006');
select extensions.lives_ok(
 $$insert into pg_temp.ucems_flow_state(name,id) values('external_registration',public.claim_external_registration((select id from pg_temp.ucems_flow_state where name='proposal_external'),'External form submission 123'))$$,
 'Student can claim an external registration for manual verification'
);
select extensions.is(
 (select verification_status from public.registrations where id=(select id from pg_temp.ucems_flow_state where name='external_registration')),
 'pending','External registration remains pending until committee verification'
);
select extensions.throws_ok(
 $$select public.issue_attendance_token((select id from pg_temp.ucems_flow_state where name='proposal_external'))$$,
 'P0001','Verified event registration required for attendance',
 'Pending external registration cannot receive an attendance token'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000002');
select extensions.lives_ok(
 $$select public.verify_external_registration((select id from pg_temp.ucems_flow_state where name='external_registration'),true,'Verified against organizer records')$$,
 'Authorized committee can verify an external registration with a reason'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000006');
select extensions.lives_ok(
 $$insert into pg_temp.ucems_flow_state(name,token) values('external_attendance_token',public.issue_attendance_token((select id from pg_temp.ucems_flow_state where name='proposal_external')))$$,
 'Verified external registrant can receive an attendance token'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000002');
select extensions.lives_ok(
 $$select public.cancel_event((select id from pg_temp.ucems_flow_state where name='proposal_external'),'Venue became unavailable')$$,
 'Authorized committee can cancel a published event with a reason'
);
select extensions.is(
 (select event_lifecycle from public.proposals where id=(select id from pg_temp.ucems_flow_state where name='proposal_external')),
 'cancelled','Cancellation updates the event lifecycle'
);
select extensions.is(
 (select status from public.registrations where id=(select id from pg_temp.ucems_flow_state where name='external_registration')),
 'cancelled','Cancellation revokes existing registration'
);
reset role;

set local role authenticated;
select pg_temp.assume_user('11110000-0000-0000-0000-000000000001');
select extensions.lives_ok(
 $$select public.admin_set_committee_permission('22220000-0000-0000-0000-000000000001','President','badge.authorize',false)$$,
 'Admin can disable badge authorization for an explicit permission test'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000002');
select extensions.throws_ok(
 $$select public.decide_badge_candidate((select (payload->>'badge_candidate_id')::uuid from pg_temp.ucems_flow_state where name='attendance_token'),true,'Authorized reason')$$,
 'P0001','badge.authorize permission required for this club','Committee without badge permission cannot authorize a badge'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000001');
select extensions.lives_ok(
 $$select public.admin_set_committee_permission('22220000-0000-0000-0000-000000000001','President','badge.authorize',true)$$,
 'Admin can grant badge authorization permission'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000002');
select extensions.lives_ok(
 $$select public.decide_badge_candidate((select (payload->>'badge_candidate_id')::uuid from pg_temp.ucems_flow_state where name='attendance_token'),true,'Attendance verified')$$,
 'Authorized committee can approve a badge candidate with a reason'
);
reset role;
select extensions.is(
 (select count(*) from public.badges where proposal_id=(select id from pg_temp.ucems_flow_state where name='proposal1') and authorized_by='11110000-0000-0000-0000-000000000002'),
 1::bigint,'Approved badge is stored with its authorizer'
);
set local role authenticated;
select pg_temp.assume_user('11110000-0000-0000-0000-000000000006');
select extensions.is(
 (select count(*) from public.payment_orders where id='44440000-0000-0000-0000-000000000001'),
 0::bigint,'RLS hides another student payment order'
);
select extensions.is(
 (select count(*) from public.proposals where id='55550000-0000-0000-0000-000000000001'),
 0::bigint,'RLS hides an unpublished proposal from an unrelated student'
);

select pg_temp.assume_user('11110000-0000-0000-0000-000000000002');
select extensions.lives_ok(
 $$insert into pg_temp.ucems_flow_state(name,id) values('proposal2',public.create_proposal('22220000-0000-0000-0000-000000000001','Version reset event','Versioned approval test',now()+interval '1 day',now()+interval '1 day 1 hour','Test Hall',20,2500))$$,
 'Committee can create a second proposal'
);
select extensions.lives_ok(
 $$select public.submit_proposal((select id from pg_temp.ucems_flow_state where name='proposal2'))$$,
 'Second proposal can be submitted'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000003');
select extensions.lives_ok(
 $$select public.lecturer_decide((select id from pg_temp.ucems_flow_state where name='proposal2'),'approved','')$$,
 'Lecturer can route the second proposal'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000004');
select extensions.lives_ok(
 $$select public.authority_decide((select id from pg_temp.ucems_flow_state where name='proposal2'),'approved','')$$,
 'First authority approves proposal version one'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000005');
select extensions.lives_ok(
 $$select public.authority_decide((select id from pg_temp.ucems_flow_state where name='proposal2'),'changes_requested','Please revise')$$,
 'Second authority can request changes with a reason'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000002');
select extensions.lives_ok(
 $$insert into pg_temp.ucems_flow_state(name,token) values('version2',public.resubmit_proposal((select id from pg_temp.ucems_flow_state where name='proposal2'),'Version reset event revised','Corrected version',now()+interval '1 day',now()+interval '1 day 1 hour','Test Hall',20,2500)::text)$$,
 'Committee can resubmit a corrected version'
);
select extensions.is(
 (select current_version from public.proposals where id=(select id from pg_temp.ucems_flow_state where name='proposal2')),
 2,'Correction creates version two'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000003');
select extensions.lives_ok(
 $$select public.lecturer_decide((select id from pg_temp.ucems_flow_state where name='proposal2'),'approved','')$$,
 'Corrected version restarts lecturer review'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000005');
select extensions.lives_ok(
 $$select public.authority_decide((select id from pg_temp.ucems_flow_state where name='proposal2'),'approved','')$$,
 'Authority can approve corrected version'
);
select extensions.is(
 (select status from public.proposals where id=(select id from pg_temp.ucems_flow_state where name='proposal2')),
 'authority_pending','A version-one approval does not satisfy version-two routing'
);
select extensions.throws_ok(
 $$select public.publish_proposal((select id from pg_temp.ucems_flow_state where name='proposal2'))$$,
 'P0001','event.publish permission required or proposal is not fully approved','Unapproved corrected version cannot be published'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000004');
select extensions.lives_ok(
 $$select public.authority_decide((select id from pg_temp.ucems_flow_state where name='proposal2'),'approved','')$$,
 'Remaining authority can approve corrected version'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000002');
select extensions.lives_ok(
 $$select public.publish_proposal((select id from pg_temp.ucems_flow_state where name='proposal2'))$$,
 'Corrected version publishes only after all version-two approvals'
);

select pg_temp.assume_user('11110000-0000-0000-0000-000000000006');
select extensions.throws_ok(
 $$select public.register_event((select id from pg_temp.ucems_flow_state where name='proposal2'))$$,
 'P0001','Paid checkout is disabled until a payment provider is configured',
 'Paid event registration remains blocked until a provider is selected'
);
select pg_temp.assume_user('11110000-0000-0000-0000-000000000007');
select extensions.throws_ok(
 $$select * from public.prepare_checkout('membership','33330000-0000-0000-0000-000000000001')$$,
 'P0001','Paid checkout is disabled until a payment provider is configured',
 'Database checkout preparation remains disabled without a configured provider'
);
select extensions.throws_ok(
 $$select public.link_checkout('44440000-0000-0000-0000-000000000001','cs_test_ucems')$$,
 'P0001','Service role only','Authenticated student cannot attach a Stripe session'
);
select extensions.throws_ok(
 $$select public.complete_checkout('44440000-0000-0000-0000-000000000001','cs_test_ucems',500,'usd')$$,
 'P0001','Service role only','Authenticated student cannot mark an order paid'
);
reset role;
select set_config('request.jwt.claim.role','service_role',true);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select extensions.lives_ok(
 $$select public.link_checkout('44440000-0000-0000-0000-000000000001','cs_test_ucems')$$,
 'Service role can associate a verified Stripe checkout session'
);
select extensions.throws_ok(
 $$select public.complete_checkout('44440000-0000-0000-0000-000000000001','cs_test_ucems',499,'usd')$$,
 'P0001','Checkout mismatch','Incorrect payment amount is rejected'
);
select extensions.lives_ok(
 $$select public.complete_checkout('44440000-0000-0000-0000-000000000001','cs_test_ucems',500,'usd')$$,
 'Service role can complete a matching test payment'
);
select extensions.is(
 (select status from public.memberships where id='33330000-0000-0000-0000-000000000001'),
 'active','Verified payment activates the membership'
);
select extensions.is(
 (select status from public.payment_orders where id='44440000-0000-0000-0000-000000000001'),
 'paid','Verified payment records a paid order'
);

select * from extensions.finish();
rollback;
