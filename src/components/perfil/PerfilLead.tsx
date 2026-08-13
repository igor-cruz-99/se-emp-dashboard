import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  LabelList,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { Panel } from '../ui/Panel'
import { RendaDonut } from '../origem/RendaDonut'
import { formatInt } from '../../utils/format'
import type { PerfilLinha } from '../../types'

/**
 * Perfil do lead — quando ele chega e quem ele é.
 *   Esquerda (1/3): leads por dia da semana · aporte mensal declarado.
 *   Direita  (2/3): atividade por horário   · profissão.
 *
 * O dia da semana fica na ordem natural (domingo→sábado), não por volume:
 * a pergunta aqui é como o lead se distribui ao longo da semana, e reordenar
 * por quantidade destruiria a sequência que dá sentido à leitura. O mesmo vale
 * para o aporte, que é escala. Já a profissão é categoria sem ordem própria —
 * essa ordena por volume, que é o que responde "quem mais chega".
 */

const DIAS = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado']

/**
 * 'Entre R$ 2.000 e R$ 5.000' → '2–5 mil'.
 * Os rótulos do formulário são frases inteiras e não cabem em volta da rosca.
 * A conversão é por regex, não por tabela fixa: se amanhã entrar uma faixa
 * nova no formulário ela encurta sozinha, e o que não casar cai no texto
 * original em vez de sumir.
 */
function curtoAporte(r: string): string {
  const valores = (r.match(/R\$\s*[\d.]+/g) ?? []).map((x) => {
    const n = Number(x.replace(/[^\d.]/g, '').replace(/\./g, ''))
    return n >= 1000 ? `${n / 1000} mil` : String(n)
  })
  if (valores.length >= 2) return `${valores[0].replace(' mil', '')}–${valores[1]}`
  if (valores.length === 1) return /acima|mais/i.test(r) ? `${valores[0]}+` : `Até ${valores[0]}`
  return r
}

const TOPO = [0x8c, 0xf8, 0xef]
const BASE = [0x0b, 0x86, 0x82]

/** Barra mais clara quanto maior o valor — o pico salta sem precisar de legenda. */
function tom(v: number, max: number): string {
  const t = max > 0 ? 1 - Math.min(v / max, 1) : 0.5
  const c = TOPO.map((x, i) => Math.round(x + (BASE[i] - x) * t))
  return `rgb(${c[0]},${c[1]},${c[2]})`
}

const eixoTick = { fill: 'var(--color-muted)', fontSize: 11 }
const tooltipEstilo = {
  background: 'var(--color-card-alt)',
  border: '1px solid var(--color-line)',
  borderRadius: 10,
  fontSize: 12,
}

export function PerfilLead({ linhas }: { linhas: PerfilLinha[] }) {
  const dias = linhas
    .filter((l) => l.tipo === 'dia_semana')
    .sort((a, b) => a.ordem - b.ordem)
    .map((l) => ({ rotulo: DIAS[l.ordem] ?? '?', leads: Number(l.leads) }))

  const horas = linhas
    .filter((l) => l.tipo === 'hora')
    .sort((a, b) => a.ordem - b.ordem)
    .map((l) => ({
      rotulo: `${String(l.ordem).padStart(2, '0')}:00`,
      leads: Number(l.leads),
    }))

  const semHora = Number(linhas.find((l) => l.tipo === 'sem_hora')?.leads ?? 0)

  // Aporte: a RPC já devolve na ordem da escala e sem vazios. O percentual é
  // calculado aqui sobre QUEM RESPONDEU — não sobre o total de leads, senão
  // as fatias somariam menos de 100% e pareceriam erro de conta.
  const aporteBruto = linhas.filter((l) => l.tipo === 'aporte').sort((a, b) => a.ordem - b.ordem)
  const totalAporte = aporteBruto.reduce((s, l) => s + Number(l.leads), 0)
  const aporte = aporteBruto.map((l) => ({
    faixa: curtoAporte(l.rotulo ?? '—'),
    ordem: l.ordem,
    leads: Number(l.leads),
    pct: totalAporte > 0 ? (100 * Number(l.leads)) / totalAporte : null,
  }))

  const profissoes = linhas
    .filter((l) => l.tipo === 'profissao')
    .sort((a, b) => a.ordem - b.ordem)
    .map((l) => ({ rotulo: l.rotulo ?? '—', leads: Number(l.leads) }))

  const totalProf = profissoes.reduce((s, p) => s + p.leads, 0)

  const maxDia = Math.max(1, ...dias.map((d) => d.leads))
  const maxHora = Math.max(1, ...horas.map((h) => h.leads))
  const maxProf = Math.max(1, ...profissoes.map((p) => p.leads))

  return (
    <div className="mt-8">
      <p className="rotulo">Análise</p>
      <h2 className="mt-1 mb-4 text-2xl font-bold tracking-tight text-ink">Perfil do lead</h2>

      <div className="grid grid-cols-1 gap-5 lg:grid-cols-3">
        {/* ---------- 1/3: dia da semana ---------- */}
        <Panel className="p-5">
          <h3 className="titulo mb-4">Leads por dia da semana</h3>
          <div className="h-72">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart
                data={dias}
                layout="vertical"
                margin={{ top: 4, right: 44, left: 4, bottom: 4 }}
              >
                <XAxis type="number" hide domain={[0, maxDia]} />
                <YAxis
                  type="category"
                  dataKey="rotulo"
                  width={68}
                  tick={eixoTick}
                  axisLine={false}
                  tickLine={false}
                />
                <Tooltip
                  cursor={{ fill: 'var(--color-card-alt)' }}
                  contentStyle={tooltipEstilo}
                  labelStyle={{ color: 'var(--color-muted)' }}
                  formatter={(v) => [`${formatInt(Number(v))} leads`, '']}
                />
                <Bar dataKey="leads" radius={[0, 4, 4, 0]} isAnimationActive={false}>
                  {dias.map((d, i) => (
                    <Cell key={i} fill={tom(d.leads, maxDia)} />
                  ))}
                  <LabelList
                    dataKey="leads"
                    position="right"
                    formatter={(v) => formatInt(Number(v))}
                    style={{ fill: 'var(--color-ink)', fontSize: 11, fontWeight: 600 }}
                  />
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        </Panel>

        {/* ---------- 2/3: horário ---------- */}
        <Panel className="p-5 lg:col-span-2">
          <div className="mb-4 flex items-baseline justify-between gap-4">
            <h3 className="titulo">Atividade por horário</h3>
            {semHora > 0 && (
              <span className="text-[11px] text-faint">
                {formatInt(semHora)} sem horário confiável, fora do gráfico
              </span>
            )}
          </div>
          <div className="h-72">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={horas} margin={{ top: 18, right: 8, left: 0, bottom: 4 }}>
                <CartesianGrid stroke="var(--color-line)" vertical={false} />
                <XAxis
                  dataKey="rotulo"
                  tick={eixoTick}
                  axisLine={false}
                  tickLine={false}
                  interval={0}
                  angle={-45}
                  textAnchor="end"
                  height={52}
                />
                <YAxis tick={eixoTick} axisLine={false} tickLine={false} width={40} />
                <Tooltip
                  cursor={{ fill: 'var(--color-card-alt)' }}
                  contentStyle={tooltipEstilo}
                  labelStyle={{ color: 'var(--color-muted)' }}
                  formatter={(v) => [`${formatInt(Number(v))} leads`, '']}
                />
                <Bar dataKey="leads" radius={[3, 3, 0, 0]} isAnimationActive={false}>
                  {horas.map((h, i) => (
                    <Cell key={i} fill={tom(h.leads, maxHora)} />
                  ))}
                  <LabelList
                    dataKey="leads"
                    position="top"
                    formatter={(v) => (Number(v) > 0 ? formatInt(Number(v)) : '')}
                    style={{ fill: 'var(--color-muted)', fontSize: 10 }}
                  />
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        </Panel>

        {/* ---------- 1/3: aporte mensal declarado ----------
            ⚠️ Vem de `disposto_a_investir`, que é o APORTE POR MÊS — não a
            renda nem a reserva. O rótulo precisa dizer isso, porque a rosca de
            faixa de renda fica logo acima na página e a confusão entre os dois
            campos já existe na base. */}
        <RendaDonut linhas={aporte} titulo="Aporte mensal declarado" />

        {/* ---------- 2/3: profissão ---------- */}
        <Panel className="p-5 lg:col-span-2">
          <div className="mb-4 flex items-baseline justify-between gap-4">
            <h3 className="titulo">Profissão</h3>
            <span className="numero text-xs text-muted">
              {formatInt(totalProf)} responderam
            </span>
          </div>
          <div className="h-80">
            {profissoes.length === 0 ? (
              <p className="flex h-full items-center justify-center text-sm text-faint">
                Sem profissão informada no período.
              </p>
            ) : (
              <ResponsiveContainer width="100%" height="100%">
                <BarChart
                  data={profissoes}
                  layout="vertical"
                  margin={{ top: 4, right: 52, left: 4, bottom: 4 }}
                >
                  {/* ⚠️ `domain` explícito: sem ele o eixo escondido não calcula
                      escala e as barras saem com largura zero. */}
                  <XAxis type="number" hide domain={[0, maxProf]} />
                  <YAxis
                    type="category"
                    dataKey="rotulo"
                    // 132px: "Servidor Público" é o rótulo mais longo da lista
                    // e quebrava em duas linhas com menos que isso.
                    width={132}
                    tick={eixoTick}
                    axisLine={false}
                    tickLine={false}
                  />
                  <Tooltip
                    cursor={{ fill: 'var(--color-card-alt)' }}
                    contentStyle={tooltipEstilo}
                    labelStyle={{ color: 'var(--color-muted)' }}
                    formatter={(v) => [`${formatInt(Number(v))} leads`, '']}
                  />
                  <Bar dataKey="leads" radius={[0, 4, 4, 0]} isAnimationActive={false}>
                    {profissoes.map((p, i) => (
                      <Cell key={i} fill={tom(p.leads, maxProf)} />
                    ))}
                    <LabelList
                      dataKey="leads"
                      position="right"
                      formatter={(v) => formatInt(Number(v))}
                      style={{ fill: 'var(--color-ink)', fontSize: 11, fontWeight: 600 }}
                    />
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            )}
          </div>
        </Panel>
      </div>
    </div>
  )
}
