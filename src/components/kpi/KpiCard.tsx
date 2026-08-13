import { Panel } from '../ui/Panel'
import { classesBadge, situacao } from '../../utils/metaColor'
import type { Meta } from '../../types'

/**
 * Cartão de KPI do topo.
 *
 * O badge mostra RÓTULO + VALOR (ex.: "CPL R$ 44,72") e a cor indica a
 * distância da meta. Sem meta cadastrada ele sai em turquesa neutro — o
 * painel funciona antes de as metas existirem.
 */
export function KpiCard({
  rotulo,
  valor,
  mediaDia,
  badgeValorBruto,
  badgeTexto,
  meta,
  baseFraca,
  avisoBase,
}: {
  rotulo: string
  valor: string
  mediaDia?: string
  /** valor numérico cru do indicador do badge, para comparar com a meta */
  badgeValorBruto?: number | null
  /** já formatado, é o que aparece */
  badgeTexto?: string
  meta?: Meta
  /**
   * Base de cálculo pequena demais para colorir. O badge sai em cor neutra:
   * um "87,5%" apoiado em 8 casos não é desempenho, é ruído — e verde ali
   * viraria decisão. Continua mostrando o número, só não afirma que é bom.
   */
  baseFraca?: boolean
  /** explica no hover por que a cor sumiu */
  avisoBase?: string
}) {
  const s = baseFraca ? 'neutro' : situacao(badgeValorBruto ?? null, meta)

  return (
    <Panel className="px-5 py-3.5">
      <div className="flex items-start justify-between gap-2">
        <span className="titulo">{rotulo}</span>
        {meta && badgeTexto && (
          <span
            className={`rounded-md border px-2 py-1 text-[10px] leading-none font-semibold tracking-wide ${classesBadge(s)}`}
            title={
              baseFraca && avisoBase
                ? avisoBase
                : `Meta: ${meta.valor}${meta.formato === 'percentual' ? '%' : ''} (${meta.direcao} é melhor)`
            }
          >
            <span className="opacity-70">{meta.rotulo}</span>{' '}
            <span className="numero">{badgeTexto}</span>
          </span>
        )}
      </div>

      <div className="numero mt-2 text-3xl font-semibold tracking-tight text-ink">{valor}</div>

      {mediaDia && (
        <div className="mt-2.5 border-t border-line/70 pt-2 text-[11px] text-faint">
          <span className="rotulo">Média/dia</span>{' '}
          <span className="numero ml-1 text-turq-soft">{mediaDia}</span>
        </div>
      )}
    </Panel>
  )
}
