// Runs every attempt from the demo page against the local API, for every
// seeded user. Needs `supabase start` first.

import { describe, expect, it } from 'vitest'
import { PASSWORD, USERS, attemptsFor, makeClient, widgetAttempts } from '../src/demo'

const URL = process.env.VITE_SUPABASE_URL ?? 'http://127.0.0.1:54321'
const KEY = process.env.VITE_SUPABASE_ANON_KEY

if (!KEY) throw new Error('Set VITE_SUPABASE_ANON_KEY (see README)')

for (const user of USERS) {
  describe(`${user.name} (${user.role})`, async () => {
    const client = makeClient(URL, KEY)
    const { error } = await client.auth.signInWithPassword({ email: user.email, password: PASSWORD })
    if (error) throw error

    it('sees exactly the tenants it should', async () => {
      const { data } = await client.from('tenants').select('id')
      expect(data!.map((t) => t.id).sort()).toEqual([...user.allowed].sort())
    })

    for (const attempt of await attemptsFor(client, user)) {
      it(`blocked: ${attempt.label} (${attempt.target})`, async () => {
        const outcome = await attempt.run()
        expect(outcome.blocked, outcome.detail).toBe(true)
      })
    }
  })
}

describe('anonymous visitor', () => {
  for (const attempt of widgetAttempts(makeClient(URL, KEY))) {
    it(`blocked: ${attempt.label}`, async () => {
      const outcome = await attempt.run()
      expect(outcome.blocked, outcome.detail).toBe(true)
    })
  }
})
