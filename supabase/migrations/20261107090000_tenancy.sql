-- Tenants, memberships, and the one function every policy goes through.
--
-- An "org" is a customer (a utility, a shop...). An "agency" resells the
-- product and manages several orgs. Agency owners/admins can see their
-- client orgs; plain agency members only see the agency itself.

create extension if not exists vector with schema extensions;

create schema if not exists private;

create table public.tenants (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  kind       text not null check (kind in ('agency', 'org')),
  agency_id  uuid references public.tenants (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint agency_only_on_orgs check (kind = 'org' or agency_id is null)
);

create index tenants_agency_id_idx on public.tenants (agency_id);

create table public.memberships (
  user_id    uuid not null references auth.users (id) on delete cascade,
  tenant_id  uuid not null references public.tenants (id) on delete cascade,
  role       text not null check (role in ('owner', 'admin', 'member')),
  created_at timestamptz not null default now(),
  primary key (user_id, tenant_id)
);

create index memberships_tenant_id_idx on public.memberships (tenant_id);

-- Which tenants can the current user act in?
--
-- security definer: it has to read memberships, and memberships has its own
-- RLS policy that calls this function. Running as the owner avoids the loop.
-- It lives in the private schema so it is not callable through the REST API.
create function private.user_tenant_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.tenant_id
  from public.memberships m
  where m.user_id = (select auth.uid())

  union

  select t.id
  from public.tenants t
  join public.memberships m on m.tenant_id = t.agency_id
  where m.user_id = (select auth.uid())
    and m.role in ('owner', 'admin');
$$;

revoke all on function private.user_tenant_ids() from public;
grant usage on schema private to authenticated;
grant execute on function private.user_tenant_ids() to authenticated;

alter table public.tenants enable row level security;
alter table public.memberships enable row level security;

-- Read-only from the client. Creating tenants and inviting people goes
-- through the server (service role), where we can check billing, limits etc.
create policy tenants_select on public.tenants
  for select to authenticated
  using (id in (select private.user_tenant_ids()));

create policy memberships_select on public.memberships
  for select to authenticated
  using (tenant_id in (select private.user_tenant_ids()));
