-- Versioned, fail-closed Higher Authority routing by event category and LKR budget.

create table public.authority_routing_rules (
 id uuid primary key default gen_random_uuid(),
 name text not null unique check(length(btrim(name)) between 3 and 120),
 event_category text,
 min_budget_lkr bigint not null default 0 check(min_budget_lkr>=0),
 max_budget_lkr bigint check(max_budget_lkr is null or max_budget_lkr>=min_budget_lkr),
 enabled boolean not null default true,
 created_by uuid not null references public.profiles(id),
 updated_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.authority_routing_rule_recipients (
 rule_id uuid not null references public.authority_routing_rules(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete restrict,
 primary key(rule_id,user_id)
);

alter table public.proposal_authority_assignments
 add column rule_snapshot jsonb not null default '[]'::jsonb
 check(jsonb_typeof(rule_snapshot)='array');

alter table public.authority_routing_rules enable row level security;
alter table public.authority_routing_rule_recipients enable row level security;
create policy authority_routing_rules_admin_read on public.authority_routing_rules
 for select to authenticated using(private.has_role('admin'));
create policy authority_routing_rule_recipients_admin_read on public.authority_routing_rule_recipients
 for select to authenticated using(private.has_role('admin'));
grant select on public.authority_routing_rules,public.authority_routing_rule_recipients to authenticated;

create or replace function public.admin_save_authority_rule(
 p_rule uuid,p_name text,p_event_category text,p_min_budget_lkr bigint,
 p_max_budget_lkr bigint,p_recipients uuid[]
) returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_rule_id uuid; recipient_count integer;
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 if length(btrim(coalesce(p_name,''))) not between 3 and 120 then
  raise exception 'Rule name must contain 3 to 120 characters';
 end if;
 if coalesce(p_min_budget_lkr,0)<0 or
   (p_max_budget_lkr is not null and p_max_budget_lkr<p_min_budget_lkr) then
  raise exception 'Invalid LKR budget range';
 end if;
 if coalesce(cardinality(p_recipients),0)=0 then
  raise exception 'Select at least one Higher Authority; empty routing rules are not allowed';
 end if;
 if exists(
  select 1 from unnest(p_recipients) requested(user_id)
  where requested.user_id is null or not exists(
   select 1 from public.user_roles ur where ur.user_id=requested.user_id and ur.role='authority'
  )
 ) then raise exception 'Every recipient must have the Higher Authority role'; end if;
 if p_rule is null then
  insert into public.authority_routing_rules(name,event_category,min_budget_lkr,max_budget_lkr,created_by,updated_by)
  values(btrim(p_name),nullif(btrim(p_event_category),''),coalesce(p_min_budget_lkr,0),p_max_budget_lkr,auth.uid(),auth.uid())
  returning id into v_rule_id;
 else
  update public.authority_routing_rules set name=btrim(p_name),
   event_category=nullif(btrim(p_event_category),''),min_budget_lkr=coalesce(p_min_budget_lkr,0),
   max_budget_lkr=p_max_budget_lkr,updated_by=auth.uid(),updated_at=now()
  where id=p_rule returning id into v_rule_id;
  if v_rule_id is null then raise exception 'Authority routing rule not found'; end if;
 end if;
 delete from public.authority_routing_rule_recipients recipients
 where recipients.rule_id=v_rule_id;
 insert into public.authority_routing_rule_recipients(rule_id,user_id)
 select v_rule_id,distinct_user.user_id from (
  select distinct requested.user_id from unnest(p_recipients) requested(user_id)
 ) distinct_user;
 get diagnostics recipient_count=row_count;
 update public.authority_routing_config set revision=revision+1,updated_by=auth.uid(),updated_at=now()
 where id=true;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'approval_routing_rule',v_rule_id,'rule_saved',
  jsonb_build_object('name',btrim(p_name),'category',nullif(btrim(p_event_category),''),
   'min_budget_lkr',coalesce(p_min_budget_lkr,0),'max_budget_lkr',p_max_budget_lkr,
   'recipient_count',recipient_count));
 return v_rule_id;
end;$$;

create or replace function public.admin_set_authority_rule_enabled(p_rule uuid,p_enabled boolean)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 update public.authority_routing_rules set enabled=coalesce(p_enabled,false),
  updated_by=auth.uid(),updated_at=now() where id=p_rule;
 if not found then raise exception 'Authority routing rule not found'; end if;
 update public.authority_routing_config set revision=revision+1,updated_by=auth.uid(),updated_at=now()
 where id=true;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'approval_routing_rule',p_rule,'rule_enabled_changed',
  jsonb_build_object('enabled',coalesce(p_enabled,false)));
end;$$;

create or replace function public.admin_delete_authority_rule(p_rule uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 delete from public.authority_routing_rules where id=p_rule;
 if not found then raise exception 'Authority routing rule not found'; end if;
 update public.authority_routing_config set revision=revision+1,updated_by=auth.uid(),updated_at=now()
 where id=true;
 insert into public.audit_log(actor_id,entity_type,entity_id,action)
 values(auth.uid(),'approval_routing_rule',p_rule,'rule_deleted');
end;$$;

create or replace function private.assign_authority_tasks(p_proposal uuid,p_version integer)
returns integer language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.proposals; v public.proposal_versions; revision integer; snapshot jsonb; inserted integer;
begin
 select * into p from public.proposals where id=p_proposal;
 if not found or p.current_version<>p_version then raise exception 'Proposal version is no longer current'; end if;
 select * into v from public.proposal_versions where proposal_id=p.id and version=p_version;
 if not found then raise exception 'Proposal version not found'; end if;
 select ac.revision into revision from public.authority_routing_config ac where id=true;
 select jsonb_agg(jsonb_build_object(
   'rule_id',r.id,'name',r.name,'category',r.event_category,
   'min_budget_lkr',r.min_budget_lkr,'max_budget_lkr',r.max_budget_lkr,
   'recipients',(select jsonb_agg(rr.user_id order by rr.user_id)
    from public.authority_routing_rule_recipients rr
    join public.user_roles ur on ur.user_id=rr.user_id and ur.role='authority'
    where rr.rule_id=r.id)
  ) order by r.name)
 into snapshot
 from public.authority_routing_rules r
 where r.enabled
  and (r.event_category is null or lower(r.event_category)=lower(v.event_category))
  and v.budget_lkr>=r.min_budget_lkr
  and (r.max_budget_lkr is null or v.budget_lkr<=r.max_budget_lkr);
 if snapshot is null then return 0; end if;
 insert into public.proposal_reviewers(proposal_id,user_id)
 select distinct p.id,rr.user_id
 from public.authority_routing_rules r
 join public.authority_routing_rule_recipients rr on rr.rule_id=r.id
 join public.user_roles ur on ur.user_id=rr.user_id and ur.role='authority'
 where r.enabled
  and (r.event_category is null or lower(r.event_category)=lower(v.event_category))
  and v.budget_lkr>=r.min_budget_lkr
  and (r.max_budget_lkr is null or v.budget_lkr<=r.max_budget_lkr)
 on conflict do nothing;
 insert into public.proposal_authority_assignments(proposal_id,version,reviewer_id,routing_revision,rule_snapshot)
 select p.id,p_version,assigned.user_id,coalesce(revision,0),snapshot
 from (
  select distinct rr.user_id
  from public.authority_routing_rules r
  join public.authority_routing_rule_recipients rr on rr.rule_id=r.id
  join public.user_roles ur on ur.user_id=rr.user_id and ur.role='authority'
  where r.enabled
   and (r.event_category is null or lower(r.event_category)=lower(v.event_category))
   and v.budget_lkr>=r.min_budget_lkr
   and (r.max_budget_lkr is null or v.budget_lkr<=r.max_budget_lkr)
 ) assigned
 on conflict do nothing;
 get diagnostics inserted=row_count;
 return inserted;
end;$$;

create or replace function public.lecturer_decide(p_proposal uuid,p_decision text,p_comment text default '')
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.proposals; reviewer_count integer;
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
  reviewer_count:=private.assign_authority_tasks(p.id,p.current_version);
  update public.proposals set
   status=case when reviewer_count>0 then 'authority_pending' else 'routing_exception' end,
   updated_at=now() where id=p.id;
  insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
  values(auth.uid(),'proposal',p.id,
   case when reviewer_count>0 then 'authority_routed' else 'authority_routing_exception' end,
   jsonb_build_object('version',p.current_version,'reviewer_count',reviewer_count));
 else
  update public.proposals set
   status=case when p_decision='rejected' then 'rejected' else 'changes_requested' end,
   updated_at=now() where id=p.id;
 end if;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'proposal',p.id,'lecturer_'||p_decision,
  jsonb_build_object('version',p.current_version,'comment',p_comment));
end;$$;

create or replace function public.admin_retry_authority_routing(p_proposal uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.proposals; reviewer_count integer; revision integer;
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 select * into p from public.proposals where id=p_proposal for update;
 if not found or p.status<>'routing_exception' then raise exception 'Proposal has no routing exception'; end if;
 reviewer_count:=private.assign_authority_tasks(p.id,p.current_version);
 if reviewer_count=0 then
  raise exception 'Add a matching category and budget rule with at least one active authority';
 end if;
 select ac.revision into revision from public.authority_routing_config ac where id=true;
 update public.proposals set status='authority_pending',updated_at=now() where id=p.id;
 insert into public.audit_log(actor_id,entity_type,entity_id,action,details)
 values(auth.uid(),'proposal',p.id,'authority_routing_retried',
  jsonb_build_object('version',p.current_version,'routing_revision',revision,'reviewer_count',reviewer_count));
end;$$;

create index authority_routing_rule_match_idx
 on public.authority_routing_rules(enabled,event_category,min_budget_lkr,max_budget_lkr);
revoke all on function public.admin_set_authority_routing(uuid[]) from public,anon,authenticated;
revoke all on function private.assign_authority_tasks(uuid,integer) from public,anon,authenticated;
grant execute on function public.admin_save_authority_rule(uuid,text,text,bigint,bigint,uuid[]),
 public.admin_set_authority_rule_enabled(uuid,boolean),public.admin_delete_authority_rule(uuid) to authenticated;
grant execute on function public.lecturer_decide(uuid,text,text),public.admin_retry_authority_routing(uuid) to authenticated;
