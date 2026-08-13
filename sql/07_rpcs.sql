-- ============================================================================
-- SE EMP — 07. RPCs do painel
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- É o contrato entre o banco e o front: o painel chama estas funções e nada
-- mais. Todo cálculo mora aqui — o navegador só formata.
--
-- Regras transversais:
--   • Divisão por zero devolve NULL, nunca 0. No painel isso vira "—".
--     Um "R$ 0,00" pareceria dado real; o traço deixa claro que não há base.
--   • Retargeting e Engajamento saem do custo de captação por padrão
--     (são campanhas de aquecimento, mirando quem já é lead/agendado).
--     p_incluir_rmkt = true traz de volta, para análise.
--   • p_origem filtra por 'Forms Nativo' | 'Quiz' | 'Typeform' | 'VSL' | …
--     null = todas.
--
-- ⚠️ COBERTURA: agendamentos e vendas só existem de forma confiável a partir
--    de jul/2026 na era CRM, e de 2025-08 a 06/2026 na era Bitrix. Ver 05.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- fn_kpis — uma linha com tudo que os cards e o funil precisam
--
-- O funil da arte, de cima para baixo:
--   INVESTIMENTO → IMPRESSÕES → CLIQUES → LEADS → MQL → AGENDAMENTOS
--                → CALLS → VENDAS
-- Taxas à esquerda, custos à direita.
-- ----------------------------------------------------------------------------
drop function if exists mkt_se.fn_kpis(date, date, text, boolean);

create or replace function mkt_se.fn_kpis(
  p_ini           date,
  p_fim           date,
  p_origem        text    default null,
  p_incluir_rmkt  boolean default false
)
returns table (
  dias            integer,
  investimento    numeric,
  impressoes      bigint,
  cliques         bigint,
  leads           bigint,
  mql             bigint,
  agendamentos    bigint,
  calls           bigint,
  no_shows        bigint,
  vendas          bigint,
  faturamento     numeric,
  -- taxas (%)
  ctr             numeric,
  pct_leads       numeric,
  pct_mql         numeric,
  pct_agend       numeric,
  pct_no_show     numeric,
  pct_conversao   numeric,
  -- custos (R$)
  cpm             numeric,
  cpc             numeric,
  cpl             numeric,
  cpmql           numeric,
  cpa             numeric,
  ccall           numeric,
  cac             numeric,
  roas            numeric
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
  select
    count(*)                        as leads,
    count(*) filter (where mql)     as mql
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and (p_incluir_rmkt or not retargeting)
),
agen as (
  select
    count(*)                                          as agendamentos,
    count(*) filter (where situacao = 'realizado')    as calls,
    count(*) filter (where situacao = 'no_show')      as no_shows
  from mkt_se.vw_agendamentos
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
),
vend as (
  select
    count(*)                    as vendas,
    coalesce(sum(valor), 0)     as faturamento
  from mkt_se.vw_vendas
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
)
select
  (p_fim - p_ini + 1)::integer,
  round(a.investimento::numeric, 2),
  a.impressoes,
  a.cliques,
  l.leads,
  l.mql,
  g.agendamentos,
  g.calls,
  g.no_shows,
  v.vendas,
  round(v.faturamento::numeric, 2),

  -- ⚠️ nullif no denominador: sem base, o resultado é NULL (vira "—" no painel)
  round(100.0 * a.cliques      / nullif(a.impressoes, 0),   2),
  round(100.0 * l.leads        / nullif(a.cliques, 0),      2),
  round(100.0 * l.mql          / nullif(l.leads, 0),        2),
  round(100.0 * g.agendamentos / nullif(l.mql, 0),          2),
  round(100.0 * g.no_shows     / nullif(g.agendamentos, 0), 2),
  round(100.0 * v.vendas       / nullif(g.calls, 0),        2),

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


-- ----------------------------------------------------------------------------
-- fn_serie_diaria — uma linha por dia do período, para os gráficos
--
-- Usa generate_series para NÃO pular dia sem dado: um dia sem investimento
-- precisa aparecer como zero no gráfico, senão a barra some e o eixo mente
-- sobre a continuidade do período.
-- ----------------------------------------------------------------------------
drop function if exists mkt_se.fn_serie_diaria(date, date, text, boolean);

create or replace function mkt_se.fn_serie_diaria(
  p_ini           date,
  p_fim           date,
  p_origem        text    default null,
  p_incluir_rmkt  boolean default false
)
returns table (
  data          date,
  investimento  numeric,
  impressoes    bigint,
  cliques       bigint,
  leads         bigint,
  mql           bigint,
  agendamentos  bigint,
  calls         bigint,
  vendas        bigint,
  faturamento   numeric
)
language sql
stable
as $$
select
  d.dia,
  round(coalesce(a.gasto, 0)::numeric, 2),
  coalesce(a.impressoes, 0),
  coalesce(a.cliques, 0),
  coalesce(l.leads, 0),
  coalesce(l.mql, 0),
  coalesce(g.agendamentos, 0),
  coalesce(g.calls, 0),
  coalesce(v.vendas, 0),
  round(coalesce(v.faturamento, 0)::numeric, 2)
from generate_series(p_ini, p_fim, interval '1 day') as d(dia)

left join (
  select data,
         sum(gasto) as gasto,
         sum(impressoes) as impressoes,
         sum(cliques) as cliques
  from mkt_se.vw_ads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and (p_incluir_rmkt or (not retargeting and origem <> 'Engajamento'))
  group by data
) a on a.data = d.dia::date

left join (
  select data,
         count(*) as leads,
         count(*) filter (where mql) as mql
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and (p_incluir_rmkt or not retargeting)
  group by data
) l on l.data = d.dia::date

left join (
  select data,
         count(*) as agendamentos,
         count(*) filter (where situacao = 'realizado') as calls
  from mkt_se.vw_agendamentos
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
  group by data
) g on g.data = d.dia::date

left join (
  select data,
         count(*) as vendas,
         sum(valor) as faturamento
  from mkt_se.vw_vendas
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
  group by data
) v on v.data = d.dia::date

order by d.dia;
$$;


-- ----------------------------------------------------------------------------
-- fn_origem — desempenho por fonte (Forms Nativo, Quiz, Typeform, VSL…)
--
-- É o bloco que substitui as ~16 medidas duplicadas do Power BI
-- (Leads Forms Nativo, CPL InLead, Investimento Google…). Aqui origem é
-- dimensão, não medida: uma linha por fonte, sempre.
-- ----------------------------------------------------------------------------
drop function if exists mkt_se.fn_origem(date, date, boolean);

create or replace function mkt_se.fn_origem(
  p_ini           date,
  p_fim           date,
  p_incluir_rmkt  boolean default false
)
returns table (
  origem        text,
  investimento  numeric,
  leads         bigint,
  mql           bigint,
  agendamentos  bigint,
  calls         bigint,
  vendas        bigint,
  faturamento   numeric,
  cpl           numeric,
  cpmql         numeric,
  cpa           numeric,
  cac           numeric,
  pct_mql       numeric,
  pct_agend     numeric
)
language sql
stable
as $$
with base as (
  select origem from mkt_se.vw_ads
    where data between p_ini and p_fim
  union
  select origem from mkt_se.vw_leads
    where data between p_ini and p_fim
),
a as (
  select origem, sum(gasto) as investimento
  from mkt_se.vw_ads
  where data between p_ini and p_fim
    and (p_incluir_rmkt or (not retargeting and origem <> 'Engajamento'))
  group by origem
),
l as (
  select origem, count(*) as leads, count(*) filter (where mql) as mql
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_incluir_rmkt or not retargeting)
  group by origem
),
g as (
  select origem,
         count(*) as agendamentos,
         count(*) filter (where situacao = 'realizado') as calls
  from mkt_se.vw_agendamentos
  where data between p_ini and p_fim
  group by origem
),
v as (
  select origem, count(*) as vendas, sum(valor) as faturamento
  from mkt_se.vw_vendas
  where data between p_ini and p_fim
  group by origem
)
select
  b.origem,
  round(coalesce(a.investimento, 0)::numeric, 2),
  coalesce(l.leads, 0),
  coalesce(l.mql, 0),
  coalesce(g.agendamentos, 0),
  coalesce(g.calls, 0),
  coalesce(v.vendas, 0),
  round(coalesce(v.faturamento, 0)::numeric, 2),
  round(a.investimento / nullif(l.leads, 0), 2),
  round(a.investimento / nullif(l.mql, 0), 2),
  round(a.investimento / nullif(g.agendamentos, 0), 2),
  round(a.investimento / nullif(v.vendas, 0), 2),
  round(100.0 * l.mql / nullif(l.leads, 0), 2),
  round(100.0 * g.agendamentos / nullif(l.mql, 0), 2)
from base b
left join a using (origem)
left join l using (origem)
left join g using (origem)
left join v using (origem)
order by coalesce(a.investimento, 0) desc;
$$;


-- ----------------------------------------------------------------------------
-- Permissões: só o porteiro (service_role) chama. Ninguém mais.
-- ----------------------------------------------------------------------------
revoke all on function mkt_se.fn_kpis(date, date, text, boolean)         from public, anon, authenticated;
revoke all on function mkt_se.fn_serie_diaria(date, date, text, boolean) from public, anon, authenticated;
revoke all on function mkt_se.fn_origem(date, date, boolean)             from public, anon, authenticated;

grant execute on function mkt_se.fn_kpis(date, date, text, boolean)         to service_role;
grant execute on function mkt_se.fn_serie_diaria(date, date, text, boolean) to service_role;
grant execute on function mkt_se.fn_origem(date, date, boolean)             to service_role;


-- ============================================================================
-- CONFERÊNCIA
-- ============================================================================
--   select * from mkt_se.fn_kpis('2026-07-01', '2026-08-12');
--   select * from mkt_se.fn_serie_diaria('2026-07-14', '2026-08-12');
--   select * from mkt_se.fn_origem('2026-07-01', '2026-08-12');
-- ============================================================================
