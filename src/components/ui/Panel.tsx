import type { ReactNode } from 'react'

/** Cartão base. Todo bloco do painel usa — mantém raio, borda e fundo iguais. */
export function Panel({
  children,
  className = '',
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <div
      className={`rounded-2xl border border-line bg-card/80 backdrop-blur-sm ${className}`}
    >
      {children}
    </div>
  )
}

export function SectionTitle({
  titulo,
  sub,
  acessorio,
}: {
  titulo: string
  sub?: string
  acessorio?: ReactNode
}) {
  return (
    <div className="flex items-start justify-between gap-4 px-6 pt-4">
      <div>
        <h2 className="titulo">{titulo}</h2>
        {sub && <p className="mt-1 text-xs text-faint">{sub}</p>}
      </div>
      {acessorio}
    </div>
  )
}
