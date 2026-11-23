-- SRS v1.2 foundations: named committee positions, scoped permissions,
-- automatic authority routing, explicit badge authorization, and legacy migration.

alter table public.committee_seats add column position_name text;
update public.committee_seats
set position_name = case seat
 when 1 then 'President'
 when 2 then 'Vice President'
 when 3 then 'Secretary'
 when 4 then 'Vice Secretary'
 when 5 then 'Treasurer'
end;
alter table public.committee_seats alter column position_name set not null;
alter table public.committee_seats
 add constraint committee_seats_position_name_check
 check(position_name in ('President','Vice President','Secretary','Vice Secretary','Treasurer'));
create unique index committee_seats_club_position_unique
 on public.committee_seats(club_id,position_name);

create table public.committee_permission_catalog (
 permission_key text primary key,
 description text not null
);
insert into public.committee_permission_catalog(permission_key,description) values
 ('club.members.view','View club membership records'),
 ('club.members.manage','Review membership requests'),
 ('event.create','Create own-club event drafts'),
 ('event.proposal.submit','Submit proposal versions'),
 ('event.publish','Publish fully approved events'),
 ('proposal.comment','Comment on shared proposal conversations'),
 ('attendance.scan','Scan attendance QR codes'),
 ('attendance.view','View attendance records'),
 ('badge.authorize','Authorize eligible badge candidates')
on conflict(permission_key) do nothing;

create table public.committee_position_permissions (
 club_id uuid not null references public.clubs(id) on delete cascade,
 position_name text not null
  check(position_name in ('President','Vice President','Secretary','Vice Secretary','Treasurer')),
 permission_key text not null references public.committee_permission_catalog(permission_key),
 enabled boolean not null default false,
 updated_by uuid references public.profiles(id),
 updated_at timestamptz not null default now(),
 primary key(club_id,position_name,permission_key)
);

create or replace function private.has_club_permission(p_club uuid,p_permission text)
returns boolean language sql stable security definer set search_path=public,private,pg_temp as $$
 select exists(
  select 1
  from public.committee_seats s
  join public.committee_position_permissions cp
    on cp.club_id=s.club_id and cp.position_name=s.position_name and cp.enabled
  where s.club_id=p_club and s.user_id=auth.uid() and cp.permission_key=p_permission
 )
$$;

alter table public.proposals drop constraint if exists proposals_status_check;
alter table public.proposals add constraint proposals_status_check
 check(status in ('draft','lecturer_pending','authority_pending','routing_exception','changes_requested','rejected','approved_unpublished','published'));

create table public.authority_routing_config (
 id boolean primary key default true check(id),
 revision integer not null default 0,
 updated_by uuid references public.profiles(id),
 updated_at timestamptz not null default now()
);
insert into public.authority_routing_config(id) values(true) on conflict(id) do nothing;
create table public.authority_routing_recipients (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 configured_at timestamptz not null default now()
);
create table public.proposal_authority_assignments (
 proposal_id uuid not null,
 version integer not null,
 reviewer_id uuid not null references public.profiles(id),
 routing_revision integer not null,
 created_at timestamptz not null default now(),
 primary key(proposal_id,version,reviewer_id),
 foreign key(proposal_id,version) references public.proposal_versions(proposal_id,version)
);
insert into public.proposal_authority_assignments(proposal_id,version,reviewer_id,routing_revision)
select p.id,p.current_version,r.user_id,0
from public.proposals p
join public.proposal_reviewers r on r.proposal_id=p.id
where p.status in ('authority_pending','approved_unpublished','published')
on conflict do nothing;

create table public.badge_candidates (
 id uuid primary key default gen_random_uuid(),
 proposal_id uuid not null references public.proposals(id),
 user_id uuid not null references public.profiles(id),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(proposal_id,user_id)
);
create or replace function private.can_view_badge_candidate(p_candidate uuid)
returns boolean language sql stable security definer set search_path=public,private,pg_temp as $$
 select exists(
  select 1 from public.badge_candidates c
  join public.proposals p on p.id=c.proposal_id
  where c.id=p_candidate and (
   private.has_role('admin') or private.has_club_permission(p.club_id,'badge.authorize')
  )
 )
$$;
create table public.badge_authorizations (
 id uuid primary key default gen_random_uuid(),
 candidate_id uuid not null unique references public.badge_candidates(id),
 reviewer_id uuid not null references public.profiles(id),
 decision text not null check(decision in ('approved','rejected')),
 reason text not null check(length(btrim(reason)) between 3 and 2000),
 created_at timestamptz not null default now()
);
alter table public.badges add column authorized_by uuid references public.profiles(id);
alter table public.badges add column authorization_reason text;
alter table public.badges add column candidate_id uuid unique references public.badge_candidates(id);

alter table public.committee_seats enable row level security;
drop policy if exists committee_read on public.committee_seats;
create policy committee_read on public.committee_seats for select to authenticated
 using(user_id=auth.uid() or private.is_committee(club_id) or private.has_role('admin'));
alter table public.committee_permission_catalog enable row level security;
create policy committee_permission_catalog_read on public.committee_permission_catalog
 for select to authenticated using(true);
alter table public.committee_position_permissions enable row level security;
create policy committee_position_permissions_read on public.committee_position_permissions
 for select to authenticated using(
  private.has_role('admin') or exists(
   select 1 from public.committee_seats s
   where s.club_id=committee_position_permissions.club_id
    and s.position_name=committee_position_permissions.position_name and s.user_id=auth.uid()
  )
 );
alter table public.authority_routing_config enable row level security;
alter table public.authority_routing_recipients enable row level security;
create policy authority_routing_admin_read on public.authority_routing_config
 for select to authenticated using(private.has_role('admin'));
create policy authority_routing_recipients_admin_read on public.authority_routing_recipients
 for select to authenticated using(private.has_role('admin'));
alter table public.proposal_authority_assignments enable row level security;
create policy proposal_authority_assignments_read on public.proposal_authority_assignments
 for select to authenticated using(private.is_proposal_stakeholder(proposal_id));
alter table public.badge_candidates enable row level security;
create policy badge_candidates_read on public.badge_candidates
 for select to authenticated using(private.can_view_badge_candidate(id));
alter table public.badge_authorizations enable row level security;
create policy badge_authorizations_read on public.badge_authorizations
 for select to authenticated using(private.can_view_badge_candidate(candidate_id));
drop policy if exists badges_read on public.badges;
create policy badges_read on public.badges for select to authenticated
 using((user_id=auth.uid() and authorized_by is not null) or private.has_role('admin'));
drop policy if exists attendance_read on public.attendance;
create policy attendance_read on public.attendance for select to authenticated using(
 user_id=auth.uid() or private.has_role('admin') or exists(
  select 1 from public.proposals p
  where p.id=proposal_id and private.has_club_permission(p.club_id,'attendance.view')
 )
);
drop policy if exists memberships_read on public.memberships;
create policy memberships_read on public.memberships for select to authenticated using(
 user_id=auth.uid() or private.has_role('admin')
 or private.has_club_permission(club_id,'club.members.view')
 or private.has_club_permission(club_id,'club.members.manage')
);
drop policy if exists registrations_read on public.registrations;
create policy registrations_read on public.registrations for select to authenticated using(
 user_id=auth.uid() or private.has_role('admin') or exists(
  select 1 from public.proposals p
  where p.id=proposal_id and private.has_club_permission(p.club_id,'registration.view')
 )
);
create policy badge_candidate_profiles_read on public.profiles for select to authenticated using(
 exists(
  select 1 from public.badge_candidates c
  join public.proposals p on p.id=c.proposal_id
  where c.user_id=profiles.id and private.has_club_permission(p.club_id,'badge.authorize')
 )
);

create or replace function public.admin_set_committee_permission(
 p_club uuid,p_position text,p_permission text,p_enabled boolean
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 if p_position not in ('President','Vice President','Secretary','Vice Secretary','Treasurer') then
  raise exception 'Invalid committee position';
 end if;
 if not exists(select 1 from public.clubs where id=p_club) then raise exception 'Club not found'; end if;
 if not exists(select 1 from public.committee_permission_catalog where permission_key=p_permission) then
  raise exception 'Unknown committee permission';
 end if;
 if coalesce(p_enabled,false) then
  insert into public.committee_position_permissions(club_id,position_name,permission_key,enabled,updated_by)
  values(p_club,p_position,p_permission,true,auth.uid())
  on conflict(club_id,position_name,permission_key) do update
   set enabled=true,updated_by=auth.uid(),updated_at=now();
 else
  delete from public.committee_position_permissions
  where club_id=p_club and position_name=p_position and permission_key=p_permission;
 end if;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'committee_permission',p_club,'permission_updated',
  jsonb_build_object('position',p_position,'permission',p_permission,'enabled',coalesce(p_enabled,false)));
end;$$;

create or replace function public.admin_set_authority_routing(p_authorities uuid[])
returns integer language plpgsql security definer set search_path=public,private,pg_temp as $$
declare next_revision integer; selected_count integer;
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 perform 1 from public.authority_routing_config where id=true for update;
 if coalesce(cardinality(p_authorities),0)>0 and exists(
  select 1 from unnest(p_authorities) as requested(user_id)
  where not exists(
   select 1 from public.user_roles r where r.user_id=requested.user_id and r.role='authority'
  )
 ) then raise exception 'Every routing recipient must have the authority role'; end if;
 delete from public.authority_routing_recipients;
 insert into public.authority_routing_recipients(user_id)
 select distinct requested.user_id from unnest(coalesce(p_authorities,'{}'::uuid[])) as requested(user_id)
 on conflict(user_id) do nothing;
 get diagnostics selected_count=row_count;
 update public.authority_routing_config
 set revision=revision+1,updated_by=auth.uid(),updated_at=now()
 where id=true returning revision into next_revision;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'approval_routing','00000000-0000-0000-0000-000000000000'::uuid,
  'routing_recipients_updated',jsonb_build_object('revision',next_revision,'recipient_count',selected_count));
 return next_revision;
end;$$;

create or replace function public.admin_assign_committee(p_club uuid,p_seat integer,p_user uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare position_label text;
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 position_label:=case p_seat
  when 1 then 'President'
  when 2 then 'Vice President'
  when 3 then 'Secretary'
  when 4 then 'Vice Secretary'
  when 5 then 'Treasurer'
  else null
 end;
 if position_label is null then raise exception 'Choose one of the five committee positions'; end if;
 if not exists(select 1 from public.clubs where id=p_club) then raise exception 'Club not found'; end if;
 if not exists(select 1 from public.profiles where id=p_user) then raise exception 'Account not found'; end if;
 delete from public.committee_seats where club_id=p_club and (seat=p_seat or user_id=p_user);
 insert into public.committee_seats(club_id,seat,position_name,user_id)
 values(p_club,p_seat,position_label,p_user);
 insert into public.user_roles(user_id,role) values(p_user,'committee') on conflict do nothing;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'committee_assignment',p_club,'position_assigned',
  jsonb_build_object('user_id',p_user,'position',position_label));
end;$$;

create or replace function public.admin_migrate_organizer_assignment(
 p_club uuid,p_user uuid,p_seat integer
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare position_label text; existing_seat integer;
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 select seat into existing_seat from public.committee_seats
 where club_id=p_club and user_id=p_user;
 if found then
  delete from public.club_organizers where club_id=p_club and user_id=p_user;
  if not exists(select 1 from public.club_organizers where user_id=p_user) then
   delete from public.user_roles where user_id=p_user and role='organizer';
  end if;
  insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
  values(auth.uid(),'committee_assignment',p_club,'legacy_organizer_merged',
   jsonb_build_object('user_id',p_user,'position',case existing_seat
    when 1 then 'President' when 2 then 'Vice President' when 3 then 'Secretary'
    when 4 then 'Vice Secretary' when 5 then 'Treasurer' end));
  return;
 end if;
 position_label:=case p_seat
  when 1 then 'President'
  when 2 then 'Vice President'
  when 3 then 'Secretary'
  when 4 then 'Vice Secretary'
  when 5 then 'Treasurer'
  else null
 end;
 if position_label is null then raise exception 'Choose one of the five committee positions'; end if;
 if not exists(select 1 from public.club_organizers where club_id=p_club and user_id=p_user) then
  raise exception 'Legacy organizer assignment not found';
 end if;
 if exists(select 1 from public.committee_seats where club_id=p_club and user_id=p_user) then
  raise exception 'This account already has a committee position in this club; keep that position and configure its permissions';
 end if;
 insert into public.committee_seats(club_id,seat,position_name,user_id)
 values(p_club,p_seat,position_label,p_user);
 delete from public.club_organizers where club_id=p_club and user_id=p_user;
 insert into public.user_roles(user_id,role) values(p_user,'committee') on conflict do nothing;
 if not exists(select 1 from public.club_organizers where user_id=p_user) then
  delete from public.user_roles where user_id=p_user and role='organizer';
 end if;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'committee_assignment',p_club,'legacy_organizer_migrated',
  jsonb_build_object('user_id',p_user,'position',position_label));
end;$$;

create or replace function public.admin_assign_role(p_user uuid,p_role text)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 if p_user is null then raise exception 'A valid account is required'; end if;
 if p_role is null or p_role not in ('student','committee','lecturer','authority','admin') then
  raise exception 'Invalid role; Organizer is not an assignable system role';
 end if;
 insert into public.user_roles(user_id,role) values(p_user,p_role) on conflict do nothing;
end;$$;

create or replace function public.admin_update_user_role(p_user uuid,p_old_role text,p_new_role text)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 if p_user is null or p_old_role is null or p_new_role is null or p_old_role=p_new_role then
  raise exception 'A valid account and two different roles are required';
 end if;
 if p_user=auth.uid() then raise exception 'Admins cannot change their own roles'; end if;
 if p_old_role not in ('student','committee','lecturer','authority','organizer','admin')
   or p_new_role not in ('student','committee','lecturer','authority','admin') then
  raise exception 'Invalid role; Organizer cannot be newly assigned';
 end if;
 if p_old_role='admin' then
  perform pg_advisory_xact_lock(175631,1);
  if not exists(select 1 from public.user_roles where role='admin' and user_id<>p_user) then
   raise exception 'Cannot remove the last administrator';
  end if;
 end if;
 delete from public.user_roles where user_id=p_user and role=p_old_role;
 if not found then raise exception 'Role assignment not found'; end if;
 insert into public.user_roles(user_id,role) values(p_user,p_new_role) on conflict do nothing;
end;$$;

create or replace function public.admin_remove_user_role(p_user uuid,p_role text)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 if p_user is null or p_role is null
   or p_role not in ('student','committee','lecturer','authority','organizer','admin') then
  raise exception 'A valid account and role are required';
 end if;
 if p_user=auth.uid() then raise exception 'Admins cannot remove their own roles'; end if;
 if p_role='admin' then
  perform pg_advisory_xact_lock(175631,1);
  if not exists(select 1 from public.user_roles where role='admin' and user_id<>p_user) then
   raise exception 'Cannot remove the last administrator';
  end if;
 end if;
 delete from public.user_roles where user_id=p_user and role=p_role;
 if not found then raise exception 'Role assignment not found'; end if;
end;$$;

create or replace function public.create_proposal(
 p_club uuid,p_title text,p_description text,p_starts_at timestamptz,p_ends_at timestamptz,
 p_venue text,p_capacity int,p_fee_cents int default 0
) returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare x uuid;
begin
 if auth.uid() is null or not private.has_club_permission(p_club,'event.create') then
  raise exception 'event.create permission required for this club';
 end if;
 insert into public.proposals(club_id,created_by) values(p_club,auth.uid()) returning id into x;
 insert into public.proposal_versions(proposal_id,version,title,description,starts_at,ends_at,venue,capacity,fee_cents)
 values(x,1,p_title,coalesce(p_description,''),p_starts_at,p_ends_at,p_venue,p_capacity,p_fee_cents);
 insert into public.audit_log(actor_id,entity_type,entity_id,action)
 values(auth.uid(),'proposal',x,'draft_created');
 return x;
end;$$;

create or replace function public.submit_proposal(p_proposal uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.proposals;
begin
 select * into p from public.proposals where id=p_proposal for update;
 if not found or p.status<>'draft'
  or not private.has_club_permission(p.club_id,'event.proposal.submit') then
  raise exception 'event.proposal.submit permission required or proposal is not a draft';
 end if;
 if not exists(select 1 from public.clubs where id=p.club_id and lecturer_id is not null) then
  raise exception 'Lecturer must be assigned';
 end if;
 update public.proposals set status='lecturer_pending',updated_at=now() where id=p.id;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'proposal',p.id,'submitted',jsonb_build_object('version',p.current_version));
end;$$;

create or replace function public.lecturer_decide(p_proposal uuid,p_decision text,p_comment text default '')
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.proposals; reviewer_count integer; routing_revision integer;
begin
 select * into p from public.proposals where id=p_proposal for update;
 if not found or not private.is_lecturer(p.club_id) or p.status<>'lecturer_pending' then
  raise exception 'Not authorized or not awaiting lecturer';
 end if;
 if p_decision not in ('approved','changes_requested','rejected') then raise exception 'Invalid decision'; end if;
 if p_decision<>'approved' and length(btrim(coalesce(p_comment,'')))<3 then
  raise exception 'Provide a reason of at least 3 characters';
 end if;
 insert into public.review_decisions(proposal_id,version,reviewer_id,stage,decision,comment)
 values(p.id,p.current_version,auth.uid(),'lecturer',p_decision,coalesce(p_comment,''));
 if p_decision='approved' then
  select revision into routing_revision from public.authority_routing_config where id=true;
  insert into public.proposal_reviewers(proposal_id,user_id)
  select p.id,r.user_id from public.authority_routing_recipients r
  join public.user_roles ur on ur.user_id=r.user_id and ur.role='authority'
  on conflict do nothing;
  insert into public.proposal_authority_assignments(proposal_id,version,reviewer_id,routing_revision)
  select p.id,p.current_version,r.user_id,coalesce(routing_revision,0)
  from public.authority_routing_recipients r
  join public.user_roles ur on ur.user_id=r.user_id and ur.role='authority'
  on conflict do nothing;
  get diagnostics reviewer_count=row_count;
  update public.proposals
   set status=case when reviewer_count>0 then 'authority_pending' else 'routing_exception' end,
       updated_at=now()
   where id=p.id;
  insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
  values(auth.uid(),'proposal',p.id,
   case when reviewer_count>0 then 'authority_routed' else 'authority_routing_exception' end,
   jsonb_build_object('version',p.current_version,'routing_revision',coalesce(routing_revision,0),'reviewer_count',reviewer_count));
 else
  update public.proposals
   set status=case when p_decision='rejected' then 'rejected' else 'changes_requested' end,
       updated_at=now()
   where id=p.id;
 end if;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'proposal',p.id,'lecturer_'||p_decision,
  jsonb_build_object('version',p.current_version,'comment',p_comment));
end;$$;

create or replace function public.admin_retry_authority_routing(p_proposal uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.proposals; reviewer_count integer; routing_revision integer;
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 select * into p from public.proposals where id=p_proposal for update;
 if not found or p.status<>'routing_exception' then raise exception 'Proposal has no routing exception'; end if;
 select revision into routing_revision from public.authority_routing_config where id=true;
 insert into public.proposal_reviewers(proposal_id,user_id)
 select p.id,r.user_id from public.authority_routing_recipients r
 join public.user_roles ur on ur.user_id=r.user_id and ur.role='authority'
 on conflict do nothing;
 insert into public.proposal_authority_assignments(proposal_id,version,reviewer_id,routing_revision)
 select p.id,p.current_version,r.user_id,coalesce(routing_revision,0)
 from public.authority_routing_recipients r
 join public.user_roles ur on ur.user_id=r.user_id and ur.role='authority'
 on conflict do nothing;
 get diagnostics reviewer_count=row_count;
 if reviewer_count=0 then raise exception 'Configure at least one active Higher Authority recipient before retrying'; end if;
 update public.proposals set status='authority_pending',updated_at=now() where id=p.id;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'proposal',p.id,'authority_routing_retried',
  jsonb_build_object('version',p.current_version,'routing_revision',routing_revision,'reviewer_count',reviewer_count));
end;$$;

create or replace function public.authority_decide(p_proposal uuid,p_decision text,p_comment text default '')
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.proposals; all_ok boolean;
begin
 select * into p from public.proposals where id=p_proposal for update;
 if not found or p.status<>'authority_pending' then raise exception 'Not awaiting higher authorities'; end if;
 if not exists(
  select 1 from public.proposal_authority_assignments a
  where a.proposal_id=p.id and a.version=p.current_version and a.reviewer_id=auth.uid()
 ) then raise exception 'You are not assigned to review this version'; end if;
 if not exists(
  select 1 from public.review_decisions d
  where d.proposal_id=p.id and d.version=p.current_version and d.stage='lecturer' and d.decision='approved'
 ) then raise exception 'Lecturer approval required for this version'; end if;
 if p_decision not in ('approved','changes_requested','rejected') then raise exception 'Invalid decision'; end if;
 if p_decision<>'approved' and length(btrim(coalesce(p_comment,'')))<3 then
  raise exception 'Provide a reason of at least 3 characters';
 end if;
 insert into public.review_decisions(proposal_id,version,reviewer_id,stage,decision,comment)
 values(p.id,p.current_version,auth.uid(),'authority',p_decision,coalesce(p_comment,''));
 if p_decision<>'approved' then
  update public.proposals set status=case when p_decision='rejected' then 'rejected' else 'changes_requested' end,
   updated_at=now() where id=p.id;
 else
  select count(*)>0 and not exists(
   select 1 from public.proposal_authority_assignments a
   where a.proposal_id=p.id and a.version=p.current_version and not exists(
    select 1 from public.review_decisions d
    where d.proposal_id=a.proposal_id and d.version=a.version and d.reviewer_id=a.reviewer_id
      and d.stage='authority' and d.decision='approved'
   )
  ) into all_ok;
  if all_ok then update public.proposals set status='approved_unpublished',updated_at=now() where id=p.id; end if;
 end if;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'proposal',p.id,'authority_'||p_decision,
  jsonb_build_object('version',p.current_version,'comment',p_comment));
end;$$;

create or replace function public.resubmit_proposal(
 p_proposal uuid,p_title text,p_description text,p_starts_at timestamptz,p_ends_at timestamptz,
 p_venue text,p_capacity int,p_fee_cents int default 0
) returns int language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.proposals; v int;
begin
 select * into p from public.proposals where id=p_proposal for update;
 if not found or not private.has_club_permission(p.club_id,'event.proposal.submit')
   or p.status<>'changes_requested' then
  raise exception 'event.proposal.submit permission required or proposal is not returned for corrections';
 end if;
 v:=p.current_version+1;
 insert into public.proposal_versions(proposal_id,version,title,description,starts_at,ends_at,venue,capacity,fee_cents)
 values(p.id,v,p_title,coalesce(p_description,''),p_starts_at,p_ends_at,p_venue,p_capacity,p_fee_cents);
 update public.proposals set current_version=v,status='lecturer_pending',updated_at=now() where id=p.id;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'proposal',p.id,'resubmitted',jsonb_build_object('version',v));
 return v;
end;$$;

create or replace function public.publish_proposal(p_proposal uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.proposals; ok boolean;
begin
 select * into p from public.proposals where id=p_proposal for update;
 if not found or not private.has_club_permission(p.club_id,'event.publish')
   or p.status<>'approved_unpublished' then
  raise exception 'event.publish permission required or proposal is not fully approved';
 end if;
 if not exists(
  select 1 from public.review_decisions d where d.proposal_id=p.id and d.version=p.current_version
   and d.stage='lecturer' and d.decision='approved'
 ) then raise exception 'Current lecturer approval missing'; end if;
 select count(*)>0 and not exists(
  select 1 from public.proposal_authority_assignments a
  where a.proposal_id=p.id and a.version=p.current_version and not exists(
   select 1 from public.review_decisions d
   where d.proposal_id=a.proposal_id and d.version=a.version and d.reviewer_id=a.reviewer_id
    and d.stage='authority' and d.decision='approved'
  )
 ) into ok;
 if not ok then raise exception 'All assigned authorities must approve current version'; end if;
 update public.proposals set status='published',published_at=now(),updated_at=now() where id=p.id;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'proposal',p.id,'published',jsonb_build_object('version',p.current_version));
end;$$;

create or replace function public.add_proposal_comment(p_proposal uuid,p_body text)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.proposals; x uuid;
begin
 select * into p from public.proposals where id=p_proposal;
 if not found or not(
  private.has_role('admin') or private.is_lecturer(p.club_id)
  or exists(select 1 from public.proposal_reviewers r where r.proposal_id=p.id and r.user_id=auth.uid())
  or private.has_club_permission(p.club_id,'proposal.comment')
 ) then raise exception 'Proposal comment permission required'; end if;
 if length(btrim(coalesce(p_body,''))) not between 1 and 3000 then
  raise exception 'Comment must contain 1-3000 characters';
 end if;
 insert into public.proposal_comments(proposal_id,version,author_id,body)
 values(p.id,p.current_version,auth.uid(),p_body) returning id into x;
 return x;
end;$$;

create or replace function public.decide_membership(p_membership uuid,p_approve boolean)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare m public.memberships; fee int;
begin
 select * into m from public.memberships where id=p_membership for update;
 if not found or not private.has_club_permission(m.club_id,'club.members.manage') or m.status<>'pending' then
  raise exception 'club.members.manage permission required or application is not pending';
 end if;
 select membership_fee_cents into fee from public.clubs where id=m.club_id;
 update public.memberships
 set status=case when not p_approve then 'rejected' when fee>0 then 'payment_due' else 'active' end
 where id=m.id;
end;$$;

create or replace function public.scan_attendance_token(p_token text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare t public.attendance_tokens;p public.proposals;v public.proposal_versions;candidate_id uuid;
begin
 if auth.uid() is null or length(coalesce(p_token,''))<>64 then raise exception 'Invalid QR token'; end if;
 select * into t from public.attendance_tokens
 where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if not found or t.used_at is not null or t.expires_at<now() then
  raise exception 'QR expired or already used';
 end if;
 select * into p from public.proposals where id=t.proposal_id;
 if not private.has_club_permission(p.club_id,'attendance.scan') then
  raise exception 'attendance.scan permission required for this club';
 end if;
 select * into v from public.proposal_versions where proposal_id=p.id and version=p.current_version;
 if now() not between v.starts_at-interval '2 hours' and v.ends_at+interval '2 hours' then
  raise exception 'Check-in not open';
 end if;
 if not exists(
  select 1 from public.registrations where proposal_id=p.id and user_id=t.user_id and status='registered'
 ) then raise exception 'No valid registration'; end if;
 update public.attendance_tokens set used_at=now() where token_hash=t.token_hash;
 insert into public.attendance(proposal_id,user_id,checked_by)
 values(p.id,t.user_id,auth.uid()) on conflict(proposal_id,user_id) do nothing;
 insert into public.badge_candidates(proposal_id,user_id)
 values(p.id,t.user_id) on conflict(proposal_id,user_id) do nothing
 returning id into candidate_id;
 if candidate_id is null then
  select id into candidate_id from public.badge_candidates
  where proposal_id=p.id and user_id=t.user_id;
 end if;
 return jsonb_build_object('ok',true,'proposal_id',p.id,'student_id',t.user_id,
  'badge_candidate_id',candidate_id,'badge_issued',false);
end;$$;

create or replace function public.decide_badge_candidate(
 p_candidate uuid,p_approve boolean,p_reason text
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare c public.badge_candidates; p public.proposals; decision text;
begin
 select * into c from public.badge_candidates where id=p_candidate for update;
 if not found then raise exception 'Badge candidate not found'; end if;
 select * into p from public.proposals where id=c.proposal_id;
 if not private.has_club_permission(p.club_id,'badge.authorize') then
  raise exception 'badge.authorize permission required for this club';
 end if;
 if c.status<>'pending' then raise exception 'Badge candidate has already been decided'; end if;
 if length(btrim(coalesce(p_reason,''))) not between 3 and 2000 then
  raise exception 'Provide a reason of at least 3 characters';
 end if;
 decision:=case when p_approve then 'approved' else 'rejected' end;
 insert into public.badge_authorizations(candidate_id,reviewer_id,decision,reason)
 values(c.id,auth.uid(),decision,btrim(p_reason));
 update public.badge_candidates set status=decision,updated_at=now() where id=c.id;
 if p_approve then
  insert into public.badges(proposal_id,user_id,authorized_by,authorization_reason,candidate_id)
  values(c.proposal_id,c.user_id,auth.uid(),btrim(p_reason),c.id)
  on conflict(proposal_id,user_id) do update
   set authorized_by=excluded.authorized_by,
       authorization_reason=excluded.authorization_reason,
       candidate_id=excluded.candidate_id;
 end if;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'badge_candidate',c.id,'badge_'||decision,
  jsonb_build_object('proposal_id',c.proposal_id,'student_id',c.user_id,'reason',btrim(p_reason)));
end;$$;

revoke insert,update,delete,truncate,references,trigger on table
 public.committee_permission_catalog,public.committee_position_permissions,
 public.authority_routing_config,public.authority_routing_recipients,
 public.proposal_authority_assignments,public.badge_candidates,public.badge_authorizations
 from public,anon,authenticated;
revoke insert,update,delete,truncate,references,trigger on table public.badges
 from public,anon,authenticated;
grant select on public.committee_permission_catalog,public.committee_position_permissions,
 public.authority_routing_config,public.authority_routing_recipients,
 public.proposal_authority_assignments,public.badge_candidates,public.badge_authorizations to authenticated;
revoke all on function private.has_club_permission(uuid,text),
 private.can_view_badge_candidate(uuid) from public,anon;
grant execute on function private.has_club_permission(uuid,text),
 private.can_view_badge_candidate(uuid) to authenticated;
grant execute on function public.admin_set_committee_permission(uuid,text,text,boolean),
 public.admin_set_authority_routing(uuid[]),public.admin_migrate_organizer_assignment(uuid,uuid,integer),
 public.admin_retry_authority_routing(uuid),public.decide_badge_candidate(uuid,boolean,text) to authenticated;

revoke all on function public.admin_assign_organizer(uuid,uuid),
 public.admin_replace_club_organizer(uuid,uuid,uuid),
 public.admin_remove_club_organizer(uuid,uuid),
 public.admin_assign_reviewer(uuid,uuid) from public,anon,authenticated;
revoke all on function public.admin_set_committee_permission(uuid,text,text,boolean),
 public.admin_set_authority_routing(uuid[]),public.admin_migrate_organizer_assignment(uuid,uuid,integer),
 public.admin_retry_authority_routing(uuid),public.decide_badge_candidate(uuid,boolean,text)
 from public,anon;
