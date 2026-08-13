import { useAuth } from './hooks/useAuth'
import { DEV_SKIP_AUTH } from './lib/devAuth'
import { Dashboard } from './pages/Dashboard'
import { Login } from './pages/Login'

/** Decide Login × Dashboard pela sessão. Respeita o bypass de desenvolvimento. */
export function App() {
  const { session, loading } = useAuth()

  if (DEV_SKIP_AUTH) return <Dashboard />

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center text-sm text-muted">
        Carregando…
      </div>
    )
  }

  return session ? <Dashboard /> : <Login />
}
