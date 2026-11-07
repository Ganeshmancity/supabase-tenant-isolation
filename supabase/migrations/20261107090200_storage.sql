-- Files live under docs/tenants/<tenant_id>/... in a private bucket.
-- The policies read the tenant id out of the path.

insert into storage.buckets (id, name, public)
values ('docs', 'docs', false)
on conflict (id) do nothing;

-- 'tenants/<uuid>/file.pdf' -> <uuid>, anything else -> null (which matches nothing)
create function private.path_tenant_id(object_name text)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  parts text[] := storage.foldername(object_name);
begin
  if parts[1] is distinct from 'tenants' then
    return null;
  end if;
  return parts[2]::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$$;

revoke all on function private.path_tenant_id(text) from public;
grant execute on function private.path_tenant_id(text) to authenticated;

create policy docs_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'docs'
    and private.path_tenant_id(name) in (select private.user_tenant_ids())
  );

create policy docs_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'docs'
    and private.path_tenant_id(name) in (select private.user_tenant_ids())
  );

create policy docs_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'docs'
    and private.path_tenant_id(name) in (select private.user_tenant_ids())
  )
  with check (
    bucket_id = 'docs'
    and private.path_tenant_id(name) in (select private.user_tenant_ids())
  );

create policy docs_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'docs'
    and private.path_tenant_id(name) in (select private.user_tenant_ids())
  );
