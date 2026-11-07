-- The public chat widget: anonymous visitors, tenant decided by the key.

begin;
create extension if not exists pgtap with schema extensions;

select plan(7);

-- a query vector to search with (any will do, the embeddings are fake)
create temp table q as select embedding from public.chunks limit 1;
grant select on q to anon;

select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select isnt_empty(
  $$ select 1 from public.widget_search('pk_riverside_demo', 'https://riversidewater.example',
                                        (select embedding from q)) $$,
  'Riverside widget answers on the Riverside site'
);

select is_empty(
  $$ select 1 from public.widget_search('pk_riverside_demo', 'https://riversidewater.example',
                                        (select embedding from q), 10)
     where content ilike '%meter reading%' or content ilike '%2027%' $$,
  'Riverside widget never returns Hillcrest text'
);

select throws_ok(
  $$ select * from public.widget_search('pk_riverside_demo', 'https://evil.example',
                                        (select embedding from q)) $$,
  '42501', null,
  'key used from another website is refused'
);

select throws_ok(
  $$ select * from public.widget_search('pk_made_up', 'https://riversidewater.example',
                                        (select embedding from q)) $$,
  '42501', null,
  'unknown key is refused'
);

select is_empty(
  'select 1 from public.documents',
  'anonymous visitors cannot read documents directly'
);

select is_empty(
  'select 1 from public.chunks',
  'anonymous visitors cannot read chunks directly'
);

select throws_ok(
  $$ select * from public.match_chunks('0c000000-0000-4000-8000-000000000001',
                                       (select embedding from q)) $$,
  '42501', null,
  'anonymous visitors cannot call the logged-in search'
);

select * from finish();
rollback;
