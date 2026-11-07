# supabase-tenant-isolation

[![test](https://github.com/Ganeshmancity/supabase-tenant-isolation/actions/workflows/test.yml/badge.svg)](https://github.com/Ganeshmancity/supabase-tenant-isolation/actions/workflows/test.yml)

Tenant isolation for a multi-tenant chatbot platform on Supabase, with the tests that prove it.

The setup: organisations upload documents and get their own chatbot. Agencies resell the product and manage several client organisations. A user from one tenant must never see, change, search or download another tenant's data, and the public chat widget must only ever answer from its own tenant's documents.

Everything here is enforced in Postgres (RLS), so it holds no matter which client talks to the database.

## Demo data

```
Pixel North        agency   maja (admin), tom (member)
└─ Riverside Water org      anna (member)
Hillcrest Energy   org      ben (owner)
```

Password for every user: `password123`. Hillcrest has an "internal" document about 2027 prices, which is used as the thing nobody else should ever reach.

## How it works

**One function decides access.** `private.user_tenant_ids()` returns the tenants the current user belongs to, plus the client tenants of any agency where they are owner or admin. Every policy calls it, so the rule lives in one place. It's `security definer` (it reads `memberships`, whose own policy calls it) and sits in a schema that isn't exposed through the API.

**Tables.** Every table has a `tenant_id`. Policies use `using` (what you can read, update, delete) and `with check` (what a row may look like after you write it). The second part is what stops inserting into another tenant, or moving your own row there. Chunks have a composite foreign key to `(document_id, tenant_id)`, so a chunk can't point at another tenant's document even from server code using the service role.

**Vector search.** `match_chunks` is `security invoker`, so RLS still applies, and it also filters on `tenant_id` itself. Two layers, and the HNSW scan stays inside one tenant.

**Files.** Private bucket, paths like `tenants/<tenant_id>/file.pdf`. Storage policies read the tenant id from the path. Anything that isn't `tenants/<valid uuid>/...` matches nothing.

**Chat widget.** Website visitors aren't logged in, so the normal policies give them nothing. `widget_search` finds the tenant from the assistant's public key (and checks the site is on the allowed list) and only searches that tenant. The tenant id never comes from the caller. In production a server route calls it with the request's `Origin` header and rate limits per key.

**What's not allowed from the browser.** Creating tenants and adding members goes through the server (service role), so there are only `select` policies on `tenants` and `memberships`.

## Tests

`supabase/tests` (pgTAP, `supabase test db`):

- every table in `public` has RLS on, views use `security_invoker`, and only the two reviewed functions are `security definer`. These catch the usual mistake: a new table added later without a policy.
- a member of one org trying to read, search, insert, update, delete and move data into another org
- agency admin vs agency member vs an org that isn't a client
- storage: listing and uploading into another tenant's folder, files outside any tenant folder, malformed paths
- the widget as an anonymous visitor: wrong website, made-up key, reading tables directly

`tests/api.test.ts` (Vitest) signs in as each user through the real API (PostgREST, Storage, RPC) and runs every cross-tenant attempt from `src/demo.ts` against every tenant that user doesn't belong to.

The demo page runs the same attempts, so what you click is what CI runs.

## Run it

Needs Docker and Node 20+.

```bash
npm install
npx supabase start          # applies migrations + seed
npx supabase test db        # database tests

npx supabase status         # copy the API URL and anon key into .env:
# VITE_SUPABASE_URL=http://127.0.0.1:54321
# VITE_SUPABASE_ANON_KEY=...

npx vitest run              # API tests
npm run dev                 # demo page on http://localhost:5173
```

## Notes

- The embeddings in the seed are fake. Retrieval quality isn't what this repo is about.
- Data residency, billing (Stripe) and the widget's server route aren't here. This is only the isolation layer, which everything else sits on.
