-- Registration policies, internal forms, external verification, and event cancellation.

alter table public.proposals
 add column if not exists event_lifecycle text not null default 'scheduled'
  check(event_lifecycle in ('scheduled','ongoing','completed','cancelled'));

alter table public.proposal_versions
 add column if not exists event_category text not null default 'General',
 add column if not exists purpose text not null default '',
 add column if not exists eligibility_policy text not null default 'all_students'
  check(eligibility_policy in ('all_students','club_members')),
 add column if not exists registration_required boolean not null default true,
 add column if not exists registration_method text not null default 'internal'
  check(registration_method in ('internal','external','none')),
 add column if not exists registration_deadline timestamptz,
 add column if not exists external_registration_url text,
 add column if not exists registration_form_schema jsonb not null default '[]'::jsonb
  check(jsonb_typeof(registration_form_schema)='array'),
 add column if not exists fee_lkr bigint not null default 0 check(fee_lkr>=0),
 add column if not exists budget_lkr bigint not null default 0 check(budget_lkr>=0),
 add column if not exists change_reason text not null default '';

alter table public.proposal_versions
 add constraint proposal_versions_external_url_check
 check(registration_method<>'external' or external_registration_url ~ '^https://');

alter table public.registrations
 add column if not exists form_answers jsonb not null default '{}'::jsonb
  check(jsonb_typeof(form_answers)='object'),
 add column if not exists verification_status text not null default 'not_required'
  check(verification_status in ('not_required','pending','verified','not_verified')),
 add column if not exists external_reference text,
 add column if not exists verification_reason text,
 add column if not exists verified_by uuid references public.profiles(id),
 add column if not exists verified_at timestamptz,
 add column if not exists confirmation_code text not null
  default upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));

create unique index if not exists registrations_confirmation_code_unique
 on public.registrations(confirmation_code);

drop policy if exists registrations_read on public.registrations;
create policy registrations_read on public.registrations for select to authenticated using(
 user_id=auth.uid() or private.has_role('admin') or exists(
  select 1 from public.proposals p where p.id=proposal_id and (
   private.has_club_permission(p.club_id,'registration.view')
   or private.has_club_permission(p.club_id,'registration.manage')
   or private.has_club_permission(p.club_id,'registration.verify_external')
  )
 )
);
create policy registration_profiles_read on public.profiles for select to authenticated using(
 exists(
  select 1 from public.registrations r join public.proposals p on p.id=r.proposal_id
  where r.user_id=profiles.id and private.has_club_permission(p.club_id,'registration.view')
 )
);

insert into public.committee_permission_catalog(permission_key,description) values
 ('event.edit','Edit own-club event details'),
 ('event.cancel','Cancel an own-club event'),
 ('registration.view','View own-club event registrations'),
 ('registration.manage','Manage own-club event registrations'),
 ('registration.verify_external','Verify external registrations'),
 ('registration.export','Export permitted event participants'),
 ('club.members.policy','Configure own-club membership policy'),
 ('badge.define','Define own-club badge criteria'),
 ('badge.nominate','Nominate badge candidates'),
 ('finance.view','View own-club financial records'),
 ('finance.refund.approve','Approve own-club refund requests'),
 ('finance.reconcile','Reconcile own-club settlements'),
 ('finance.export','Export own-club finance reports')
on conflict(permission_key) do nothing;

insert into public.committee_position_permissions(club_id,position_name,permission_key,enabled)
select c.id,p.position_name,pc.permission_key,true
from public.clubs c
cross join (values ('President'),('Vice President'),('Secretary'),('Vice Secretary'),('Treasurer')) p(position_name)
cross join public.committee_permission_catalog pc
where pc.permission_key in (
 'event.edit','event.cancel','registration.view','registration.manage',
 'registration.verify_external','registration.export','club.members.policy',
 'badge.define','badge.nominate','finance.view','finance.refund.approve',
 'finance.reconcile','finance.export'
)
on conflict(club_id,position_name,permission_key) do nothing;

create table public.registration_verification_history (
 id uuid primary key default gen_random_uuid(),
 registration_id uuid not null references public.registrations(id),
 reviewer_id uuid not null references public.profiles(id),
 decision text not null check(decision in ('verified','not_verified')),
 reason text not null check(length(btrim(reason)) between 3 and 2000),
 created_at timestamptz not null default now()
);
alter table public.registration_verification_history enable row level security;
create policy registration_verification_history_read on public.registration_verification_history
 for select to authenticated using(
  exists(select 1 from public.registrations r where r.id=registration_id and (
   r.user_id=auth.uid() or private.has_role('admin') or exists(
    select 1 from public.proposals p
    where p.id=r.proposal_id and private.has_club_permission(p.club_id,'registration.view')
   )
  ))
 );
grant select on public.registration_verification_history to authenticated;

create or replace function private.validate_registration_answers(
 p_schema jsonb,p_answers jsonb,p_check_required boolean default true
)
returns void language plpgsql immutable set search_path=public,pg_temp as $$
declare field jsonb; field_key text; field_type text; field_value jsonb;
begin
 if jsonb_typeof(coalesce(p_schema,'[]'::jsonb))<>'array'
  or jsonb_typeof(coalesce(p_answers,'{}'::jsonb))<>'object' then
  raise exception 'Invalid registration form data';
 end if;
 if octet_length(coalesce(p_answers,'{}'::jsonb)::text)>32768 then
  raise exception 'Registration answers exceed the size limit';
 end if;
 if jsonb_array_length(p_schema)>40 then raise exception 'Registration form has too many fields'; end if;
 if exists(
  select 1 from jsonb_array_elements(p_schema) f(value)
  group by f.value->>'key' having count(*)>1
 ) then raise exception 'Registration form field keys must be unique'; end if;
 for field in select value from jsonb_array_elements(p_schema) loop
  field_key:=field->>'key'; field_type:=field->>'type';
  if field_key is null or field_key !~ '^[a-z][a-z0-9_]{0,39}$'
   or field_type not in ('text','email','number','select','checkbox')
   or nullif(btrim(field->>'label'),'') is null then
   raise exception 'Event registration form contains an invalid field';
  end if;
  if field_type='select' then
   if coalesce(jsonb_array_length(
    case when jsonb_typeof(field->'options')='array' then field->'options' else '[]'::jsonb end
   ),0)=0 then
    raise exception 'Select field "%" needs at least one option',field->>'label';
   end if;
   if exists(
    select 1 from jsonb_array_elements(field->'options') option(value)
    where jsonb_typeof(option.value)<>'string' or length(option.value#>>'{}')>200
   ) then raise exception 'Select options must be short text values'; end if;
  end if;
  field_value:=p_answers->field_key;
  if p_check_required and coalesce((field->>'required')::boolean,false)
   and (field_value is null or field_value='null'::jsonb or field_value='""'::jsonb) then
   raise exception 'Required registration field "%" is missing',field->>'label';
  end if;
  if field_value is null or field_value='null'::jsonb then continue; end if;
  if field_type in ('text','email','select') and jsonb_typeof(field_value)<>'string' then
   raise exception 'Registration field "%" must be text',field->>'label';
  end if;
  if field_type='number' and jsonb_typeof(field_value)<>'number' then
   raise exception 'Registration field "%" must be numeric',field->>'label';
  end if;
  if field_type='checkbox' and jsonb_typeof(field_value)<>'boolean' then
   raise exception 'Registration field "%" must be true or false',field->>'label';
  end if;
  if field_type='checkbox' and p_check_required
   and coalesce((field->>'required')::boolean,false) and field_value='false'::jsonb then
   raise exception 'Required registration field "%" must be checked',field->>'label';
  end if;
  if field_type in ('text','email','select') and length(field_value#>>'{}')>5000 then
   raise exception 'Registration field "%" exceeds the length limit',field->>'label';
  end if;
  if field_type='email' and (field_value#>>'{}') !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
   raise exception 'Registration field "%" must be a valid email address',field->>'label';
  end if;
  if field_type='select' and not (coalesce(field->'options','[]'::jsonb) ? (field_value#>>'{}')) then
   raise exception 'Registration field "%" has an invalid option',field->>'label';
  end if;
 end loop;
 if exists(
  select 1 from jsonb_object_keys(p_answers) answer(key)
  where not exists(
   select 1 from jsonb_array_elements(p_schema) f(value) where f.value->>'key'=answer.key
  )
 ) then raise exception 'Registration contains an unknown form field'; end if;
end;$$;

create or replace function public.configure_proposal_registration(
 p_proposal uuid,p_event_category text,p_purpose text,p_eligibility_policy text,
 p_registration_required boolean,p_registration_method text,p_registration_deadline timestamptz,
 p_external_registration_url text,p_form_schema jsonb,p_fee_lkr bigint,p_budget_lkr bigint
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.proposals;
begin
 select * into p from public.proposals where id=p_proposal for update;
 if not found or p.status<>'draft'
  or not private.has_club_permission(p.club_id,'event.edit') then
  raise exception 'event.edit permission required and proposal must be a draft';
 end if;
 if p_registration_method is null or p_eligibility_policy is null
  or p_registration_method not in ('internal','external','none')
  or p_eligibility_policy not in ('all_students','club_members') then
  raise exception 'Invalid registration policy';
 end if;
 if p_registration_method='external'
  and coalesce(p_external_registration_url,'') !~ '^https://[^[:space:]]+$' then
  raise exception 'External registration requires an HTTPS URL';
 end if;
 if p_registration_method<>'external' and p_external_registration_url is not null then
  raise exception 'External URL is only valid for external registration';
 end if;
 if p_registration_method='none' and p_registration_required then
  raise exception 'Registration cannot be required when registration is disabled';
 end if;
 if p_registration_method='internal' then
  perform private.validate_registration_answers(coalesce(p_form_schema,'[]'::jsonb),'{}'::jsonb,false);
 elsif coalesce(p_form_schema,'[]'::jsonb)<>'[]'::jsonb then
  raise exception 'Form fields are only supported for internal registration';
 end if;
 if p_registration_deadline is not null and p_registration_deadline> (
  select starts_at from public.proposal_versions
  where proposal_id=p.id and version=p.current_version
 ) then raise exception 'Registration deadline must be before the event starts'; end if;
 if coalesce(p_fee_lkr,0)<0 or coalesce(p_budget_lkr,0)<0 then
  raise exception 'Fee and budget must be non-negative';
 end if;
 update public.proposal_versions set
  event_category=coalesce(nullif(btrim(p_event_category),''),'General'),
  purpose=coalesce(p_purpose,''),
  eligibility_policy=p_eligibility_policy,
  registration_required=p_registration_required,
  registration_method=p_registration_method,
  registration_deadline=p_registration_deadline,
  external_registration_url=p_external_registration_url,
  registration_form_schema=coalesce(p_form_schema,'[]'::jsonb),
  fee_lkr=coalesce(p_fee_lkr,0),
  budget_lkr=coalesce(p_budget_lkr,0)
 where proposal_id=p.id and version=p.current_version;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'proposal',p.id,'registration_policy_configured',
  jsonb_build_object('version',p.current_version,'method',p_registration_method,
   'required',p_registration_required,'eligibility',p_eligibility_policy));
end;$$;

create or replace function public.create_proposal_with_registration(
 p_club uuid,p_title text,p_description text,p_starts_at timestamptz,p_ends_at timestamptz,
 p_venue text,p_capacity integer,p_event_category text,p_purpose text,p_eligibility_policy text,
 p_registration_required boolean,p_registration_method text,p_registration_deadline timestamptz,
 p_external_registration_url text,p_form_schema jsonb,p_fee_lkr bigint,p_budget_lkr bigint
) returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare proposal_id uuid;
begin
 proposal_id:=public.create_proposal(p_club,p_title,p_description,p_starts_at,p_ends_at,p_venue,p_capacity,0);
 perform public.configure_proposal_registration(proposal_id,p_event_category,p_purpose,
  p_eligibility_policy,p_registration_required,p_registration_method,p_registration_deadline,
  p_external_registration_url,p_form_schema,p_fee_lkr,p_budget_lkr);
 return proposal_id;
end;$$;

create or replace function public.resubmit_proposal_with_registration(
 p_proposal uuid,p_title text,p_description text,p_starts_at timestamptz,p_ends_at timestamptz,
 p_venue text,p_capacity integer,p_event_category text,p_purpose text,p_eligibility_policy text,
 p_registration_required boolean,p_registration_method text,p_registration_deadline timestamptz,
 p_external_registration_url text,p_form_schema jsonb,p_fee_lkr bigint,p_budget_lkr bigint,
 p_change_reason text
) returns integer language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.proposals; v public.proposal_versions; next_version integer;
begin
 select * into p from public.proposals where id=p_proposal for update;
 if not found or p.status<>'changes_requested'
  or not private.has_club_permission(p.club_id,'event.proposal.submit') then
  raise exception 'event.proposal.submit permission required or proposal is not returned for changes';
 end if;
 if length(btrim(coalesce(p_change_reason,'')))<3 then raise exception 'Provide a reason for this revision'; end if;
 if p_registration_method is null or p_eligibility_policy is null
  or p_registration_method not in ('internal','external','none')
  or p_eligibility_policy not in ('all_students','club_members') then
  raise exception 'Invalid registration policy';
 end if;
 if p_registration_method='external'
  and coalesce(p_external_registration_url,'') !~ '^https://[^[:space:]]+$' then
  raise exception 'External registration requires an HTTPS URL';
 end if;
 if p_registration_method<>'external' and p_external_registration_url is not null then
  raise exception 'External URL is only valid for external registration';
 end if;
 if p_registration_method='none' and p_registration_required then
  raise exception 'Registration cannot be required when registration is disabled';
 end if;
 if p_registration_method='internal' then
  perform private.validate_registration_answers(coalesce(p_form_schema,'[]'::jsonb),'{}'::jsonb,false);
 elsif coalesce(p_form_schema,'[]'::jsonb)<>'[]'::jsonb then
  raise exception 'Form fields are only supported for internal registration';
 end if;
 if coalesce(p_fee_lkr,0)<0 or coalesce(p_budget_lkr,0)<0 then
  raise exception 'Fee and budget must be non-negative';
 end if;
 if p_registration_deadline is not null and p_registration_deadline>p_starts_at then
  raise exception 'Registration deadline must be before the event starts';
 end if;
 select * into v from public.proposal_versions
 where proposal_id=p.id and version=p.current_version;
 next_version:=p.current_version+1;
 insert into public.proposal_versions(
  proposal_id,version,title,description,starts_at,ends_at,venue,capacity,fee_cents,
  event_category,purpose,eligibility_policy,registration_required,registration_method,
  registration_deadline,external_registration_url,registration_form_schema,fee_lkr,budget_lkr,change_reason
 ) values(
  p.id,next_version,p_title,coalesce(p_description,''),p_starts_at,p_ends_at,p_venue,p_capacity,0,
  coalesce(nullif(btrim(p_event_category),''),'General'),coalesce(p_purpose,''),p_eligibility_policy,
  p_registration_required,p_registration_method,p_registration_deadline,p_external_registration_url,
  coalesce(p_form_schema,'[]'::jsonb),coalesce(p_fee_lkr,0),coalesce(p_budget_lkr,0),btrim(p_change_reason)
 );
 update public.proposals set current_version=next_version,status='lecturer_pending',updated_at=now()
 where id=p.id;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'proposal',p.id,'resubmitted',
  jsonb_build_object('version',next_version,'change_reason',btrim(p_change_reason)));
 return next_version;
end;$$;

create or replace function public.register_event_with_answers(p_proposal uuid,p_answers jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.proposals; v public.proposal_versions; n integer; x uuid;
begin
 if auth.uid() is null or not private.has_role('student') then raise exception 'Student sign-in required'; end if;
 select * into p from public.proposals where id=p_proposal for update;
 if not found or p.status<>'published' or p.event_lifecycle='cancelled' then
  raise exception 'Event is not open for registration';
 end if;
 select * into v from public.proposal_versions
 where proposal_id=p.id and version=coalesce(p.published_version,p.current_version);
 if not found then raise exception 'Published event version not found'; end if;
 if v.registration_method='none' then
  raise exception 'This event does not require registration';
 end if;
 if v.registration_method<>'internal' then
  raise exception 'Use external registration for this event';
 end if;
 if v.ends_at<=now() then raise exception 'Event has ended'; end if;
 if v.registration_deadline is not null and now()>v.registration_deadline then
  raise exception 'Registration deadline has passed';
 end if;
 if v.fee_lkr>0 or v.fee_cents>0 then
  raise exception 'Paid checkout is disabled until a payment provider is configured';
 end if;
 if v.eligibility_policy='club_members' and not exists(
  select 1 from public.memberships m where m.club_id=p.club_id and m.user_id=auth.uid() and m.status='active'
 ) then raise exception 'Active club membership is required to register'; end if;
 perform private.validate_registration_answers(v.registration_form_schema,coalesce(p_answers,'{}'::jsonb));
 if exists(select 1 from public.registrations where proposal_id=p.id and user_id=auth.uid()) then
  select id into x from public.registrations where proposal_id=p.id and user_id=auth.uid();
  return x;
 end if;
 select count(*) into n from public.registrations where proposal_id=p.id and status<>'cancelled';
 if n>=v.capacity then raise exception 'Event is full'; end if;
 insert into public.registrations(proposal_id,version,user_id,status,form_answers,verification_status)
 values(p.id,v.version,auth.uid(),'registered',coalesce(p_answers,'{}'::jsonb),'not_required')
 returning id into x;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'registration',x,'registration_submitted',
  jsonb_build_object('proposal_id',p.id,'version',v.version,
   'confirmation_code',(select confirmation_code from public.registrations where id=x)));
 return x;
end;$$;

create or replace function public.register_event(p_proposal uuid)
returns uuid language sql security definer set search_path=public,private,pg_temp as $$
 select public.register_event_with_answers(p_proposal,'{}'::jsonb)
$$;

create or replace function public.claim_external_registration(p_proposal uuid,p_external_reference text)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.proposals; v public.proposal_versions; x uuid; n integer;
begin
 if auth.uid() is null or not private.has_role('student') then raise exception 'Student sign-in required'; end if;
 select * into p from public.proposals where id=p_proposal for update;
 if not found or p.status<>'published' or p.event_lifecycle='cancelled' then
  raise exception 'Event is not open for registration';
 end if;
 select * into v from public.proposal_versions
 where proposal_id=p.id and version=coalesce(p.published_version,p.current_version);
 if not found or v.registration_method<>'external' then
  raise exception 'Event does not use external registration';
 end if;
 if v.registration_deadline is not null and now()>v.registration_deadline then
  raise exception 'Registration deadline has passed';
 end if;
 if v.fee_lkr>0 or v.fee_cents>0 then
  raise exception 'Paid checkout is disabled until a payment provider is configured';
 end if;
 if v.eligibility_policy='club_members' and not exists(
  select 1 from public.memberships m where m.club_id=p.club_id and m.user_id=auth.uid() and m.status='active'
 ) then raise exception 'Active club membership is required to register'; end if;
 if length(btrim(coalesce(p_external_reference,''))) not between 1 and 500 then
  raise exception 'Provide an external submission reference or explanation';
 end if;
 if exists(select 1 from public.registrations where proposal_id=p.id and user_id=auth.uid()) then
  select id into x from public.registrations where proposal_id=p.id and user_id=auth.uid();
  return x;
 end if;
 select count(*) into n from public.registrations where proposal_id=p.id and status<>'cancelled';
 if n>=v.capacity then raise exception 'Event is full'; end if;
 insert into public.registrations(proposal_id,version,user_id,status,verification_status,external_reference)
 values(p.id,v.version,auth.uid(),'registered','pending',btrim(p_external_reference)) returning id into x;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'registration',x,'external_registration_claimed',
  jsonb_build_object('proposal_id',p.id,'version',v.version));
 return x;
end;$$;

create or replace function public.verify_external_registration(
 p_registration uuid,p_verified boolean,p_reason text
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare r public.registrations; p public.proposals; decision text;
begin
 select * into r from public.registrations where id=p_registration for update;
 if not found or r.verification_status<>'pending' then
  raise exception 'External registration is not awaiting verification';
 end if;
 select * into p from public.proposals where id=r.proposal_id;
 if not private.has_club_permission(p.club_id,'registration.verify_external') then
  raise exception 'registration.verify_external permission required';
 end if;
 if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Provide a verification reason'; end if;
 decision:=case when p_verified then 'verified' else 'not_verified' end;
 update public.registrations set verification_status=decision,verified_by=auth.uid(),
  verified_at=now(),verification_reason=btrim(p_reason) where id=r.id;
 insert into public.registration_verification_history(registration_id,reviewer_id,decision,reason)
 values(r.id,auth.uid(),decision,btrim(p_reason));
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'registration',r.id,'external_registration_'||decision,
  jsonb_build_object('proposal_id',r.proposal_id,'student_id',r.user_id,'reason',btrim(p_reason)));
 perform private.insert_notification(r.user_id,extensions.gen_random_uuid(),
  'registration.'||decision,
  case when p_verified then 'External registration verified' else 'External registration not verified' end,
  'registration',r.id,auth.uid());
end;$$;

create table public.event_cancellations (
 id uuid primary key default gen_random_uuid(),
 proposal_id uuid not null unique references public.proposals(id),
 cancelled_by uuid not null references public.profiles(id),
 reason text not null check(length(btrim(reason)) between 3 and 2000),
 created_at timestamptz not null default now()
);

create or replace function private.require_verified_registration_for_attendance()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if not exists(
  select 1 from public.registrations r where r.proposal_id=new.proposal_id
   and r.version=new.version and r.user_id=new.user_id and r.status='registered'
   and r.verification_status in ('not_required','verified')
 ) then raise exception 'Verified event registration required for attendance'; end if;
 return new;
end;$$;
create trigger require_verified_registration_for_attendance
 before insert on public.attendance for each row
 execute function private.require_verified_registration_for_attendance();

create trigger require_verified_registration_for_token
 before insert on public.attendance_tokens for each row
 execute function private.require_verified_registration_for_attendance();

create table public.refund_requests (
 id uuid primary key default gen_random_uuid(),
 payment_order_id uuid not null unique references public.payment_orders(id),
 registration_id uuid references public.registrations(id),
 proposal_id uuid not null references public.proposals(id),
 club_id uuid not null references public.clubs(id),
 amount_minor bigint not null check(amount_minor>0),
 currency text not null,
 cancellation_reason text not null,
 status text not null default 'awaiting_approval'
  check(status in ('awaiting_approval','rejected','approved','processing','completed','failed')),
 provider_status text not null default 'not_configured'
  check(provider_status in ('not_configured','pending','succeeded','failed')),
 reviewed_by uuid references public.profiles(id),
 reviewed_at timestamptz,
 review_reason text,
 provider_ref text,
 provider_updated_at timestamptz,
 created_at timestamptz not null default now()
);

alter table public.event_cancellations enable row level security;
alter table public.refund_requests enable row level security;
create policy event_cancellations_read on public.event_cancellations
 for select to authenticated using(
  private.has_role('admin') or private.is_proposal_stakeholder(proposal_id)
  or exists(select 1 from public.proposals p where p.id=proposal_id and p.published_version is not null)
 );
create policy refund_requests_read on public.refund_requests
 for select to authenticated using(
  exists(select 1 from public.payment_orders po where po.id=payment_order_id and po.user_id=auth.uid())
  or private.has_role('admin')
  or private.has_club_permission(club_id,'finance.view')
  or private.has_club_permission(club_id,'finance.refund.approve')
 );
create policy payments_finance_read on public.payment_orders for select to authenticated using(
 user_id=auth.uid() or private.has_role('admin')
 or exists(select 1 from public.registrations r
  where r.id=reference_id and kind='registration'
   and private.has_club_permission((select p.club_id from public.proposals p where p.id=r.proposal_id),'finance.view'))
);
grant select on public.event_cancellations,public.refund_requests to authenticated;

create or replace function public.cancel_event(p_proposal uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.proposals; cancelled_count integer;
begin
 select * into p from public.proposals where id=p_proposal for update;
 if not found or p.status<>'published' or p.event_lifecycle='cancelled'
  or not private.has_club_permission(p.club_id,'event.cancel') then
  raise exception 'event.cancel permission required and event must be published';
 end if;
 if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Provide an event cancellation reason'; end if;
 insert into public.event_cancellations(proposal_id,cancelled_by,reason)
 values(p.id,auth.uid(),btrim(p_reason));
 update public.proposals set event_lifecycle='cancelled',updated_at=now() where id=p.id;
 update public.registrations set status='cancelled' where proposal_id=p.id and status<>'cancelled';
 get diagnostics cancelled_count=row_count;
 insert into public.refund_requests(payment_order_id,registration_id,proposal_id,club_id,
  amount_minor,currency,cancellation_reason)
 select po.id,r.id,p.id,p.club_id,po.amount_cents,po.currency,btrim(p_reason)
 from public.registrations r
 join public.payment_orders po on po.kind='registration' and po.reference_id=r.id and po.status='paid'
 where r.proposal_id=p.id
 on conflict(payment_order_id) do nothing;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'event',p.id,'cancelled',
  jsonb_build_object('reason',btrim(p_reason),'cancelled_registrations',cancelled_count));
 perform private.insert_notification(r.user_id,extensions.gen_random_uuid(),'event.cancelled',
  'An event you registered for has been cancelled: '||btrim(p_reason),'event',p.id,auth.uid())
 from public.registrations r where r.proposal_id=p.id;
end;$$;

create or replace function public.decide_refund_request(p_refund uuid,p_approve boolean,p_reason text)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare r public.refund_requests;
begin
 select * into r from public.refund_requests where id=p_refund for update;
 if not found or r.status<>'awaiting_approval' then raise exception 'Refund is not awaiting approval'; end if;
 if not private.has_club_permission(r.club_id,'finance.refund.approve') then
  raise exception 'finance.refund.approve permission required';
 end if;
 if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Provide a refund decision reason'; end if;
 update public.refund_requests set status=case when p_approve then 'approved' else 'rejected' end,
  provider_status=case when p_approve then 'not_configured' else provider_status end,
  reviewed_by=auth.uid(),reviewed_at=now(),review_reason=btrim(p_reason)
 where id=r.id;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'refund',r.id,case when p_approve then 'approved_waiting_provider' else 'rejected' end,
  jsonb_build_object('proposal_id',r.proposal_id,'amount_minor',r.amount_minor,
   'currency',r.currency,'reason',btrim(p_reason)));
 perform private.insert_notification(po.user_id,extensions.gen_random_uuid(),
  case when p_approve then 'refund.approved_pending_provider' else 'refund.rejected' end,
  case when p_approve then 'Refund approved; gateway processing is not configured yet'
       else 'Refund request rejected: '||btrim(p_reason) end,'refund',r.id,auth.uid())
 from public.payment_orders po where po.id=r.payment_order_id;
end;$$;

create index if not exists registrations_event_status_idx
 on public.registrations(proposal_id,status,verification_status);
create index if not exists refund_requests_club_status_idx
 on public.refund_requests(club_id,status,created_at desc);
create index if not exists registration_verification_history_registration_idx
 on public.registration_verification_history(registration_id,created_at desc);

revoke all on function private.validate_registration_answers(jsonb,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.configure_proposal_registration(uuid,text,text,text,boolean,text,timestamptz,text,jsonb,bigint,bigint),
 public.create_proposal_with_registration(uuid,text,text,timestamptz,timestamptz,text,integer,text,text,text,boolean,text,timestamptz,text,jsonb,bigint,bigint),
 public.resubmit_proposal_with_registration(uuid,text,text,timestamptz,timestamptz,text,integer,text,text,text,boolean,text,timestamptz,text,jsonb,bigint,bigint,text) to authenticated;
grant execute on function public.register_event_with_answers(uuid,jsonb),public.register_event(uuid),
 public.claim_external_registration(uuid,text),public.verify_external_registration(uuid,boolean,text),
 public.cancel_event(uuid,text),public.decide_refund_request(uuid,boolean,text) to authenticated;
