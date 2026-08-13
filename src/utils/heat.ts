/**
 * Mapa de calor das células da tabela de tráfego.
 *
 * A intensidade é relativa ao MAIOR valor da coluna, não a uma escala fixa:
 * o que interessa é comparar campanhas entre si dentro do período, e uma
 * escala absoluta ficaria toda apagada num mês fraco.
 *
 * Vale tanto para métrica "boa" (investimento, leads) quanto para métrica de
 * custo (CPL, CAC): nos dois casos o que merece o olho é o valor ALTO — muito
 * volume ou muito caro. Por isso não há inversão de sentido aqui; quem decide
 * se o destaque é bom ou ruim é o leitor, pelo nome da coluna.
 */
export function heat(valor: number | null | undefined, max: number): string | undefined {
  if (valor == null || !Number.isFinite(valor) || max <= 0) return undefined

  const t = Math.min(Math.max(valor / max, 0), 1)

  // Abaixo de 8% a célula fica sem fundo: pintar tudo faz o realce perder função.
  if (t < 0.08) return undefined

  // Turquesa translúcido — segue o tema sem competir com a leitura do texto.
  return `rgba(34, 225, 214, ${(t * 0.22).toFixed(3)})`
}

/** Maior valor de uma coluna, ignorando nulos. */
export function maxDe<T>(linhas: T[], pega: (l: T) => number | null | undefined): number {
  const nums = linhas.map((l) => Number(pega(l) ?? 0)).filter(Number.isFinite)
  return nums.length ? Math.max(0, ...nums) : 0
}
