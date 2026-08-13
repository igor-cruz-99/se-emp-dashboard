/**
 * Gera a versão executável de um SQL a partir do modelo com placeholders.
 *
 *   node scripts/gerar-sql.mjs            → gera todos os sql/*.sql que tiverem <<...>>
 *   node scripts/gerar-sql.mjs 01_fdw     → gera só esse
 *
 * Lê os valores do .env.local (que fica fora do git) e escreve em
 * sql/.gerado/<nome>.local.sql — também fora do git.
 *
 * Motivo de existir: as senhas dos bancos do Anchor e do Backup QV precisam
 * entrar no SQL, mas não podem viver num arquivo versionado nem passar por
 * chat/log. O modelo fica no git com placeholders; o arquivo com segredo é
 * gerado na máquina, usado e pode ser apagado.
 */
import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync } from 'node:fs'
import { join, dirname, basename } from 'node:path'
import { fileURLToPath } from 'node:url'

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..')
const dirSql = join(raiz, 'sql')
const dirSaida = join(dirSql, '.gerado')

// --- .env.local -------------------------------------------------------------
const envPath = join(raiz, '.env.local')
if (!existsSync(envPath)) {
  console.error('✗ .env.local não encontrado.')
  console.error('  Copie o .env.example para .env.local e preencha os valores.')
  process.exit(1)
}

/** Parser simples de .env: IGNORA comentários e linhas vazias, não expande nada. */
const env = {}
for (const linha of readFileSync(envPath, 'utf8').split(/\r?\n/)) {
  const t = linha.trim()
  if (!t || t.startsWith('#')) continue
  const i = t.indexOf('=')
  if (i === -1) continue
  const chave = t.slice(0, i).trim()
  let valor = t.slice(i + 1).trim()
  // tolera valor entre aspas
  if (
    (valor.startsWith('"') && valor.endsWith('"')) ||
    (valor.startsWith("'") && valor.endsWith("'"))
  ) {
    valor = valor.slice(1, -1)
  }
  if (valor) env[chave] = valor
}

// --- quais arquivos gerar ---------------------------------------------------
const alvo = process.argv[2]
const arquivos = readdirSync(dirSql)
  .filter((f) => f.endsWith('.sql'))
  .filter((f) => (alvo ? f.startsWith(alvo) : true))

if (arquivos.length === 0) {
  console.error(`✗ Nenhum .sql encontrado em sql/${alvo ? ` para "${alvo}"` : ''}.`)
  process.exit(1)
}

mkdirSync(dirSaida, { recursive: true })

let gerados = 0
let falhou = false

for (const arquivo of arquivos) {
  const modelo = readFileSync(join(dirSql, arquivo), 'utf8')
  const placeholders = [...new Set([...modelo.matchAll(/<<([A-Z0-9_]+)>>/g)].map((m) => m[1]))]
  if (placeholders.length === 0) continue

  const faltando = placeholders.filter((p) => !env[p])
  if (faltando.length > 0) {
    console.error(`✗ ${arquivo}: faltam no .env.local → ${faltando.join(', ')}`)
    falhou = true
    continue
  }

  // Aspas simples dentro de uma senha quebrariam o literal do SQL. Duplicar
  // é o escape do Postgres ('ab''c' = ab'c).
  let saida = modelo
  for (const p of placeholders) {
    saida = saida.replaceAll(`<<${p}>>`, env[p].replaceAll("'", "''"))
  }

  const destino = join(dirSaida, `${basename(arquivo, '.sql')}.local.sql`)
  writeFileSync(destino, saida, 'utf8')
  console.log(`✓ ${arquivo} → sql/.gerado/${basename(destino)}  (${placeholders.length} valores)`)
  gerados++
}

if (falhou) process.exit(1)
if (gerados === 0) {
  console.log('Nada a gerar — nenhum arquivo tem placeholders.')
} else {
  console.log('\nAbra o arquivo gerado e cole no SQL Editor do projeto CERTO:')
  console.log('  00_roles_remotos → Parte A no ANCHOR, Parte B no BACKUP QV')
  console.log('  01_fdw           → BUSINESS DATA')
}
