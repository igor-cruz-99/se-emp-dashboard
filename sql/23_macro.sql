-- ============================================================================
-- SE EMP — 23. Matriz de visão macro (mês a mês do ano)
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- Uma linha por mês do ano, com o funil inteiro. Alimenta a tabela macro e o
-- gráfico combo (leads em barra + CPL em linha) do fim do painel.
--
-- ⚠️ NÃO recebe período: esta seção mostra sempre o ANO todo, independente do
--    filtro de datas da página. É a visão de tendência — recortá-la pelo mesmo
--    filtro dos outros blocos a tornaria redundante com eles.
--    `p_ano` default null = ano corrente.
--
-- Reaproveita o `fn_kpis` mês a mês em vez de reescrever as agregações. Assim
-- a matriz NUNCA diverge dos cartões do topo: se uma regra mudar (retargeting,
-- MQL, comparecimento), muda nos dois ao mesmo tempo. Duplicar o SQL aqui
-- seria a forma mais rápida de criar dois números diferentes na mesma tela.
--
-- ⚠️ Meses futuros do ano vêm com zeros — de propósito. O gráfico precisa do
--    eixo completo de janeiro a dezembro para a tendência ser lida na escala
--    certa; se os meses sumissem, dezembro apareceria colado em agosto.
-- ============================================================================

drop function if exists mkt_se.fn_macro(integer);

create or replace function mkt_se.fn_macro(p_ano integer default null)
returns table (
  mes                date,
  investimento       numeric,
  impressoes         bigint,
  cliques            bigint,
  cpc                numeric,
  leads              bigint,
  cpl                numeric,
  mql                bigint,
  pct_mql            numeric,
  cpmql              numeric,
  agendamentos       bigint,
  agendas            bigint,
  calls              bigint,
  cust_agen          numeric,
  vendas             bigint,
  cac                numeric,
  faturamento        numeric,
  pct_comparecimento numeric,
  sem_registro       bigint
)
language sql
stable
as $$
with ano as (
  select coalesce(p_ano, extract(year from current_date)::integer) as a
)
select
  d::date,
  k.investimento, k.impressoes, k.cliques, k.cpc,
  k.leads, k.cpl, k.mql, k.pct_mql, k.cpmql,
  k.agendamentos, k.agendas, k.calls, k.cpa,
  k.vendas, k.cac, k.faturamento,
  k.pct_comparecimento, k.sem_registro
from ano
cross join generate_series(
  make_date(ano.a, 1, 1),
  make_date(ano.a, 12, 1),
  interval '1 month'
) as d
cross join lateral mkt_se.fn_kpis(
  d::date,
  (d + interval '1 month' - interval '1 day')::date
) k
order by 1;
$$;

revoke all on function mkt_se.fn_macro(integer) from public, anon, authenticated;
grant execute on function mkt_se.fn_macro(integer) to service_role;


-- ----------------------------------------------------------------------------
-- Ponte no public
-- ----------------------------------------------------------------------------
create or replace function public.se_macro(p_ano integer default null)
returns table (
  mes date, investimento numeric, impressoes bigint, cliques bigint, cpc numeric,
  leads bigint, cpl numeric, mql bigint, pct_mql numeric, cpmql numeric,
  agendamentos bigint, agendas bigint, calls bigint, cust_agen numeric,
  vendas bigint, cac numeric, faturamento numeric,
  pct_comparecimento numeric, sem_registro bigint
)
language sql
stable
security definer
set search_path = mkt_se, public
as $$ select * from mkt_se.fn_macro(p_ano); $$;

revoke all on function public.se_macro(integer) from public, anon, authenticated;
grant execute on function public.se_macro(integer) to service_role;

notify pgrst, 'reload schema';


-- ============================================================================
-- CONFERÊNCIA — a soma do ano tem de bater com um fn_kpis de 01/01 a 31/12
-- ============================================================================
--   select round(sum(investimento),2) inv, sum(leads) leads,
--          sum(agendamentos) agend, sum(vendas) vendas
--   from mkt_se.fn_macro(2026);
--
--   select investimento, leads, agendamentos, vendas
--   from mkt_se.fn_kpis('2026-01-01','2026-12-31');
-- ============================================================================
