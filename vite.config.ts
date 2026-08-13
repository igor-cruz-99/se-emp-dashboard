import { defineConfig, loadEnv, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

/**
 * Em produção, a Vercel serve `api/dashboard.ts` como função serverless.
 * Em desenvolvimento, este plugin faz o próprio Vite servir a mesma função —
 * assim `npm run dev` já sobe site + API, sem precisar do Vercel CLI.
 */
function localApi(): Plugin {
  return {
    name: 'local-api',
    configureServer(server) {
      server.middlewares.use('/api/dashboard', async (req, res) => {
        try {
          // Lê o corpo da requisição
          const chunks: Buffer[] = []
          for await (const chunk of req) chunks.push(chunk as Buffer)
          const raw = Buffer.concat(chunks).toString()
          const body = raw ? JSON.parse(raw) : {}

          // Adapta req/res do Node para a assinatura que a função da Vercel espera
          const reqShim = { method: req.method, headers: req.headers, body }
          const resShim = {
            status(code: number) {
              res.statusCode = code
              return this
            },
            json(payload: unknown) {
              res.setHeader('Content-Type', 'application/json')
              res.end(JSON.stringify(payload))
            },
          }

          const mod = await server.ssrLoadModule('/api/dashboard.ts')
          await mod.default(reqShim, resShim)
        } catch (err) {
          res.statusCode = 500
          res.setHeader('Content-Type', 'application/json')
          res.end(JSON.stringify({ error: (err as Error)?.message ?? 'Erro na API local' }))
        }
      })
    },
  }
}

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  // Carrega TODAS as variáveis do .env (inclusive as sem prefixo VITE_) para o
  // process.env — a API local precisa delas. Isso roda só no Node do dev server;
  // no bundle do navegador o Vite continua expondo apenas as VITE_*.
  Object.assign(process.env, loadEnv(mode, process.cwd(), ''))

  return {
    plugins: [react(), tailwindcss(), localApi()],
    server: {
      port: 5185,
    },
    build: {
      chunkSizeWarningLimit: 900,
      rollupOptions: {
        output: {
          // Separa dependências grandes em chunks próprios (melhor cache do navegador).
          manualChunks(id: string) {
            if (!id.includes('node_modules')) return
            if (id.includes('recharts') || id.includes('d3-')) return 'charts'
            if (id.includes('@supabase')) return 'supabase'
            if (id.includes('react')) return 'react'
            return 'vendor'
          },
        },
      },
    },
  }
})
