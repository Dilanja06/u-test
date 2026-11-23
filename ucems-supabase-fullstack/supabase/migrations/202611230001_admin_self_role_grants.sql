create or replace function public.admin_assign_role(p_user uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 if p_user is null then raise exception 'A valid account is required'; end if;
 if p_role is null or p_role not in ('student','committee','lecturer','authority','organizer','admin') then raise exception 'Invalid role'; end if;
 insert into public.user_roles(user_id, role)
 values (p_user, p_role)
 on conflict do nothing;
end;
$$;

revoke all on function public.admin_assign_role(uuid, text) from public, anon;
grant execute on function public.admin_assign_role(uuid, text) to authenticated;
