/**
 * Carrega o CSV de agendamentos em `public.se_agendamento_carga`.
 *
 *   node scripts/carregar-agendamentos.mjs "C:\\caminho\\arquivo.csv"
 *
 * Rode o sql/20_carga_agendamentos.sql ANTES (passo 1), e o passo 3 depois
 * para mover a tabela ao schema de backup.
 *
 * Envia em lotes de 500 pela API REST com a service_role. Não apaga nada:
 * se a tabela já tiver linhas, o script para e avisa — recarregar por cima
 * duplicaria tudo em silêncio.
 */
import { readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..')

// --- credenciais -----------------------------------------------------------
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
  console.error('✗ Faltam SUPABASE_URL / SUPABASE_SERVICE_ROLE no .env.local.')
  process.exit(1)
}
const cabecalhos = {
  apikey: KEY,
  Authorization: `Bearer ${KEY}`,
  'Content-Type': 'application/json',
}

// --- CSV -------------------------------------------------------------------
const arquivo = process.argv[2]
if (!arquivo || !existsSync(arquivo)) {
  console.error('uso: node scripts/carregar-agendamentos.mjs "<caminho do .csv>"')
  process.exit(1)
}

/**
 * Parser CSV com aspas. Escrito à mão em vez de usar biblioteca porque o
 * projeto não tem dependência de parsing e isto roda uma vez só — o formato
 * aqui é simples (vírgula, aspas duplas, aspas escapadas por duplicação).
 */
function parseCsv(texto) {
  const linhas = []
  let campos = []
  let atual = ''
  let dentroDeAspas = false

  for (let i = 0; i < texto.length; i++) {
    const c = texto[i]
    if (dentroDeAspas) {
      if (c === '"') {
        if (texto[i + 1] === '"') {
          atual += '"'
          i++
        } else dentroDeAspas = false
      } else atual += c
    } else if (c === '"') dentroDeAspas = true
    else if (c === ',') {
      campos.push(atual)
      atual = ''
    } else if (c === '\r') {
      /* ignora */
    } else if (c === '\n') {
      campos.push(atual)
      linhas.push(campos)
      campos = []
      atual = ''
    } else atual += c
  }
  if (atual || campos.length) {
    campos.push(atual)
    linhas.push(campos)
  }
  return linhas
}

// Cabeçalho do CSV → coluna da tabela.
const MAPA = {
  Data: 'data',
  'Hora Entrada': 'hora_entrada',
  Funil: 'funil',
  Origem: 'origem',
  Nome: 'nome',
  Email: 'email',
  Telefone: 'telefone',
  'Data sessão': 'data_sessao',
  'Hora Sessão': 'hora_sessao',
  Closer: 'closer',
  Situação: 'situacao',
  Observações: 'observacoes',
  'Comprou?': 'comprou',
  Produto: 'produto',
  'Data de Compra': 'data_de_compra',
  'Telefone Closer': 'telefone_closer',
  'Data lembrete 1': 'data_lembrete_1',
  'Lembrete 1 Enviado?': 'lembrete_1_enviado',
  'Data lembrete 2': 'data_lembrete_2',
  'Lembrete 2 Enviado?': 'lembrete_2_enviado',
  'Recuperação SDR?': 'recuperacao_sdr',
  'Nome SDR': 'nome_sdr',
  Renda: 'renda',
}

const linhas = parseCsv(readFileSync(arquivo, 'utf8'))
const cabecalho = linhas[0].map((h) => h.trim())
const naoMapeadas = cabecalho.filter((h) => h && !MAPA[h])
if (naoMapeadas.length) {
  console.error(`✗ Colunas do CSV sem correspondência: ${naoMapeadas.join(', ')}`)
  console.error('  Ajuste o MAPA no script antes de carregar.')
  process.exit(1)
}

const registros = linhas
  .slice(1)
  .filter((l) => l.some((c) => c && c.trim()))
  .map((l) => {
    const o = {}
    cabecalho.forEach((h, i) => {
      if (!MAPA[h]) return
      const v = (l[i] ?? '').trim()
      o[MAPA[h]] = v === '' ? null : v
    })
    return o
  })

console.log(`${registros.length} registros lidos de ${arquivo.split(/[\\/]/).pop()}`)

// --- carga -----------------------------------------------------------------
const TABELA = `${URL_BASE}/rest/v1/se_agendamento_carga`

const jaTem = await fetch(`${TABELA}?select=uid&limit=1`, { headers: cabecalhos })
if (!jaTem.ok) {
  console.error(`✗ ${jaTem.status}: ${await jaTem.text()}`)
  console.error('  → falta rodar o PASSO 1 do sql/20_carga_agendamentos.sql.')
  process.exit(1)
}
if ((await jaTem.json()).length > 0) {
  console.error('✗ A tabela já tem dados. Recarregar por cima duplicaria tudo.')
  console.error('  Para refazer: truncate public.se_agendamento_carga;')
  process.exit(1)
}

const LOTE = 500
let enviados = 0
for (let i = 0; i < registros.length; i += LOTE) {
  const lote = registros.slice(i, i + LOTE)
  const r = await fetch(TABELA, {
    method: 'POST',
    headers: { ...cabecalhos, Prefer: 'return=minimal' },
    body: JSON.stringify(lote),
  })
  if (!r.ok) {
    console.error(`✗ lote ${i / LOTE + 1} falhou (${r.status}): ${await r.text()}`)
    console.error(`  ${enviados} registros já entraram — rode o truncate antes de tentar de novo.`)
    process.exit(1)
  }
  enviados += lote.length
  process.stdout.write(`\r  ${enviados}/${registros.length} enviados`)
}

console.log(`\n✓ ${enviados} registros carregados.`)
console.log('  Agora rode o PASSO 3 do sql/20_carga_agendamentos.sql para mover ao backup.')
