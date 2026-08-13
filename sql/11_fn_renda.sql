-- ============================================================================
-- SE EMP — 11. Distribuição dos leads por faixa de renda
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- Por que existe: o `%MQL` fica cravado em ~99% (quase todo lead passa do corte
-- de 20 mil), então o cartão de MQL não varia e não informa nada. O sinal útil
-- para o gestor está no MIX das faixas — é ele que mostra se o tráfego está
-- atraindo renda mais alta ou mais baixa ao longo do tempo.
--
-- A `ordem` existe porque faixa de renda é dado ORDINAL: o gráfico deve ir de
-- '<20k' até '100k+' na sequência natural, não do maior para o menor volume.
-- 'Não informado' vai para o fim.
-- ============================================================================

drop function if exists mkt_se.fn_renda(date, date, text);

create or replace function mkt_se.fn_renda(
  p_ini    date,
  p_fim    date,
  p_origem text default null
)
returns table (
  faixa text,
  ordem integer,
  leads bigint,
  pct   numeric
)
language sql
stable
as $$
with base as (
  select faixa_renda, renda_piso
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and not retargeting
),
agrupado as (
  select
    faixa_renda                        as faixa,
    coalesce(min(renda_piso), 999)     as ordem,
    count(*)                           as leads
  from base
  group by faixa_renda
)
select
  a.faixa,
  a.ordem::integer,
  a.leads,
  round(100.0 * a.leads / nullif(sum(a.leads) over (), 0), 1)
from agrupado a
order by a.ordem;
$$;

revoke all on function mkt_se.fn_renda(date, date, text) from public, anon, authenticated;
grant execute on function mkt_se.fn_renda(date, date, text) to service_role;


-- ----------------------------------------------------------------------------
-- Ponte no public (o Exposed schemas deste projeto não alcança mkt_se — ver 08)
-- ----------------------------------------------------------------------------
create or replace function public.se_renda(
  p_ini date, p_fim date, p_origem text default null
)
returns table (faixa text, ordem integer, leads bigint, pct numeric)
language sql
stable
security definer
set search_path = mkt_se, public
as $$ select * from mkt_se.fn_renda(p_ini, p_fim, p_origem); $$;

revoke all on function public.se_renda(date, date, text) from public, anon, authenticated;
grant execute on function public.se_renda(date, date, text) to service_role;

notify pgrst, 'reload schema';

-- Teste:
select * from mkt_se.fn_renda('2026-08-01', '2026-08-31');
