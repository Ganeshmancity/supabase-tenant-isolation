-- Files: tenant id comes from the path, tenants/<tenant_id>/...

begin;
create extension if not exists pgtap with schema extensions;

select plan(6);

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

select pg_temp.act_as(:anna);

select isnt_empty(
  format($$ select 1 from storage.objects where name like 'tenants/%s/%%' $$, :riverside),
  'Anna can list her own files'
);

select is_empty(
  format($$ select 1 from storage.objects where name like 'tenants/%s/%%' $$, :hillcrest),
  'Anna cannot list Hillcrest files'
);

select throws_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('docs', 'tenants/%s/planted.pdf') $$, :hillcrest),
  '42501', null,
  'cannot upload into the Hillcrest folder'
);

select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values ('docs', 'loose-file.pdf') $$,
  '42501', null,
  'cannot upload outside a tenant folder'
);

select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values ('docs', 'tenants/not-a-uuid/x.pdf') $$,
  '42501', null,
  'a malformed tenant folder is rejected, not an error leak'
);

select lives_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('docs', 'tenants/%s/new.pdf') $$, :riverside),
  'can upload into her own folder'
);

select * from finish();
rollback;
