-- Snapshot every authority-role account at submission instead of selecting
-- reviewers individually for each proposal.
create or replace function public.submit_proposal(p_proposal uuid) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
 p public.proposals;
 reviewer_count int;
begin
 select * into p from public.proposals where id = p_proposal for update;
 if not found or not private.is_committee(p.club_id) or p.status <> 'draft' then
  raise exception 'Cannot submit this proposal';
 end if;
 if not exists (
  select 1 from public.clubs where id = p.club_id and lecturer_id is not null
 ) then
  raise exception 'Lecturer must be assigned';
 end if;

 delete from public.proposal_reviewers where proposal_id = p.id;
 insert into public.proposal_reviewers(proposal_id, user_id)
 select p.id, r.user_id
 from public.user_roles r
 where r.role = 'authority'
 on conflict do nothing;
 get diagnostics reviewer_count = row_count;
 if reviewer_count < 1 then
  raise exception 'Assign the authority role to at least one account before submission';
 end if;

 update public.proposals
 set status = 'lecturer_pending', updated_at = now()
 where id = p.id;
 insert into public.audit_log(actor_id, entity_type, entity_id, action, details)
 values (
  auth.uid(),
  'proposal',
  p.id,
  'submitted',
  jsonb_build_object('version', p.current_version, 'authority_reviewer_count', reviewer_count)
 );
end;
$$;

-- Existing in-flight proposals now include the authority-role accounts present
-- when this migration is applied. New submissions snapshot roles at submission.
insert into public.proposal_reviewers(proposal_id, user_id)
select p.id, r.user_id
from public.proposals p
cross join public.user_roles r
where p.status in ('lecturer_pending', 'authority_pending', 'changes_requested')
  and r.role = 'authority'
on conflict do nothing;

-- Individual per-proposal reviewer selection is no longer an application API.
revoke all on function public.admin_assign_reviewer(uuid, uuid) from public, anon, authenticated;
