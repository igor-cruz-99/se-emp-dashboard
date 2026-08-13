/**
 * "Porteiro" do dashboard — roda no servidor (Vercel), nunca no navegador.
 *
 *   1. Recebe o token do usuário logado (projeto de AUTH dos funcionários).
 *   2. Valida esse token. Inválido → 401 e nada mais.
 *   3. Confere a allowlist — estar logado não basta.
 *   4. Só então consulta o Business Data com a service_role.
 *
 * A service_role fica só aqui (variável sem prefixo VITE_), então nunca vai
 * parar no bundle do navegador.
 *
 * ⚠️ As RPCs chamadas ficam no schema `public` (`se_*`), não em `mkt_se`.
 *    Motivo: o "Exposed schemas" deste projeto Supabase não aceita schemas
 *    novos, então o mkt_se é inalcançável pela API. As funções `se_*` são
 *    pontes finas no public — ver sql/08_ponte_public.sql.
 */
import { createClient } from '@supabase/supabase-js'

declare const process: { env: Record<string, string | undefined> }

const DATA_URL = process.env.SUPABASE_URL ?? process.env.VITE_SUPABASE_URL
const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE
const AUTH_URL = process.env.SUPABASE_AUTH_URL ?? process.env.VITE_SUPABASE_AUTH_URL
const AUTH_ANON = process.env.SUPABASE_AUTH_ANON_KEY ?? process.env.VITE_SUPABASE_AUTH_ANON_KEY

/** Operações permitidas — impede chamar RPC arbitrária pela API. */
const ALLOWED_RPC = new Set([
  'se_kpis',
  'se_serie_diaria',
  'se_origem',
  'se_renda',
  'se_trafego',
  'se_ciclo_vendas',
  'se_perfil_lead',
  'se_formularios',
  'se_macro',
  'se_metas',
])

interface Req {
  method?: string
  headers: Record<string, string | string[] | undefined>
  body?: { fn?: string; params?: Record<string, unknown> }
}
interface Res {
  status: (code: number) => Res
  json: (body: unknown) => void
}

const ALLOWED_EMAILS = (process.env.DASHBOARD_ALLOWED_EMAILS ?? '')
  .split(',')
  .map((e) => e.trim().toLowerCase())
  .filter(Boolean)
const ALLOWED_DOMAINS = (process.env.DASHBOARD_ALLOWED_DOMAINS ?? '')
  .split(',')
  .map((d) => d.trim().toLowerCase().replace(/^@/, ''))
  .filter(Boolean)

async function getUserEmail(token: string): Promise<string | null> {
  try {
    const r = await fetch(`${AUTH_URL}/auth/v1/user`, {
      headers: { apikey: AUTH_ANON as string, Authorization: `Bearer ${token}` },
    })
    if (!r.ok) return null
    const user = (await r.json()) as { email?: string }
    return user.email?.toLowerCase() ?? null
  } catch {
    return null
  }
}

/**
 * Interruptor de desenvolvimento. A trava `NODE_ENV !== 'production'` é o que
 * torna impossível ligar isso na Vercel, mesmo definindo a variável por engano.
 */
const DEV_SKIP_AUTH =
  process.env.DEV_SKIP_AUTH === '1' && process.env.NODE_ENV !== 'production'

function isAllowed(email: string): boolean {
  if (ALLOWED_EMAILS.includes(email)) return true
  const domain = email.split('@')[1] ?? ''
  return ALLOWED_DOMAINS.includes(domain)
}

export default async function handler(req: Req, res: Res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Método não permitido' })

  if (!DATA_URL || !SERVICE_ROLE || !AUTH_URL || !AUTH_ANON) {
    return res.status(500).json({ error: 'Servidor sem as variáveis de ambiente configuradas.' })
  }

  // Sem allowlist configurada, ninguém entra (falha fechada, nunca aberta).
  if (!DEV_SKIP_AUTH && ALLOWED_EMAILS.length === 0 && ALLOWED_DOMAINS.length === 0) {
    return res.status(500).json({
      error: 'Allowlist não configurada. Defina DASHBOARD_ALLOWED_EMAILS e/ou _DOMAINS.',
    })
  }

  if (!DEV_SKIP_AUTH) {
    const raw = req.headers.authorization
    const header = Array.isArray(raw) ? raw[0] : raw
    const token = header?.startsWith('Bearer ') ? header.slice(7) : ''
    if (!token) return res.status(401).json({ error: 'Sem token de sessão.' })

    const email = await getUserEmail(token)
    if (!email) return res.status(401).json({ error: 'Sessão inválida ou expirada.' })

    if (!isAllowed(email)) {
      return res.status(403).json({ error: 'Sua conta não tem acesso a este painel.' })
    }
  }

  const db = createClient(DATA_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const fn = req.body?.fn
  const params = req.body?.params ?? {}

  if (!fn || !ALLOWED_RPC.has(fn)) {
    return res.status(400).json({ error: 'Operação não permitida.' })
  }

  try {
    const { data, error } = await db.rpc(fn, params)
    if (error) throw error
    return res.status(200).json({ data })
  } catch (err) {
    const message = (err as { message?: string })?.message ?? 'Erro ao consultar os dados.'
    return res.status(500).json({ error: message })
  }
}
