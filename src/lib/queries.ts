import { supabaseAuth } from './supabase'
import { DEV_SKIP_AUTH } from './devAuth'
import type {
  CicloLinha,
  DiaSerie,
  FormularioLinha,
  Kpis,
  MacroLinha,
  Meta,
  OrigemLinha,
  PerfilLinha,
  RendaLinha,
  TrafegoLinha,
} from '../types'

/**
 * Toda leitura de dado passa por aqui — e daqui para `/api/dashboard`.
 * O navegador nunca fala com o banco: só com o porteiro, que valida a sessão.
 */
async function chamar<T>(fn: string, params: Record<string, unknown> = {}): Promise<T[]> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }

  if (!DEV_SKIP_AUTH) {
    const { data } = await supabaseAuth!.auth.getSession()
    const token = data.session?.access_token
    if (!token) throw new Error('Sessão expirada. Faça login novamente.')
    headers.Authorization = `Bearer ${token}`
  }

  const r = await fetch('/api/dashboard', {
    method: 'POST',
    headers,
    body: JSON.stringify({ fn, params }),
  })

  const corpo = (await r.json()) as { data?: T[]; error?: string }
  if (!r.ok) throw new Error(corpo.error ?? 'Falha ao consultar os dados.')
  return corpo.data ?? []
}

export async function fetchKpis(
  inicio: string,
  fim: string,
  origens: string[] | null,
): Promise<Kpis | null> {
  const linhas = await chamar<Kpis>('se_kpis', {
    p_ini: inicio,
    p_fim: fim,
    p_origens: origens,
  })
  return linhas[0] ?? null
}

export async function fetchSerie(
  inicio: string,
  fim: string,
  origens: string[] | null,
): Promise<DiaSerie[]> {
  return chamar<DiaSerie>('se_serie_diaria', {
    p_ini: inicio,
    p_fim: fim,
    p_origens: origens,
  })
}

export async function fetchOrigens(inicio: string, fim: string): Promise<OrigemLinha[]> {
  return chamar<OrigemLinha>('se_origem', { p_ini: inicio, p_fim: fim })
}

export async function fetchRenda(
  inicio: string,
  fim: string,
  origens: string[] | null,
): Promise<RendaLinha[]> {
  return chamar<RendaLinha>('se_renda', { p_ini: inicio, p_fim: fim, p_origens: origens })
}

export async function fetchTrafego(
  inicio: string,
  fim: string,
  origens: string[] | null,
): Promise<TrafegoLinha[]> {
  return chamar<TrafegoLinha>('se_trafego', { p_ini: inicio, p_fim: fim, p_origens: origens })
}

export async function fetchCiclo(
  inicio: string,
  fim: string,
  origens: string[] | null,
): Promise<CicloLinha[]> {
  return chamar<CicloLinha>('se_ciclo_vendas', { p_ini: inicio, p_fim: fim, p_origens: origens })
}

export async function fetchPerfil(
  inicio: string,
  fim: string,
  origens: string[] | null,
): Promise<PerfilLinha[]> {
  return chamar<PerfilLinha>('se_perfil_lead', { p_ini: inicio, p_fim: fim, p_origens: origens })
}

export async function fetchFormularios(
  inicio: string,
  fim: string,
  origens: string[] | null,
): Promise<FormularioLinha[]> {
  return chamar<FormularioLinha>('se_formularios', {
    p_ini: inicio,
    p_fim: fim,
    p_origens: origens,
  })
}

/**
 * A matriz macro NÃO recebe período: mostra sempre o ano corrente,
 * independente do filtro da página. Ver sql/23_macro.sql.
 */
export async function fetchMacro(): Promise<MacroLinha[]> {
  return chamar<MacroLinha>('se_macro', {})
}

/**
 * Metas são opcionais: se a tabela ainda não existir ou vier vazia, os badges
 * saem em cor neutra em vez de derrubar o painel inteiro.
 */
export async function fetchMetas(): Promise<Record<string, Meta>> {
  try {
    const linhas = await chamar<Meta>('se_metas')
    return Object.fromEntries(linhas.map((m) => [m.chave, m]))
  } catch {
    return {}
  }
}
