-- UCEMS V1 | Supabase Postgres | Apply once to a fresh Supabase project.
-- Business rules: committee(5 seats), lecturer first, all assigned peer authorities must approve
-- EACH proposal version; every revision restarts lecturer review.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default 'Student', created_at timestamptz not null default now()
);
create table public.user_roles (
 user_id uuid not null references public.profiles(id) on delete cascade,
 role text not null check(role in ('student','committee','lecturer','authority','organizer','admin')),
 primary key(user_id,role)
);
create table public.clubs (
 id uuid primary key default gen_random_uuid(),
 name text not null unique, description text not null default '', category text not null default 'General',
 lecturer_id uuid references public.profiles(id), membership_fee_cents int not null default 0 check(membership_fee_cents>=0),
 created_at timestamptz not null default now()
);
create table public.committee_seats (
 club_id uuid not null references public.clubs(id) on delete cascade,
 seat smallint not null check(seat between 1 and 5), user_id uuid not null references public.profiles(id),
 primary key(club_id,seat),unique(club_id,user_id)
);
create table public.club_organizers (
 club_id uuid not null references public.clubs(id) on delete cascade,
 user_id uuid not null references public.profiles(id),primary key(club_id,user_id)
);
create table public.proposals (
 id uuid primary key default gen_random_uuid(),club_id uuid not null references public.clubs(id),
 created_by uuid not null references public.profiles(id),current_version int not null default 1 check(current_version>0),
 status text not null default 'draft' check(status in ('draft','lecturer_pending','authority_pending','changes_requested','rejected','approved_unpublished','published')),
 published_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table public.proposal_versions (
 proposal_id uuid not null references public.proposals(id) on delete cascade,
 version int not null check(version>0),title text not null,description text not null default '',
 starts_at timestamptz not null,ends_at timestamptz not null,venue text not null,
 capacity int not null check(capacity between 1 and 20000),fee_cents int not null default 0 check(fee_cents>=0),
 created_at timestamptz not null default now(),
 primary key(proposal_id,version),check(ends_at>starts_at),check(length(btrim(title))>=4)
);
create table public.proposal_reviewers (
 proposal_id uuid not null references public.proposals(id) on delete cascade,
 user_id uuid not null references public.profiles(id),primary key(proposal_id,user_id)
);
create table public.review_decisions (
 id uuid primary key default gen_random_uuid(),proposal_id uuid not null references public.proposals(id),
 version int not null,reviewer_id uuid not null references public.profiles(id),
 stage text not null check(stage in ('lecturer','authority')),
 decision text not null check(decision in ('approved','changes_requested','rejected')),
 comment text not null default '',created_at timestamptz not null default now(),
 unique(proposal_id,version,reviewer_id,stage),
 foreign key(proposal_id,version) references public.proposal_versions(proposal_id,version)
);
create table public.proposal_comments (
 id uuid primary key default gen_random_uuid(),proposal_id uuid not null references public.proposals(id),
 version int not null,author_id uuid not null references public.profiles(id),
 body text not null check(length(btrim(body)) between 1 and 3000),created_at timestamptz not null default now(),
 foreign key(proposal_id,version) references public.proposal_versions(proposal_id,version)
);
create table public.memberships (
 id uuid primary key default gen_random_uuid(),club_id uuid not null references public.clubs(id),
 user_id uuid not null references public.profiles(id),
 status text not null default 'pending' check(status in ('pending','payment_due','active','rejected')),
 created_at timestamptz not null default now(),unique(club_id,user_id)
);
create table public.registrations (
 id uuid primary key default gen_random_uuid(),proposal_id uuid not null references public.proposals(id),
 user_id uuid not null references public.profiles(id),
 status text not null check(status in ('payment_due','registered','cancelled')),
 created_at timestamptz not null default now(),unique(proposal_id,user_id)
);
create table public.payment_orders (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id),
 kind text not null check(kind in ('membership','registration')),
 reference_id uuid not null,amount_cents int not null check(amount_cents>0),currency text not null default 'usd',
 status text not null default 'pending' check(status in ('pending','paid','failed')),
 stripe_session_id text unique,created_at timestamptz not null default now(),paid_at timestamptz
);
create table public.attendance_tokens (
 token_hash text primary key,proposal_id uuid not null references public.proposals(id),
 user_id uuid not null references public.profiles(id),expires_at timestamptz not null,used_at timestamptz
);
create table public.attendance (
 id uuid primary key default gen_random_uuid(),proposal_id uuid not null references public.proposals(id),
 user_id uuid not null references public.profiles(id),checked_by uuid not null references public.profiles(id),
 checked_at timestamptz not null default now(),unique(proposal_id,user_id)
);
create table public.badges (
 id uuid primary key default gen_random_uuid(),proposal_id uuid not null references public.proposals(id),
 user_id uuid not null references public.profiles(id),issued_at timestamptz not null default now(),
 unique(proposal_id,user_id)
);
create table public.audit_log (
 id bigint generated always as identity primary key,actor_id uuid,entity_type text not null,
 entity_id uuid not null,action text not null,details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index on public.proposals(club_id,status);
create index on public.proposals(status,published_at);
create index on public.review_decisions(proposal_id,version);
create index on public.proposal_reviewers(user_id);
create index on public.registrations(user_id,status);
create index on public.memberships(user_id,status);
create index on public.attendance_tokens(expires_at);

create function public.on_auth_created() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 insert into public.profiles(id,full_name) values(new.id,coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(new.email,'@',1))) on conflict(id) do nothing;
 insert into public.user_roles(user_id,role) values(new.id,'student') on conflict do nothing;
 return new;
end;$$;
create trigger auth_created after insert on auth.users for each row execute function public.on_auth_created();

create schema if not exists private;
create function private.has_role(p_role text) returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from public.user_roles where user_id=auth.uid() and role=p_role)
$$;
create function private.is_committee(p_club uuid) returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from public.committee_seats where club_id=p_club and user_id=auth.uid())
$$;
create function private.is_lecturer(p_club uuid) returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from public.clubs where id=p_club and lecturer_id=auth.uid())
$$;
create function private.is_proposal_stakeholder(p_id uuid) returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from public.proposals p where p.id=p_id and (
 private.has_role('admin') or private.is_committee(p.club_id) or private.is_lecturer(p.club_id)
 or exists(select 1 from public.proposal_reviewers r where r.proposal_id=p.id and r.user_id=auth.uid())))
$$;
create function private.can_view_proposal(p_id uuid) returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from public.proposals p where p.id=p_id and (
 p.status='published' or private.has_role('admin') or private.is_committee(p.club_id) or private.is_lecturer(p.club_id)
 or exists(select 1 from public.proposal_reviewers r where r.proposal_id=p.id and r.user_id=auth.uid())))
$$;

-- Read-only policies. All business mutations are granted ONLY through validated RPCs below.
alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.clubs enable row level security;
alter table public.committee_seats enable row level security;
alter table public.club_organizers enable row level security;
alter table public.proposals enable row level security;
alter table public.proposal_versions enable row level security;
alter table public.proposal_reviewers enable row level security;
alter table public.review_decisions enable row level security;
alter table public.proposal_comments enable row level security;
alter table public.memberships enable row level security;
alter table public.registrations enable row level security;
alter table public.payment_orders enable row level security;
alter table public.attendance_tokens enable row level security;
alter table public.attendance enable row level security;
alter table public.badges enable row level security;
alter table public.audit_log enable row level security;
create policy profiles_read on public.profiles for select to authenticated using (id=auth.uid() or private.has_role('admin'));
create policy roles_read on public.user_roles for select to authenticated using (user_id=auth.uid() or private.has_role('admin'));
create policy clubs_read on public.clubs for select to authenticated using(true);
create policy committee_read on public.committee_seats for select to authenticated using(true);
create policy organizers_read on public.club_organizers for select to authenticated using(user_id=auth.uid() or private.is_committee(club_id) or private.has_role('admin'));
create policy proposals_read on public.proposals for select to authenticated using(private.can_view_proposal(id));
create policy versions_read on public.proposal_versions for select to authenticated using(
 private.is_proposal_stakeholder(proposal_id) or exists(
 select 1 from public.proposals p where p.id=proposal_id and p.status='published' and p.current_version=version)
);
create policy reviewers_read on public.proposal_reviewers for select to authenticated using(private.is_proposal_stakeholder(proposal_id));
create policy decisions_read on public.review_decisions for select to authenticated using(private.is_proposal_stakeholder(proposal_id));
create policy comments_read on public.proposal_comments for select to authenticated using(private.is_proposal_stakeholder(proposal_id));
create policy memberships_read on public.memberships for select to authenticated using(user_id=auth.uid() or private.is_committee(club_id) or private.has_role('admin'));
create policy registrations_read on public.registrations for select to authenticated using(user_id=auth.uid() or private.can_view_proposal(proposal_id) and exists (select 1 from public.proposals p where p.id=proposal_id and (private.is_committee(p.club_id) or private.has_role('admin'))));
create policy payments_read on public.payment_orders for select to authenticated using(user_id=auth.uid() or private.has_role('admin'));
create policy attendance_read on public.attendance for select to authenticated using(user_id=auth.uid() or exists(select 1 from public.proposals p where p.id=proposal_id and (private.is_committee(p.club_id) or private.has_role('admin') or exists(select 1 from public.club_organizers o where o.club_id=p.club_id and o.user_id=auth.uid()))));
create policy badges_read on public.badges for select to authenticated using(user_id=auth.uid() or private.has_role('admin'));
create policy audit_read on public.audit_log for select to authenticated using(actor_id=auth.uid() or private.has_role('admin'));

-- All RPCs run as the DB owner. Each checks auth.uid() and enforces business rules explicitly.
create function public.admin_assign_role(p_user uuid,p_role text) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 if p_role not in('student','committee','lecturer','authority','organizer','admin') then raise exception 'Invalid role'; end if;
 insert into public.user_roles(user_id,role) values(p_user,p_role) on conflict do nothing;
end;$$;
create function public.admin_create_club(p_name text,p_description text default '',p_category text default 'General',p_fee_cents int default 0) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare x uuid;
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 insert into public.clubs(name,description,category,membership_fee_cents) values(btrim(p_name),coalesce(p_description,''),coalesce(p_category,'General'),p_fee_cents) returning id into x;
 return x;
end;$$;
create function public.admin_assign_lecturer(p_club uuid,p_user uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 update public.clubs set lecturer_id=p_user where id=p_club;
 if not found then raise exception 'Club not found'; end if;
 insert into public.user_roles values(p_user,'lecturer') on conflict do nothing;
end;$$;
create function public.admin_assign_committee(p_club uuid,p_seat int,p_user uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 if p_seat not between 1 and 5 then raise exception 'Seat must be 1-5'; end if;
 delete from public.committee_seats where club_id=p_club and (seat=p_seat or user_id=p_user);
 insert into public.committee_seats(club_id,seat,user_id) values(p_club,p_seat,p_user);
 insert into public.user_roles values(p_user,'committee') on conflict do nothing;
end;$$;
create function public.admin_assign_organizer(p_club uuid,p_user uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 insert into public.club_organizers values(p_club,p_user) on conflict do nothing;
 insert into public.user_roles values(p_user,'organizer') on conflict do nothing;
end;$$;
create function public.admin_assign_reviewer(p_proposal uuid,p_user uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 if not exists(select 1 from public.user_roles where user_id=p_user and role='authority') then raise exception 'User must have authority role'; end if;
 if not exists(select 1 from public.proposals where id=p_proposal and status='draft') then raise exception 'Reviewers only editable on draft'; end if;
 insert into public.proposal_reviewers values(p_proposal,p_user) on conflict do nothing;
end;$$;
create function public.create_proposal(p_club uuid,p_title text,p_description text,p_starts_at timestamptz,p_ends_at timestamptz,p_venue text,p_capacity int,p_fee_cents int default 0) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare x uuid;
begin
 if auth.uid() is null or not private.is_committee(p_club) then raise exception 'Club committee permission required'; end if;
 insert into public.proposals(club_id,created_by) values(p_club,auth.uid()) returning id into x;
 insert into public.proposal_versions(proposal_id,version,title,description,starts_at,ends_at,venue,capacity,fee_cents)
 values(x,1,p_title,coalesce(p_description,''),p_starts_at,p_ends_at,p_venue,p_capacity,p_fee_cents);
 insert into public.audit_log(actor_id,entity_type,entity_id,action) values(auth.uid(),'proposal',x,'draft_created');
 return x;
end;$$;
create function public.submit_proposal(p_proposal uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare p public.proposals; n int;
begin
 select * into p from public.proposals where id=p_proposal for update;
 if not found or not private.is_committee(p.club_id) or p.status<>'draft' then raise exception 'Cannot submit this proposal'; end if;
 if not exists(select 1 from public.clubs where id=p.club_id and lecturer_id is not null) then raise exception 'Lecturer must be assigned'; end if;
 select count(*) into n from public.proposal_reviewers where proposal_id=p.id;
 if n<1 then raise exception 'Assign at least one higher authority before submission'; end if;
 update public.proposals set status='lecturer_pending',updated_at=now() where id=p.id;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details) values(auth.uid(),'proposal',p.id,'submitted',jsonb_build_object('version',p.current_version));
end;$$;
create function public.lecturer_decide(p_proposal uuid,p_decision text,p_comment text default '') returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare p public.proposals;
begin
 select * into p from public.proposals where id=p_proposal for update;
 if not found or not private.is_lecturer(p.club_id) or p.status<>'lecturer_pending' then raise exception 'Not authorized or not awaiting lecturer'; end if;
 if p_decision not in ('approved','changes_requested','rejected') then raise exception 'Invalid decision'; end if;
 insert into public.review_decisions(proposal_id,version,reviewer_id,stage,decision,comment)
 values(p.id,p.current_version,auth.uid(),'lecturer',p_decision,coalesce(p_comment,''));
 update public.proposals set status=case when p_decision='approved' then 'authority_pending' when p_decision='rejected' then 'rejected' else 'changes_requested' end,updated_at=now() where id=p.id;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details) values(auth.uid(),'proposal',p.id,'lecturer_'||p_decision,jsonb_build_object('version',p.current_version,'comment',p_comment));
end;$$;
create function public.authority_decide(p_proposal uuid,p_decision text,p_comment text default '') returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare p public.proposals; all_ok boolean;
begin
 select * into p from public.proposals where id=p_proposal for update;
 if not found or p.status<>'authority_pending' then raise exception 'Not awaiting higher authorities'; end if;
 if not exists(select 1 from public.proposal_reviewers where proposal_id=p.id and user_id=auth.uid()) then raise exception 'You are not an assigned reviewer'; end if;
 if not exists(select 1 from public.review_decisions d where d.proposal_id=p.id and d.version=p.current_version and d.stage='lecturer' and d.decision='approved') then raise exception 'Lecturer approval required for this version'; end if;
 if p_decision not in ('approved','changes_requested','rejected') then raise exception 'Invalid decision'; end if;
 insert into public.review_decisions(proposal_id,version,reviewer_id,stage,decision,comment) values(p.id,p.current_version,auth.uid(),'authority',p_decision,coalesce(p_comment,''));
 if p_decision<>'approved' then
 update public.proposals set status=case when p_decision='rejected' then 'rejected' else 'changes_requested' end,updated_at=now() where id=p.id;
 else
 select count(*)>0 and not exists(
 select 1 from public.proposal_reviewers r where r.proposal_id=p.id and not exists(
 select 1 from public.review_decisions d where d.proposal_id=p.id and d.version=p.current_version and d.reviewer_id=r.user_id and d.stage='authority' and d.decision='approved'))
 into all_ok from public.proposal_reviewers where proposal_id=p.id;
 if all_ok then update public.proposals set status='approved_unpublished',updated_at=now() where id=p.id; end if;
 end if;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details) values(auth.uid(),'proposal',p.id,'authority_'||p_decision,jsonb_build_object('version',p.current_version,'comment',p_comment));
end;$$;
create function public.resubmit_proposal(p_proposal uuid,p_title text,p_description text,p_starts_at timestamptz,p_ends_at timestamptz,p_venue text,p_capacity int,p_fee_cents int default 0) returns int language plpgsql security definer set search_path=public,pg_temp as $$
declare p public.proposals; v int;
begin
 select * into p from public.proposals where id=p_proposal for update;
 if not found or not private.is_committee(p.club_id) or p.status<>'changes_requested' then raise exception 'Proposal is not returned for corrections'; end if;
 v:=p.current_version+1;
 insert into public.proposal_versions(proposal_id,version,title,description,starts_at,ends_at,venue,capacity,fee_cents)
 values(p.id,v,p_title,coalesce(p_description,''),p_starts_at,p_ends_at,p_venue,p_capacity,p_fee_cents);
 update public.proposals set current_version=v,status='lecturer_pending',updated_at=now() where id=p.id;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details) values(auth.uid(),'proposal',p.id,'resubmitted',jsonb_build_object('version',v));
 return v;
end;$$;
create function public.publish_proposal(p_proposal uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare p public.proposals; ok boolean;
begin
 select * into p from public.proposals where id=p_proposal for update;
 if not found or not private.is_committee(p.club_id) or p.status<>'approved_unpublished' then raise exception 'Not eligible to publish'; end if;
 if not exists(select 1 from public.review_decisions d where d.proposal_id=p.id and d.version=p.current_version and d.stage='lecturer' and d.decision='approved') then raise exception 'Current lecturer approval missing'; end if;
 select count(*)>0 and not exists(select 1 from public.proposal_reviewers r where r.proposal_id=p.id and not exists(
 select 1 from public.review_decisions d where d.proposal_id=p.id and d.version=p.current_version and d.reviewer_id=r.user_id and d.stage='authority' and d.decision='approved')) into ok from public.proposal_reviewers where proposal_id=p.id;
 if not ok then raise exception 'All assigned authorities must approve current version'; end if;
 update public.proposals set status='published',published_at=now(),updated_at=now() where id=p.id;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details) values(auth.uid(),'proposal',p.id,'published',jsonb_build_object('version',p.current_version));
end;$$;

create function public.add_proposal_comment(p_proposal uuid,p_body text) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare p public.proposals; x uuid;
begin
 select * into p from public.proposals where id=p_proposal;
 if not found or not private.is_proposal_stakeholder(p.id) then raise exception 'Proposal access required'; end if;
 if length(btrim(coalesce(p_body,''))) not between 1 and 3000 then raise exception 'Comment must contain 1-3000 characters'; end if;
 insert into public.proposal_comments(proposal_id,version,author_id,body) values(p.id,p.current_version,auth.uid(),p_body) returning id into x;
 return x;
end;$$;
create function public.apply_membership(p_club uuid) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare x uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 insert into public.memberships(club_id,user_id) values(p_club,auth.uid()) on conflict (club_id,user_id) do nothing;
 select id into x from public.memberships where club_id=p_club and user_id=auth.uid();
 return x;
end;$$;
create function public.decide_membership(p_membership uuid,p_approve boolean) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare m public.memberships; fee int;
begin
 select * into m from public.memberships where id=p_membership for update;
 if not found or not private.is_committee(m.club_id) or m.status<>'pending' then raise exception 'Not permitted or application not pending'; end if;
 select membership_fee_cents into fee from public.clubs where id=m.club_id;
 update public.memberships set status=case when not p_approve then 'rejected' when fee>0 then 'payment_due' else 'active' end where id=m.id;
end;$$;
create function public.register_event(p_proposal uuid) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare p public.proposals; v public.proposal_versions; n int;x uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into p from public.proposals where id=p_proposal for update;
 if not found or p.status<>'published' then raise exception 'Not published'; end if;
 select * into v from public.proposal_versions where proposal_id=p.id and version=p.current_version;
 if v.ends_at<=now() then raise exception 'Event has ended'; end if;
 if exists(select 1 from public.registrations where proposal_id=p.id and user_id=auth.uid()) then
 select id into x from public.registrations where proposal_id=p.id and user_id=auth.uid();return x;
 end if;
 select count(*) into n from public.registrations where proposal_id=p.id and status <> 'cancelled';
 if n>=v.capacity then raise exception 'Event is full'; end if;
 insert into public.registrations(proposal_id,user_id,status) values(p.id,auth.uid(),case when v.fee_cents>0 then 'payment_due' else 'registered' end) returning id into x;
 return x;
end;$$;
create function public.prepare_checkout(p_kind text,p_reference uuid) returns table(order_id uuid,amount_cents int,currency text,label text) language plpgsql security definer set search_path=public,pg_temp as $$
declare fee int; title text; x uuid;
begin
 if auth.uid() is null or p_kind not in ('membership','registration') then raise exception 'Invalid checkout'; end if;
 if p_kind='membership' then
 select c.membership_fee_cents,c.name into fee,title from public.memberships m join public.clubs c on c.id=m.club_id where m.id=p_reference and m.user_id=auth.uid() and m.status='payment_due';
 else
 select v.fee_cents,v.title into fee,title from public.registrations r join public.proposals p on p.id=r.proposal_id join public.proposal_versions v on v.proposal_id=p.id and v.version=p.current_version where r.id=p_reference and r.user_id=auth.uid() and r.status='payment_due';
 end if;
 if fee is null or fee<=0 then raise exception 'No payment is due'; end if;
 insert into public.payment_orders(user_id,kind,reference_id,amount_cents) values(auth.uid(),p_kind,p_reference,fee) returning id into x;
 return query select x,fee,'usd'::text,title;
end;$$;
create function public.link_checkout(p_order uuid,p_session text) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.role()<>'service_role' then raise exception 'Service role only'; end if;
 update public.payment_orders set stripe_session_id=p_session where id=p_order and status='pending';
 if not found then raise exception 'Missing pending order'; end if;
end;$$;
create function public.complete_checkout(p_order uuid,p_session text,p_amount int,p_currency text) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare o public.payment_orders;
begin
 if auth.role()<>'service_role' then raise exception 'Service role only'; end if;
 select * into o from public.payment_orders where id=p_order for update;
 if not found then raise exception 'Order not found'; end if;
 if o.status='paid' then return; end if;
 if o.amount_cents<>p_amount or o.currency<>lower(p_currency) or o.stripe_session_id is distinct from p_session then raise exception 'Checkout mismatch'; end if;
 update public.payment_orders set status='paid',paid_at=now() where id=o.id;
 if o.kind='membership' then update public.memberships set status='active' where id=o.reference_id and user_id=o.user_id and status='payment_due';
 else update public.registrations set status='registered' where id=o.reference_id and user_id=o.user_id and status='payment_due'; end if;
end;$$;

-- 90-second QR tokens are random, hashed at rest, checked by server & single-use.
create function public.issue_attendance_token(p_proposal uuid) returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare t text; v public.proposal_versions;
begin
 if auth.uid() is null or not exists(select 1 from public.registrations where proposal_id=p_proposal and user_id=auth.uid() and status='registered') then raise exception 'Valid event registration required'; end if;
 select v0.* into v from public.proposals p join public.proposal_versions v0 on v0.proposal_id=p.id and v0.version=p.current_version where p.id=p_proposal and p.status='published';
 if not found or now() not between v.starts_at - interval '2 hours' and v.ends_at+interval '2 hours' then raise exception 'Check-in is not open for this event'; end if;
 delete from public.attendance_tokens where user_id=auth.uid() and proposal_id=p_proposal;
 t:=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.attendance_tokens(token_hash,proposal_id,user_id,expires_at) values(encode(extensions.digest(t,'sha256'),'hex'),p_proposal,auth.uid(),now()+interval '90 seconds');
 return t;
end;$$;
create function public.scan_attendance_token(p_token text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare t public.attendance_tokens;p public.proposals;v public.proposal_versions;
begin
 if auth.uid() is null or length(coalesce(p_token,''))<>64 then raise exception 'Invalid QR token'; end if;
 select * into t from public.attendance_tokens where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if not found or t.used_at is not null or t.expires_at<now() then raise exception 'QR expired or already used'; end if;
 select * into p from public.proposals where id=t.proposal_id;
 if not (private.is_committee(p.club_id) or private.has_role('admin') or exists(select 1 from public.club_organizers o where o.club_id=p.club_id and o.user_id=auth.uid())) then raise exception 'Organizer access required for this club'; end if;
 select * into v from public.proposal_versions where proposal_id=p.id and version=p.current_version;
 if now() not between v.starts_at-interval '2 hours' and v.ends_at+interval '2 hours' then raise exception 'Check-in not open'; end if;
 if not exists(select 1 from public.registrations where proposal_id=p.id and user_id=t.user_id and status='registered') then raise exception 'No valid registration'; end if;
 update public.attendance_tokens set used_at=now() where token_hash=t.token_hash;
 insert into public.attendance(proposal_id,user_id,checked_by) values(p.id,t.user_id,auth.uid()) on conflict(proposal_id,user_id) do nothing;
 insert into public.badges(proposal_id,user_id) values(p.id,t.user_id) on conflict(proposal_id,user_id) do nothing;
 return jsonb_build_object('ok',true,'proposal_id',p.id,'student_id',t.user_id,'badge_issued',true);
end;$$;

-- Explicit SELECT grants for PostgREST. Authenticated clients cannot mutate tables directly.
grant select on public.profiles,public.user_roles,public.clubs,public.committee_seats,
 public.club_organizers,public.proposals,public.proposal_versions,public.proposal_reviewers,
 public.review_decisions,public.proposal_comments,public.memberships,public.registrations,
 public.payment_orders,public.attendance,public.badges,public.audit_log to authenticated;
revoke insert,update,delete,truncate,references,trigger on public.profiles,public.user_roles,
 public.clubs,public.committee_seats,public.club_organizers,public.proposals,
 public.proposal_versions,public.proposal_reviewers,public.review_decisions,
 public.proposal_comments,public.memberships,public.registrations,public.payment_orders,
 public.attendance_tokens,public.attendance,public.badges,public.audit_log from authenticated,anon;
revoke all on public.attendance_tokens from authenticated,anon;

-- Explicitly revoke default PUBLIC execute access, grant only safe entry points.
revoke all on all functions in schema public from public,anon;
revoke all on all functions in schema private from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.has_role(text),private.is_committee(uuid),private.is_lecturer(uuid),private.is_proposal_stakeholder(uuid),private.can_view_proposal(uuid) to authenticated;
grant execute on function public.admin_assign_role(uuid,text),public.admin_create_club(text,text,text,int),public.admin_assign_lecturer(uuid,uuid),public.admin_assign_committee(uuid,int,uuid),public.admin_assign_organizer(uuid,uuid),public.admin_assign_reviewer(uuid,uuid),public.create_proposal(uuid,text,text,timestamptz,timestamptz,text,int,int),public.submit_proposal(uuid),public.lecturer_decide(uuid,text,text),public.authority_decide(uuid,text,text),public.resubmit_proposal(uuid,text,text,timestamptz,timestamptz,text,int,int),public.publish_proposal(uuid),public.add_proposal_comment(uuid,text),public.apply_membership(uuid),public.decide_membership(uuid,boolean),public.register_event(uuid),public.prepare_checkout(text,uuid),public.issue_attendance_token(uuid),public.scan_attendance_token(text) to authenticated;
grant execute on function public.link_checkout(uuid,text),public.complete_checkout(uuid,text,int,text) to service_role;
-- No direct modification privileges to the API roles: RLS plus no insert/update/delete policy.
-- Never place your service_role key in web or mobile code.
