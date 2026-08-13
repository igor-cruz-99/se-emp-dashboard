-- ============================================================================
-- SE EMP — 08. Ponte no schema public
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- POR QUE EXISTE
--   O PostgREST só enxerga schemas na lista "Exposed schemas" do painel.
--   Nesse projeto a lista está travada em `public, bl_test, dw_bitrix,
--   contracts_app` — a alteração pelo painel não é aplicada, e nem
--   `notify pgrst,'reload config'` resolveu.
--
--   Como `public` já está exposto, estas funções finas dão acesso ao mkt_se
--   sem depender daquela configuração.
--
--   Efeito colateral bom: o porteiro do painel (api/dashboard.ts) também deixa
--   de depender do Exposed schemas — ele chama `se_*` no public e pronto.
--
-- ⚠️ A LISTA DE COLUNAS É REPETIDA DE PROPÓSITO.
--   `returns setof mkt_se.fn_kpis` não compila: funções com `returns table(...)`
--   não criam um tipo composto nomeado (só `returns setof <tabela/view>` criaria).
--   Então a assinatura precisa ser redeclarada aqui.
--   ⚠️ Ao mudar o retorno de uma fn_* no 07, mude também aqui — senão a ponte
--      quebra com "return type mismatch".
--
-- SEGURANÇA
--   Estar no `public` não torna nada público: o EXECUTE é revogado de anon e
--   authenticated e concedido só à service_role, que só o servidor tem.
--   `security definer` é o que permite à função alcançar o mkt_se, que
--   continua trancado para os demais papéis.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Sonda de desenvolvimento (espelha mkt_se.q — STABLE, só leitura)
-- ----------------------------------------------------------------------------
create or replace function public.se_q(sql text)
returns jsonb
language sql
stable
security definer
set search_path = mkt_se, public
as $$ select mkt_se.q(sql); $$;


-- ----------------------------------------------------------------------------
-- KPIs
-- ----------------------------------------------------------------------------
create or replace function public.se_kpis(
  p_ini date, p_fim date, p_origem text default null, p_incluir_rmkt boolean default false
)
returns table (
  dias integer, investimento numeric, impressoes bigint, cliques bigint,
  leads bigint, mql bigint, agendamentos bigint, calls bigint, no_shows bigint,
  vendas bigint, faturamento numeric,
  ctr numeric, pct_leads numeric, pct_mql numeric, pct_agend numeric,
  pct_no_show numeric, pct_conversao numeric,
  cpm numeric, cpc numeric, cpl numeric, cpmql numeric,
  cpa numeric, ccall numeric, cac numeric, roas numeric
)
language sql
stable
security definer
set search_path = mkt_se, public
as $$ select * from mkt_se.fn_kpis(p_ini, p_fim, p_origem, p_incluir_rmkt); $$;


-- ----------------------------------------------------------------------------
-- Série diária
-- ----------------------------------------------------------------------------
create or replace function public.se_serie_diaria(
  p_ini date, p_fim date, p_origem text default null, p_incluir_rmkt boolean default false
)
returns table (
  data date, investimento numeric, impressoes bigint, cliques bigint,
  leads bigint, mql bigint, agendamentos bigint, calls bigint,
  vendas bigint, faturamento numeric
)
language sql
stable
security definer
set search_path = mkt_se, public
as $$ select * from mkt_se.fn_serie_diaria(p_ini, p_fim, p_origem, p_incluir_rmkt); $$;


-- ----------------------------------------------------------------------------
-- Desempenho por origem
-- ----------------------------------------------------------------------------
create or replace function public.se_origem(
  p_ini date, p_fim date, p_incluir_rmkt boolean default false
)
returns table (
  origem text, investimento numeric, leads bigint, mql bigint,
  agendamentos bigint, calls bigint, vendas bigint, faturamento numeric,
  cpl numeric, cpmql numeric, cpa numeric, cac numeric,
  pct_mql numeric, pct_agend numeric
)
language sql
stable
security definer
set search_path = mkt_se, public
as $$ select * from mkt_se.fn_origem(p_ini, p_fim, p_incluir_rmkt); $$;


-- ----------------------------------------------------------------------------
-- Permissões — nada de anon/authenticated tocando nisso
-- ----------------------------------------------------------------------------
revoke all on function public.se_q(text)                                    from public, anon, authenticated;
revoke all on function public.se_kpis(date, date, text, boolean)            from public, anon, authenticated;
revoke all on function public.se_serie_diaria(date, date, text, boolean)    from public, anon, authenticated;
revoke all on function public.se_origem(date, date, boolean)                from public, anon, authenticated;

grant execute on function public.se_q(text)                                 to service_role;
grant execute on function public.se_kpis(date, date, text, boolean)         to service_role;
grant execute on function public.se_serie_diaria(date, date, text, boolean) to service_role;
grant execute on function public.se_origem(date, date, boolean)             to service_role;

notify pgrst, 'reload schema';

-- Teste:
select public.se_q('select count(*) as linhas from mkt_se.vw_agendamentos');
