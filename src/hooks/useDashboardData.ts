import { useCallback, useEffect, useState } from 'react'
import {
  fetchCiclo,
  fetchFormularios,
  fetchKpis,
  fetchMetas,
  fetchOrigens,
  fetchPerfil,
  fetchRenda,
  fetchSerie,
  fetchTrafego,
} from '../lib/queries'
import type { DadosPainel, Filtros } from '../types'

const VAZIO: DadosPainel = {
  kpis: null,
  serie: [],
  origens: [],
  renda: [],
  trafego: [],
  ciclo: [],
  perfil: [],
  formularios: [],
  metas: {},
}

/**
 * Orquestra os fetches: dispara tudo em paralelo a cada mudança de filtro.
 *
 * As metas são buscadas junto, mas seu erro não derruba o painel (o fetch
 * delas já é tolerante em queries.ts) — sem meta, os badges saem neutros.
 */
export function useDashboardData(filtros: Filtros) {
  const [dados, setDados] = useState<DadosPainel>(VAZIO)
  const [carregando, setCarregando] = useState(true)
  const [erro, setErro] = useState<string | null>(null)

  const carregar = useCallback(async () => {
    setCarregando(true)
    setErro(null)
    try {
      const [kpis, serie, origens, renda, trafego, ciclo, perfil, formularios, metas] =
        await Promise.all([
        fetchKpis(filtros.inicio, filtros.fim, filtros.origens),
        fetchSerie(filtros.inicio, filtros.fim, filtros.origens),
        fetchOrigens(filtros.inicio, filtros.fim),
        fetchRenda(filtros.inicio, filtros.fim, filtros.origens),
        fetchTrafego(filtros.inicio, filtros.fim, filtros.origens),
        fetchCiclo(filtros.inicio, filtros.fim, filtros.origens),
        fetchPerfil(filtros.inicio, filtros.fim, filtros.origens),
        fetchFormularios(filtros.inicio, filtros.fim, filtros.origens),
        fetchMetas(),
      ])
      setDados({ kpis, serie, origens, renda, trafego, ciclo, perfil, formularios, metas })
    } catch (e) {
      setErro((e as Error).message)
      setDados(VAZIO)
    } finally {
      setCarregando(false)
    }
  }, [filtros.inicio, filtros.fim, filtros.origens])

  useEffect(() => {
    void carregar()
  }, [carregar])

  return { dados, carregando, erro, recarregar: carregar }
}
