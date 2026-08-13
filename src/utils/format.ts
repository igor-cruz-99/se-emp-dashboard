/**
 * Formatação pt-BR.
 *
 * Regra que atravessa o painel: valor ausente vira "—", nunca "0" ou "R$ 0,00".
 * As RPCs devolvem null quando não há base de cálculo (divisão por zero), e um
 * zero na tela pareceria dado real — "CAC R$ 0,00" leria como aquisição de
 * graça, quando na verdade não houve venda.
 */

const VAZIO = '—'

export function formatBRL(v: number | null | undefined): string {
  if (v == null || !Number.isFinite(v)) return VAZIO
  return v.toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    minimumFractionDigits: 2,
  })
}

/** Moeda compacta para eixos de gráfico: R$ 8 mil. */
export function formatBRLCurto(v: number | null | undefined): string {
  if (v == null || !Number.isFinite(v)) return VAZIO
  if (Math.abs(v) >= 1000) return `R$ ${(v / 1000).toLocaleString('pt-BR', { maximumFractionDigits: 0 })} mil`
  return `R$ ${v.toLocaleString('pt-BR', { maximumFractionDigits: 0 })}`
}

export function formatInt(v: number | null | undefined): string {
  if (v == null || !Number.isFinite(v)) return VAZIO
  return Math.round(v).toLocaleString('pt-BR')
}

export function formatPct(v: number | null | undefined, casas = 2): string {
  if (v == null || !Number.isFinite(v)) return VAZIO
  return `${v.toLocaleString('pt-BR', { minimumFractionDigits: casas, maximumFractionDigits: casas })}%`
}

export function formatDec(v: number | null | undefined, casas = 2): string {
  if (v == null || !Number.isFinite(v)) return VAZIO
  return v.toLocaleString('pt-BR', { minimumFractionDigits: casas, maximumFractionDigits: casas })
}

/** '2026-08-12' → '12/08' (para eixo de gráfico). */
export function diaCurto(iso: string): string {
  const [, m, d] = iso.split('-')
  return `${d}/${m}`
}

/** Date → 'YYYY-MM-DD' no fuso local (não UTC — evita voltar um dia). */
export function paraISO(d: Date): string {
  const mes = String(d.getMonth() + 1).padStart(2, '0')
  const dia = String(d.getDate()).padStart(2, '0')
  return `${d.getFullYear()}-${mes}-${dia}`
}
