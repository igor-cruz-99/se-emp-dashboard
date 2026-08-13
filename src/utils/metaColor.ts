import type { Meta } from '../types'

/**
 * Cor do badge conforme a distância da meta.
 *
 * ⚠️ `direcao` é o que evita o erro clássico de métrica de custo: um CPL que
 * SOBE está piorando, mesmo "superando" o número da meta. Sem isso o painel
 * pintaria de verde exatamente o cenário ruim.
 *
 *   direcao 'maior' → atingimento = valor / meta   (conversão, comparecimento)
 *   direcao 'menor' → atingimento = meta / valor   (CPL, CAC)
 *
 * Em ambos os casos, atingimento >= 1 significa "na meta".
 */
export type Situacao = 'bom' | 'atencao' | 'ruim' | 'neutro'

export function atingimento(valor: number | null, meta: Meta | undefined): number | null {
  if (valor == null || !Number.isFinite(valor) || !meta || meta.valor === 0) return null
  return meta.direcao === 'menor' ? meta.valor / valor : valor / meta.valor
}

export function situacao(valor: number | null, meta: Meta | undefined): Situacao {
  const a = atingimento(valor, meta)
  if (a == null) return 'neutro'
  if (a >= 1) return 'bom'
  if (a >= 0.8) return 'atencao'
  return 'ruim'
}

/**
 * Escala vermelho → âmbar → verde para comparar meses entre si.
 *
 * Usada nas colunas de eficiência da matriz macro (CPL, %MQL, $Cust/Agen, CAC).
 * A referência é o PRÓPRIO ano: o melhor mês da coluna fica verde, o pior
 * vermelho, e o resto no degradê. É diferente do badge dos cartões, que compara
 * com a meta — aqui a pergunta é "qual mês foi bom", não "batemos o alvo".
 *
 * ⚠️ `direcao` é o que impede o erro clássico: num CPL, valor BAIXO é o bom.
 * Sem isso a tabela pintaria de verde justamente o mês mais caro.
 */
const RUIM = [0xf8, 0x71, 0x71]
const MEIO = [0xfb, 0xbf, 0x24]
const BOM = [0x34, 0xd3, 0x99]

/** t: 0 = pior, 1 = melhor. */
function misturar(t: number): string {
  const [a, b, f] = t < 0.5 ? [RUIM, MEIO, t * 2] : [MEIO, BOM, (t - 0.5) * 2]
  const c = a.map((v, i) => Math.round(v + (b[i] - v) * f))
  return `rgb(${c[0]},${c[1]},${c[2]})`
}

export function corEscala(
  valor: number | null | undefined,
  min: number,
  max: number,
  direcao: 'maior' | 'menor',
): string | undefined {
  if (valor == null || !Number.isFinite(valor)) return undefined
  // Um mês só, ou todos iguais: não há o que comparar — cor neutra.
  if (max <= min) return undefined
  const bruto = (valor - min) / (max - min)
  return misturar(direcao === 'menor' ? 1 - bruto : bruto)
}

/** Classes Tailwind do badge. Neutro = ainda não há meta cadastrada. */
export function classesBadge(s: Situacao): string {
  switch (s) {
    case 'bom':
      return 'bg-good/15 text-good border-good/30'
    case 'atencao':
      return 'bg-warn/15 text-warn border-warn/30'
    case 'ruim':
      return 'bg-bad/15 text-bad border-bad/30'
    default:
      return 'bg-turq/10 text-turq-soft border-turq/25'
  }
}
