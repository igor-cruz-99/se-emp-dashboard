-- ============================================================================
-- SE EMP — 22. fn_kpis devolve a base do comparecimento
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- POR QUÊ
--   O comparecimento é `realizados / (realizados + no_show)`. Em jan–mai/2026
--   esse denominador tem 73 a 89 casos — número sólido. Em JUNHO e JULHO ele
--   tem 8 e 7, porque a Bitrix (de onde vem o desfecho) já não era alimentada,
--   enquanto os agendamentos eram 247 e 254.
--
--   Um "87,5% de comparecimento" apoiado em 8 sessões não é tendência, é
--   ruído — e é exatamente o tipo de número que vira decisão numa reunião.
--   Devolvendo `sem_registro`, o painel consegue medir a solidez da base e
--   apagar a cor do indicador quando ela for pequena demais.
--
-- ⚠️ Mudou o retorno → a ponte public.se_kpis TEM de ser recriada junto,
--    senão quebra com "return type mismatch". Estão no mesmo arquivo por isso.
-- ============================================================================

drop function if exists mkt_se.fn_kpis(date, date, text, boolean);

create or replace function mkt_se.fn_kpis(
  p_ini           date,
  p_fim           date,
  p_origem        text    default null,
  p_incluir_rmkt  boolean default false
)
returns table (
  dias integer, investimento numeric, impressoes bigint, cliques bigint,
  leads bigint, mql bigint, agendamentos bigint, agendas bigint,
  calls bigint, no_shows bigint, pendentes bigint, sem_registro bigint,
  vendas bigint, faturamento numeric,
  ctr numeric, pct_leads numeric, pct_mql numeric, pct_agend numeric,
  pct_comparecimento numeric, pct_no_show numeric, pct_conversao numeric,
  cpm numeric, cpc numeric, cpl numeric, cpmql numeric,
  cpa numeric, ccall numeric, cac numeric, roas numeric
)
language sql
stable
as $$
with ads as (
  select
    coalesce(sum(gasto), 0)      as investimento,
    coalesce(sum(impressoes), 0) as impressoes,
    coalesce(sum(cliques), 0)    as cliques
  from mkt_se.vw_ads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and (p_incluir_rmkt or (not retargeting and origem <> 'Engajamento'))
),
lead as (
  select count(*) as leads, count(*) filter (where mql) as mql
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and (p_incluir_rmkt or not retargeting)
),
agen as (
  select
    count(*)                                            as agendamentos,  -- sessões
    count(distinct email)                               as agendas,       -- pessoas
    count(*) filter (where situacao = 'realizado')      as calls,
    count(*) filter (where situacao = 'no_show')        as no_shows,
    count(*) filter (where situacao = 'pendente')       as pendentes,
    count(*) filter (where situacao = 'sem_registro')   as sem_registro
  from mkt_se.vw_agendamentos
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
),
vend as (
  select count(*) as vendas, coalesce(sum(valor), 0) as faturamento
  from mkt_se.vw_vendas
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
)
select
  (p_fim - p_ini + 1)::integer,
  round(a.investimento::numeric, 2),
  a.impressoes, a.cliques, l.leads, l.mql,
  g.agendamentos, g.agendas, g.calls, g.no_shows, g.pendentes, g.sem_registro,
  v.vendas, round(v.faturamento::numeric, 2),

  round(100.0 * a.cliques      / nullif(a.impressoes, 0),           2),
  round(100.0 * l.leads        / nullif(a.cliques, 0),              2),
  round(100.0 * l.mql          / nullif(l.leads, 0),                2),
  round(100.0 * g.agendamentos / nullif(l.mql, 0),                  2),
  round(100.0 * g.calls        / nullif(g.calls + g.no_shows, 0),   2),
  round(100.0 * g.no_shows     / nullif(g.calls + g.no_shows, 0),   2),
  round(100.0 * v.vendas       / nullif(g.agendamentos, 0),         2),

  round(1000 * a.investimento  / nullif(a.impressoes, 0),   2),
  round(a.investimento         / nullif(a.cliques, 0),      2),
  round(a.investimento         / nullif(l.leads, 0),        2),
  round(a.investimento         / nullif(l.mql, 0),          2),
  round(a.investimento         / nullif(g.agendamentos, 0), 2),
  round(a.investimento         / nullif(g.calls, 0),        2),
  round(a.investimento         / nullif(v.vendas, 0),       2),
  round(v.faturamento          / nullif(a.investimento, 0), 2)
from ads a, lead l, agen g, vend v;
$$;

revoke all on function mkt_se.fn_kpis(date, date, text, boolean) from public, anon, authenticated;
grant execute on function mkt_se.fn_kpis(date, date, text, boolean) to service_role;


-- ----------------------------------------------------------------------------
-- Ponte no public — assinatura tem de acompanhar
-- ----------------------------------------------------------------------------
drop function if exists public.se_kpis(date, date, text, boolean);

create or replace function public.se_kpis(
  p_ini date, p_fim date, p_origem text default null, p_incluir_rmkt boolean default false
)
returns table (
  dias integer, investimento numeric, impressoes bigint, cliques bigint,
  leads bigint, mql bigint, agendamentos bigint, agendas bigint,
  calls bigint, no_shows bigint, pendentes bigint, sem_registro bigint,
  vendas bigint, faturamento numeric,
  ctr numeric, pct_leads numeric, pct_mql numeric, pct_agend numeric,
  pct_comparecimento numeric, pct_no_show numeric, pct_conversao numeric,
  cpm numeric, cpc numeric, cpl numeric, cpmql numeric,
  cpa numeric, ccall numeric, cac numeric, roas numeric
)
language sql
stable
security definer
set search_path = mkt_se, public
as $$ select * from mkt_se.fn_kpis(p_ini, p_fim, p_origem, p_incluir_rmkt); $$;

revoke all on function public.se_kpis(date, date, text, boolean) from public, anon, authenticated;
grant execute on function public.se_kpis(date, date, text, boolean) to service_role;

notify pgrst, 'reload schema';


-- ============================================================================
-- CONFERÊNCIA — a base de junho/julho tem de aparecer pequena
-- ============================================================================
--   select to_char(d,'YYYY-MM') mes, k.agendamentos, k.agendas,
--          k.calls + k.no_shows as base_comparecimento, k.sem_registro,
--          k.pct_comparecimento
--   from generate_series(date '2026-01-01', date '2026-08-01', interval '1 month') d
--   cross join lateral mkt_se.fn_kpis(d::date, (d + interval '1 month - 1 day')::date) k
--   order by 1;
-- ============================================================================
