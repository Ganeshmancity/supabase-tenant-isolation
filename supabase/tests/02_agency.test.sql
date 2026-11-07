-- Agencies: admins see their client orgs, plain members don't,
-- and nobody at the agency sees orgs that aren't their clients.

begin;
create extension if not exists pgtap with schema extensions;

select plan(7);

create function pg_temp.act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

\set agency    '''0a000000-0000-4000-8000-000000000001'''
\set riverside '''0b000000-0000-4000-8000-000000000001'''
\set hillcrest '''0c000000-0000-4000-8000-000000000001'''
\set ben       '''00000000-0000-4000-8000-0000000000b1'''
\set maja      '''00000000-0000-4000-8000-0000000000c1'''
\set tom       '''00000000-0000-4000-8000-0000000000c2'''

-- Maja, agency admin
select pg_temp.act_as(:maja);

select set_eq(
  'select id from public.tenants',
  format('values (%L::uuid), (%L::uuid)', :agency, :riverside),
  'agency admin sees the agency and its client Riverside'
);

select isnt_empty(
  format('select 1 from public.documents where tenant_id = %L', :riverside),
  'agency admin can read client documents'
);

select is_empty(
  format('select 1 from public.documents where tenant_id = %L', :hillcrest),
  'agency admin cannot read Hillcrest (not a client)'
);

select throws_ok(
  format($$ insert into public.documents (tenant_id, title) values (%L, 'planted') $$, :hillcrest),
  '42501', null,
  'agency admin cannot write into Hillcrest'
);

-- Tom, plain agency member
reset role;
select pg_temp.act_as(:tom);

select results_eq(
  'select id from public.tenants',
  format('values (%L::uuid)', :agency),
  'agency member sees only the agency itself'
);

select is_empty(
  format('select 1 from public.documents where tenant_id = %L', :riverside),
  'agency member cannot read client documents'
);

-- Ben, Hillcrest owner
reset role;
select pg_temp.act_as(:ben);

select results_eq(
  'select id from public.tenants',
  format('values (%L::uuid)', :hillcrest),
  'Hillcrest owner sees neither the agency nor its clients'
);

select * from finish();
rollback;
