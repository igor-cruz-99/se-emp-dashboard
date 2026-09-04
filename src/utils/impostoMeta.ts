import type {
  DadosPainel,
  DiaSerie,
  FormularioLinha,
  Kpis,
  MacroLinha,
  OrigemLinha,
  TrafegoLinha,
} from '../types'

/**
 * Imposto da Meta — 12% sobre o investimento.
 *
 * O que o banco devolve é o gasto que a Meta cobra na plataforma. O custo real
 * da empresa é 12% maior. Ligado, o painel passa a mostrar o custo real; e como
 * quase toda métrica de eficiência nasce do investimento, TODAS mudam junto.
 *
 * ⚠️ POR QUE ISTO ACONTECE AQUI E NÃO NO BANCO
 *   O caminho "certo" seria um parâmetro nas RPCs. Seriam 16 funções alteradas,
 *   e o botão passaria a exigir uma ida ao servidor a cada clique. Aqui é uma
 *   multiplicação sobre o resultado já pronto: o mesmo número, sem round-trip,
 *   e o banco continua guardando o dado como a Meta o entrega — que é o que se
 *   confere contra o gerenciador de anúncios quando algo não bate.
 *
 * ⚠️ O RISCO DESTE DESENHO, E COMO ELE É CONTIDO
 *   Se um campo de custo novo aparecer numa RPC e ninguém o incluir nas listas
 *   abaixo, ele fica sem imposto e o painel passa a mostrar dois padrões de
 *   custo ao mesmo tempo — sem erro nenhum, exatamente o tipo de falha
 *   silenciosa que já custou caro neste projeto.
 *   Por isso as listas ficam TODAS neste arquivo, coladas umas nas outras: ao
 *   acrescentar um custo em `types/index.ts`, o lugar de refletir isso é óbvio.
 *
 * ⚠️ O QUE NÃO MUDA
 *   Contagens (leads, agendamentos, vendas) e faturamento são fatos — o imposto
 *   não cria nem destrói lead. Percentuais de conversão também não mudam: são
 *   razões entre contagens.
 *   O ROAS é o único que anda para o OUTRO LADO: é faturamento ÷ investimento,
 *   então investimento maior significa retorno menor. Multiplicá-lo junto com
 *   os demais seria o erro fácil aqui.
 */
export const TAXA_IMPOSTO_META = 0.12
export const FATOR_IMPOSTO = 1 + TAXA_IMPOSTO_META

/** Multiplica os campos indicados, preservando `null` (sem base de cálculo). */
function escalar<T extends object>(linha: T, campos: readonly (keyof T)[]): T {
  const saida = { ...linha }
  for (const campo of campos) {
    const v = saida[campo]
    if (typeof v === 'number') saida[campo] = (v * FATOR_IMPOSTO) as T[keyof T]
  }
  return saida
}

// ---------------------------------------------------------------------------
// Campos que sobem 12%. Um por contrato de dados, na mesma ordem de types/.
// ---------------------------------------------------------------------------
const KPIS: readonly (keyof Kpis)[] = [
  'investimento', 'cpm', 'cpc', 'cpl', 'cpmql', 'cpa', 'ccall', 'cac',
]
const SERIE: readonly (keyof DiaSerie)[] = ['investimento']
const ORIGEM: readonly (keyof OrigemLinha)[] = [
  'investimento', 'cpl', 'cpmql', 'cpa', 'cac',
]
const TRAFEGO: readonly (keyof TrafegoLinha)[] = ['investimento', 'cpl', 'cac']
const FORMULARIO: readonly (keyof FormularioLinha)[] = ['investimento', 'cpl']
const MACRO: readonly (keyof MacroLinha)[] = [
  'investimento', 'cpc', 'cpl', 'cpmql', 'cust_agen', 'cac',
]

/** O ROAS é o caso invertido — ver o comentário no topo. */
function comImpostoKpis(k: Kpis): Kpis {
  return {
    ...escalar(k, KPIS),
    roas: k.roas == null ? null : k.roas / FATOR_IMPOSTO,
  }
}

export function comImpostoPainel(dados: DadosPainel, ligado: boolean): DadosPainel {
  if (!ligado) return dados
  return {
    ...dados,
    kpis: dados.kpis ? comImpostoKpis(dados.kpis) : null,
    serie: dados.serie.map((l) => escalar(l, SERIE)),
    origens: dados.origens.map((l) => escalar(l, ORIGEM)),
    trafego: dados.trafego.map((l) => escalar(l, TRAFEGO)),
    formularios: dados.formularios.map((l) => escalar(l, FORMULARIO)),
    // renda, perfil e ciclo não têm dinheiro: passam intactos.
  }
}

export function comImpostoMacro(linhas: MacroLinha[], ligado: boolean): MacroLinha[] {
  return ligado ? linhas.map((l) => escalar(l, MACRO)) : linhas
}
