import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from 'recharts'
import { Panel } from '../ui/Panel'
import { formatInt, formatPct } from '../../utils/format'
import { tooltipProps } from '../../utils/chartTheme'
import type { RendaLinha } from '../../types'

/**
 * Rosca da distribuição dos leads por faixa de renda.
 *
 * É o bloco que compensa o `%MQL` não informar nada: com o corte em 20 mil,
 * ~99% dos leads são MQL e o cartão fica cravado. O que mostra se o tráfego
 * está melhorando é o MIX — mais gente em 50–100k e 100k+, menos em 20–29k.
 *
 * As fatias seguem a ORDEM DA FAIXA (dado ordinal), não o volume: a cor
 * escurece conforme a renda sobe, então a leitura da rosca é monotônica e o
 * olho identifica a faixa pela cor sem consultar a legenda toda vez.
 */
const TOPO = [0x8c, 0xf8, 0xef]
const BASE = [0x0b, 0x86, 0x82]

function tom(t: number): string {
  const c = TOPO.map((v, i) => Math.round(v + (BASE[i] - v) * Math.min(Math.max(t, 0), 1)))
  return `rgb(${c[0]},${c[1]},${c[2]})`
}

interface Fatia {
  faixa: string
  leads: number
  pct: number | null
}

/**
 * Rótulo externo com linha-guia: nome da faixa em cima, contagem e % embaixo.
 * Recharts não tem rótulo de duas linhas pronto — daí o <text> manual com
 * dois <tspan>, ancorados conforme o lado da rosca para não invadir o centro.
 */
function Rotulo(props: {
  cx: number
  cy: number
  midAngle: number
  outerRadius: number
  payload: Fatia
}) {
  const { cx, cy, midAngle, outerRadius, payload } = props
  const RAD = Math.PI / 180
  const rInicio = outerRadius + 4
  const rCotovelo = outerRadius + 12
  const cos = Math.cos(-midAngle * RAD)
  const sin = Math.sin(-midAngle * RAD)

  const x1 = cx + rInicio * cos
  const y1 = cy + rInicio * sin
  const x2 = cx + rCotovelo * cos
  const y2 = cy + rCotovelo * sin
  const direita = cos >= 0
  const x3 = x2 + (direita ? 10 : -10)
  const miudo = (payload.pct ?? 0) < 3

  return (
    <g>
      <polyline
        points={`${x1},${y1} ${x2},${y2} ${x3},${y2}`}
        stroke="var(--color-line)"
        fill="none"
      />
      <text
        x={x3 + (direita ? 5 : -5)}
        y={y2}
        textAnchor={direita ? 'start' : 'end'}
        dominantBaseline="central"
      >
        {/* Fatia pequena ganha rótulo de UMA linha. Duas linhas empurram ~13px
            de altura, e fatias minúsculas ficam angularmente coladas nas
            vizinhas — foi o que fez '<20k' (0,2%) encostar em '100k+'. */}
        {miudo ? (
          <tspan fill="var(--color-ink)" fontSize={11} fontWeight={500}>
            {payload.faixa}
            <tspan fill="var(--color-muted)" fontSize={10}>
              {'  '}
              {formatInt(payload.leads)} ({formatPct(payload.pct, 0)})
            </tspan>
          </tspan>
        ) : (
          <>
            <tspan fill="var(--color-ink)" fontSize={11} fontWeight={500}>
              {payload.faixa}
            </tspan>
            <tspan x={x3 + (direita ? 5 : -5)} dy={13} fill="var(--color-muted)" fontSize={10}>
              {formatInt(payload.leads)} ({formatPct(payload.pct, 0)})
            </tspan>
          </>
        )}
      </text>
    </g>
  )
}

/**
 * `titulo` existe porque a mesma rosca serve dois blocos: a renda declarada
 * (aqui) e o aporte mensal, no perfil do lead. São escalas ordinais com o
 * mesmo formato de dado — duplicar o componente só multiplicaria o ajuste
 * fino dos rótulos externos, que foi a parte trabalhosa.
 */
export function RendaDonut({
  linhas,
  titulo = 'Renda dos leads',
}: {
  linhas: RendaLinha[]
  titulo?: string
}) {
  // Já vem ordenado pelo piso da faixa na RPC; só tira o que zerou.
  const dados: Fatia[] = linhas
    .filter((l) => l.leads > 0)
    .map((l) => ({ faixa: l.faixa, leads: l.leads, pct: l.pct }))

  const total = dados.reduce((s, d) => s + d.leads, 0)

  return (
    <Panel className="flex h-full flex-col p-5">
      <div className="mb-2 flex shrink-0 items-baseline justify-between">
        <h3 className="titulo">{titulo}</h3>
        <span className="numero text-xs text-muted">{formatInt(total)} leads</span>
      </div>

      {dados.length === 0 ? (
        <p className="flex flex-1 items-center justify-center text-sm text-faint">Sem leads no período.</p>
      ) : (
        // `flex-1`: a rosca ocupa a altura que sobra do cartão em vez de um
        // valor fixo. Como os três cartões da linha esticam para a mesma
        // altura, altura fixa deixava um vazio embaixo toda vez que um vizinho
        // crescia — e obrigava a reeditar o número a cada mudança.
        // O `min-h` é o piso: abaixo disso os rótulos externos se atropelam.
        <div className="min-h-[200px] flex-1">
          <ResponsiveContainer width="100%" height="100%">
            <PieChart margin={{ top: 8, right: 76, bottom: 8, left: 76 }}>
              <Pie
                data={dados}
                dataKey="leads"
                nameKey="faixa"
                cx="50%"
                cy="50%"
                innerRadius="54%"
                outerRadius="78%"
                paddingAngle={0.8}
                stroke="var(--color-card)"
                strokeWidth={1.5}
                isAnimationActive={false}
                labelLine={false}
                label={Rotulo as never}
              >
                {dados.map((_, i) => (
                  <Cell key={i} fill={tom(dados.length > 1 ? i / (dados.length - 1) : 0)} />
                ))}
              </Pie>
              <Tooltip
                {...tooltipProps}
                formatter={(v, n) => [`${formatInt(Number(v))} leads`, String(n)]}
              />
            </PieChart>
          </ResponsiveContainer>
        </div>
      )}
    </Panel>
  )
}
