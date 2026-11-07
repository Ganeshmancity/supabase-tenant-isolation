import { useEffect, useMemo, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
import {
  PASSWORD,
  USERS,
  attemptsFor,
  makeClient,
  widgetAttempts,
  type Attempt,
  type DemoUser,
  type Outcome,
} from './demo'

const URL = import.meta.env.VITE_SUPABASE_URL as string
const KEY = import.meta.env.VITE_SUPABASE_ANON_KEY as string

type Tenant = { id: string; name: string; kind: string }
type Doc = { id: string; title: string; tenant_id: string }
type Row = Attempt & { outcome?: Outcome }

export default function App() {
  const [user, setUser] = useState<DemoUser>(USERS[0])
  const [client, setClient] = useState<SupabaseClient | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [tenants, setTenants] = useState<Tenant[]>([])
  const [docs, setDocs] = useState<Doc[]>([])
  const [attempts, setAttempts] = useState<Row[]>([])
  const [running, setRunning] = useState(false)

  const anon = useMemo(() => makeClient(URL, KEY), [])
  const [widget, setWidget] = useState<Row[]>(() => widgetAttempts(anon))

  useEffect(() => {
    let cancelled = false
    setClient(null)
    setAttempts([])
    setError(null)

    const c = makeClient(URL, KEY)
    ;(async () => {
      const { error } = await c.auth.signInWithPassword({ email: user.email, password: PASSWORD })
      if (error) return !cancelled && setError(`Sign in failed: ${error.message}`)

      const [t, d] = await Promise.all([
        c.from('tenants').select('id, name, kind').order('name'),
        c.from('documents').select('id, title, tenant_id').order('title'),
      ])
      if (cancelled) return
      setTenants(t.data ?? [])
      setDocs(d.data ?? [])
      setAttempts(await attemptsFor(c, user))
      setClient(c)
    })()

    return () => {
      cancelled = true
    }
  }, [user])

  async function runAll() {
    setRunning(true)
    const done: Row[] = []
    for (const a of attempts) done.push({ ...a, outcome: await a.run() })
    setAttempts(done)

    const w: Row[] = []
    for (const a of widget) w.push({ ...a, outcome: await a.run() })
    setWidget(w)
    setRunning(false)
  }

  const all = [...attempts, ...widget]
  const finished = all.filter((a) => a.outcome)
  const leaks = finished.filter((a) => !a.outcome!.blocked).length

  return (
    <div className="page">
      <header>
        <h1>Tenant isolation demo</h1>
        <p className="muted">
          Supabase RLS for a multi-tenant chatbot platform. Sign in as one of the seeded users, then try to
          reach another tenant's data.
        </p>
      </header>

      <div className="layout">
        <aside>
          <h2>Sign in as</h2>
          <ul className="users">
            {USERS.map((u) => (
              <li key={u.email}>
                <button className={u.email === user.email ? 'user active' : 'user'} onClick={() => setUser(u)}>
                  <span className="name">{u.name}</span>
                  <span className="muted small">{u.role}</span>
                </button>
              </li>
            ))}
          </ul>
          <p className="muted small">
            Pixel North is an agency. Riverside Water is its client. Hillcrest Energy has nothing to do with
            either.
          </p>
        </aside>

        <main>
          {error && <p className="error">{error}</p>}

          <section>
            <h2>What {user.name} can see</h2>
            <table>
              <thead>
                <tr>
                  <th>Tenant</th>
                  <th>Type</th>
                  <th>Documents</th>
                </tr>
              </thead>
              <tbody>
                {tenants.map((t) => (
                  <tr key={t.id}>
                    <td>{t.name}</td>
                    <td>{t.kind}</td>
                    <td>
                      {docs
                        .filter((d) => d.tenant_id === t.id)
                        .map((d) => d.title)
                        .join(', ') || <span className="muted">none</span>}
                    </td>
                  </tr>
                ))}
                {client && tenants.length === 0 && (
                  <tr>
                    <td colSpan={3} className="muted">
                      nothing
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </section>

          <section>
            <div className="row">
              <h2>Trying to get around it</h2>
              <button className="run" disabled={!client || running} onClick={runAll}>
                {running ? 'Running…' : 'Run all'}
              </button>
              {finished.length > 0 && !running && (
                <span className={leaks ? 'bad' : 'good'}>
                  {leaks ? `${leaks} leaked` : `${finished.length} of ${all.length} blocked`}
                </span>
              )}
            </div>

            <AttemptTable title={`As ${user.name}`} rows={attempts} />
            <AttemptTable title="As an anonymous visitor (chat widget)" rows={widget} />
          </section>

          <p className="muted small">
            The same attempts run in CI against every user (<code>npm run test:api</code>), next to the
            database tests (<code>supabase test db</code>).
          </p>
        </main>
      </div>
    </div>
  )
}

function AttemptTable({ title, rows }: { title: string; rows: Row[] }) {
  return (
    <>
      <h3>{title}</h3>
      <table>
        <thead>
          <tr>
            <th>Attempt</th>
            <th>Target</th>
            <th>Result</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={i}>
              <td>{r.label}</td>
              <td>{r.target === 'any' || r.target === 'all' ? <span className="muted">{r.target}</span> : r.target}</td>
              <td>
                {r.outcome ? (
                  <>
                    <span className={r.outcome.blocked ? 'good' : 'bad'}>
                      {r.outcome.blocked ? 'blocked' : 'LEAKED'}
                    </span>{' '}
                    <span className="muted small mono">{r.outcome.detail}</span>
                  </>
                ) : (
                  <span className="muted">–</span>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </>
  )
}

