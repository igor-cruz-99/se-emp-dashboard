-- ============================================================================
-- SE EMP — 19. CPL por formulário (investimento rateado)
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- ⚠️ ISTO É ESTIMATIVA, NÃO MEDIÇÃO.
--   O Meta não devolve `id_formulario` junto com o gasto — o investimento é
--   por campanha/conjunto/anúncio, e o formulário só aparece do lado do lead.
--   Então o gasto de cada campanha é dividido entre os formulários dos leads
--   DAQUELA campanha, proporcional ao volume de cada um.
--
--   Isso assume que, dentro de uma campanha, todo lead custou o mesmo. Se um
--   formulário converte muito melhor que outro na mesma campanha, o rateio
--   subestima o CPL do ruim e superestima o do bom. Para comparar formulários
--   de campanhas DIFERENTES o número é confiável; dentro da mesma campanha,
--   é aproximação.
--
--   O `leads` continua sendo contagem real — só o investimento é rateado.
--
-- ⚠️ SOBRA: campanha que gastou e não gerou lead nenhum não tem como ser
--   rateada. Esse valor vai para uma linha própria, '(não rateado)', com 0
--   leads e CPL vazio — assim a soma do investimento continua batendo com os
--   KPIs em vez de sumir em silêncio (foi o bug do arquivo 15).
-- ============================================================================

drop function if exists mkt_se.fn_formularios(date, date, text);

create or replace function mkt_se.fn_formularios(
  p_ini    date,
  p_fim    date,
  p_origem text default null
)
returns table (
  formulario   text,
  leads        bigint,
  pct          numeric,
  investimento numeric,
  cpl          numeric
)
language sql
stable
as $$
with ads as (
  select mkt_se.norm_chave(campanha) k, sum(gasto) g
  from mkt_se.vw_ads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and not retargeting
    and origem <> 'Engajamento'
  group by 1
),
lds as (
  select
    mkt_se.norm_chave(campanha) k,
    coalesce(nullif(trim(id_formulario), ''), '(sem formulário)') as formulario,
    count(*) as n
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and not retargeting
  group by 1, 2
),
-- total de leads por campanha, para saber a fatia de cada formulário
tot as (
  select k, sum(n) as n_total from lds group by k
),
rateio as (
  select
    l.formulario,
    sum(l.n)                                     as leads,
    sum(coalesce(a.g, 0) * l.n / t.n_total)      as investimento
  from lds l
  join tot t on t.k is not distinct from l.k
  left join ads a on a.k is not distinct from l.k
  group by l.formulario
),
-- gasto de campanha que não gerou lead: não há como ratear
sobra as (
  select coalesce(sum(a.g), 0) as g
  from ads a
  where not exists (select 1 from tot t where t.k is not distinct from a.k)
),
juntado as (
  select formulario, leads, investimento from rateio
  union all
  select '(não rateado)', 0::bigint, s.g from sobra s where s.g > 0
)
select
  formulario,
  leads,
  round(100.0 * leads / nullif(sum(leads) over (), 0), 1),
  round(investimento::numeric, 2),
  -- ⚠️ nullif no NUMERADOR também: formulário com leads e zero investimento
  -- (entrada orgânica) daria "R$ 0,00", que lê como lead de graça. Sem base
  -- de cálculo o certo é NULL, que a tela mostra como "—".
  round(nullif(investimento, 0) / nullif(leads, 0), 2)
from juntado
order by leads desc, investimento desc;
$$;

revoke all on function mkt_se.fn_formularios(date, date, text) from public, anon, authenticated;
grant execute on function mkt_se.fn_formularios(date, date, text) to service_role;


-- ----------------------------------------------------------------------------
-- Ponte no public (a assinatura mudou — tem de recriar junto)
-- ----------------------------------------------------------------------------
drop function if exists public.se_formularios(date, date, text);

create or replace function public.se_formularios(
  p_ini date, p_fim date, p_origem text default null
)
returns table (
  formulario text, leads bigint, pct numeric, investimento numeric, cpl numeric
)
language sql
stable
security definer
set search_path = mkt_se, public
as $$ select * from mkt_se.fn_formularios(p_ini, p_fim, p_origem); $$;

revoke all on function public.se_formularios(date, date, text) from public, anon, authenticated;
grant execute on function public.se_formularios(date, date, text) to service_role;

notify pgrst, 'reload schema';


-- ============================================================================
-- CONFERÊNCIA — leads E investimento têm de bater com os KPIs
-- ============================================================================
--   select sum(leads) as leads, round(sum(investimento),2) as investimento
--   from mkt_se.fn_formularios('2026-08-01','2026-08-31');
--
--   select leads, investimento from mkt_se.fn_kpis('2026-08-01','2026-08-31');
-- ============================================================================
