-- ============================================================================
-- SE EMP — 18. Leads por formulário
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- O cartão "Origem dos leads" passa a dividir por `id_formulario` em vez da
-- origem deduzida do nome da campanha. São coisas diferentes:
--   origem        → o tipo de captação (Forms Nativo, Quiz, Typeform, VSL)
--   id_formulario → QUAL formulário específico ('21MAI-J', '9 MAR', '22 DEZ')
--
-- O segundo é mais granular: em agosto, 98% dos leads são "Forms Nativo", mas
-- se repartem em três formulários bem distintos — 188, 174 e 42 leads. A
-- origem sozinha escondia essa divisão.
--
-- ⚠️ O cartão "Investimento por origem" continua pela origem da campanha: a
--    tabela de ads não tem id_formulario, então não há como repartir gasto
--    por formulário. Os dois cartões passam a responder perguntas diferentes.
-- ============================================================================

drop function if exists mkt_se.fn_formularios(date, date, text);

create or replace function mkt_se.fn_formularios(
  p_ini    date,
  p_fim    date,
  p_origem text default null
)
returns table (
  formulario text,
  leads      bigint,
  pct        numeric
)
language sql
stable
as $$
with base as (
  select coalesce(nullif(trim(id_formulario), ''), '(sem formulário)') as formulario
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and not retargeting
),
agrupado as (
  select formulario, count(*) as leads
  from base
  group by formulario
)
select
  formulario,
  leads,
  round(100.0 * leads / nullif(sum(leads) over (), 0), 1)
from agrupado
order by leads desc;
$$;

revoke all on function mkt_se.fn_formularios(date, date, text) from public, anon, authenticated;
grant execute on function mkt_se.fn_formularios(date, date, text) to service_role;


-- ----------------------------------------------------------------------------
-- Ponte no public
-- ----------------------------------------------------------------------------
create or replace function public.se_formularios(
  p_ini date, p_fim date, p_origem text default null
)
returns table (formulario text, leads bigint, pct numeric)
language sql
stable
security definer
set search_path = mkt_se, public
as $$ select * from mkt_se.fn_formularios(p_ini, p_fim, p_origem); $$;

revoke all on function public.se_formularios(date, date, text) from public, anon, authenticated;
grant execute on function public.se_formularios(date, date, text) to service_role;

notify pgrst, 'reload schema';


-- ============================================================================
-- CONFERÊNCIA — a soma tem de bater com os leads dos KPIs
-- ============================================================================
--   select sum(leads) from mkt_se.fn_formularios('2026-08-01','2026-08-31');
--   select leads      from mkt_se.fn_kpis('2026-08-01','2026-08-31');
-- ============================================================================
