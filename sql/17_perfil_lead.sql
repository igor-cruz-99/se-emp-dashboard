-- ============================================================================
-- SE EMP — 17. Perfil do lead: dia da semana e horário
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- Devolve os dois recortes numa chamada só, distinguidos por `tipo`:
--   'dia_semana'  → ordem 0..6  (0 = domingo, 6 = sábado)
--   'hora'        → ordem 0..23
--   'sem_hora'    → uma linha com quantos leads ficaram de fora do gráfico
--
-- ⚠️ EXCLUSÃO DO `00:00:00` EXATO
--   1.091 leads de 2026 têm hora exatamente meia-noite, todos entre 01/01 e
--   28/06 e nenhum depois — é valor padrão de uma integração antiga, não lead
--   de madrugada. Sem excluir, a hora 0 apareceria com ~1.276 contra ~350 das
--   vizinhas: um pico inventado, quatro vezes o normal.
--   Eles continuam contando no gráfico de DIA DA SEMANA, onde só a data
--   importa e ela está correta.
--
-- ⚠️ ARREDONDAMENTO
--   Minuto < 30 desce, >= 30 sobe. Como 23:30 subiria para "24:00", que não
--   existe, o resultado passa por `% 24` e volta para 00:00 — senão a query
--   criaria uma faixa fantasma fora do eixo.
--
-- ⚠️ generate_series nos dois: dia ou hora sem lead precisa aparecer como
--   zero. Sumir do eixo faria o gráfico mentir sobre a continuidade.
-- ============================================================================

drop function if exists mkt_se.fn_perfil_lead(date, date, text);

create or replace function mkt_se.fn_perfil_lead(
  p_ini    date,
  p_fim    date,
  p_origem text default null
)
returns table (
  tipo  text,
  ordem integer,
  leads bigint
)
language sql
stable
as $$
with base as (
  select data, hora
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and not retargeting
),
-- dia da semana: 0 = domingo … 6 = sábado
dias as (
  select extract(dow from data)::integer as ordem, count(*) as n
  from base
  group by 1
),
-- horário: descarta o 00:00:00 exato e arredonda o resto para a hora cheia
horas as (
  select
    (
      (extract(hour from hora)::integer
        + case when extract(minute from hora) >= 30 then 1 else 0 end)
      % 24
    ) as ordem,
    count(*) as n
  from base
  where hora is not null
    and hora <> time '00:00:00'
  group by 1
)
select 'dia_semana', d.ordem, coalesce(x.n, 0)
from generate_series(0, 6) as d(ordem)
left join dias x on x.ordem = d.ordem

union all

select 'hora', h.ordem, coalesce(y.n, 0)
from generate_series(0, 23) as h(ordem)
left join horas y on y.ordem = h.ordem

union all

select 'sem_hora', 0, count(*)
from base
where hora is null or hora = time '00:00:00'

order by 1, 2;
$$;

revoke all on function mkt_se.fn_perfil_lead(date, date, text) from public, anon, authenticated;
grant execute on function mkt_se.fn_perfil_lead(date, date, text) to service_role;


-- ----------------------------------------------------------------------------
-- Ponte no public
-- ----------------------------------------------------------------------------
create or replace function public.se_perfil_lead(
  p_ini date, p_fim date, p_origem text default null
)
returns table (tipo text, ordem integer, leads bigint)
language sql
stable
security definer
set search_path = mkt_se, public
as $$ select * from mkt_se.fn_perfil_lead(p_ini, p_fim, p_origem); $$;

revoke all on function public.se_perfil_lead(date, date, text) from public, anon, authenticated;
grant execute on function public.se_perfil_lead(date, date, text) to service_role;

notify pgrst, 'reload schema';


-- ============================================================================
-- CONFERÊNCIA — a soma dos dias tem de bater com os leads dos KPIs
-- ============================================================================
--   select sum(leads) from mkt_se.fn_perfil_lead('2026-08-01','2026-08-31')
--   where tipo = 'dia_semana';
--   select leads from mkt_se.fn_kpis('2026-08-01','2026-08-31');
--
-- E o gráfico de hora + os descartados também:
--   select tipo, sum(leads) from mkt_se.fn_perfil_lead('2026-08-01','2026-08-31')
--   group by 1;
-- ============================================================================
