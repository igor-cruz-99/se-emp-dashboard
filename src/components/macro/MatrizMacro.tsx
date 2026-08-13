import { useMemo } from 'react'
import {
  Bar,
  CartesianGrid,
  ComposedChart,
  LabelList,
  Line,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { Panel } from '../ui/Panel'
import { heat, maxDe } from '../../utils/heat'
import { corEscala } from '../../utils/metaColor'
import { formatBRL, formatBRLCurto, formatInt, formatPct } from '../../utils/format'
import type { MacroLinha } from '../../types'

/**
 * Matriz de visão macro — o ano inteiro, mês a mês, e o combo leads × CPL.
 *
 * ⚠️ Esta seção NÃO reage ao filtro de datas da página: é a visão de
 * tendência. Recortá-la pelo mesmo período dos outros blocos a tornaria uma
 * repetição deles.
 *
 * Meses futuros aparecem zerados de propósito — o eixo precisa ir de janeiro a
 * dezembro para a escala não mentir sobre onde o ano está.
 */

const MESES = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
]

/** '2026-03-01' → 'março'. Fatia a string: `new Date(iso)` seria lido como UTC
 *  e voltaria um dia, jogando o mês para o anterior em fuso -03. */
function nomeMes(iso: string): string {
  const m = Number(iso.slice(5, 7))
  return MESES[m - 1] ?? iso
}

interface Coluna {
  chave: keyof MacroLinha
  titulo: string
  formata: (v: number | null) => string
  /** fundo proporcional ao volume — para colunas de tamanho (investimento, leads) */
  comCalor?: boolean
  /**
   * Texto em vermelho→verde comparando os meses entre si. Só nas colunas de
   * EFICIÊNCIA, onde existe "bom" e "ruim". Volume não entra: um mês com mais
   * leads não é melhor nem pior, é só maior.
   */
  escala?: 'maior' | 'menor'
}

const COLUNAS: Coluna[] = [
  { chave: 'investimento', titulo: 'Investimento', formata: formatBRL, comCalor: true },
  { chave: 'impressoes', titulo: 'Impressões', formata: (v) => formatInt(v) },
  { chave: 'cliques', titulo: 'Cliques', formata: (v) => formatInt(v) },
  { chave: 'cpc', titulo: 'CPC', formata: formatBRL },
  { chave: 'leads', titulo: 'Leads', formata: (v) => formatInt(v), comCalor: true },
  { chave: 'cpl', titulo: 'CPL', formata: formatBRL, escala: 'menor' },
  { chave: 'mql', titulo: 'MQL', formata: (v) => formatInt(v) },
  { chave: 'pct_mql', titulo: '%MQL', formata: (v) => formatPct(v, 1), escala: 'maior' },
  { chave: 'cpmql', titulo: 'CPMQL', formata: formatBRL },
  { chave: 'agendamentos', titulo: 'Agendamentos', formata: (v) => formatInt(v), comCalor: true },
  { chave: 'agendas', titulo: 'Agendas', formata: (v) => formatInt(v) },
  { chave: 'calls', titulo: 'Calls realizadas', formata: (v) => formatInt(v) },
  { chave: 'cust_agen', titulo: '$Cust/Agen', formata: formatBRL, escala: 'menor' },
  { chave: 'vendas', titulo: 'Vendas', formata: (v) => formatInt(v), comCalor: true },
  { chave: 'cac', titulo: 'CAC', formata: formatBRL, escala: 'menor' },
]

export function MatrizMacro({ linhas }: { linhas: MacroLinha[] }) {
  /**
   * Faixa (mín/máx) de cada coluna com escala, considerando SÓ os meses que
   * têm dado. Incluir setembro em diante — que vem zerado — faria o zero virar
   * o "melhor CPL do ano" e jogaria todos os meses reais para o vermelho.
   */
  const faixas = useMemo(() => {
    const r: Record<string, { min: number; max: number }> = {}
    for (const c of COLUNAS) {
      if (!c.escala) continue
      const vs = linhas
        .map((l) => l[c.chave])
        .filter((v): v is number => typeof v === 'number' && Number.isFinite(v) && v > 0)
      if (vs.length) r[String(c.chave)] = { min: Math.min(...vs), max: Math.max(...vs) }
    }
    return r
  }, [linhas])

  const maximos = useMemo(
    () =>
      Object.fromEntries(
        COLUNAS.map((c) => [c.chave, maxDe(linhas, (l) => Number(l[c.chave] ?? 0))]),
      ) as Record<string, number>,
    [linhas],
  )

  /**
   * O total soma o que é somável e RECALCULA o que é razão. Média de CPL
   * mensal não é o CPL do ano: meses com poucos leads pesariam igual aos
   * grandes, e o número do rodapé não bateria com o dos cartões.
   */
  const total = useMemo(() => {
    const s = linhas.reduce(
      (a, l) => ({
        investimento: a.investimento + Number(l.investimento ?? 0),
        impressoes: a.impressoes + Number(l.impressoes ?? 0),
        cliques: a.cliques + Number(l.cliques ?? 0),
        leads: a.leads + Number(l.leads ?? 0),
        mql: a.mql + Number(l.mql ?? 0),
        agendamentos: a.agendamentos + Number(l.agendamentos ?? 0),
        agendas: a.agendas + Number(l.agendas ?? 0),
        calls: a.calls + Number(l.calls ?? 0),
        vendas: a.vendas + Number(l.vendas ?? 0),
      }),
      {
        investimento: 0,
        impressoes: 0,
        cliques: 0,
        leads: 0,
        mql: 0,
        agendamentos: 0,
        agendas: 0,
        calls: 0,
        vendas: 0,
      },
    )
    const div = (a: number, b: number) => (b > 0 ? a / b : null)
    return {
      ...s,
      cpc: div(s.investimento, s.cliques),
      cpl: div(s.investimento, s.leads),
      cpmql: div(s.investimento, s.mql),
      pct_mql: s.leads ? (100 * s.mql) / s.leads : null,
      cust_agen: div(s.investimento, s.agendamentos),
      cac: div(s.investimento, s.vendas),
    } as Record<string, number | null>
  }, [linhas])

  // Só os meses que já aconteceram entram no gráfico — uma linha de CPL
  // despencando para zero em setembro leria como queda de custo, não como
  // ausência de dado.
  const serie = useMemo(
    () =>
      linhas
        .filter((l) => Number(l.leads ?? 0) > 0 || Number(l.investimento ?? 0) > 0)
        .map((l) => ({
          mes: nomeMes(l.mes),
          leads: Number(l.leads ?? 0),
          cpl: l.cpl == null ? null : Number(l.cpl),
        })),
    [linhas],
  )

  const anoAtual = linhas[0]?.mes?.slice(0, 4) ?? ''

  return (
    <div className="mt-8">
      <p className="rotulo">Visão macro</p>
      <div className="mt-1 mb-4 flex items-baseline gap-3">
        <h2 className="text-2xl font-bold tracking-tight text-ink">Matriz mês a mês</h2>
        <span className="numero rounded-md bg-card-alt px-2 py-0.5 text-xs text-muted">
          {anoAtual}
        </span>
        <span className="text-[11px] text-faint">não segue o filtro de período</span>
      </div>

      <Panel className="mb-5 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-sm">
            <thead className="bg-card-alt">
              <tr>
                <th className="titulo sticky left-0 z-10 bg-card-alt px-3 py-2.5 text-left">Mês</th>
                {COLUNAS.map((c) => (
                  <th
                    key={String(c.chave)}
                    className="titulo px-3 py-2.5 text-right whitespace-nowrap"
                  >
                    {c.titulo}
                  </th>
                ))}
              </tr>
            </thead>

            <tbody>
              {linhas.map((l) => {
                const vazio = Number(l.investimento ?? 0) === 0 && Number(l.leads ?? 0) === 0
                return (
                  <tr
                    key={l.mes}
                    className={`border-t border-line/60 ${vazio ? 'opacity-40' : ''}`}
                  >
                    <td className="sticky left-0 z-10 bg-card px-3 py-2 whitespace-nowrap text-ink capitalize">
                      {nomeMes(l.mes)}
                    </td>
                    {COLUNAS.map((c) => {
                      const v = l[c.chave] as number | null
                      const faixa = c.escala ? faixas[String(c.chave)] : undefined
                      return (
                        <td
                          key={String(c.chave)}
                          className="numero px-3 py-2 text-right font-medium whitespace-nowrap"
                          style={{
                            background: c.comCalor
                              ? heat(v, maximos[String(c.chave)])
                              : undefined,
                            color:
                              (faixa && c.escala
                                ? corEscala(v, faixa.min, faixa.max, c.escala)
                                : undefined) ?? 'var(--color-ink)',
                          }}
                        >
                          {c.formata(v)}
                        </td>
                      )
                    })}
                  </tr>
                )
              })}
            </tbody>

            <tfoot className="bg-card-alt">
              <tr className="border-t border-line">
                <td className="sticky left-0 z-10 bg-card-alt px-3 py-2.5 font-semibold text-ink">
                  Total
                </td>
                {COLUNAS.map((c) => {
                  /**
                   * "Agendas" é gente única no MÊS. Somar os doze meses conta
                   * duas vezes quem agendou em meses diferentes — no ano são
                   * 1.177 somados contra 1.142 reais. Marcado com ~ e explicado
                   * no hover; corrigir exigiria uma consulta anual só para esta
                   * célula, e o número somado ainda é útil como ordem de grandeza.
                   */
                  const aproximado = c.chave === 'agendas'
                  return (
                    <td
                      key={String(c.chave)}
                      className="numero px-3 py-2.5 text-right font-semibold whitespace-nowrap text-ink"
                      title={
                        aproximado
                          ? 'Soma dos meses: quem agendou em mais de um mês é contado uma vez por mês. O total real de pessoas no ano é menor.'
                          : undefined
                      }
                    >
                      {aproximado ? '~' : ''}
                      {c.formata(total[String(c.chave)] ?? null)}
                    </td>
                  )
                })}
              </tr>
            </tfoot>
          </table>
        </div>
      </Panel>

      {/* ---------- combo: leads em barra, CPL em linha ---------- */}
      <Panel className="p-5">
        <div className="mb-4 flex items-baseline justify-between">
          <h3 className="titulo">Leads e CPL por mês</h3>
          <div className="flex items-center gap-4 text-[10px] text-muted">
            <span className="flex items-center gap-1.5">
              <span className="inline-block h-2 w-2 rounded-full bg-turq" /> LEADS
            </span>
            <span className="flex items-center gap-1.5">
              <span className="inline-block h-0.5 w-4 bg-warn" /> CPL
            </span>
          </div>
        </div>

        <div className="h-80">
          <ResponsiveContainer width="100%" height="100%">
            <ComposedChart
              data={serie}
              margin={{ top: 12, right: 12, left: 0, bottom: 4 }}
              // Barras largas: com 8 meses sobra espaço horizontal, e barra
              // fina desperdiça a área do gráfico sem ganhar precisão.
              // O vão de 22% é o que ainda separa um mês do outro.
              barCategoryGap="22%"
            >
              <CartesianGrid stroke="var(--color-line)" vertical={false} />
              <XAxis
                dataKey="mes"
                tick={{ fill: 'var(--color-muted)', fontSize: 11 }}
                axisLine={false}
                tickLine={false}
              />
              {/* Eixos separados: leads chegam a milhares, CPL fica na casa das
                  dezenas. Num eixo só, a linha de CPL viraria um traço no chão. */}
              <YAxis
                yAxisId="leads"
                tick={{ fill: 'var(--color-muted)', fontSize: 11 }}
                axisLine={false}
                tickLine={false}
                width={48}
              />
              <YAxis
                yAxisId="cpl"
                orientation="right"
                tick={{ fill: 'var(--color-warn)', fontSize: 11 }}
                axisLine={false}
                tickLine={false}
                width={64}
                tickFormatter={(v) => formatBRLCurto(Number(v))}
              />
              <Tooltip
                cursor={{ fill: 'var(--color-card-alt)' }}
                contentStyle={{
                  background: 'var(--color-card-alt)',
                  border: '1px solid var(--color-line)',
                  borderRadius: 10,
                  fontSize: 12,
                }}
                labelStyle={{ color: 'var(--color-muted)', textTransform: 'capitalize' }}
                formatter={(v, n) =>
                  n === 'cpl'
                    ? [formatBRL(Number(v)), 'CPL']
                    : [`${formatInt(Number(v))} leads`, 'Leads']
                }
              />
              <Bar
                yAxisId="leads"
                dataKey="leads"
                fill="var(--color-turq)"
                radius={[3, 3, 0, 0]}
                maxBarSize={110}
                isAnimationActive={false}
              >
                <LabelList
                  dataKey="leads"
                  position="top"
                  formatter={(v) => formatInt(Number(v))}
                  style={{ fill: 'var(--color-ink)', fontSize: 11, fontWeight: 600 }}
                />
              </Bar>
              <Line
                yAxisId="cpl"
                type="monotone"
                dataKey="cpl"
                stroke="var(--color-warn)"
                strokeWidth={2}
                dot={{ r: 4, fill: 'var(--color-warn)', stroke: 'var(--color-bg)', strokeWidth: 2 }}
                isAnimationActive={false}
                connectNulls
              >
                {/* Rótulo abaixo do ponto para não colidir com o número da
                    barra, que fica acima dela. */}
                <LabelList
                  dataKey="cpl"
                  position="bottom"
                  offset={10}
                  formatter={(v) => formatBRL(Number(v))}
                  style={{ fill: 'var(--color-warn)', fontSize: 11, fontWeight: 600 }}
                />
              </Line>
            </ComposedChart>
          </ResponsiveContainer>
        </div>
      </Panel>
    </div>
  )
}
