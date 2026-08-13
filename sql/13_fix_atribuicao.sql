-- ============================================================================
-- SE EMP — 13. Corrige a atribuição por campanha/conjunto/anúncio + índices
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- O PROBLEMA
--   A tabela de ads e a de leads escrevem o MESMO nome de campanha de formas
--   diferentes:
--       ads   : GNB_SE_CAPTACAO_F_FORMS_ABO_NATIVO_SEMELHANTES_TESTE_ADS_CARROSSEL
--       leads : GNB SE CAPTACAO F FORMS ABO NATIVO SEMELHANTES TESTE ADS CARROSSEL
--   (underscore virou espaço em algum ponto da integração do formulário)
--
--   Campanhas com hífen (`ls-SE-...`) casam; as com underscore não casam
--   nenhuma. Em agosto isso deixou 208 leads órfãos, e campanhas com milhares
--   de reais apareciam com 0 leads e CPL vazio na tabela de tráfego.
--
--   ⚠️ Isso afeta SÓ a tabela de tráfego (que cruza os dois lados). Os KPIs e o
--   funil sempre estiveram certos: lá cada fonte é contada isoladamente.
--
-- ⚠️ Os índices saíram deste arquivo para o 14: criar índice no schema
--    `bitrix` exige permissão que talvez não exista, e como o SQL Editor roda
--    tudo numa transação só, um erro lá derrubava também a correção do nome.
--
-- A CORREÇÃO
--   Comparar por uma chave normalizada — minúsculas, e espaço/underscore/hífen
--   todos reduzidos a um separador só. O nome exibido continua sendo o da
--   tabela de ads, que é o canônico do Meta.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Normalizador de chave
-- ----------------------------------------------------------------------------
create or replace function mkt_se.norm_chave(p text)
returns text
language sql
immutable
as $$
  select nullif(regexp_replace(lower(trim(coalesce(p, ''))), '[\s_-]+', '-', 'g'), '');
$$;


-- ----------------------------------------------------------------------------
-- 2. fn_trafego com chave normalizada
--
--    Cada fonte devolve (nivel, k) onde k = norm_chave(...), mais o nome cru.
--    O nome exibido sai do lado de ads quando existe — é o canônico; só cai
--    para o nome do lead quando a campanha não tem investimento no período.
-- ----------------------------------------------------------------------------
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
with ads_base as (
  select
    campanha, conjunto, anuncio, gasto, impressoes, cliques,
    video_3s, video_25, video_50
  from mkt_se.vw_ads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and (p_incluir_rmkt or (not retargeting and origem <> 'Engajamento'))
),
ads as (
  select 'campanha' as nivel, mkt_se.norm_chave(campanha) k, max(campanha) nome,
         sum(gasto) g, sum(impressoes) imp, sum(cliques) cli,
         sum(video_3s) v3, sum(video_25) v25, sum(video_50) v50
  from ads_base group by 1, 2
  union all
  select 'conjunto', mkt_se.norm_chave(conjunto), max(conjunto),
         sum(gasto), sum(impressoes), sum(cliques),
         sum(video_3s), sum(video_25), sum(video_50)
  from ads_base group by 1, 2
  union all
  select 'anuncio', mkt_se.norm_chave(anuncio), max(anuncio),
         sum(gasto), sum(impressoes), sum(cliques),
         sum(video_3s), sum(video_25), sum(video_50)
  from ads_base group by 1, 2
),
leads_base as (
  select campanha, conjunto, anuncio, renda_piso
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
),
lds as (
  select 'campanha' as nivel, mkt_se.norm_chave(campanha) k, max(campanha) nome,
         count(*) n, count(*) filter (where renda_piso >= 50) q50
  from leads_base group by 1, 2
  union all
  select 'conjunto', mkt_se.norm_chave(conjunto), max(conjunto),
         count(*), count(*) filter (where renda_piso >= 50)
  from leads_base group by 1, 2
  union all
  select 'anuncio', mkt_se.norm_chave(anuncio), max(anuncio),
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
  select 'campanha' as nivel, mkt_se.norm_chave(campanha) k, count(*) n
  from agd_base group by 1, 2
  union all
  select 'conjunto', mkt_se.norm_chave(conjunto), count(*) from agd_base group by 1, 2
  union all
  select 'anuncio',  mkt_se.norm_chave(anuncio),  count(*) from agd_base group by 1, 2
),
vds_base as (
  select campanha, conjunto, anuncio, valor
  from mkt_se.vw_vendas
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
),
vds as (
  select 'campanha' as nivel, mkt_se.norm_chave(campanha) k, count(*) n, sum(valor) v
  from vds_base group by 1, 2
  union all
  select 'conjunto', mkt_se.norm_chave(conjunto), count(*), sum(valor) from vds_base group by 1, 2
  union all
  select 'anuncio',  mkt_se.norm_chave(anuncio),  count(*), sum(valor) from vds_base group by 1, 2
),
chaves as (
  select nivel, k from ads
  union select nivel, k from lds
  union select nivel, k from agd
  union select nivel, k from vds
)
select
  c.nivel,
  coalesce(a.nome, l.nome, '(sem atribuição)') as chave,
  round(coalesce(a.g, 0)::numeric, 2),
  coalesce(a.imp, 0)::bigint,
  coalesce(a.cli, 0)::bigint,
  coalesce(l.n, 0)::bigint,
  coalesce(g.n, 0)::bigint,
  coalesce(v.n, 0)::bigint,
  round(coalesce(v.v, 0)::numeric, 2),
  round(a.g / nullif(l.n, 0), 2),
  round(a.g / nullif(v.n, 0), 2),
  round(100.0 * l.q50 / nullif(l.n, 0), 1),
  round(100.0 * a.v3  / nullif(a.imp, 0), 1),
  round(100.0 * a.v25 / nullif(a.v3, 0), 1),
  round(100.0 * a.v50 / nullif(a.imp, 0), 1)
from chaves c
left join ads a using (nivel, k)
left join lds l using (nivel, k)
left join agd g using (nivel, k)
left join vds v using (nivel, k)
order by c.nivel, coalesce(a.g, 0) desc;
$$;

revoke all on function mkt_se.fn_trafego(date, date, text, boolean) from public, anon, authenticated;
grant execute on function mkt_se.fn_trafego(date, date, text, boolean) to service_role;

notify pgrst, 'reload schema';


-- ============================================================================
-- CONFERÊNCIA — nenhuma campanha com investimento pode ficar com 0 leads
-- ============================================================================
--   select chave, investimento, leads, cpl, agendamentos, vendas
--   from mkt_se.fn_trafego('2026-08-01','2026-08-31')
--   where nivel = 'campanha' order by investimento desc limit 10;
--
-- Órfãos: quanto ficou sem casar dos dois lados
--   select count(*) filter (where investimento > 0 and leads = 0) as gastou_sem_lead,
--          count(*) filter (where investimento = 0 and leads > 0) as lead_sem_gasto
--   from mkt_se.fn_trafego('2026-08-01','2026-08-31') where nivel = 'campanha';
-- ============================================================================
