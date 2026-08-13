import { useMemo, useState } from 'react'
import { Panel } from '../ui/Panel'
import { CampoBusca } from '../ui/CampoBusca'
import { heat, maxDe } from '../../utils/heat'
import { formatBRL, formatInt, formatPct } from '../../utils/format'
import type { TrafegoLinha } from '../../types'

/**
 * Tabela de tráfego de um nível (campanha, conjunto ou anúncio).
 *
 * Ordem padrão: investimento decrescente — o dinheiro é o que decide para onde
 * o olho vai primeiro. Clicar num cabeçalho reordena.
 *
 * O mapa de calor é por COLUNA, relativo ao maior valor dela: assim o realce
 * compara linhas entre si, que é a pergunta da tabela ("qual anúncio está
 * puxando o custo?"), e não valores de colunas diferentes.
 */

type Campo = keyof Pick<
  TrafegoLinha,
  | 'investimento'
  | 'vendas'
  | 'leads'
  | 'cpl'
  | 'agendamentos'
  | 'cac'
  | 'qualif_50k'
  | 'hook'
  | 'hold'
  | 'body'
>

interface Coluna {
  campo: Campo
  titulo: string
  formata: (v: number | null) => string
  /** colunas de contexto (Hook/Hold/Body) não entram no calor: poluiriam */
  comCalor?: boolean
}

// A ordem aqui é a ordem na tela. Agendamentos entra logo depois do CPL.
const COLUNAS: Coluna[] = [
  { campo: 'investimento', titulo: 'Investimento', formata: formatBRL, comCalor: true },
  { campo: 'vendas', titulo: 'Vendas', formata: (v) => formatInt(v), comCalor: true },
  { campo: 'leads', titulo: 'Leads', formata: (v) => formatInt(v), comCalor: true },
  { campo: 'cpl', titulo: 'CPL', formata: formatBRL, comCalor: true },
  { campo: 'agendamentos', titulo: 'Agendamentos', formata: (v) => formatInt(v), comCalor: true },
  { campo: 'cac', titulo: 'CAC', formata: formatBRL, comCalor: true },
  { campo: 'qualif_50k', titulo: 'Qualif. 50k+', formata: (v) => formatPct(v, 0), comCalor: true },
  { campo: 'hook', titulo: 'Hook', formata: (v) => formatPct(v, 0) },
  { campo: 'hold', titulo: 'Hold', formata: (v) => formatPct(v, 0) },
  { campo: 'body', titulo: 'Body', formata: (v) => formatPct(v, 0) },
]

export function TrafficTable({
  titulo,
  rotuloChave,
  linhas,
  busca,
  onBusca,
  selecionado,
  onSelecionar,
}: {
  titulo: string
  rotuloChave: string
  linhas: TrafegoLinha[]
  busca: string
  onBusca: (v: string) => void
  /** chave da linha em foco, para destacar */
  selecionado?: string | null
  /** clique na linha cruza o filtro com os outros níveis */
  onSelecionar?: (l: TrafegoLinha) => void
}) {
  const [ordem, setOrdem] = useState<{ campo: Campo; desc: boolean }>({
    campo: 'investimento',
    desc: true,
  })

  // A busca já foi aplicada pela SecaoTrafego (ela precisa do resultado dos três
  // níveis para cruzá-los). Aqui só ordena.
  const filtradas = useMemo(() => {
    return [...linhas].sort((a, b) => {
      const va = Number(a[ordem.campo] ?? -Infinity)
      const vb = Number(b[ordem.campo] ?? -Infinity)
      return ordem.desc ? vb - va : va - vb
    })
  }, [linhas, ordem])

  const maximos = useMemo(
    () =>
      Object.fromEntries(
        COLUNAS.map((c) => [c.campo, maxDe(filtradas, (l) => Number(l[c.campo] ?? 0))]),
      ) as Record<Campo, number>,
    [filtradas],
  )

  // O total soma; o "por unidade" (CPL, CAC, taxas) é recalculado do agregado.
  // Somar CPL linha a linha e dividir daria a média das médias, que é errada.
  const total = useMemo(() => {
    const s = filtradas.reduce(
      (acc, l) => ({
        investimento: acc.investimento + Number(l.investimento ?? 0),
        leads: acc.leads + Number(l.leads ?? 0),
        agendamentos: acc.agendamentos + Number(l.agendamentos ?? 0),
        vendas: acc.vendas + Number(l.vendas ?? 0),
      }),
      { investimento: 0, leads: 0, agendamentos: 0, vendas: 0 },
    )
    return {
      ...s,
      cpl: s.leads ? s.investimento / s.leads : null,
      cac: s.vendas ? s.investimento / s.vendas : null,
    }
  }, [filtradas])

  function ordenarPor(campo: Campo) {
    setOrdem((o) => (o.campo === campo ? { campo, desc: !o.desc } : { campo, desc: true }))
  }

  return (
    <div>
      <div className="mb-2 flex items-center gap-2">
        <span className="rotulo">{titulo}</span>
        <span className="numero rounded-md bg-card-alt px-1.5 py-0.5 text-[10px] text-muted">
          {filtradas.length}
        </span>
      </div>

      <CampoBusca
        valor={busca}
        onChange={onBusca}
        placeholder={rotuloChave}
        className="mb-3"
      />

      <Panel className="overflow-hidden">
        <div className="max-h-80 overflow-auto">
          <table className="w-full border-collapse text-sm">
            <thead className="sticky top-0 z-10 bg-card-alt">
              <tr>
                <th className="rotulo px-3 py-2.5 text-left font-semibold">{rotuloChave}</th>
                {COLUNAS.map((c) => (
                  <th
                    key={c.campo}
                    onClick={() => ordenarPor(c.campo)}
                    className="rotulo cursor-pointer px-3 py-2.5 text-right font-semibold whitespace-nowrap select-none hover:text-ink"
                    title="Clique para ordenar"
                  >
                    {c.titulo}
                    {ordem.campo === c.campo && (
                      <span className="ml-1 text-turq">{ordem.desc ? '▾' : '▴'}</span>
                    )}
                  </th>
                ))}
              </tr>
            </thead>

            <tbody>
              {filtradas.length === 0 ? (
                <tr>
                  <td colSpan={COLUNAS.length + 1} className="px-3 py-8 text-center text-faint">
                    Nada encontrado no período.
                  </td>
                </tr>
              ) : (
                filtradas.map((l) => {
                  const foco = selecionado != null && selecionado === l.chave
                  return (
                  <tr
                    key={`${l.campanha_pai ?? ''}|${l.conjunto_pai ?? ''}|${l.chave}`}
                    onClick={() => onSelecionar?.(l)}
                    className={`border-t border-line/60 ${
                      onSelecionar ? 'cursor-pointer hover:bg-card-alt/60' : ''
                    } ${foco ? 'bg-turq/10' : ''}`}
                    title={onSelecionar ? 'Clique para cruzar com os outros níveis' : undefined}
                  >
                    <td
                      className={`max-w-[260px] truncate px-3 py-2 ${
                        foco ? 'font-semibold text-turq' : 'text-ink'
                      }`}
                      title={l.chave}
                    >
                      {l.chave}
                    </td>
                    {COLUNAS.map((c) => {
                      const v = l[c.campo] as number | null
                      return (
                        <td
                          key={c.campo}
                          className="numero px-3 py-2 text-right whitespace-nowrap text-ink"
                          style={
                            c.comCalor
                              ? { background: heat(v, maximos[c.campo]) }
                              : undefined
                          }
                        >
                          {c.formata(v)}
                        </td>
                      )
                    })}
                  </tr>
                  )
                })
              )}
            </tbody>

            {filtradas.length > 0 && (
              <tfoot className="sticky bottom-0 bg-card-alt">
                <tr className="border-t border-line">
                  <td className="px-3 py-2.5 font-semibold text-ink">Total</td>
                  <td className="numero px-3 py-2.5 text-right font-semibold text-ink">
                    {formatBRL(total.investimento)}
                  </td>
                  <td className="numero px-3 py-2.5 text-right font-semibold text-ink">
                    {formatInt(total.vendas)}
                  </td>
                  <td className="numero px-3 py-2.5 text-right font-semibold text-ink">
                    {formatInt(total.leads)}
                  </td>
                  <td className="numero px-3 py-2.5 text-right font-semibold text-ink">
                    {formatBRL(total.cpl)}
                  </td>
                  <td className="numero px-3 py-2.5 text-right font-semibold text-ink">
                    {formatInt(total.agendamentos)}
                  </td>
                  <td className="numero px-3 py-2.5 text-right font-semibold text-ink">
                    {formatBRL(total.cac)}
                  </td>
                  <td colSpan={4} />
                </tr>
              </tfoot>
            )}
          </table>
        </div>
      </Panel>
    </div>
  )
}
