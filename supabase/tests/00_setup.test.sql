-- Guards that catch the usual way isolation breaks: someone adds a table
-- or a view later and forgets RLS.

begin;
create extension if not exists pgtap with schema extensions;

select plan(3);

select is_empty(
  $$ select c.relname
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind in ('r', 'p')
       and not c.relrowsecurity $$,
  'every table in public has RLS enabled'
);

-- views run as their owner by default, which skips RLS
select is_empty(
  $$ select c.relname
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind = 'v'
       and not coalesce(c.reloptions @> array['security_invoker=true'], false) $$,
  'every view in public uses security_invoker'
);

-- security definer functions skip RLS too; only the reviewed ones are allowed
select is(
  (select array_agg(p.proname::text order by p.proname)
   from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'private')
     and p.prosecdef),
  array['user_tenant_ids', 'widget_search'],
  'only reviewed functions are security definer'
);

select * from finish();
rollback;
