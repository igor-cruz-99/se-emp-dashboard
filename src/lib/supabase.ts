import { createClient } from '@supabase/supabase-js'

/**
 * O front só fala com o Supabase para LOGIN (projeto dos funcionários).
 * Os DADOS passam pela API /api/dashboard (que valida a sessão no servidor e
 * consulta o banco com a service_role) — por isso não existe mais um cliente
 * de dados aqui, nem a anon key do projeto de dados no bundle.
 */
const authUrl = import.meta.env.VITE_SUPABASE_AUTH_URL as string | undefined
const authKey = import.meta.env.VITE_SUPABASE_AUTH_ANON_KEY as string | undefined

export const supabaseAuth =
  authUrl && authKey
    ? createClient(authUrl, authKey, {
        auth: {
          storageKey: 'se-emp-dashboard-auth',
          persistSession: true,
          autoRefreshToken: true,
          // PKCE: retorna ?code= de uso único em vez do token na URL.
          flowType: 'pkce',
          detectSessionInUrl: true,
        },
      })
    : null

export const isAuthConfigured = Boolean(authUrl && authKey)
