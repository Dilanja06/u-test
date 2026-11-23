-- Club logo uploads for the admin-managed club directory.
alter table public.clubs add column logo_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('club-logos', 'club-logos', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
 public = excluded.public,
 file_size_limit = excluded.file_size_limit,
 allowed_mime_types = excluded.allowed_mime_types;

create policy club_logos_admin_upload
on storage.objects for insert to authenticated
with check (bucket_id = 'club-logos' and private.has_role('admin'));

create policy club_logos_admin_delete
on storage.objects for delete to authenticated
using (bucket_id = 'club-logos' and private.has_role('admin'));

create function public.admin_create_club_with_logo(
 p_name text,
 p_description text default '',
 p_category text default 'General',
 p_fee_cents int default 0,
 p_logo_path text default null
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
 x uuid;
begin
 if not private.has_role('admin') then raise exception 'Admin required'; end if;
 if length(btrim(coalesce(p_name, ''))) < 2 then raise exception 'Club name must contain at least 2 characters'; end if;
 if p_fee_cents is null or p_fee_cents < 0 then raise exception 'Membership fee cannot be negative'; end if;
 if p_logo_path is not null and not exists (
  select 1 from storage.objects
  where bucket_id = 'club-logos' and name = p_logo_path
 ) then raise exception 'Uploaded club logo was not found'; end if;

 insert into public.clubs(name, description, category, membership_fee_cents, logo_path)
 values (btrim(p_name), coalesce(p_description, ''), coalesce(p_category, 'General'), p_fee_cents, p_logo_path)
 returning id into x;
 return x;
end;
$$;

revoke all on function public.admin_create_club_with_logo(text, text, text, int, text) from public, anon;
grant execute on function public.admin_create_club_with_logo(text, text, text, int, text) to authenticated;
