import { Panel } from '../ui/Panel'
import { formatBRL, formatInt, formatPct } from '../../utils/format'
import type { OrigemLinha } from '../../types'

/**
 * "Investimento por origem" — barras horizontais.
 *
 * ⚠️ Feito com divs, não com Recharts. O `BarChart layout="vertical"` renderiza
 * o retângulo com largura zero aqui (o <g> da barra sai vazio), e para 2–7
 * origens uma biblioteca de gráfico não paga o próprio peso. Divs também
 * deixam esta metade com a mesma linguagem do cartão de leads ao lado.
 *
 * A barra é proporcional ao MAIOR investimento, não ao total: com uma origem
 * concentrando quase tudo, proporcional ao total apagaria as demais.
 *
 * O degradê acompanha a ordem — turquesa claro no maior, fundo no menor —,
 * mesma linguagem do funil: a cor já indica posição antes de o olho ler o valor.
 */
const TOPO = [0x8c, 0xf8, 0xef]
const BASE = [0x0b, 0x86, 0x82]

function tom(t: number): string {
  const c = TOPO.map((v, i) => Math.round(v + (BASE[i] - v) * Math.min(Math.max(t, 0), 1)))
  return `rgb(${c[0]},${c[1]},${c[2]})`
}

export function InvestimentoOrigemChart({ linhas }: { linhas: OrigemLinha[] }) {
  const dados = linhas
    .filter((l) => l.investimento > 0)
    .sort((a, b) => b.investimento - a.investimento)

  const max = Math.max(1, ...dados.map((d) => d.investimento))
  const total = dados.reduce((s, d) => s + d.investimento, 0)

  return (
    <Panel className="p-5">
      <div className="mb-4 flex items-baseline justify-between">
        <h3 className="titulo">Investimento por origem</h3>
        <span className="numero text-xs text-muted">{formatBRL(total)}</span>
      </div>

      {dados.length === 0 ? (
        <p className="py-8 text-center text-sm text-faint">Sem investimento no período.</p>
      ) : (
        <div className="flex flex-col gap-3">
          {dados.map((d, i) => (
            <div key={d.origem}>
              <div className="mb-1 flex items-baseline justify-between gap-3">
                <span className="truncate text-sm text-ink" title={d.origem}>
                  {d.origem}
                </span>
                <span className="numero shrink-0 text-sm font-semibold text-ink">
                  {formatBRL(d.investimento)}
                </span>
              </div>

              <div className="flex items-center gap-3">
                <div className="h-2.5 flex-1 overflow-hidden rounded-full bg-card-alt">
                  <div
                    className="h-full rounded-full"
                    style={{
                      width: `${(d.investimento / max) * 100}%`,
                      background: `linear-gradient(90deg, ${tom(
                        dados.length > 1 ? i / (dados.length - 1) : 0,
                      )}, ${tom(dados.length > 1 ? (i + 0.6) / (dados.length - 1) : 0.3)})`,
                    }}
                  />
                </div>
                <span className="numero w-12 shrink-0 text-right text-xs text-muted">
                  {formatPct(total ? (d.investimento / total) * 100 : null, 0)}
                </span>
              </div>

              <div className="mt-1 text-[11px] text-ink">
                {formatInt(d.leads)} leads · CPL {formatBRL(d.cpl)}
              </div>
            </div>
          ))}
        </div>
      )}
    </Panel>
  )
}
