import { TAXA_IMPOSTO_META } from '../../utils/impostoMeta'

/**
 * Interruptor do imposto da Meta.
 *
 * Fica em âmbar, não no turquesa da marca, de propósito: o turquesa marca o que
 * está selecionado (atalho de período, origem), e este botão não é uma seleção
 * — é um aviso de que **todo número de custo na tela está ajustado**. Cor
 * diferente para significado diferente.
 *
 * Desligado ele não some nem fica cinza-morto: continua legível, com a trilha
 * apagada. Precisa dar para ver, num relance, em qual dos dois estados o painel
 * está — senão a pessoa lê CPL ajustado achando que é o da plataforma.
 */
export function BotaoImposto({
  ligado,
  onMudar,
}: {
  ligado: boolean
  onMudar: (v: boolean) => void
}) {
  const pct = `${Math.round(TAXA_IMPOSTO_META * 100)}%`

  return (
    <button
      type="button"
      role="switch"
      aria-checked={ligado}
      onClick={() => onMudar(!ligado)}
      title={
        ligado
          ? `Ligado: o investimento e todos os custos derivados estão ${pct} acima do que a Meta cobra na plataforma.`
          : `Desligado: os valores são os da plataforma, sem o imposto de ${pct}.`
      }
      className={`flex items-center gap-2.5 rounded-full border px-3.5 py-2 text-xs font-semibold tracking-wide transition ${
        ligado
          ? 'border-warn/60 bg-warn/10 text-warn'
          : 'border-line bg-card text-muted hover:text-ink'
      }`}
    >
      {/* Trilha do interruptor: o estado precisa ser visível sem depender só da
          cor, para quem enxerga cor de outro jeito. Daí o botão que anda. */}
      <span
        aria-hidden="true"
        className={`relative inline-block h-3.5 w-7 shrink-0 rounded-full transition ${
          ligado ? 'bg-warn/70' : 'bg-line'
        }`}
      >
        <span
          className={`absolute top-0.5 h-2.5 w-2.5 rounded-full transition-all ${
            ligado ? 'left-[15px] bg-bg' : 'left-0.5 bg-muted'
          }`}
        />
      </span>
      IMPOSTO META
    </button>
  )
}
