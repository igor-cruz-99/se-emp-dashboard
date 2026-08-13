-- ============================================================================
-- SE EMP — 25. fn_trafego passa a conhecer a hierarquia
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- POR QUÊ
--   Hoje os três níveis são agregados isoladamente: a função sabe que existe o
--   conjunto "00-auto-advantage", mas não de qual campanha ele é. Sem isso o
--   painel não consegue filtrar um nível pelo outro.
--
--   Agora cada linha carrega os pais:
--     campanha → (sem pai)
--     conjunto → campanha_pai
--     anúncio  → campanha_pai + conjunto_pai
--
-- ⚠️ MUDANÇA DE NÚMERO ESPERADA no nível conjunto/anúncio.
--   Nome de conjunto se repete entre campanhas ("00-auto-f-advantage" aparece
--   em várias). Antes eles eram somados como se fossem um só; agora cada par
--   (campanha, conjunto) é uma linha própria — que é o correto, e é o que o
--   painel do WEP mostra. O TOTAL de cada nível continua idêntico.
--
-- ⚠️ A junção usa uma CHAVE COMPOSTA em texto em vez de várias colunas.
--   `join ... using (nivel, k, pai_c, pai_j)` não casaria as linhas de nível
--   campanha, onde os pais são NULL — em SQL, null = null não é verdadeiro.
--   Foi exatamente o bug que escondeu uma venda inteira no arquivo 15.
-- ============================================================================

drop function if exists mkt_se.fn_trafego(date, date, text, boolean);

create or replace function mkt_se.fn_trafego(
  p_ini          date,
  p_fim          date,
  p_origem       text    default null,
  p_incluir_rmkt boolean default false
)
returns table (
  nivel        text,
  chave        text,
  campanha_pai text,
  conjunto_pai text,
  investimento numeric,
  impressoes   bigint,
  cliques      bigint,
  leads        bigint,
  agendamentos bigint,
  vendas       bigint,
  faturamento  numeric,
  cpl          numeric,
  cac          numeric,
  qualif_50k   numeric,
  hook         numeric,
  hold         numeric,
  body         numeric
)
language sql
stable
as $$
with
-- identificador único da linha: nível + pais + chave, tudo normalizado
ads_base as (
  select campanha, conjunto, anuncio, gasto, impressoes, cliques,
         video_3s, video_25, video_50
  from mkt_se.vw_ads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and (p_incluir_rmkt or (not retargeting and origem <> 'Engajamento'))
),
ads as (
  select 'campanha' as nivel,
         'campanha||' || coalesce(mkt_se.norm_chave(campanha), '~') as id,
         max(campanha) nome, null::text pai_c, null::text pai_j,
         sum(gasto) g, sum(impressoes) imp, sum(cliques) cli,
         sum(video_3s) v3, sum(video_25) v25, sum(video_50) v50
  from ads_base group by 1, 2
  union all
  select 'conjunto',
         'conjunto|' || coalesce(mkt_se.norm_chave(campanha), '~')
                     || '|' || coalesce(mkt_se.norm_chave(conjunto), '~'),
         max(conjunto), max(campanha), null,
         sum(gasto), sum(impressoes), sum(cliques),
         sum(video_3s), sum(video_25), sum(video_50)
  from ads_base group by 1, 2
  union all
  select 'anuncio',
         'anuncio|' || coalesce(mkt_se.norm_chave(campanha), '~')
                    || '|' || coalesce(mkt_se.norm_chave(conjunto), '~')
                    || '|' || coalesce(mkt_se.norm_chave(anuncio), '~'),
         max(anuncio), max(campanha), max(conjunto),
         sum(gasto), sum(impressoes), sum(cliques),
         sum(video_3s), sum(video_25), sum(video_50)
  from ads_base group by 1, 2
),
leads_base as (
  select campanha, conjunto, anuncio, renda_piso
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and (p_incluir_rmkt or not retargeting)
),
lds as (
  select 'campanha' as nivel,
         'campanha||' || coalesce(mkt_se.norm_chave(campanha), '~') as id,
         max(campanha) nome, null::text pai_c, null::text pai_j,
         count(*) n, count(*) filter (where renda_piso >= 50) q50
  from leads_base group by 1, 2
  union all
  select 'conjunto',
         'conjunto|' || coalesce(mkt_se.norm_chave(campanha), '~')
                     || '|' || coalesce(mkt_se.norm_chave(conjunto), '~'),
         max(conjunto), max(campanha), null,
         count(*), count(*) filter (where renda_piso >= 50)
  from leads_base group by 1, 2
  union all
  select 'anuncio',
         'anuncio|' || coalesce(mkt_se.norm_chave(campanha), '~')
                    || '|' || coalesce(mkt_se.norm_chave(conjunto), '~')
                    || '|' || coalesce(mkt_se.norm_chave(anuncio), '~'),
         max(anuncio), max(campanha), max(conjunto),
         count(*), count(*) filter (where renda_piso >= 50)
  from leads_base group by 1, 2
),
agd_base as (
  select campanha, conjunto, anuncio
  from mkt_se.vw_agendamentos
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
),
agd as (
  select 'campanha||' || coalesce(mkt_se.norm_chave(campanha), '~') as id, count(*) n
  from agd_base group by 1
  union all
  select 'conjunto|' || coalesce(mkt_se.norm_chave(campanha), '~')
                     || '|' || coalesce(mkt_se.norm_chave(conjunto), '~'), count(*)
  from agd_base group by 1
  union all
  select 'anuncio|' || coalesce(mkt_se.norm_chave(campanha), '~')
                    || '|' || coalesce(mkt_se.norm_chave(conjunto), '~')
                    || '|' || coalesce(mkt_se.norm_chave(anuncio), '~'), count(*)
  from agd_base group by 1
),
vds_base as (
  select campanha, conjunto, anuncio, valor
  from mkt_se.vw_vendas
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
),
vds as (
  select 'campanha||' || coalesce(mkt_se.norm_chave(campanha), '~') as id,
         count(*) n, sum(valor) v
  from vds_base group by 1
  union all
  select 'conjunto|' || coalesce(mkt_se.norm_chave(campanha), '~')
                     || '|' || coalesce(mkt_se.norm_chave(conjunto), '~'),
         count(*), sum(valor)
  from vds_base group by 1
  union all
  select 'anuncio|' || coalesce(mkt_se.norm_chave(campanha), '~')
                    || '|' || coalesce(mkt_se.norm_chave(conjunto), '~')
                    || '|' || coalesce(mkt_se.norm_chave(anuncio), '~'),
         count(*), sum(valor)
  from vds_base group by 1
),
chaves as (
  select id, max(nivel) nivel, max(nome) nome, max(pai_c) pai_c, max(pai_j) pai_j
  from (
    select id, nivel, nome, pai_c, pai_j from ads
    union all
    select id, nivel, nome, pai_c, pai_j from lds
  ) t
  group by id
)
select
  c.nivel,
  coalesce(nullif(trim(c.nome), ''), '(sem atribuição)'),
  nullif(trim(c.pai_c), ''),
  nullif(trim(c.pai_j), ''),
  round(coalesce(a.g, 0)::numeric, 2),
  coalesce(a.imp, 0)::bigint,
  coalesce(a.cli, 0)::bigint,
  coalesce(l.n, 0)::bigint,
  coalesce(g.n, 0)::bigint,
  coalesce(v.n, 0)::bigint,
  round(coalesce(v.v, 0)::numeric, 2),
  round(nullif(a.g, 0) / nullif(l.n, 0), 2),
  round(nullif(a.g, 0) / nullif(v.n, 0), 2),
  round(100.0 * l.q50 / nullif(l.n, 0), 1),
  round(100.0 * a.v3  / nullif(a.imp, 0), 1),
  round(100.0 * a.v25 / nullif(a.v3, 0), 1),
  round(100.0 * a.v50 / nullif(a.imp, 0), 1)
from chaves c
left join ads a using (id)
left join lds l using (id)
left join agd g using (id)
left join vds v using (id)
order by c.nivel, coalesce(a.g, 0) desc;
$$;

revoke all on function mkt_se.fn_trafego(date, date, text, boolean) from public, anon, authenticated;
grant execute on function mkt_se.fn_trafego(date, date, text, boolean) to service_role;


-- ----------------------------------------------------------------------------
-- Ponte no public — assinatura mudou, recriar junto
-- ----------------------------------------------------------------------------
drop function if exists public.se_trafego(date, date, text, boolean);

create or replace function public.se_trafego(
  p_ini date, p_fim date, p_origem text default null, p_incluir_rmkt boolean default false
)
returns table (
  nivel text, chave text, campanha_pai text, conjunto_pai text,
  investimento numeric, impressoes bigint, cliques bigint,
  leads bigint, agendamentos bigint, vendas bigint, faturamento numeric,
  cpl numeric, cac numeric, qualif_50k numeric,
  hook numeric, hold numeric, body numeric
)
language sql
stable
security definer
set search_path = mkt_se, public
as $$ select * from mkt_se.fn_trafego(p_ini, p_fim, p_origem, p_incluir_rmkt); $$;

revoke all on function public.se_trafego(date, date, text, boolean) from public, anon, authenticated;
grant execute on function public.se_trafego(date, date, text, boolean) to service_role;

notify pgrst, 'reload schema';


-- ============================================================================
-- CONFERÊNCIA — os totais por nível continuam iguais aos KPIs
-- ============================================================================
--   select nivel, count(*) linhas, round(sum(investimento),2) inv,
--          sum(leads) leads, sum(agendamentos) agend, sum(vendas) vendas
--   from mkt_se.fn_trafego('2026-08-01','2026-08-31') group by 1;
--
--   select investimento, leads, agendamentos, vendas
--   from mkt_se.fn_kpis('2026-08-01','2026-08-31');
-- ============================================================================
