/**
 * Sonda de leitura do Business Data — para eu conferir o banco sem depender
 * de você abrir o SQL Editor e colar o resultado a cada pergunta.
 *
 *   node scripts/check.mjs "select count(*) from mkt_se.vw_agendamentos"
 *   node scripts/check.mjs --tabela mkt_se vw_agendamentos "limit=5"
 *
 * Dois modos:
 *
 *   SQL  (precisa da função mkt_se.q — ver sql/06_sonda.sql)
 *        roda qualquer SELECT, inclusive agregação. É o modo útil.
 *
 *        ⚠️ DESLIGADO desde 13/08/2026. O sql/30_fechar_sondas.sql removeu a
 *        `q` e a `se_q` antes da publicação — a `se_q` era security definer do
 *        `postgres`, ou seja, executava com poder de dono do banco. Este modo
 *        devolve 404 (PGRST202) até alguém rodar o sql/06 de novo, e nesse
 *        caso o sql/30 tem de ser rodado outra vez antes de publicar.
 *
 *   --tabela  (só precisa do schema exposto no Data API)
 *        lê uma tabela/view via PostgREST. Sem group by, sem join.
 *
 * Lê SUPABASE_URL e SUPABASE_SERVICE_ROLE do .env.local (fora do git).
 * Nunca imprime a chave.
 */
import { readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..')
const envPath = join(raiz, '.env.local')

if (!existsSync(envPath)) {
  console.error('✗ .env.local não encontrado.')
  process.exit(1)
}

const env = {}
for (const linha of readFileSync(envPath, 'utf8').split(/\r?\n/)) {
  const t = linha.trim()
  if (!t || t.startsWith('#')) continue
  const i = t.indexOf('=')
  if (i === -1) continue
  const v = t.slice(i + 1).trim().replace(/^["']|["']$/g, '')
  if (v) env[t.slice(0, i).trim()] = v
}

const URL_BASE = env.SUPABASE_URL
const KEY = env.SUPABASE_SERVICE_ROLE
if (!URL_BASE || !KEY) {
  console.error('✗ Faltam SUPABASE_URL e/ou SUPABASE_SERVICE_ROLE no .env.local.')
  process.exit(1)
}

const cabecalhos = { apikey: KEY, Authorization: `Bearer ${KEY}` }

function mostrar(dados) {
  if (Array.isArray(dados) && dados.length > 0 && typeof dados[0] === 'object') {
    console.table(dados)
    console.log(`${dados.length} linha(s)`)
  } else {
    console.log(JSON.stringify(dados, null, 2))
  }
}

const args = process.argv.slice(2)

if (args[0] === '--tabela') {
  // Leitura direta via PostgREST: node check.mjs --tabela <schema> <tabela> [query]
  const [, schema, tabela, query = 'limit=20'] = args
  if (!schema || !tabela) {
    console.error('uso: node scripts/check.mjs --tabela <schema> <tabela> ["select=a,b&limit=5"]')
    process.exit(1)
  }
  const r = await fetch(`${URL_BASE}/rest/v1/${tabela}?${query}`, {
    headers: { ...cabecalhos, 'Accept-Profile': schema },
  })
  const corpo = await r.json()
  if (!r.ok) {
    console.error(`✗ ${r.status}:`, corpo)
    if (r.status === 404) {
      console.error(`  → o schema "${schema}" provavelmente não está em Exposed schemas.`)
    }
    process.exit(1)
  }
  mostrar(corpo)
} else {
  // Modo SQL, via função mkt_se.q
  const sql = args.join(' ')
  if (!sql) {
    console.error('uso: node scripts/check.mjs "select ... from ..."')
    process.exit(1)
  }
  // Vai pelo `public.se_q`, não pelo `mkt_se.q`: o Exposed schemas deste
  // projeto está travado nos 4 originais e não aceita mkt_se. Ver 08.
  const r = await fetch(`${URL_BASE}/rest/v1/rpc/se_q`, {
    method: 'POST',
    headers: { ...cabecalhos, 'Content-Type': 'application/json' },
    body: JSON.stringify({ sql }),
  })
  const corpo = await r.json()
  if (!r.ok) {
    console.error(`✗ ${r.status}:`, corpo)
    if (r.status === 404) console.error('  → falta rodar sql/08_ponte_public.sql.')
    process.exit(1)
  }
  mostrar(corpo)
}
