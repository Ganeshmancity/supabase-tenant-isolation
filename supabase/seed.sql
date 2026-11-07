-- Demo data. Fixed ids so tests and the demo app can refer to them.
--
--   Pixel North        agency   maja (admin), tom (member)
--   └─ Riverside Water org      anna (member)
--   Hillcrest Energy   org      ben (owner)       <- not an agency client
--
-- Every user's password is: password123

-- users ----------------------------------------------------------------

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
  extensions.crypt('password123', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', jsonb_build_object('name', u.name), now(), now(),
  '', '', '', ''
from (values
  ('00000000-0000-4000-8000-0000000000a1'::uuid, 'anna@riverside.test',  'Anna'),
  ('00000000-0000-4000-8000-0000000000b1'::uuid, 'ben@hillcrest.test',   'Ben'),
  ('00000000-0000-4000-8000-0000000000c1'::uuid, 'maja@pixelnorth.test', 'Maja'),
  ('00000000-0000-4000-8000-0000000000c2'::uuid, 'tom@pixelnorth.test',  'Tom')
) as u (id, email, name);

insert into auth.identities (
  id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
)
select gen_random_uuid(), u.id, u.id::text,
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
       'email', now(), now(), now()
from auth.users u
where u.email like '%.test';

-- tenants ----------------------------------------------------------------

insert into public.tenants (id, name, kind, agency_id) values
  ('0a000000-0000-4000-8000-000000000001', 'Pixel North',      'agency', null),
  ('0b000000-0000-4000-8000-000000000001', 'Riverside Water',  'org',    '0a000000-0000-4000-8000-000000000001'),
  ('0c000000-0000-4000-8000-000000000001', 'Hillcrest Energy', 'org',    null);

insert into public.memberships (user_id, tenant_id, role) values
  ('00000000-0000-4000-8000-0000000000a1', '0b000000-0000-4000-8000-000000000001', 'member'),
  ('00000000-0000-4000-8000-0000000000b1', '0c000000-0000-4000-8000-000000000001', 'owner'),
  ('00000000-0000-4000-8000-0000000000c1', '0a000000-0000-4000-8000-000000000001', 'admin'),
  ('00000000-0000-4000-8000-0000000000c2', '0a000000-0000-4000-8000-000000000001', 'member');

-- assistants (one embeddable chatbot per org) ------------------------------

insert into public.assistants (tenant_id, name, public_key, allowed_origins) values
  ('0b000000-0000-4000-8000-000000000001', 'Riverside help',  'pk_riverside_demo', '{https://riversidewater.example}'),
  ('0c000000-0000-4000-8000-000000000001', 'Hillcrest help',  'pk_hillcrest_demo', '{https://hillcrest-energy.example}');

-- documents + chunks ---------------------------------------------------------
-- The embeddings are fake (a deterministic function of the row number).
-- Retrieval quality isn't what this repo is about; who can reach which row is.

insert into public.documents (id, tenant_id, title, storage_path) values
  ('d0000000-0000-4000-8000-0000000000b1', '0b000000-0000-4000-8000-000000000001', 'Billing FAQ',
   'tenants/0b000000-0000-4000-8000-000000000001/billing-faq.pdf'),
  ('d0000000-0000-4000-8000-0000000000b2', '0b000000-0000-4000-8000-000000000001', 'Leaks and outages',
   'tenants/0b000000-0000-4000-8000-000000000001/leaks.pdf'),
  ('d0000000-0000-4000-8000-0000000000c1', '0c000000-0000-4000-8000-000000000001', 'Meter readings',
   'tenants/0c000000-0000-4000-8000-000000000001/meter-readings.pdf'),
  ('d0000000-0000-4000-8000-0000000000c2', '0c000000-0000-4000-8000-000000000001', 'Pricing plan 2027 (internal)',
   'tenants/0c000000-0000-4000-8000-000000000001/pricing-2027-internal.pdf');

insert into public.chunks (tenant_id, document_id, content, embedding)
select c.tenant_id, c.document_id, c.content,
       array(select sin(g * 0.37 * c.n) from generate_series(1, 384) g)::extensions.vector(384)
from (values
  (1, '0b000000-0000-4000-8000-000000000001'::uuid, 'd0000000-0000-4000-8000-0000000000b1'::uuid,
      'Water bills are sent every two months. You can pay by direct debit or bank transfer.'),
  (2, '0b000000-0000-4000-8000-000000000001'::uuid, 'd0000000-0000-4000-8000-0000000000b1'::uuid,
      'If a bill looks too high, check the meter for a leak before contacting us.'),
  (3, '0b000000-0000-4000-8000-000000000001'::uuid, 'd0000000-0000-4000-8000-0000000000b2'::uuid,
      'To report a burst pipe on the street, call the 24 hour line. We aim to be on site within 4 hours.'),
  (4, '0c000000-0000-4000-8000-000000000001'::uuid, 'd0000000-0000-4000-8000-0000000000c1'::uuid,
      'Submit your meter reading by the 25th of the month to avoid an estimated bill.'),
  (5, '0c000000-0000-4000-8000-000000000001'::uuid, 'd0000000-0000-4000-8000-0000000000c2'::uuid,
      'INTERNAL: tariffs go up 6% from March 2027. Do not share with customers before the board signs off.')
) as c (n, tenant_id, document_id, content);

-- file metadata only (no actual bytes), enough for listing/policy checks
insert into storage.objects (bucket_id, name, metadata)
select 'docs', d.storage_path, '{"mimetype":"application/pdf","size":0}'::jsonb
from public.documents d;
