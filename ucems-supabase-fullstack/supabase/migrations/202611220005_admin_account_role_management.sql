create or replace function public.admin_assign_role(p_user uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 if p_user is null or p_user = auth.uid() then raise exception 'Admins cannot assign roles to their own account'; end if;
 if p_role not in ('student','committee','lecturer','authority','organizer','admin') then raise exception 'Invalid role'; end if;
 insert into public.user_roles(user_id, role)
 values (p_user, p_role)
 on conflict do nothing;
end;
$$;

create function public.admin_update_user_role(p_user uuid, p_old_role text, p_new_role text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 if p_user is null or p_old_role is null or p_new_role is null or p_old_role = p_new_role then
  raise exception 'A valid account and two different roles are required';
 end if;
 if p_user = auth.uid() then raise exception 'Admins cannot change their own roles'; end if;
 if p_old_role not in ('student','committee','lecturer','authority','organizer','admin')
    or p_new_role not in ('student','committee','lecturer','authority','organizer','admin') then
  raise exception 'Invalid role';
 end if;
 if p_old_role = 'admin' then
  perform pg_advisory_xact_lock(175631, 1);
  if not private.has_role('admin') then raise exception 'Admin required'; end if;
  if not exists(select 1 from public.user_roles where role = 'admin' and user_id <> p_user) then
   raise exception 'Cannot remove the last administrator';
  end if;
 end if;
 delete from public.user_roles where user_id = p_user and role = p_old_role;
 if not found then raise exception 'Role assignment not found'; end if;
 insert into public.user_roles(user_id, role)
 values (p_user, p_new_role)
 on conflict do nothing;
end;
$$;

create function public.admin_remove_user_role(p_user uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 if p_user is null or p_role is null
    or p_role not in ('student','committee','lecturer','authority','organizer','admin') then
  raise exception 'A valid account and role are required';
 end if;
 if p_user = auth.uid() then raise exception 'Admins cannot remove their own roles'; end if;
 if p_role = 'admin' then
  perform pg_advisory_xact_lock(175631, 1);
  if not private.has_role('admin') then raise exception 'Admin required'; end if;
  if not exists(select 1 from public.user_roles where role = 'admin' and user_id <> p_user) then
   raise exception 'Cannot remove the last administrator';
  end if;
 end if;
 delete from public.user_roles where user_id = p_user and role = p_role;
 if not found then raise exception 'Role assignment not found'; end if;
end;
$$;

revoke all on function public.admin_update_user_role(uuid, text, text) from public, anon;
revoke all on function public.admin_remove_user_role(uuid, text) from public, anon;
revoke all on function public.admin_assign_role(uuid, text) from public, anon;
grant execute on function public.admin_update_user_role(uuid, text, text) to authenticated;
grant execute on function public.admin_remove_user_role(uuid, text) to authenticated;
grant execute on function public.admin_assign_role(uuid, text) to authenticated;
