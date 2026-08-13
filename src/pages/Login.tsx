import { useState } from 'react'
import type { FormEvent } from 'react'
import { supabaseAuth, isAuthConfigured } from '../lib/supabase'

export function Login() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    if (!supabaseAuth) return
    setLoading(true)
    setError(null)
    const { error } = await supabaseAuth.auth.signInWithPassword({ email, password })
    setLoading(false)
    if (error) {
      // Mensagens amigáveis para os casos comuns.
      setError(
        error.message.includes('Invalid login')
          ? 'Email ou senha incorretos.'
          : error.message
      )
    }
    // Sucesso: o onAuthStateChange no App troca pra tela do dashboard.
  }

  async function handleGoogle() {
    if (!supabaseAuth) return
    setError(null)
    // Redireciona pro Google e volta pra esta URL (precisa estar na allowlist
    // de Redirect URLs do projeto de auth).
    const { error } = await supabaseAuth.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.origin },
    })
    if (error) setError(error.message)
  }

  return (
    <div className="flex min-h-screen items-center justify-center px-4">
      <div className="w-full max-w-sm">
        <div className="mb-6 flex flex-col items-center gap-3 text-center">
          {/* Marca em texto até existir um /logo.png da Sessão Estratégica.
              Basta soltar o arquivo em public/ e trocar por <img src="/logo.png" />. */}
          <div className="text-3xl font-bold tracking-tight text-turq">SE</div>
          <div>
            <p className="text-[10px] font-semibold uppercase tracking-[0.25em] text-muted">
              Dashboard
            </p>
            <h1 className="text-2xl font-bold text-ink">
              Sessão Estratégica
            </h1>
          </div>
        </div>

        <form
          onSubmit={handleSubmit}
          className="flex flex-col gap-4 rounded-2xl border border-line bg-card p-6"
        >
          <label className="flex flex-col gap-1.5">
            <span className="text-[11px] font-semibold uppercase tracking-[0.15em] text-muted">
              Email
            </span>
            <input
              type="email"
              required
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="rounded-lg border border-line bg-card-alt px-3 py-2.5 text-sm text-ink outline-none focus:border-turq/60"
              placeholder="voce@empresa.com"
            />
          </label>

          <label className="flex flex-col gap-1.5">
            <span className="text-[11px] font-semibold uppercase tracking-[0.15em] text-muted">
              Senha
            </span>
            <input
              type="password"
              required
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="rounded-lg border border-line bg-card-alt px-3 py-2.5 text-sm text-ink outline-none focus:border-turq/60"
              placeholder="••••••••"
            />
          </label>

          {error && (
            <p className="rounded-lg border border-[#e07b4f]/40 bg-[#e07b4f]/10 px-3 py-2 text-xs text-[#e8a05c]">
              {error}
            </p>
          )}

          {!isAuthConfigured && (
            <p className="rounded-lg border border-line bg-card-alt px-3 py-2 text-xs text-muted">
              Auth não configurado (.env.local vazio).
            </p>
          )}

          <button
            type="submit"
            disabled={loading || !isAuthConfigured}
            className="mt-1 flex items-center justify-center gap-2 rounded-lg bg-turq px-4 py-2.5 text-sm font-semibold text-bg transition-opacity hover:opacity-90 disabled:opacity-50"
          >
            {loading ? 'Entrando…' : 'Entrar'}
          </button>

          {/* Divisor */}
          <div className="flex items-center gap-3 py-1">
            <span className="h-px flex-1 bg-line" />
            <span className="text-[10px] uppercase tracking-[0.2em] text-muted">ou</span>
            <span className="h-px flex-1 bg-line" />
          </div>

          {/* Entrar com Google */}
          <button
            type="button"
            onClick={handleGoogle}
            disabled={!isAuthConfigured}
            className="flex items-center justify-center gap-2.5 rounded-lg border border-line bg-card-alt px-4 py-2.5 text-sm font-semibold text-ink transition-colors hover:border-turq/50 disabled:opacity-50"
          >
            <svg width="16" height="16" viewBox="0 0 48 48" aria-hidden>
              <path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3c-1.6 4.7-6.1 8-11.3 8-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.9 1.2 8 3.1l5.7-5.7C34.6 6.1 29.6 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.3-.4-3.5z"/>
              <path fill="#FF3D00" d="m6.3 14.7 6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.9 1.2 8 3.1l5.7-5.7C34.6 6.1 29.6 4 24 4 16.3 4 9.7 8.3 6.3 14.7z"/>
              <path fill="#4CAF50" d="M24 44c5.5 0 10.5-2.1 14.3-5.6l-6.6-5.6C29.6 34.5 26.9 36 24 36c-5.2 0-9.6-3.3-11.3-7.9l-6.5 5C9.6 39.6 16.2 44 24 44z"/>
              <path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.6 5.6C39.9 36.2 44 30.7 44 24c0-1.3-.1-2.3-.4-3.5z"/>
            </svg>
            Entrar com Google
          </button>
        </form>
      </div>
    </div>
  )
}
