import { useMemo, useState } from 'react'
import { Header, mesAtual, periodoDoAtalho, type Atalho } from '../components/layout/Header'
import { Sidebar, type Secao } from '../components/layout/Sidebar'
import { KpiCard } from '../components/kpi/KpiCard'
import { Funnel } from '../components/funnel/Funnel'
import { ChartCard } from '../components/charts/ChartCard'
import { OrigemLeadsTable } from '../components/origem/OrigemLeadsTable'
import { InvestimentoOrigemChart } from '../components/origem/InvestimentoOrigemChart'
import { RendaDonut } from '../components/origem/RendaDonut'
import { SecaoTrafego } from '../components/tables/SecaoTrafego'
import { CicloVendasTable } from '../components/tables/CicloVendasTable'
import { PerfilLead } from '../components/perfil/PerfilLead'
import { MatrizMacro } from '../components/macro/MatrizMacro'
import { Panel } from '../components/ui/Panel'
import { useDashboardData } from '../hooks/useDashboardData'
import { useMacro } from '../hooks/useMacro'
import { supabaseAuth } from '../lib/supabase'
import { formatBRL, formatBRLCurto, formatInt, formatPct } from '../utils/format'
import type { Filtros } from '../types'

/**
 * Data em que o funil (agendamento/venda) passa a existir de verdade.
 * Antes disso: a Bitrix parou em 26/06 e o CRM novo só começou em 01/08 —
 * julho inteiro não tem registro em sistema nenhum. Sem este aviso na tela,
 * um período que cruze julho parece colapso da operação em vez de lacuna.
 */
const FUNIL_CONFIAVEL_DE = '2026-08-01'

/**
 * Origens que o painel já conhece, usadas para montar o filtro ANTES da
 * primeira resposta do servidor. Sem essa semente, o primeiro pedido sairia
 * com a lista vazia — que o backend leria como "nenhuma origem" e devolveria
 * o painel zerado por um instante.
 * A lista real vem de `fn_origem` e é unida a esta; origem nova nasce marcada.
 */
const ORIGENS_CONHECIDAS = [
  'Forms Nativo',
  'Quiz',
  'Typeform',
  'Typebot',
  'VSL',
  'Landing Page',
  'Outros',
  'Não identificado',
]

/** O VSL não faz parte do funil principal — nasce desmarcado, por decisão. */
const DESMARCADAS_PADRAO = ['VSL']

export function Dashboard() {
  // Abre no mês corrente; os atalhos 30D/7D/Ontem/Hoje ficam sem seleção
  // até alguém clicar, porque nenhum deles corresponde a esse recorte.
  const [atalho, setAtalho] = useState<Atalho | null>(null)
  const [desmarcadas, setDesmarcadas] = useState<string[]>(DESMARCADAS_PADRAO)
  const [filtros, setFiltros] = useState<Filtros>(() => ({
    ...mesAtual(),
    origens: ORIGENS_CONHECIDAS.filter((o) => !DESMARCADAS_PADRAO.includes(o)),
  }))

  const { dados, carregando, erro } = useDashboardData(filtros)
  const macro = useMacro()
  const { kpis: k, serie, origens, renda, trafego, ciclo, perfil, formularios, metas } = dados

  // União do que o servidor devolveu com o que já conhecíamos, para o filtro
  // nunca perder uma opção enquanto os dados não chegam.
  const listaOrigens = useMemo(() => {
    const doServidor = origens.map((o) => o.origem).filter(Boolean)
    return [...new Set([...ORIGENS_CONHECIDAS, ...doServidor])].sort()
  }, [origens])

  function trocarOrigens(novas: string[]) {
    setDesmarcadas(novas)
    setFiltros((f) => ({ ...f, origens: listaOrigens.filter((o) => !novas.includes(o)) }))
  }

  const avisoLacuna = filtros.inicio < FUNIL_CONFIAVEL_DE

  /** Um dia só selecionado: o clique numa barra dos gráficos diários recorta aqui. */
  const diaUnico = filtros.inicio === filtros.fim ? filtros.inicio : null

  function focarDia(iso: string) {
    setAtalho(null)
    // Clicar no mesmo dia solta o recorte e volta para o mês — senão a pessoa
    // fica presa num dia sem saber como sair.
    setFiltros((f) =>
      f.inicio === iso && f.fim === iso ? { ...f, ...mesAtual() } : { ...f, inicio: iso, fim: iso },
    )
  }

  function aplicarAtalho(a: Atalho) {
    setAtalho(a)
    setFiltros((f) => ({ ...f, ...periodoDoAtalho(a) }))
  }

  function aplicarPeriodo(inicio: string, fim: string) {
    setAtalho(null)
    setFiltros((f) => ({ ...f, inicio, fim }))
  }

  const SECOES: Secao[] = [
    { id: 'sec-visao', titulo: 'Visão geral' },
    { id: 'sec-origem', titulo: 'Origem e renda' },
    { id: 'sec-trafego', titulo: 'Tráfego por campanha' },
    { id: 'sec-ciclo', titulo: 'Ciclo de vendas' },
    { id: 'sec-perfil', titulo: 'Perfil do lead' },
    { id: 'sec-macro', titulo: 'Matriz mês a mês' },
  ]

  const dias = k?.dias ?? 1
  const porDia = (v: number | null | undefined) => (v == null ? null : v / dias)

  /**
   * O comparecimento só é confiável quando um pedaço razoável dos agendamentos
   * tem desfecho registrado. Em jun/jul-2026, 247 de 247 e 247 de 254 ficaram
   * sem registro (a Bitrix parou de ser alimentada), e a taxa saía de 8 e 7
   * casos. Abaixo de 30% de cobertura o badge perde a cor — mostra o número,
   * mas não afirma que é bom nem ruim.
   */
  const baseComparecimento = (k?.calls ?? 0) + (k?.no_shows ?? 0)
  const coberturaDesfecho = k && k.agendamentos > 0 ? baseComparecimento / k.agendamentos : 1
  const baseFracaComparecimento = coberturaDesfecho < 0.3

  return (
    <div className="fundo-grid min-h-screen">
      <div className="mx-auto max-w-[1760px] px-6 py-4">
        <Header
          filtros={filtros}
          atalho={atalho}
          onAtalho={aplicarAtalho}
          onPeriodo={aplicarPeriodo}
          origensDisponiveis={listaOrigens}
          origensDesmarcadas={desmarcadas}
          onOrigens={trocarOrigens}
          onSair={() => supabaseAuth?.auth.signOut()}
        />

        {erro && (
          <Panel className="mb-5 border-bad/40 px-5 py-4 text-sm text-bad">{erro}</Panel>
        )}

        {avisoLacuna && (
          <Panel className="mb-5 border-warn/30 px-5 py-3 text-xs text-warn/90">
            <strong className="font-semibold">Atenção:</strong> agendamentos, calls e vendas só
            existem a partir de 01/08/2026. A Bitrix parou em 26/06 e o CRM novo começou em 01/08 —
            julho não foi registrado em sistema nenhum. Investimento, leads e CPL estão íntegros no
            período todo.
          </Panel>
        )}

        <div className="flex gap-6">
          <Sidebar secoes={SECOES} />

          <div className="min-w-0 flex-1">
        {/* ---------- Cards do topo ---------- */}
        <div id="sec-visao" className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-5 scroll-mt-6">
          <KpiCard
            rotulo="Investimento"
            valor={formatBRL(k?.investimento)}
            mediaDia={formatBRL(porDia(k?.investimento))}
          />
          <KpiCard
            rotulo="Leads"
            valor={formatInt(k?.leads)}
            mediaDia={formatInt(porDia(k?.leads))}
            badgeValorBruto={k?.cpl ?? null}
            badgeTexto={formatBRL(k?.cpl)}
            meta={metas.cpl}
          />
          <KpiCard
            rotulo="MQL"
            valor={formatInt(k?.mql)}
            mediaDia={formatInt(porDia(k?.mql))}
            badgeValorBruto={k?.pct_mql ?? null}
            badgeTexto={formatPct(k?.pct_mql, 1)}
            meta={metas.pct_mql}
          />
          <KpiCard
            rotulo="Agendamentos"
            valor={formatInt(k?.agendamentos)}
            mediaDia={formatInt(porDia(k?.agendamentos))}
            badgeValorBruto={k?.pct_comparecimento ?? null}
            badgeTexto={formatPct(k?.pct_comparecimento, 1)}
            meta={metas.pct_comparecimento}
            baseFraca={baseFracaComparecimento}
            avisoBase={`Base pequena: só ${formatInt(baseComparecimento)} de ${formatInt(
              k?.agendamentos,
            )} agendamentos têm desfecho registrado. A taxa aparece, mas sem cor — não há base para dizer se está boa.`}
          />
          <KpiCard
            rotulo="Vendas"
            valor={formatInt(k?.vendas)}
            mediaDia={formatInt(porDia(k?.vendas))}
            badgeValorBruto={k?.pct_conversao ?? null}
            badgeTexto={formatPct(k?.pct_conversao, 1)}
            meta={metas.pct_conversao}
          />
        </div>

        {/* ---------- Gráficos + funil ---------- */}
        <div className="mt-5 grid grid-cols-1 gap-5 lg:grid-cols-2">
          <div className="flex flex-col gap-5">
            <ChartCard
              titulo="Investimento por dia"
              sub={`${serie.length} dias`}
              serie={serie}
              campo="investimento"
              formatar={formatBRLCurto}
              onDia={focarDia}
              diaSelecionado={diaUnico}
            />
            <ChartCard
              titulo="Leads por dia"
              sub={`${serie.length} dias`}
              serie={serie}
              campo="leads"
              formatar={(v) => formatInt(v)}
              onDia={focarDia}
              diaSelecionado={diaUnico}
            />
          </div>

          <Funnel k={k} />
        </div>

        {/* ---------- Origem e qualificação ---------- */}
        <div id="sec-origem" className="mt-5 grid grid-cols-1 gap-5 scroll-mt-6 lg:grid-cols-2 xl:grid-cols-3">
          <OrigemLeadsTable linhas={formularios} />
          <InvestimentoOrigemChart linhas={origens} />
          <RendaDonut linhas={renda} />
        </div>

        {/* ---------- Análise ---------- */}
        <div id="sec-trafego" className="mt-8 scroll-mt-6">
          <SecaoTrafego linhas={trafego} />
        </div>

        <div id="sec-ciclo" className="scroll-mt-6">
          <CicloVendasTable linhas={ciclo} />
        </div>

        <div id="sec-perfil" className="scroll-mt-6">
          <PerfilLead linhas={perfil} />
        </div>

        <div id="sec-macro" className="scroll-mt-6">
          {macro.linhas.length > 0 && <MatrizMacro linhas={macro.linhas} />}
        </div>

        {carregando && (
          <p className="mt-6 text-center text-xs text-faint">Carregando…</p>
        )}
          </div>
        </div>
      </div>
    </div>
  )
}
