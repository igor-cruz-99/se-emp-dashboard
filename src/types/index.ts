/** Contratos de dados — espelham o retorno das RPCs em sql/07 e sql/10. */

export interface Kpis {
  dias: number
  investimento: number
  impressoes: number
  cliques: number
  leads: number
  mql: number
  /** sessões marcadas (uma linha por sessão) */
  agendamentos: number
  /** pessoas únicas que agendaram — o "Agendas" do BI antigo */
  agendas: number
  calls: number
  no_shows: number
  pendentes: number
  /** agendamentos sem desfecho registrado na origem */
  sem_registro: number
  vendas: number
  faturamento: number
  // taxas (%) — null quando não há base de cálculo
  ctr: number | null
  pct_leads: number | null
  pct_mql: number | null
  pct_agend: number | null
  pct_comparecimento: number | null
  pct_no_show: number | null
  pct_conversao: number | null
  // custos (R$)
  cpm: number | null
  cpc: number | null
  cpl: number | null
  cpmql: number | null
  cpa: number | null
  ccall: number | null
  cac: number | null
  roas: number | null
}

export interface DiaSerie {
  data: string
  investimento: number
  impressoes: number
  cliques: number
  leads: number
  mql: number
  agendamentos: number
  calls: number
  vendas: number
  faturamento: number
}

export interface OrigemLinha {
  origem: string
  investimento: number
  leads: number
  mql: number
  agendamentos: number
  calls: number
  vendas: number
  faturamento: number
  cpl: number | null
  cpmql: number | null
  cpa: number | null
  cac: number | null
  pct_mql: number | null
  pct_agend: number | null
}

export interface RendaLinha {
  faixa: string
  /** piso da faixa em milhares — serve para ordenar (dado ordinal, não volume) */
  ordem: number
  leads: number
  pct: number | null
}

export type NivelTrafego = 'campanha' | 'conjunto' | 'anuncio'

export interface TrafegoLinha {
  nivel: NivelTrafego
  chave: string
  /** campanha à qual esta linha pertence (null no nível campanha) */
  campanha_pai: string | null
  /** conjunto ao qual esta linha pertence (só no nível anúncio) */
  conjunto_pai: string | null
  investimento: number
  impressoes: number
  cliques: number
  leads: number
  agendamentos: number
  vendas: number
  faturamento: number
  cpl: number | null
  cac: number | null
  /** % dos leads com renda >= 50 mil — o %MQL fica em ~99% e não separa nada */
  qualif_50k: number | null
  hook: number | null
  hold: number | null
  body: number | null
}

export interface CicloLinha {
  nome: string
  anuncio: string
  data_criacao: string | null
  data_agendamento: string | null
  data_venda: string | null
  dias_cria_agen: number | null
  dias_agen_venda: number | null
  dias_cria_venda: number | null
}

export interface MacroLinha {
  /** primeiro dia do mês, em ISO */
  mes: string
  investimento: number
  impressoes: number
  cliques: number
  cpc: number | null
  leads: number
  cpl: number | null
  mql: number
  pct_mql: number | null
  cpmql: number | null
  /** sessões marcadas */
  agendamentos: number
  /** pessoas únicas */
  agendas: number
  calls: number
  cust_agen: number | null
  vendas: number
  cac: number | null
  faturamento: number
  pct_comparecimento: number | null
  sem_registro: number
}

export interface FormularioLinha {
  formulario: string
  leads: number
  pct: number | null
  /** ⚠️ rateado do gasto da campanha proporcional aos leads — estimativa */
  investimento: number
  cpl: number | null
}

export interface PerfilLinha {
  /**
   * 'dia_semana' (0=domingo..6=sábado) · 'hora' (0..23) · 'sem_hora'
   * 'aporte' (ordem = escala do menor para o maior) · 'profissao' (ordem = ranking)
   */
  tipo: 'dia_semana' | 'hora' | 'sem_hora' | 'aporte' | 'profissao'
  ordem: number
  /** Só em 'aporte' e 'profissao'. Nos outros o nome sai de `ordem`. */
  rotulo: string | null
  leads: number
}

/** Direção diz para que lado o número é bom — CPL menor, conversão maior. */
export interface Meta {
  chave: string
  rotulo: string
  valor: number
  direcao: 'maior' | 'menor'
  formato: 'moeda' | 'percentual' | 'numero'
}

export interface Filtros {
  inicio: string
  fim: string
  /** origens marcadas no filtro; null = todas */
  origens: string[] | null
}

export interface DadosPainel {
  kpis: Kpis | null
  serie: DiaSerie[]
  origens: OrigemLinha[]
  renda: RendaLinha[]
  trafego: TrafegoLinha[]
  ciclo: CicloLinha[]
  perfil: PerfilLinha[]
  formularios: FormularioLinha[]
  metas: Record<string, Meta>
}
