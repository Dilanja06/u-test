-- SRS operations: university email allow-list, durable notifications,
-- private proposal documents, version-safe publication, and permission defaults.

create table public.allowed_email_domains (
 domain text primary key check(domain=lower(domain) and domain !~ '^@|@|/$'),
 created_at timestamptz not null default now(),
 created_by uuid references public.profiles(id)
);
insert into public.allowed_email_domains(domain) values ('edu.lnbti.lk')
on conflict(domain) do nothing;
alter table public.allowed_email_domains enable row level security;
create policy allowed_email_domains_admin_read on public.allowed_email_domains
 for select to authenticated using(private.has_role('admin'));
grant select on public.allowed_email_domains to authenticated;
revoke insert,update,delete,truncate,references,trigger on public.allowed_email_domains
 from public,anon,authenticated;

create or replace function private.require_university_email()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare email_domain text;
begin
 email_domain:=lower(split_part(btrim(coalesce(new.email,'')),'@',2));
 if email_domain='' or not exists(
  select 1 from public.allowed_email_domains where domain=email_domain
 ) then
  raise exception 'Use an email address from an approved university domain';
 end if;
 return new;
end;$$;
create trigger require_university_email
 before insert or update of email on auth.users
 for each row execute function private.require_university_email();

create or replace function public.admin_set_email_domains(p_domains text[])
returns integer language plpgsql security definer set search_path=public,private,pg_temp as $$
declare normalized text[]; affected integer;
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 select coalesce(array_agg(distinct lower(regexp_replace(btrim(domain),'^@',''))),array[]::text[])
 into normalized from unnest(coalesce(p_domains,array[]::text[])) as input(domain)
 where nullif(btrim(domain),'') is not null;
 if cardinality(normalized)=0 then raise exception 'At least one approved email domain is required'; end if;
 if exists(select 1 from unnest(normalized) as x(domain) where domain !~ '^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$') then
  raise exception 'One or more email domains are invalid';
 end if;
 delete from public.allowed_email_domains;
 insert into public.allowed_email_domains(domain,created_by)
 select domain,auth.uid() from unnest(normalized) as x(domain);
 get diagnostics affected=row_count;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'email_domain','00000000-0000-0000-0000-000000000000'::uuid,
  'allowed_domains_updated',jsonb_build_object('domains',to_jsonb(normalized)));
 return affected;
end;$$;
revoke all on function public.admin_set_email_domains(text[]) from public,anon;
grant execute on function public.admin_set_email_domains(text[]) to authenticated;

alter table public.proposals add column published_version integer;
update public.proposals set published_version=current_version where status='published';
alter table public.proposals add constraint proposals_published_version_fk
 foreign key(id,published_version) references public.proposal_versions(proposal_id,version);

create or replace function private.set_published_version()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if new.status='published' then
  new.published_version:=new.current_version;
 end if;
 return new;
end;$$;
create trigger set_published_version
 before insert or update of status,current_version on public.proposals
 for each row execute function private.set_published_version();

create or replace function private.can_view_proposal(p_id uuid)
returns boolean language sql stable security definer set search_path=public,private,pg_temp as $$
 select exists(select 1 from public.proposals p where p.id=p_id and (
  p.published_version is not null or private.has_role('admin')
  or private.is_committee(p.club_id) or private.is_lecturer(p.club_id)
  or exists(select 1 from public.proposal_reviewers r where r.proposal_id=p.id and r.user_id=auth.uid())
 ))
$$;
drop policy if exists versions_read on public.proposal_versions;
create policy versions_read on public.proposal_versions for select to authenticated using(
 private.is_proposal_stakeholder(proposal_id) or exists(
  select 1 from public.proposals p where p.id=proposal_id and p.published_version=version
 )
);

alter table public.registrations add column version integer;
update public.registrations r set version=coalesce(p.published_version,p.current_version)
from public.proposals p where p.id=r.proposal_id;
alter table public.registrations alter column version set not null;
alter table public.registrations add constraint registrations_version_fk
 foreign key(proposal_id,version) references public.proposal_versions(proposal_id,version);
alter table public.attendance_tokens add column version integer;
update public.attendance_tokens t set version=r.version
from public.registrations r
where r.proposal_id=t.proposal_id and r.user_id=t.user_id;
alter table public.attendance_tokens add constraint attendance_tokens_version_fk
 foreign key(proposal_id,version) references public.proposal_versions(proposal_id,version);
alter table public.attendance add column version integer;
update public.attendance a set version=r.version
from public.registrations r
where r.proposal_id=a.proposal_id and r.user_id=a.user_id;
alter table public.attendance add constraint attendance_version_fk
 foreign key(proposal_id,version) references public.proposal_versions(proposal_id,version);

create or replace function public.register_event(p_proposal uuid)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.proposals; v public.proposal_versions; existing_id uuid; existing_status text; has_existing boolean; occupied integer; x uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into p from public.proposals where id=p_proposal for update;
 if not found or p.published_version is null then raise exception 'No published event version'; end if;
 select * into v from public.proposal_versions
 where proposal_id=p.id and version=p.published_version;
 if v.ends_at<=now() then raise exception 'Event has ended'; end if;
 select id,status into existing_id,existing_status from public.registrations
 where proposal_id=p.id and user_id=auth.uid();
 has_existing:=found;
 if has_existing and existing_status<>'cancelled' then return existing_id; end if;
 select count(*) into occupied from public.registrations
 where proposal_id=p.id and status<>'cancelled';
 if occupied>=v.capacity then raise exception 'Event is full'; end if;
 if v.fee_cents>0 then
  raise exception 'Paid registration is disabled until a payment provider is configured';
 end if;
 if has_existing then
  update public.registrations set version=p.published_version,status='registered',created_at=now()
  where id=existing_id returning id into x;
 else
  insert into public.registrations(proposal_id,version,user_id,status)
  values(p.id,p.published_version,auth.uid(),'registered') returning id into x;
 end if;
 return x;
end;$$;

create or replace function public.prepare_checkout(p_kind text,p_reference uuid)
returns table(order_id uuid,amount_cents int,currency text,label text)
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare fee int; title text; x uuid;
begin
 if auth.uid() is null or p_kind not in ('membership','registration') then raise exception 'Invalid checkout'; end if;
 if p_kind='membership' then
  select c.membership_fee_cents,c.name into fee,title
  from public.memberships m join public.clubs c on c.id=m.club_id
  where m.id=p_reference and m.user_id=auth.uid() and m.status='payment_due';
 else
  select v.fee_cents,v.title into fee,title
  from public.registrations r
  join public.proposal_versions v on v.proposal_id=r.proposal_id and v.version=r.version
  where r.id=p_reference and r.user_id=auth.uid() and r.status='payment_due';
 end if;
 if fee is null or fee<=0 then raise exception 'No payment is due'; end if;
 raise exception 'Paid checkout is disabled until a payment provider is configured';
end;$$;

create or replace function public.issue_attendance_token(p_proposal uuid)
returns text language plpgsql security definer set search_path=public,private,pg_temp as $$
declare t text; v public.proposal_versions; registration_version integer;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select r.version into registration_version from public.registrations r
 where r.proposal_id=p_proposal and r.user_id=auth.uid() and r.status='registered';
 if not found then raise exception 'Valid event registration required'; end if;
 select v0.* into v from public.proposal_versions v0
 where v0.proposal_id=p_proposal and v0.version=registration_version;
 if not found or now() not between v.starts_at-interval '2 hours' and v.ends_at+interval '2 hours' then
  raise exception 'Check-in is not open for this event';
 end if;
 delete from public.attendance_tokens where user_id=auth.uid() and proposal_id=p_proposal;
 t:=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.attendance_tokens(token_hash,proposal_id,version,user_id,expires_at)
 values(encode(extensions.digest(t,'sha256'),'hex'),p_proposal,registration_version,auth.uid(),now()+interval '90 seconds');
 return t;
end;$$;

create or replace function public.scan_attendance_token(p_token text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare t public.attendance_tokens; p public.proposals; v public.proposal_versions; candidate_id uuid; token_version integer;
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
 token_version:=coalesce(t.version,p.published_version,p.current_version);
 select * into v from public.proposal_versions where proposal_id=p.id and version=token_version;
 if not found or now() not between v.starts_at-interval '2 hours' and v.ends_at+interval '2 hours' then
  raise exception 'Check-in not open';
 end if;
 if not exists(
  select 1 from public.registrations
  where proposal_id=p.id and user_id=t.user_id and version=token_version and status='registered'
 ) then raise exception 'No valid registration'; end if;
 update public.attendance_tokens set used_at=now() where token_hash=t.token_hash;
 insert into public.attendance(proposal_id,version,user_id,checked_by)
 values(p.id,token_version,t.user_id,auth.uid())
 on conflict(proposal_id,user_id) do nothing;
 insert into public.badge_candidates(proposal_id,user_id)
 values(p.id,t.user_id) on conflict(proposal_id,user_id) do nothing returning id into candidate_id;
 if candidate_id is null then
  select id into candidate_id from public.badge_candidates
  where proposal_id=p.id and user_id=t.user_id;
 end if;
 return jsonb_build_object('ok',true,'proposal_id',p.id,'student_id',t.user_id,
  'badge_candidate_id',candidate_id,'badge_issued',false);
end;$$;

create table public.notifications (
 id uuid primary key default gen_random_uuid(),
 recipient_id uuid not null references public.profiles(id) on delete cascade,
 source_event_id uuid not null,
 event_key text not null,
 summary text not null check(length(btrim(summary)) between 1 and 500),
 entity_type text not null,
 entity_id uuid not null,
 actor_id uuid references public.profiles(id),
 created_at timestamptz not null default now(),
 read_at timestamptz,
 unique(recipient_id,source_event_id)
);
create index notifications_inbox_idx on public.notifications(recipient_id,created_at desc);
alter table public.notifications enable row level security;
create policy notifications_read_own on public.notifications for select to authenticated
 using(recipient_id=auth.uid());
grant select on public.notifications to authenticated;
revoke insert,update,delete,truncate,references,trigger on public.notifications
 from public,anon,authenticated;

create or replace function private.insert_notification(
 p_recipient uuid,p_event_id uuid,p_event_key text,p_summary text,
 p_entity_type text,p_entity_id uuid,p_actor uuid
) returns void language sql security definer set search_path=public,private,pg_temp as $$
 insert into public.notifications(recipient_id,source_event_id,event_key,summary,entity_type,entity_id,actor_id)
 select p_recipient,p_event_id,p_event_key,p_summary,p_entity_type,p_entity_id,p_actor
 where p_recipient is not null and p_recipient<>p_actor
 on conflict(recipient_id,source_event_id) do nothing
$$;

create or replace function private.notify_proposal_stakeholders(
 p_proposal uuid,p_event_id uuid,p_event_key text,p_summary text,p_actor uuid
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare club uuid;
begin
 select club_id into club from public.proposals where id=p_proposal;
 if not found then return; end if;
 insert into public.notifications(recipient_id,source_event_id,event_key,summary,entity_type,entity_id,actor_id)
 select distinct recipients.user_id,p_event_id,p_event_key,p_summary,'proposal',p_proposal,p_actor
 from (
  select p.created_by user_id from public.proposals p where p.id=p_proposal
  union select s.user_id from public.committee_seats s where s.club_id=club
  union select c.lecturer_id from public.clubs c where c.id=club and c.lecturer_id is not null
  union select a.reviewer_id from public.proposal_authority_assignments a
   join public.proposals p on p.id=a.proposal_id and p.current_version=a.version
   where a.proposal_id=p_proposal
  union select r.user_id from public.user_roles r where r.role='admin'
 ) recipients
 where recipients.user_id is not null and recipients.user_id<>p_actor
 on conflict(recipient_id,source_event_id) do nothing;
end;$$;

create or replace function private.notify_proposal_status_change()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if old.status is distinct from new.status then
  perform private.notify_proposal_stakeholders(
   new.id,extensions.gen_random_uuid(),'proposal_'||new.status,
   'Proposal status changed to '||replace(new.status,'_',' ')||'.',auth.uid()
  );
 end if;
 return new;
end;$$;
create trigger proposal_status_notifications after update of status on public.proposals
 for each row execute function private.notify_proposal_status_change();

create or replace function private.notify_proposal_comment()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 perform private.notify_proposal_stakeholders(
  new.proposal_id,extensions.gen_random_uuid(),'proposal_comment',
  'A new comment was added to a proposal.',new.author_id
 );
 return new;
end;$$;
create trigger proposal_comment_notifications after insert on public.proposal_comments
 for each row execute function private.notify_proposal_comment();

create or replace function private.notify_membership_change()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare event_id uuid:=extensions.gen_random_uuid(); changed boolean;
begin
 if tg_op='INSERT' then changed:=true; else changed:=old.status is distinct from new.status; end if;
 if changed then
  perform private.insert_notification(new.user_id,event_id,'membership_'||new.status,
   'Membership request is '||replace(new.status,'_',' ')||'.','membership',new.id,auth.uid());
  insert into public.notifications(recipient_id,source_event_id,event_key,summary,entity_type,entity_id,actor_id)
  select distinct s.user_id,event_id,'membership_request',
   'A club membership request needs review.','membership',new.id,auth.uid()
  from public.committee_seats s where s.club_id=new.club_id
   and private.has_club_permission(new.club_id,'club.members.manage')
   and s.user_id<>coalesce(auth.uid(),new.user_id)
  on conflict(recipient_id,source_event_id) do nothing;
 end if;
 return new;
end;$$;
create trigger membership_notifications after insert or update of status on public.memberships
 for each row execute function private.notify_membership_change();

create or replace function private.notify_registration_change()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare event_id uuid:=extensions.gen_random_uuid(); club uuid; changed boolean;
begin
 if tg_op='INSERT' then changed:=true; else changed:=old.status is distinct from new.status; end if;
 if changed then
  perform private.insert_notification(new.user_id,event_id,'registration_'||new.status,
   'Event registration is '||replace(new.status,'_',' ')||'.','registration',new.id,auth.uid());
  select club_id into club from public.proposals where id=new.proposal_id;
  insert into public.notifications(recipient_id,source_event_id,event_key,summary,entity_type,entity_id,actor_id)
  select distinct s.user_id,event_id,'registration_update',
   'An event registration needs attention.','registration',new.id,auth.uid()
  from public.committee_seats s where s.club_id=club
   and private.has_club_permission(club,'registration.view')
   and s.user_id<>coalesce(auth.uid(),new.user_id)
  on conflict(recipient_id,source_event_id) do nothing;
 end if;
 return new;
end;$$;
create trigger registration_notifications after insert or update of status on public.registrations
 for each row execute function private.notify_registration_change();

create or replace function private.notify_payment_change()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare event_id uuid:=extensions.gen_random_uuid();
begin
 if old.status is distinct from new.status then
  perform private.insert_notification(new.user_id,event_id,'payment_'||new.status,
   'Payment status changed to '||replace(new.status,'_',' ')||'.','payment',new.id,auth.uid());
  insert into public.notifications(recipient_id,source_event_id,event_key,summary,entity_type,entity_id,actor_id)
  select r.user_id,event_id,'payment_update','A payment order changed status.',
   'payment',new.id,auth.uid()
  from public.user_roles r where r.role='admin' and r.user_id<>coalesce(auth.uid(),new.user_id)
  on conflict(recipient_id,source_event_id) do nothing;
 end if;
 return new;
end;$$;
create trigger payment_notifications after update of status on public.payment_orders
 for each row execute function private.notify_payment_change();

create or replace function private.notify_badge_decision()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if old.status is distinct from new.status then
  perform private.insert_notification(new.user_id,extensions.gen_random_uuid(),
   'badge_'||new.status,'Your badge candidate was '||new.status||'.',
   'badge_candidate',new.id,auth.uid());
 end if;
 return new;
end;$$;
create trigger badge_decision_notifications after update of status on public.badge_candidates
 for each row execute function private.notify_badge_decision();

create or replace function public.mark_notification_read(p_notification uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 update public.notifications set read_at=coalesce(read_at,now())
 where id=p_notification and recipient_id=auth.uid();
 if not found then raise exception 'Notification not found'; end if;
end;$$;
create or replace function public.mark_all_notifications_read()
returns integer language plpgsql security definer set search_path=public,private,pg_temp as $$
declare changed integer;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 update public.notifications set read_at=now()
 where recipient_id=auth.uid() and read_at is null;
 get diagnostics changed=row_count;
 return changed;
end;$$;
revoke all on function public.mark_notification_read(uuid),public.mark_all_notifications_read()
 from public,anon;
grant execute on function public.mark_notification_read(uuid),public.mark_all_notifications_read()
 to authenticated;

create table public.proposal_documents (
 id uuid primary key default gen_random_uuid(),
 proposal_id uuid not null,
 version integer not null,
 uploaded_by uuid not null references public.profiles(id),
 object_path text not null unique,
 file_name text not null check(length(btrim(file_name)) between 1 and 255),
 mime_type text not null,
 file_size_bytes bigint not null check(file_size_bytes between 1 and 10485760),
 created_at timestamptz not null default now(),
 foreign key(proposal_id,version) references public.proposal_versions(proposal_id,version)
);
create index proposal_documents_version_idx on public.proposal_documents(proposal_id,version);
alter table public.proposal_documents enable row level security;
create policy proposal_documents_read on public.proposal_documents for select to authenticated
 using(private.is_proposal_stakeholder(proposal_id) or exists(
  select 1 from public.proposals p where p.id=proposal_id and p.published_version=version
 ));
grant select on public.proposal_documents to authenticated;
revoke insert,update,delete,truncate,references,trigger on public.proposal_documents
 from public,anon,authenticated;

create or replace function private.proposal_document_access(p_path text,p_upload boolean)
returns boolean language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare proposal uuid; doc_version integer; owner uuid; current_status text; current_version integer;
begin
 if p_path !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/[1-9][0-9]*/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/[^/]+$' then return false; end if;
 begin
  proposal:=split_part(p_path,'/',1)::uuid;
  doc_version:=split_part(p_path,'/',2)::integer;
  owner:=split_part(p_path,'/',3)::uuid;
 exception when invalid_text_representation or numeric_value_out_of_range then
  return false;
 end;
 if p_upload then
  select status,current_version into current_status,current_version
  from public.proposals where id=proposal;
  return owner=auth.uid() and doc_version=current_version
   and current_status in ('draft','changes_requested')
   and (private.has_role('admin') or private.has_club_permission(
    (select club_id from public.proposals where id=proposal),'event.create'
   ));
 end if;
 return exists(select 1 from public.proposals p where p.id=proposal
  and p.published_version=doc_version)
  or private.is_proposal_stakeholder(proposal);
end;$$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('proposal-documents','proposal-documents',false,10485760,
 array['application/pdf','image/jpeg','image/png','image/webp',
 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,
 allowed_mime_types=excluded.allowed_mime_types;
create policy proposal_documents_upload on storage.objects for insert to authenticated
 with check(bucket_id='proposal-documents' and private.proposal_document_access(name,true));
create policy proposal_documents_read on storage.objects for select to authenticated
 using(bucket_id='proposal-documents' and private.proposal_document_access(name,false));
create policy proposal_documents_orphan_cleanup on storage.objects for delete to authenticated
 using(bucket_id='proposal-documents'
  and private.proposal_document_access(name,true)
  and not exists(select 1 from public.proposal_documents d where d.object_path=name));

create or replace function public.add_proposal_document(
 p_proposal uuid,p_version integer,p_object_path text,p_file_name text,p_mime_type text
) returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare object_size bigint; x uuid; path_proposal uuid; path_version integer;
begin
 if p_object_path !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/[1-9][0-9]*/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/[^/]+$' then
  raise exception 'Invalid proposal document path';
 end if;
 begin
  path_proposal:=split_part(p_object_path,'/',1)::uuid;
  path_version:=split_part(p_object_path,'/',2)::integer;
 exception when invalid_text_representation or numeric_value_out_of_range then
  raise exception 'Invalid proposal document path';
 end;
 if not private.proposal_document_access(p_object_path,true)
  or path_proposal<>p_proposal or path_version<>p_version then
  raise exception 'Document upload is not allowed for this proposal version';
 end if;
 select nullif(metadata->>'size','')::bigint into object_size from storage.objects
 where bucket_id='proposal-documents' and name=p_object_path;
 if object_size is null or object_size not between 1 and 10485760 then
  raise exception 'Document is missing or exceeds the 10 MB limit';
 end if;
 if p_mime_type not in ('application/pdf','image/jpeg','image/png','image/webp',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document') then
  raise exception 'Unsupported document type';
 end if;
 insert into public.proposal_documents(proposal_id,version,uploaded_by,object_path,file_name,mime_type,file_size_bytes)
 values(p_proposal,p_version,auth.uid(),p_object_path,left(btrim(p_file_name),255),p_mime_type,object_size)
 returning id into x;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'proposal_document',x,'document_uploaded',
  jsonb_build_object('proposal_id',p_proposal,'version',p_version,'file_name',left(p_file_name,255)));
 return x;
end;$$;
revoke all on function public.add_proposal_document(uuid,integer,text,text,text) from public,anon;
grant execute on function public.add_proposal_document(uuid,integer,text,text,text) to authenticated;

-- A club has one account holder per position; all catalogued permissions are
-- enabled for each position by default per the approved institution policy.
insert into public.committee_position_permissions(club_id,position_name,permission_key,enabled)
select c.id,positions.position_name,permissions.permission_key,true
from public.clubs c
cross join unnest(array['President','Vice President','Secretary','Vice Secretary','Treasurer']) positions(position_name)
cross join public.committee_permission_catalog permissions
on conflict(club_id,position_name,permission_key) do update set enabled=true,updated_at=now();

create or replace function private.initialize_club_permissions()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 insert into public.committee_position_permissions(club_id,position_name,permission_key,enabled)
 select new.id,positions.position_name,permissions.permission_key,true
 from unnest(array['President','Vice President','Secretary','Vice Secretary','Treasurer']) positions(position_name)
 cross join public.committee_permission_catalog permissions
 on conflict(club_id,position_name,permission_key) do nothing;
 return new;
end;$$;
create trigger initialize_club_permissions after insert on public.clubs
 for each row execute function private.initialize_club_permissions();

revoke all on function private.require_university_email(),private.set_published_version(),
 private.insert_notification(uuid,uuid,text,text,text,uuid,uuid),
 private.notify_proposal_stakeholders(uuid,uuid,text,text,uuid),
 private.notify_proposal_status_change(),private.notify_proposal_comment(),
 private.notify_membership_change(),private.notify_registration_change(),
 private.notify_payment_change(),private.notify_badge_decision(),
 private.proposal_document_access(text,boolean),private.initialize_club_permissions()
 from public,anon,authenticated;
grant execute on function private.can_view_proposal(uuid),private.proposal_document_access(text,boolean)
 to authenticated;
