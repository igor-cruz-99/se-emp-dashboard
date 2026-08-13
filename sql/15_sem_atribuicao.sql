-- ============================================================================
-- SE EMP — 15. Registros sem campanha param de sumir da tabela de tráfego
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- O BUG
--   `norm_chave(null)` devolve NULL, e `join ... using (nivel, k)` NUNCA casa
--   NULL com NULL (em SQL, null = null é "desconhecido", não verdadeiro).
--   Resultado: lead, agendamento ou venda sem campanha atribuída era
--   descartado da tabela — silenciosamente, sem erro nenhum.
--
--   Em agosto isso escondia:
--       leads          413 nos KPIs  →  405 na tabela
--       agendamentos    76           →   74
--       vendas           4           →    3   (uma venda inteira invisível)
--
--   ⚠️ É a pior classe de bug num painel: o total parece plausível, ninguém
--   desconfia, e a decisão sai com base num número menor que o real. Só
--   apareceu porque conferimos a tabela contra o fn_kpis.
--
-- A CORREÇÃO
--   A chave nula vira o rótulo '(sem atribuição)' ANTES do agrupamento. Aí o
--   registro tem onde cair, o total bate com os KPIs, e o rótulo deixa claro
--   quanto do resultado não se sabe de onde veio — que é uma informação útil
--   por si só.
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
  select campanha, conjunto, anuncio, gasto, impressoes, cliques,
         video_3s, video_25, video_50
  from mkt_se.vw_ads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and (p_incluir_rmkt or (not retargeting and origem <> 'Engajamento'))
),
ads as (
  select 'campanha' as nivel,
         coalesce(mkt_se.norm_chave(campanha), '(sem atribuição)') k,
         max(campanha) nome,
         sum(gasto) g, sum(impressoes) imp, sum(cliques) cli,
         sum(video_3s) v3, sum(video_25) v25, sum(video_50) v50
  from ads_base group by 1, 2
  union all
  select 'conjunto', coalesce(mkt_se.norm_chave(conjunto), '(sem atribuição)'), max(conjunto),
         sum(gasto), sum(impressoes), sum(cliques),
         sum(video_3s), sum(video_25), sum(video_50)
  from ads_base group by 1, 2
  union all
  select 'anuncio', coalesce(mkt_se.norm_chave(anuncio), '(sem atribuição)'), max(anuncio),
         sum(gasto), sum(impressoes), sum(cliques),
         sum(video_3s), sum(video_25), sum(video_50)
  from ads_base group by 1, 2
),
leads_base as (
  select campanha, conjunto, anuncio, renda_piso
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    -- ⚠️ Mesmo filtro de retargeting do fn_kpis. Sem ele a tabela contava um
    -- lead a mais que os KPIs — inconsistência entre dois blocos da mesma tela
    -- é o que faz alguém perder a confiança no painel inteiro.
    and (p_incluir_rmkt or not retargeting)
),
lds as (
  select 'campanha' as nivel,
         coalesce(mkt_se.norm_chave(campanha), '(sem atribuição)') k,
         max(campanha) nome,
         count(*) n, count(*) filter (where renda_piso >= 50) q50
  from leads_base group by 1, 2
  union all
  select 'conjunto', coalesce(mkt_se.norm_chave(conjunto), '(sem atribuição)'), max(conjunto),
         count(*), count(*) filter (where renda_piso >= 50)
  from leads_base group by 1, 2
  union all
  select 'anuncio', coalesce(mkt_se.norm_chave(anuncio), '(sem atribuição)'), max(anuncio),
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
  select 'campanha' as nivel,
         coalesce(mkt_se.norm_chave(campanha), '(sem atribuição)') k, count(*) n
  from agd_base group by 1, 2
  union all
  select 'conjunto', coalesce(mkt_se.norm_chave(conjunto), '(sem atribuição)'), count(*)
  from agd_base group by 1, 2
  union all
  select 'anuncio', coalesce(mkt_se.norm_chave(anuncio), '(sem atribuição)'), count(*)
  from agd_base group by 1, 2
),
vds_base as (
  select campanha, conjunto, anuncio, valor
  from mkt_se.vw_vendas
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
),
vds as (
  select 'campanha' as nivel,
         coalesce(mkt_se.norm_chave(campanha), '(sem atribuição)') k,
         count(*) n, sum(valor) v
  from vds_base group by 1, 2
  union all
  select 'conjunto', coalesce(mkt_se.norm_chave(conjunto), '(sem atribuição)'), count(*), sum(valor)
  from vds_base group by 1, 2
  union all
  select 'anuncio', coalesce(mkt_se.norm_chave(anuncio), '(sem atribuição)'), count(*), sum(valor)
  from vds_base group by 1, 2
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
-- CONFERÊNCIA — os três níveis têm de bater com os KPIs, linha por linha
-- ============================================================================
--   select nivel, round(sum(investimento),2) inv, sum(leads) leads,
--          sum(agendamentos) agend, sum(vendas) vendas
--   from mkt_se.fn_trafego('2026-08-01','2026-08-31') group by 1;
--
--   select investimento, leads, agendamentos, vendas
--   from mkt_se.fn_kpis('2026-08-01','2026-08-31');
--
-- Esperado hoje: 18288.57 · 413 leads · 76 agendamentos · 4 vendas nos quatro.
-- ============================================================================
