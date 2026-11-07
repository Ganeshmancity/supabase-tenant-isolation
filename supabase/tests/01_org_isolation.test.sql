-- Anna (Riverside Water) tries to reach Hillcrest Energy's data.

begin;
create extension if not exists pgtap with schema extensions;

select plan(16);

create function pg_temp.act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

\set riverside '''0b000000-0000-4000-8000-000000000001'''
\set hillcrest '''0c000000-0000-4000-8000-000000000001'''
\set anna      '''00000000-0000-4000-8000-0000000000a1'''
\set hill_doc  '''d0000000-0000-4000-8000-0000000000c1'''
\set river_doc '''d0000000-0000-4000-8000-0000000000b1'''

select pg_temp.act_as(:anna);

-- reading ---------------------------------------------------------------

select results_eq(
  'select id from public.tenants',
  format('values (%L::uuid)', :riverside),
  'Anna sees only her own tenant'
);

select results_eq(
  'select distinct tenant_id from public.documents',
  format('values (%L::uuid)', :riverside),
  'Anna sees only Riverside documents'
);

select is_empty(
  format('select 1 from public.documents where tenant_id = %L', :hillcrest),
  'asking for Hillcrest documents by tenant id returns nothing'
);

select is_empty(
  format('select 1 from public.documents where id = %L', :hill_doc),
  'asking for a Hillcrest document by its id returns nothing'
);

select is_empty(
  $$ select 1 from public.chunks where content ilike '%2027%' $$,
  'the Hillcrest internal pricing text is not reachable'
);

select is_empty(
  format('select 1 from public.memberships where tenant_id = %L', :hillcrest),
  'Anna cannot list who works at Hillcrest'
);

select is_empty(
  format('select 1 from public.assistants where tenant_id = %L', :hillcrest),
  'Anna cannot read Hillcrest assistant settings'
);

-- vector search ---------------------------------------------------------

select is_empty(
  format($$ select 1 from public.match_chunks(%L, (select embedding from public.chunks limit 1)) $$, :hillcrest),
  'vector search with Hillcrest tenant id returns nothing'
);

select isnt_empty(
  format($$ select 1 from public.match_chunks(%L, (select embedding from public.chunks limit 1)) $$, :riverside),
  'vector search in her own tenant still works'
);

-- writing ---------------------------------------------------------------

select throws_ok(
  format($$ insert into public.documents (tenant_id, title) values (%L, 'planted') $$, :hillcrest),
  '42501', null,
  'cannot insert a document into Hillcrest'
);

select throws_ok(
  format($$ update public.documents set tenant_id = %L where id = %L $$, :hillcrest, :river_doc),
  '42501', null,
  'cannot move her own document into Hillcrest'
);

select is_empty(
  format($$ update public.documents set title = 'changed' where id = %L returning id $$, :hill_doc),
  'updating a Hillcrest document changes nothing'
);

select is_empty(
  format($$ delete from public.documents where tenant_id = %L returning id $$, :hillcrest),
  'deleting Hillcrest documents removes nothing'
);

select throws_ok(
  format($$ insert into public.memberships (user_id, tenant_id, role) values (%L, %L, 'owner') $$, :anna, :hillcrest),
  '42501', null,
  'cannot add herself to Hillcrest'
);

select lives_ok(
  format($$ insert into public.documents (tenant_id, title) values (%L, 'New price list') $$, :riverside),
  'can still add documents to her own tenant'
);

-- the data is really still there (checked as the database owner)
reset role;

select is(
  (select count(*)::int from public.documents where tenant_id = :hillcrest and title <> 'changed'),
  2,
  'Hillcrest documents are untouched'
);

select * from finish();
rollback;
