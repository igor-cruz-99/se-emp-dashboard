import { useEffect, useRef, useState } from 'react'

/**
 * Filtro de origem em caixas de seleção.
 *
 * Substituiu o `<select>` de origem única porque o gestor precisa ver várias
 * fontes juntas — e porque o **VSL não entra no funil principal**, então ele
 * nasce desmarcado. Com escolha única não havia como expressar "tudo menos
 * uma".
 *
 * ⚠️ A lista de origens vem do servidor e pode crescer. Origem nova nasce
 * MARCADA: o padrão seguro é incluir — esquecer de marcar esconderia verba da
 * conta sem ninguém perceber. Só o VSL começa fora, por decisão explícita.
 */
export function FiltroOrigens({
  disponiveis,
  desmarcadas,
  onMudar,
}: {
  disponiveis: string[]
  desmarcadas: string[]
  onMudar: (desmarcadas: string[]) => void
}) {
  const [aberto, setAberto] = useState(false)
  const caixa = useRef<HTMLDivElement>(null)

  // Fecha ao clicar fora — sem isso o painel fica com um menu pendurado
  // enquanto a pessoa tenta usar o resto da tela.
  useEffect(() => {
    if (!aberto) return
    function fora(e: MouseEvent) {
      if (caixa.current && !caixa.current.contains(e.target as Node)) setAberto(false)
    }
    document.addEventListener('mousedown', fora)
    return () => document.removeEventListener('mousedown', fora)
  }, [aberto])

  const marcadas = disponiveis.filter((o) => !desmarcadas.includes(o))
  const todas = marcadas.length === disponiveis.length

  const resumo = todas
    ? 'TODAS AS ORIGENS'
    : marcadas.length === 0
      ? 'NENHUMA ORIGEM'
      : marcadas.length === 1
        ? marcadas[0].toUpperCase()
        : `${marcadas.length} DE ${disponiveis.length} ORIGENS`

  function alternar(o: string) {
    onMudar(desmarcadas.includes(o) ? desmarcadas.filter((x) => x !== o) : [...desmarcadas, o])
  }

  return (
    <div className="relative" ref={caixa}>
      <button
        onClick={() => setAberto((a) => !a)}
        className={`flex items-center gap-2 rounded-full border bg-card px-4 py-2 text-xs tracking-wide transition ${
          todas ? 'border-line text-ink' : 'border-turq/50 text-turq-soft'
        }`}
      >
        {resumo}
        <svg
          viewBox="0 0 24 24"
          aria-hidden="true"
          className={`h-3 w-3 transition-transform ${aberto ? 'rotate-180' : ''}`}
          fill="none"
          stroke="currentColor"
          strokeWidth={2.5}
          strokeLinecap="round"
        >
          <polyline points="6 9 12 15 18 9" />
        </svg>
      </button>

      {aberto && (
        <div className="absolute right-0 z-30 mt-2 w-60 rounded-xl border border-line bg-card p-2 shadow-xl">
          <div className="mb-1 flex gap-1 border-b border-line/70 pb-2">
            <button
              onClick={() => onMudar([])}
              className="flex-1 rounded-md px-2 py-1 text-[11px] text-muted transition hover:bg-card-alt hover:text-ink"
            >
              Marcar todas
            </button>
            <button
              onClick={() => onMudar(disponiveis)}
              className="flex-1 rounded-md px-2 py-1 text-[11px] text-muted transition hover:bg-card-alt hover:text-ink"
            >
              Limpar
            </button>
          </div>

          {disponiveis.length === 0 ? (
            <p className="px-2 py-3 text-xs text-faint">Carregando origens…</p>
          ) : (
            disponiveis.map((o) => {
              const marcada = !desmarcadas.includes(o)
              return (
                <label
                  key={o}
                  className="flex cursor-pointer items-center gap-2.5 rounded-md px-2 py-1.5 text-sm text-ink transition hover:bg-card-alt"
                >
                  <input
                    type="checkbox"
                    checked={marcada}
                    onChange={() => alternar(o)}
                    className="h-3.5 w-3.5 accent-[var(--color-turq)]"
                  />
                  {o}
                </label>
              )
            })
          )}
        </div>
      )}
    </div>
  )
}
