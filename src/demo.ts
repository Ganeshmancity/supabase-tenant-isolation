// Ids and users from supabase/seed.sql, plus the cross-tenant attempts.
// Used by both the demo page and the API tests, so what you click in the
// browser is exactly what CI runs.

import { createClient, type SupabaseClient } from '@supabase/supabase-js'

export const TENANTS = {
  pixelNorth: { id: '0a000000-0000-4000-8000-000000000001', name: 'Pixel North' },
  riverside: { id: '0b000000-0000-4000-8000-000000000001', name: 'Riverside Water' },
  hillcrest: { id: '0c000000-0000-4000-8000-000000000001', name: 'Hillcrest Energy' },
} as const

const ALL_TENANT_IDS = Object.values(TENANTS).map((t) => t.id)

export const PASSWORD = 'password123'

export type DemoUser = {
  email: string
  name: string
  role: string
  // what the policies should let this user see
  allowed: string[]
}

export const USERS: DemoUser[] = [
  {
    email: 'anna@riverside.test',
    name: 'Anna',
    role: 'member, Riverside Water',
    allowed: [TENANTS.riverside.id],
  },
  {
    email: 'ben@hillcrest.test',
    name: 'Ben',
    role: 'owner, Hillcrest Energy',
    allowed: [TENANTS.hillcrest.id],
  },
  {
    email: 'maja@pixelnorth.test',
    name: 'Maja',
    role: 'admin, Pixel North (agency for Riverside)',
    allowed: [TENANTS.pixelNorth.id, TENANTS.riverside.id],
  },
  {
    email: 'tom@pixelnorth.test',
    name: 'Tom',
    role: 'member, Pixel North',
    allowed: [TENANTS.pixelNorth.id],
  },
]

export const tenantName = (id: string) =>
  Object.values(TENANTS).find((t) => t.id === id)?.name ?? id

export function makeClient(url: string, key: string): SupabaseClient {
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
}

// any 384-dim vector works, the seeded embeddings are fake
export const QUERY_VECTOR = `[${Array.from({ length: 384 }, (_, i) => Math.sin(i * 0.37).toFixed(4)).join(',')}]`

export type Outcome = { blocked: boolean; detail: string }

export type Attempt = {
  label: string
  target: string
  run: () => Promise<Outcome>
}

const rows = (n: number): Outcome => ({ blocked: n === 0, detail: `${n} row${n === 1 ? '' : 's'}` })

const refused = (error: { code?: string; message: string } | null, okDetail = 'accepted'): Outcome =>
  error
    ? { blocked: true, detail: `${error.code ?? 'error'}: ${error.message}` }
    : { blocked: false, detail: okDetail }

// Everything a signed-in user should NOT be able to do, aimed at every tenant
// they don't belong to.
export async function attemptsFor(client: SupabaseClient, user: DemoUser): Promise<Attempt[]> {
  const foreign = ALL_TENANT_IDS.filter((id) => !user.allowed.includes(id))
  const { data: ownDocs } = await client.from('documents').select('id').limit(1)
  const ownDocId = ownDocs?.[0]?.id as string | undefined

  const list: Attempt[] = []

  for (const tid of foreign) {
    const target = tenantName(tid)

    list.push(
      {
        label: 'Read their documents',
        target,
        run: async () => {
          const { data, error } = await client.from('documents').select('id').eq('tenant_id', tid)
          return error ? refused(error) : rows(data.length)
        },
      },
      {
        label: 'Read their assistant settings',
        target,
        run: async () => {
          const { data, error } = await client.from('assistants').select('public_key').eq('tenant_id', tid)
          return error ? refused(error) : rows(data.length)
        },
      },
      {
        label: 'List their team',
        target,
        run: async () => {
          const { data, error } = await client.from('memberships').select('user_id').eq('tenant_id', tid)
          return error ? refused(error) : rows(data.length)
        },
      },
      {
        label: 'Vector search in their tenant',
        target,
        run: async () => {
          const { data, error } = await client.rpc('match_chunks', {
            p_tenant_id: tid,
            p_embedding: QUERY_VECTOR,
            p_count: 20,
          })
          return error ? refused(error) : rows(data.length)
        },
      },
      {
        label: 'Insert a document into their tenant',
        target,
        run: async () => {
          const { error } = await client.from('documents').insert({ tenant_id: tid, title: 'planted' })
          return refused(error, 'row inserted')
        },
      },
      {
        label: 'List files in their folder',
        target,
        run: async () => {
          const { data, error } = await client.storage.from('docs').list(`tenants/${tid}`)
          return error ? refused(error) : rows(data.length)
        },
      },
      {
        label: 'Upload a file into their folder',
        target,
        run: async () => {
          const { error } = await client.storage
            .from('docs')
            .upload(`tenants/${tid}/planted-${Date.now()}.txt`, new Blob(['x'], { type: 'text/plain' }))
          return refused(error, 'file uploaded')
        },
      },
    )

    if (ownDocId) {
      list.push({
        label: 'Move one of my documents into their tenant',
        target,
        run: async () => {
          const { data, error } = await client
            .from('documents')
            .update({ tenant_id: tid })
            .eq('id', ownDocId)
            .select('id')
          return error ? refused(error) : rows(data.length)
        },
      })
    }
  }

  if (!user.allowed.includes(TENANTS.hillcrest.id)) {
    list.push({
      label: 'Find the internal 2027 pricing text',
      target: 'Hillcrest Energy',
      run: async () => {
        const { data, error } = await client.from('chunks').select('id').ilike('content', '%2027%')
        return error ? refused(error) : rows(data.length)
      },
    })
  }

  list.push({
    label: 'Call the private membership function through the API',
    target: 'any',
    run: async () => {
      const { error } = await client.schema('private' as 'public').rpc('user_tenant_ids')
      return refused(error, 'function answered')
    },
  })

  return list
}

// The embedded widget, as an anonymous visitor.
export function widgetAttempts(anon: SupabaseClient): Attempt[] {
  const search = (key: string, origin: string) =>
    anon.rpc('widget_search', { p_public_key: key, p_origin: origin, p_embedding: QUERY_VECTOR, p_count: 10 })

  return [
    {
      label: 'Riverside widget returns Hillcrest text',
      target: 'Hillcrest Energy',
      run: async () => {
        const { data, error } = await search('pk_riverside_demo', 'https://riversidewater.example')
        if (error) return refused(error)
        const leaked = (data as { content: string }[]).filter((r) => /meter reading|2027/i.test(r.content))
        return { blocked: leaked.length === 0, detail: `${data.length} answers, ${leaked.length} from Hillcrest` }
      },
    },
    {
      label: 'Use the Riverside key from another website',
      target: 'Riverside Water',
      run: async () => refused((await search('pk_riverside_demo', 'https://evil.example')).error, 'answered'),
    },
    {
      label: 'Use a made-up key',
      target: 'any',
      run: async () => refused((await search('pk_guess', 'https://riversidewater.example')).error, 'answered'),
    },
    {
      label: 'Read documents without logging in',
      target: 'all',
      run: async () => {
        const { data, error } = await anon.from('documents').select('id')
        return error ? refused(error) : rows(data.length)
      },
    },
  ]
}
