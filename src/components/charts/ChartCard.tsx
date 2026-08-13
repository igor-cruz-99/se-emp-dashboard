import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { Panel, SectionTitle } from '../ui/Panel'
import { diaCurto } from '../../utils/format'
import type { DiaSerie } from '../../types'

/**
 * Gráfico diário em barras, com linha tracejada na média do período —
 * é a média que dá sentido à barra individual ("esse dia foi acima ou abaixo?").
 */
export function ChartCard({
  titulo,
  sub,
  serie,
  campo,
  formatar,
  onDia,
  diaSelecionado,
}: {
  titulo: string
  sub?: string
  serie: DiaSerie[]
  campo: keyof DiaSerie
  formatar: (v: number | null) => string
  /** clique na barra recorta o painel inteiro naquele dia */
  onDia?: (dataISO: string) => void
  /** dia em foco, para destacar a barra correspondente */
  diaSelecionado?: string | null
}) {
  // A data ISO viaja junto com o rótulo curto: o clique precisa devolver
  // '2026-08-07', não '07/08'.
  const dados = serie.map((d) => ({
    dia: diaCurto(d.data),
    iso: d.data,
    valor: Number(d[campo] ?? 0),
  }))

  const media = dados.length
    ? dados.reduce((s, d) => s + d.valor, 0) / dados.length
    : 0

  return (
    <Panel className="pb-3">
      <SectionTitle
        titulo={titulo}
        sub={sub}
        acessorio={
          <div className="flex items-center gap-4 text-[10px] text-muted">
            <span className="flex items-center gap-1.5">
              <span className="inline-block h-2 w-2 rounded-full bg-turq" /> POR DIA
            </span>
            <span className="flex items-center gap-1.5">
              <span className="inline-block h-px w-4 border-t border-dashed border-muted" /> MÉDIA
            </span>
          </div>
        }
      />

      <div className="mt-2 h-44 px-3">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={dados} margin={{ top: 8, right: 8, left: 8, bottom: 0 }}>
            <CartesianGrid stroke="var(--color-line)" vertical={false} />
            <XAxis
              dataKey="dia"
              tick={{ fill: 'var(--color-faint)', fontSize: 10 }}
              axisLine={false}
              tickLine={false}
              interval="preserveStartEnd"
            />
            <YAxis
              tick={{ fill: 'var(--color-faint)', fontSize: 10 }}
              axisLine={false}
              tickLine={false}
              tickFormatter={(v) => formatar(v as number)}
              width={70}
            />
            <Tooltip
              cursor={{ fill: 'var(--color-card-alt)' }}
              contentStyle={{
                background: 'var(--color-card-alt)',
                border: '1px solid var(--color-line)',
                borderRadius: 10,
                fontSize: 12,
              }}
              labelStyle={{ color: 'var(--color-muted)' }}
              formatter={(v) => [formatar(v as number), titulo]}
            />
            <ReferenceLine y={media} stroke="var(--color-muted)" strokeDasharray="4 4" />
            <Bar
              dataKey="valor"
              radius={[3, 3, 0, 0]}
              maxBarSize={22}
              isAnimationActive={false}
              cursor={onDia ? 'pointer' : undefined}
              onClick={(d) => {
                const iso = (d as unknown as { payload?: { iso?: string } })?.payload?.iso
                if (iso && onDia) onDia(iso)
              }}
            >
              {dados.map((d) => (
                <Cell
                  key={d.iso}
                  // Com um dia selecionado, os demais apagam — assim o recorte
                  // fica visível no gráfico e não só no campo de data.
                  fill={
                    diaSelecionado && diaSelecionado !== d.iso
                      ? 'var(--color-turq-deep)'
                      : 'var(--color-turq)'
                  }
                />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
    </Panel>
  )
}
