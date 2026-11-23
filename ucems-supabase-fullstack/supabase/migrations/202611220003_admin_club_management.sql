-- Admin workflows for editing club profiles and maintaining scoped staff assignments.
create function public.admin_update_club(
 p_club uuid,
 p_name text,
 p_description text,
 p_category text,
 p_fee_cents int,
 p_logo_path text default null,
 p_update_logo boolean default false
) returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
 old_logo_path text;
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 if length(btrim(coalesce(p_name, ''))) < 2 then raise exception 'Club name must contain at least 2 characters'; end if;
 if p_fee_cents is null or p_fee_cents < 0 then raise exception 'Membership fee cannot be negative'; end if;
 select logo_path into old_logo_path from public.clubs where id = p_club for update;
 if not found then raise exception 'Club not found'; end if;
 if p_update_logo and p_logo_path is not null and not exists (
  select 1 from storage.objects
  where bucket_id = 'club-logos' and name = p_logo_path
 ) then raise exception 'Uploaded club logo was not found'; end if;

 update public.clubs
 set name = btrim(p_name),
     description = coalesce(p_description, ''),
     category = coalesce(nullif(btrim(p_category), ''), 'General'),
     membership_fee_cents = p_fee_cents,
     logo_path = case when p_update_logo then p_logo_path else logo_path end
 where id = p_club;
 return old_logo_path;
end;
$$;

create function public.admin_clear_club_lecturer(p_club uuid) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 update public.clubs set lecturer_id = null where id = p_club;
 if not found then raise exception 'Club not found'; end if;
end;
$$;

create function public.admin_remove_committee_seat(p_club uuid, p_seat int) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 if p_seat not between 1 and 5 then raise exception 'Seat must be 1-5'; end if;
 delete from public.committee_seats where club_id = p_club and seat = p_seat;
 if not found then raise exception 'Committee seat is not assigned'; end if;
end;
$$;

create function public.admin_remove_club_organizer(p_club uuid, p_user uuid) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 delete from public.club_organizers where club_id = p_club and user_id = p_user;
 if not found then raise exception 'Organizer assignment not found'; end if;
end;
$$;

create function public.admin_replace_club_organizer(p_club uuid, p_old_user uuid, p_new_user uuid) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 if p_new_user is null or not exists(select 1 from public.profiles where id = p_new_user) then
  raise exception 'A valid replacement account is required';
 end if;
 delete from public.club_organizers where club_id = p_club and user_id = p_old_user;
 if not found then raise exception 'Organizer assignment not found'; end if;
 insert into public.club_organizers(club_id, user_id)
 values (p_club, p_new_user)
 on conflict (club_id, user_id) do nothing;
 insert into public.user_roles(user_id, role)
 values (p_new_user, 'organizer')
 on conflict do nothing;
end;
$$;

revoke all on function public.admin_update_club(uuid, text, text, text, int, text, boolean) from public, anon;
revoke all on function public.admin_clear_club_lecturer(uuid) from public, anon;
revoke all on function public.admin_remove_committee_seat(uuid, int) from public, anon;
revoke all on function public.admin_remove_club_organizer(uuid, uuid) from public, anon;
revoke all on function public.admin_replace_club_organizer(uuid, uuid, uuid) from public, anon;
grant execute on function public.admin_update_club(uuid, text, text, text, int, text, boolean) to authenticated;
grant execute on function public.admin_clear_club_lecturer(uuid) to authenticated;
grant execute on function public.admin_remove_committee_seat(uuid, int) to authenticated;
grant execute on function public.admin_remove_club_organizer(uuid, uuid) to authenticated;
grant execute on function public.admin_replace_club_organizer(uuid, uuid, uuid) to authenticated;
