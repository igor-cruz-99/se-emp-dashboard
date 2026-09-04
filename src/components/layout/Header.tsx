import type { Filtros } from '../../types'
import { FiltroOrigens } from './FiltroOrigens'
import { BotaoImposto } from './BotaoImposto'
import { paraISO } from '../../utils/format'

/** Atalhos de período pedidos no escopo: 30D · 7D · Ontem · Hoje. */
export type Atalho = '30d' | '7d' | 'ontem' | 'hoje'

const ATALHOS: { chave: Atalho; texto: string }[] = [
  { chave: '30d', texto: '30D' },
  { chave: '7d', texto: '7D' },
  { chave: 'ontem', texto: 'ONTEM' },
  { chave: 'hoje', texto: 'HOJE' },
]

/**
 * Período padrão: o mês corrente inteiro, do dia 1 ao último dia.
 * O fim vai até o último dia mesmo que ainda não tenha chegado — é assim que o
 * gestor lê o mês ("como estamos em agosto"), e as sessões já marcadas para os
 * dias à frente aparecem como pipeline em vez de sumirem do recorte.
 * `new Date(ano, mes + 1, 0)` devolve o último dia do mês sem tabela de 30/31.
 */
export function mesAtual(): { inicio: string; fim: string } {
  const h = new Date()
  return {
    inicio: paraISO(new Date(h.getFullYear(), h.getMonth(), 1)),
    fim: paraISO(new Date(h.getFullYear(), h.getMonth() + 1, 0)),
  }
}

/** Converte o atalho em intervalo de datas. Hoje/Ontem são um dia só. */
export function periodoDoAtalho(a: Atalho): { inicio: string; fim: string } {
  const hoje = new Date()
  const ontem = new Date()
  ontem.setDate(hoje.getDate() - 1)

  switch (a) {
    case 'hoje':
      return { inicio: paraISO(hoje), fim: paraISO(hoje) }
    case 'ontem':
      return { inicio: paraISO(ontem), fim: paraISO(ontem) }
    case '7d': {
      const i = new Date()
      i.setDate(hoje.getDate() - 6)
      return { inicio: paraISO(i), fim: paraISO(hoje) }
    }
    default: {
      const i = new Date()
      i.setDate(hoje.getDate() - 29)
      return { inicio: paraISO(i), fim: paraISO(hoje) }
    }
  }
}

export function Header({
  filtros,
  atalho,
  onAtalho,
  onPeriodo,
  origensDisponiveis,
  origensDesmarcadas,
  onOrigens,
  imposto,
  onImposto,
  onSair,
}: {
  filtros: Filtros
  atalho: Atalho | null
  onAtalho: (a: Atalho) => void
  onPeriodo: (inicio: string, fim: string) => void
  origensDisponiveis: string[]
  origensDesmarcadas: string[]
  onOrigens: (desmarcadas: string[]) => void
  imposto: boolean
  onImposto: (v: boolean) => void
  onSair: () => void
}) {
  return (
    <header className="flex flex-wrap items-end justify-between gap-4 px-1 pt-2 pb-6">
      <div>
        <p className="rotulo">Performance</p>
        <h1 className="mt-1 text-3xl font-bold tracking-tight text-turq">
          Dashboard — Sessão Estratégica
        </h1>
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <FiltroOrigens
          disponiveis={origensDisponiveis}
          desmarcadas={origensDesmarcadas}
          onMudar={onOrigens}
        />

        <div className="flex items-center gap-1 rounded-full border border-line bg-card p-1">
          {ATALHOS.map((a) => (
            <button
              key={a.chave}
              onClick={() => onAtalho(a.chave)}
              className={`rounded-full px-4 py-1.5 text-xs font-semibold tracking-wide transition ${
                atalho === a.chave ? 'bg-turq text-bg' : 'text-muted hover:text-ink'
              }`}
            >
              {a.texto}
            </button>
          ))}
        </div>

        <div className="flex items-center gap-2 rounded-full border border-line bg-card px-4 py-2">
          <input
            type="date"
            value={filtros.inicio}
            onChange={(e) => onPeriodo(e.target.value, filtros.fim)}
            className="bg-transparent text-xs text-ink outline-none"
          />
          <span className="text-faint">→</span>
          <input
            type="date"
            value={filtros.fim}
            onChange={(e) => onPeriodo(filtros.inicio, e.target.value)}
            className="bg-transparent text-xs text-ink outline-none"
          />
        </div>

        <BotaoImposto ligado={imposto} onMudar={onImposto} />

        <button
          onClick={onSair}
          className="rounded-full border border-line px-4 py-2 text-xs text-muted transition hover:text-ink"
        >
          SAIR
        </button>
      </div>
    </header>
  )
}
