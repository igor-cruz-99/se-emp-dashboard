import { useMemo, useState } from 'react'
import { TrafficTable } from './TrafficTable'
import type { TrafegoLinha } from '../../types'

/**
 * Seção de tráfego: campanhas, conjuntos e anúncios que se filtram entre si.
 *
 * Regras do cruzamento:
 *   • Clicar numa campanha mostra só os conjuntos e anúncios dela.
 *   • Clicar num conjunto sobe também para a campanha dele (e desce para os
 *     anúncios) — o "vice-versa" pedido.
 *   • Clicar num anúncio fixa a linhagem inteira.
 *   • Buscar em qualquer nível estreita os outros dois: procurar por "quiz" nos
 *     anúncios deixa visíveis só as campanhas e conjuntos que têm algum.
 *   • Clicar de novo na linha selecionada solta o filtro.
 *
 * O estado mora aqui, e não no Dashboard, porque só estas três tabelas o usam —
 * subir mais um nível faria o painel inteiro re-renderizar a cada clique.
 */
interface Selecao {
  campanha?: string
  conjunto?: string
  anuncio?: string
}

const VAZIA: Selecao = {}

export function SecaoTrafego({ linhas }: { linhas: TrafegoLinha[] }) {
  const [buscas, setBuscas] = useState({ campanha: '', conjunto: '', anuncio: '' })
  const [sel, setSel] = useState<Selecao>(VAZIA)

  const { campanhas, conjuntos, anuncios } = useMemo(() => {
    const bruto = {
      campanha: linhas.filter((l) => l.nivel === 'campanha'),
      conjunto: linhas.filter((l) => l.nivel === 'conjunto'),
      anuncio: linhas.filter((l) => l.nivel === 'anuncio'),
    }

    const casa = (texto: string, termo: string) =>
      !termo.trim() || texto.toLowerCase().includes(termo.trim().toLowerCase())

    // 1) cada nível filtrado pela própria busca
    const bc = bruto.campanha.filter((l) => casa(l.chave, buscas.campanha))
    const bj = bruto.conjunto.filter((l) => casa(l.chave, buscas.conjunto))
    const ba = bruto.anuncio.filter((l) => casa(l.chave, buscas.anuncio))

    // 2) as buscas dos filhos limitam quem pode aparecer acima
    const campDeConjunto = new Set(bj.map((l) => l.campanha_pai))
    const campDeAnuncio = new Set(ba.map((l) => l.campanha_pai))
    const conjDeAnuncio = new Set(ba.map((l) => l.conjunto_pai))
    const temBuscaConjunto = Boolean(buscas.conjunto.trim())
    const temBuscaAnuncio = Boolean(buscas.anuncio.trim())

    return {
      campanhas: bc.filter(
        (l) =>
          (!sel.campanha || l.chave === sel.campanha) &&
          (!temBuscaConjunto || campDeConjunto.has(l.chave)) &&
          (!temBuscaAnuncio || campDeAnuncio.has(l.chave)),
      ),
      conjuntos: bj.filter(
        (l) =>
          (!sel.campanha || l.campanha_pai === sel.campanha) &&
          (!sel.conjunto || l.chave === sel.conjunto) &&
          (!temBuscaAnuncio || conjDeAnuncio.has(l.chave)),
      ),
      anuncios: ba.filter(
        (l) =>
          (!sel.campanha || l.campanha_pai === sel.campanha) &&
          (!sel.conjunto || l.conjunto_pai === sel.conjunto) &&
          (!sel.anuncio || l.chave === sel.anuncio),
      ),
    }
  }, [linhas, buscas, sel])

  /** Clique numa linha: fixa a linhagem dela, ou solta se já estava fixa. */
  function selecionar(l: TrafegoLinha) {
    setSel((atual) => {
      if (l.nivel === 'campanha') {
        return atual.campanha === l.chave && !atual.conjunto ? VAZIA : { campanha: l.chave }
      }
      if (l.nivel === 'conjunto') {
        return atual.conjunto === l.chave
          ? { campanha: atual.campanha }
          : { campanha: l.campanha_pai ?? undefined, conjunto: l.chave }
      }
      return atual.anuncio === l.chave
        ? { campanha: atual.campanha, conjunto: atual.conjunto }
        : {
            campanha: l.campanha_pai ?? undefined,
            conjunto: l.conjunto_pai ?? undefined,
            anuncio: l.chave,
          }
    })
  }

  const ativo = Boolean(sel.campanha || sel.conjunto || sel.anuncio)

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-baseline gap-3">
        <p className="rotulo">Análise</p>
        <h2 className="text-2xl font-bold tracking-tight text-ink">Tráfego por campanha</h2>
        {ativo && (
          <button
            onClick={() => setSel(VAZIA)}
            className="rounded-full border border-turq/40 bg-turq/10 px-3 py-1 text-[11px] text-turq-soft transition hover:bg-turq/20"
          >
            {[sel.campanha, sel.conjunto, sel.anuncio].filter(Boolean).join(' › ')} · limpar
          </button>
        )}
      </div>

      <div className="flex flex-col gap-6">
        <TrafficTable
          titulo="Campanhas"
          rotuloChave="Campanha"
          linhas={campanhas}
          busca={buscas.campanha}
          onBusca={(v) => setBuscas((b) => ({ ...b, campanha: v }))}
          selecionado={sel.campanha ?? null}
          onSelecionar={selecionar}
        />
        <TrafficTable
          titulo="Conjuntos"
          rotuloChave="Conjunto"
          linhas={conjuntos}
          busca={buscas.conjunto}
          onBusca={(v) => setBuscas((b) => ({ ...b, conjunto: v }))}
          selecionado={sel.conjunto ?? null}
          onSelecionar={selecionar}
        />
        <TrafficTable
          titulo="Anúncios"
          rotuloChave="Anúncio"
          linhas={anuncios}
          busca={buscas.anuncio}
          onBusca={(v) => setBuscas((b) => ({ ...b, anuncio: v }))}
          selecionado={sel.anuncio ?? null}
          onSelecionar={selecionar}
        />
      </div>
    </div>
  )
}
