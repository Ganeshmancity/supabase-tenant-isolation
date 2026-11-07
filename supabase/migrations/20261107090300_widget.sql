-- The embedded chat widget. Visitors on the customer's website are not
-- logged in, so auth.uid() is null and the normal policies give them nothing.
--
-- Instead the tenant comes from the assistant's public key, never from
-- anything else the caller sends. In production this is called by a server
-- route that passes the request's Origin header and rate limits per key;
-- the origin check here is a second gate, not the security boundary.
-- The real boundary: a key can only ever reach its own tenant's chunks.

create function public.widget_search(
  p_public_key text,
  p_origin     text,
  p_embedding  extensions.vector(384),
  p_count      int default 5
)
returns table (content text, distance float8)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
begin
  select a.tenant_id
    into v_tenant_id
  from public.assistants a
  where a.public_key = p_public_key
    and p_origin = any (a.allowed_origins);

  if v_tenant_id is null then
    raise exception 'unknown assistant or origin not allowed'
      using errcode = '42501';
  end if;

  return query
    select c.content,
           c.embedding operator(extensions.<=>) p_embedding
    from public.chunks c
    where c.tenant_id = v_tenant_id
    order by 2
    limit least(p_count, 10);
end;
$$;

revoke all on function public.widget_search(text, text, extensions.vector, int) from public;
grant execute on function public.widget_search(text, text, extensions.vector, int) to anon, authenticated;
