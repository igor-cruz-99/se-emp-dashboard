import { Panel } from '../ui/Panel'
import { formatBRL, formatInt, formatPct } from '../../utils/format'
import type { FormularioLinha } from '../../types'

/**
 * "Origem dos leads" — dividido por FORMULÁRIO (`id_formulario`), não pela
 * origem deduzida da campanha.
 *
 * A diferença importa: em agosto 98% dos leads são "Forms Nativo", o que não
 * separa nada. Repartindo por formulário, os mesmos leads viram '21MAI-J',
 * '9 MAR' e '22 DEZ' — criativos de captação diferentes, comparáveis entre si.
 *
 * ⚠️ O CPL é ESTIMADO: o Meta não devolve o formulário junto com o gasto, então
 * o investimento da campanha é rateado entre os formulários dos leads dela,
 * proporcional ao volume. Daí o "~" antes do valor — sinaliza na tela que
 * aquele número é aproximação, não medição.
 *
 * A barra é proporcional ao MAIOR valor, não ao total: com um formulário
 * dominante, proporcional ao total deixaria os outros como riscos invisíveis.
 */
export function OrigemLeadsTable({ linhas }: { linhas: FormularioLinha[] }) {
  const comLeads = linhas.filter((l) => l.leads > 0)
  const naoRateado = linhas.find((l) => l.leads === 0 && l.investimento > 0)
  const max = Math.max(1, ...comLeads.map((l) => l.leads))
  const total = comLeads.reduce((s, l) => s + l.leads, 0)

  return (
    <Panel className="p-5">
      <div className="mb-4 flex items-baseline justify-between">
        <h3 className="titulo">Origem dos leads</h3>
        <span className="numero text-xs text-muted">{formatInt(total)} leads</span>
      </div>

      {comLeads.length === 0 ? (
        <p className="py-8 text-center text-sm text-faint">Sem leads no período.</p>
      ) : (
        <div className="flex flex-col gap-3">
          {comLeads.map((l) => (
            <div key={l.formulario}>
              <div className="flex items-center gap-3">
                <span
                  className="w-28 shrink-0 truncate text-sm text-ink"
                  title={l.formulario}
                >
                  {l.formulario}
                </span>
                <div className="h-2 flex-1 overflow-hidden rounded-full bg-card-alt">
                  <div
                    className="h-full rounded-full"
                    style={{
                      width: `${(l.leads / max) * 100}%`,
                      background:
                        'linear-gradient(90deg, var(--color-turq-soft), var(--color-turq))',
                    }}
                  />
                </div>
                <span className="numero w-12 shrink-0 text-right text-sm font-semibold text-ink">
                  {formatInt(l.leads)}
                </span>
                <span className="numero w-10 shrink-0 text-right text-xs text-muted">
                  {formatPct(l.pct, 0)}
                </span>
              </div>

              <div className="mt-1 pl-31 text-[11px] text-muted">
                CPL <span className="numero text-ink">~{formatBRL(l.cpl)}</span>
                <span className="ml-2 text-faint">
                  {formatBRL(l.investimento)} rateado
                </span>
              </div>
            </div>
          ))}
        </div>
      )}

      {naoRateado && (
        <p
          className="mt-4 border-t border-line/70 pt-3 text-[11px] text-faint"
          title="Campanha que gastou sem gerar lead: não há como ratear"
        >
          {formatBRL(naoRateado.investimento)} de campanha sem lead — fora do rateio
        </p>
      )}
    </Panel>
  )
}
