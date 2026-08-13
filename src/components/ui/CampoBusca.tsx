/**
 * Campo de busca com lupa à direita.
 *
 * Componente próprio porque a barra se repete em quatro lugares (os três
 * níveis da tabela de tráfego e o ciclo de vendas) — copiar o SVG em cada um
 * garantiria que um dia eles divergissem.
 *
 * A lupa é `pointer-events-none`: sem isso, clicar exatamente no ícone não
 * focaria o campo, que é onde o clique costuma cair.
 */
export function CampoBusca({
  valor,
  onChange,
  placeholder,
  className = '',
}: {
  valor: string
  onChange: (v: string) => void
  placeholder: string
  className?: string
}) {
  return (
    <div className={`relative ${className}`}>
      <input
        value={valor}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="w-full rounded-lg border border-line bg-card py-2 pr-10 pl-3 text-sm text-ink outline-none placeholder:text-faint focus:border-turq/60"
      />
      <svg
        viewBox="0 0 24 24"
        aria-hidden="true"
        className="pointer-events-none absolute top-1/2 right-3 h-4 w-4 -translate-y-1/2 text-faint"
        fill="none"
        stroke="currentColor"
        strokeWidth={2}
        strokeLinecap="round"
      >
        <circle cx="11" cy="11" r="7" />
        <line x1="16.5" y1="16.5" x2="21" y2="21" />
      </svg>
    </div>
  )
}
