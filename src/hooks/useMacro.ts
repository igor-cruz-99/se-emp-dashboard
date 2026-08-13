import { useEffect, useState } from 'react'
import { fetchMacro } from '../lib/queries'
import type { MacroLinha } from '../types'

/**
 * Busca a matriz macro UMA vez, na montagem.
 *
 * Hook separado do `useDashboardData` de propósito: esta seção mostra sempre o
 * ano corrente e não deve reagir ao filtro de datas da página. Se ela vivesse
 * junto com o resto, refaria a consulta a cada troca de período — 12 chamadas
 * ao fn_kpis — para devolver exatamente o mesmo resultado.
 */
export function useMacro() {
  const [linhas, setLinhas] = useState<MacroLinha[]>([])
  const [carregando, setCarregando] = useState(true)

  useEffect(() => {
    let ativo = true
    fetchMacro()
      .then((r) => {
        if (ativo) setLinhas(r)
      })
      .catch(() => {
        // Falha aqui não pode derrubar o painel: é um bloco de contexto,
        // não o dado principal. Sem ele, a seção só não aparece.
        if (ativo) setLinhas([])
      })
      .finally(() => {
        if (ativo) setCarregando(false)
      })
    return () => {
      ativo = false
    }
  }, [])

  return { linhas, carregando }
}
