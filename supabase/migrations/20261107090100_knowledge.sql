-- What each tenant uploads: assistants, documents and their embedded chunks.

create table public.assistants (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants (id) on delete cascade,
  name            text not null,
  -- goes into the embed snippet on the customer's site, so it is not a secret
  public_key      text not null unique default 'pk_' || encode(extensions.gen_random_bytes(12), 'hex'),
  allowed_origins text[] not null default '{}',
  created_at      timestamptz not null default now()
);

create index assistants_tenant_id_idx on public.assistants (tenant_id);

create table public.documents (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants (id) on delete cascade,
  title        text not null,
  storage_path text,
  created_at   timestamptz not null default now(),
  unique (id, tenant_id)
);

create index documents_tenant_id_idx on public.documents (tenant_id);

create table public.chunks (
  id          bigint generated always as identity primary key,
  tenant_id   uuid not null,
  document_id uuid not null,
  content     text not null,
  embedding   extensions.vector(384) not null,
  -- a chunk can only point at a document of the same tenant,
  -- even for code running with the service role
  foreign key (document_id, tenant_id)
    references public.documents (id, tenant_id) on delete cascade
);

create index chunks_tenant_id_idx on public.chunks (tenant_id);
create index chunks_embedding_idx on public.chunks
  using hnsw (embedding extensions.vector_cosine_ops);

alter table public.assistants enable row level security;
alter table public.documents enable row level security;
alter table public.chunks enable row level security;

-- using      = which existing rows you can see / change / delete
-- with check = what a row is allowed to look like after you write it
--              (stops inserting into, or moving a row to, another tenant)

create policy assistants_tenant on public.assistants
  for all to authenticated
  using (tenant_id in (select private.user_tenant_ids()))
  with check (tenant_id in (select private.user_tenant_ids()));

create policy documents_tenant on public.documents
  for all to authenticated
  using (tenant_id in (select private.user_tenant_ids()))
  with check (tenant_id in (select private.user_tenant_ids()));

create policy chunks_tenant on public.chunks
  for all to authenticated
  using (tenant_id in (select private.user_tenant_ids()))
  with check (tenant_id in (select private.user_tenant_ids()));

-- Vector search for logged-in users (dashboard, testing an assistant).
-- security invoker, so the chunks policy above still applies. The explicit
-- tenant filter is a second layer, and keeps the HNSW scan to one tenant.
create function public.match_chunks(
  p_tenant_id uuid,
  p_embedding extensions.vector(384),
  p_count     int default 5
)
returns table (id bigint, document_id uuid, content text, distance float8)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.id, c.document_id, c.content,
         c.embedding operator(extensions.<=>) p_embedding
  from public.chunks c
  where c.tenant_id = p_tenant_id
  order by c.embedding operator(extensions.<=>) p_embedding
  limit least(p_count, 20);
$$;

revoke all on function public.match_chunks(uuid, extensions.vector, int) from public, anon;
grant execute on function public.match_chunks(uuid, extensions.vector, int) to authenticated;
