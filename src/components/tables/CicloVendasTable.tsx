import { useMemo, useState } from 'react'
import { Panel } from '../ui/Panel'
import { CampoBusca } from '../ui/CampoBusca'
import { formatInt } from '../../utils/format'
import type { CicloLinha } from '../../types'

/**
 * Ciclo de vendas — uma linha por venda, com o caminho do lead no tempo:
 * criação → agendamento → venda, e os intervalos entre essas datas.
 *
 * Só entra quem comprou, e o período da página recorta pela DATA DA VENDA.
 * O agendamento buscado é o primeiro do lead, de qualquer período: o ciclo é
 * do lead, não da janela de filtro.
 */

/** '2026-08-12' → '12/08/2026'. Corta a string em vez de usar Date: `new
 *  Date('2026-08-12')` é interpretado como UTC e volta um dia em fuso -03. */
function dataBR(iso: string | null): string {
  if (!iso) return '—'
  const [a, m, d] = iso.slice(0, 10).split('-')
  return `${d}/${m}/${a}`
}

function dias(v: number | null): string {
  if (v == null || !Number.isFinite(v)) return '—'
  if (v === 0) return 'mesmo dia'
  return `${formatInt(v)} ${v === 1 ? 'dia' : 'dias'}`
}

/** Média simples ignorando nulos — a base de cada tempo é diferente. */
function media(linhas: CicloLinha[], campo: keyof CicloLinha): number | null {
  const nums = linhas
    .map((l) => l[campo])
    .filter((v): v is number => typeof v === 'number' && Number.isFinite(v))
  if (nums.length === 0) return null
  return Math.round(nums.reduce((s, n) => s + n, 0) / nums.length)
}

export function CicloVendasTable({ linhas }: { linhas: CicloLinha[] }) {
  const [busca, setBusca] = useState('')

  const filtradas = useMemo(() => {
    const t = busca.trim().toLowerCase()
    if (!t) return linhas
    return linhas.filter(
      (l) => l.nome.toLowerCase().includes(t) || l.anuncio.toLowerCase().includes(t),
    )
  }, [linhas, busca])

  const medias = useMemo(
    () => ({
      cria_agen: media(filtradas, 'dias_cria_agen'),
      agen_venda: media(filtradas, 'dias_agen_venda'),
      cria_venda: media(filtradas, 'dias_cria_venda'),
    }),
    [filtradas],
  )

  return (
    <div className="mt-8">
      <p className="rotulo">Análise</p>
      <h2 className="mt-1 mb-4 text-2xl font-bold tracking-tight text-ink">Ciclo de vendas</h2>

      <div className="mb-3 flex items-center gap-3">
        <CampoBusca
          valor={busca}
          onChange={setBusca}
          placeholder="Nome do lead ou anúncio"
          className="w-full max-w-md"
        />
        <span className="numero rounded-md bg-card-alt px-2 py-1 text-[11px] text-muted">
          {filtradas.length} {filtradas.length === 1 ? 'venda' : 'vendas'}
        </span>
      </div>

      <Panel className="overflow-hidden">
        <div className="max-h-96 overflow-auto">
          <table className="w-full border-collapse text-sm">
            <thead className="sticky top-0 z-10 bg-card-alt">
              <tr>
                <th className="titulo px-3 py-2.5 text-left">Nome do lead</th>
                <th className="titulo px-3 py-2.5 text-left">Anúncio</th>
                <th className="titulo px-3 py-2.5 text-right whitespace-nowrap">Data criação</th>
                <th className="titulo px-3 py-2.5 text-right whitespace-nowrap">Data agendamento</th>
                <th className="titulo px-3 py-2.5 text-right whitespace-nowrap">Data da venda</th>
                <th className="titulo px-3 py-2.5 text-right whitespace-nowrap">Criação → agend.</th>
                <th className="titulo px-3 py-2.5 text-right whitespace-nowrap">Agend. → venda</th>
                <th className="titulo px-3 py-2.5 text-right whitespace-nowrap">Criação → venda</th>
              </tr>
            </thead>

            <tbody>
              {filtradas.length === 0 ? (
                <tr>
                  <td colSpan={8} className="px-3 py-10 text-center text-faint">
                    Nenhuma venda no período.
                  </td>
                </tr>
              ) : (
                filtradas.map((l, i) => (
                  <tr key={`${l.nome}-${l.data_venda}-${i}`} className="border-t border-line/60">
                    <td className="max-w-[220px] truncate px-3 py-2 text-ink" title={l.nome}>
                      {l.nome}
                    </td>
                    <td className="max-w-[260px] truncate px-3 py-2 text-muted" title={l.anuncio}>
                      {l.anuncio}
                    </td>
                    <td className="numero px-3 py-2 text-right whitespace-nowrap text-ink">
                      {dataBR(l.data_criacao)}
                    </td>
                    <td className="numero px-3 py-2 text-right whitespace-nowrap text-ink">
                      {dataBR(l.data_agendamento)}
                    </td>
                    <td className="numero px-3 py-2 text-right whitespace-nowrap text-ink">
                      {dataBR(l.data_venda)}
                    </td>
                    <td className="numero px-3 py-2 text-right whitespace-nowrap text-turq-soft">
                      {dias(l.dias_cria_agen)}
                    </td>
                    <td className="numero px-3 py-2 text-right whitespace-nowrap text-turq-soft">
                      {dias(l.dias_agen_venda)}
                    </td>
                    <td className="numero px-3 py-2 text-right whitespace-nowrap font-semibold text-turq">
                      {dias(l.dias_cria_venda)}
                    </td>
                  </tr>
                ))
              )}
            </tbody>

            {filtradas.length > 0 && (
              <tfoot className="sticky bottom-0 bg-card-alt">
                <tr className="border-t border-line">
                  <td colSpan={5} className="px-3 py-2.5 font-semibold text-ink">
                    Média
                  </td>
                  <td className="numero px-3 py-2.5 text-right font-semibold text-ink">
                    {dias(medias.cria_agen)}
                  </td>
                  <td className="numero px-3 py-2.5 text-right font-semibold text-ink">
                    {dias(medias.agen_venda)}
                  </td>
                  <td className="numero px-3 py-2.5 text-right font-semibold text-ink">
                    {dias(medias.cria_venda)}
                  </td>
                </tr>
              </tfoot>
            )}
          </table>
        </div>
      </Panel>
    </div>
  )
}
