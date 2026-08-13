import { useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabaseAuth } from '../lib/supabase'

/**
 * Estado de autenticação via Supabase Auth (projeto de funcionários).
 * - session: sessão atual (null = deslogado)
 * - loading: enquanto verifica a sessão inicial
 */
export function useAuth() {
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!supabaseAuth) {
      setLoading(false)
      return
    }
    // Sessão inicial (persistida no localStorage pelo supabase-js).
    supabaseAuth.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setLoading(false)
    })
    // Reage a login/logout/refresh de token.
    const { data: sub } = supabaseAuth.auth.onAuthStateChange((_event, s) => {
      setSession(s)
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  return { session, loading }
}
