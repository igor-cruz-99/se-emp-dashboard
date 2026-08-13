import { useEffect, useState } from 'react'

/**
 * Índice âncora fixo à esquerda, colapsável.
 *
 * A página ficou longa (seis seções, várias com tabela rolável) e voltar da
 * matriz macro para o funil dava três telas de scroll. Mas o índice aberto
 * comia ~210px de largura — espaço que as tabelas de tráfego, com 11 colunas,
 * usam melhor.
 *
 * Colapsado ele vira uma faixa de 44px com só as iniciais, e continua
 * marcando onde você está. A escolha fica gravada no navegador: quem prefere
 * fechado não precisa fechar de novo a cada visita.
 */
export interface Secao {
  id: string
  titulo: string
}

const CHAVE = 'se-dash-indice-aberto'

/** "Matriz mês a mês" → "MM" · "Origem e renda" → "OR" */
function iniciais(titulo: string): string {
  const p = titulo.split(/\s+/).filter((w) => w.length > 2)
  return (p[0]?.[0] ?? titulo[0] ?? '').toUpperCase() + (p[1]?.[0] ?? '').toUpperCase()
}

export function Sidebar({ secoes }: { secoes: Secao[] }) {
  const [ativa, setAtiva] = useState(secoes[0]?.id ?? '')
  const [aberto, setAberto] = useState(() => {
    // Começa fechado: o padrão certo é o que sobra espaço para o conteúdo.
    if (typeof window === 'undefined') return false
    return window.localStorage.getItem(CHAVE) === '1'
  })

  useEffect(() => {
    window.localStorage.setItem(CHAVE, aberto ? '1' : '0')
  }, [aberto])

  useEffect(() => {
    const alvos = secoes
      .map((s) => document.getElementById(s.id))
      .filter((e): e is HTMLElement => e != null)
    if (alvos.length === 0) return

    const obs = new IntersectionObserver(
      (entradas) => {
        // A seção "ativa" é a mais alta entre as visíveis. Sem esse desempate,
        // duas seções na tela ao mesmo tempo ficam piscando entre si.
        const visiveis = entradas
          .filter((e) => e.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)
        if (visiveis[0]) setAtiva(visiveis[0].target.id)
      },
      { rootMargin: '-72px 0px -70% 0px', threshold: 0 },
    )

    alvos.forEach((a) => obs.observe(a))
    return () => obs.disconnect()
  }, [secoes])

  return (
    // ⚠️ `shrink-0`: sem ele o irmão `flex-1` comprime o nav de volta ao
    // tamanho fechado, e expandir não muda nada na tela — a classe `w-52`
    // aplica, mas o flex a ignora ao distribuir o espaço.
    <nav className={`hidden shrink-0 lg:block ${aberto ? 'w-52' : 'w-11'}`}>
      <div
        className={`sticky top-6 ${aberto ? "pr-4" : ""}`}
      >
        <button
          onClick={() => setAberto((a) => !a)}
          title={aberto ? 'Recolher índice' : 'Expandir índice'}
          className="mb-3 flex h-7 w-full items-center gap-2 rounded-md px-2 text-muted transition hover:bg-card-alt hover:text-ink"
        >
          <svg
            viewBox="0 0 24 24"
            aria-hidden="true"
            className="h-4 w-4 shrink-0"
            fill="none"
            stroke="currentColor"
            strokeWidth={2}
            strokeLinecap="round"
          >
            <line x1="4" y1="7" x2="20" y2="7" />
            <line x1="4" y1="12" x2="20" y2="12" />
            <line x1="4" y1="17" x2="14" y2="17" />
          </svg>
          {aberto && <span className="rotulo">Índice</span>}
        </button>

        <ul className="flex flex-col gap-0.5 border-l border-line">
          {secoes.map((s) => {
            const atual = ativa === s.id
            return (
              <li key={s.id}>
                <a
                  href={`#${s.id}`}
                  onClick={(e) => {
                    e.preventDefault()
                    document.getElementById(s.id)?.scrollIntoView({ behavior: 'smooth' })
                    setAtiva(s.id)
                  }}
                  // Fechado, o título vira tooltip — sem isso as iniciais
                  // sozinhas não dizem para onde o clique leva.
                  title={aberto ? undefined : s.titulo}
                  className={`-ml-px block border-l-2 py-1.5 transition ${
                    aberto ? 'pl-3 text-xs' : 'text-center text-[10px] font-semibold'
                  } ${
                    atual
                      ? 'border-turq font-semibold text-turq'
                      : 'border-transparent text-muted hover:text-ink'
                  }`}
                >
                  {aberto ? s.titulo : iniciais(s.titulo)}
                </a>
              </li>
            )
          })}
        </ul>
      </div>
    </nav>
  )
}
