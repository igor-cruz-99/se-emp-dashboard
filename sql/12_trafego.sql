-- ============================================================================
-- SE EMP — 12. Atribuição por anúncio + RPC da tabela de tráfego
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- Duas partes:
--   1. vw_agendamentos e vw_vendas passam a carregar campanha/conjunto/anúncio.
--      Sem isso não há como dizer quantos agendamentos cada anúncio gerou.
--   2. fn_trafego devolve os três níveis (campanha, conjunto, anúncio) numa
--      chamada só.
--
-- COMO A ATRIBUIÇÃO FUNCIONA EM CADA ERA
--   CRM novo : crm_leads.external_lead_id → se_facebook_leads.id  (chave exata)
--   Bitrix   : timeline_agendamentos.deal_id → dados_raw.id → email
--              → se_facebook_leads.email                        (chave fraca)
--
--   ⚠️ O caminho da Bitrix depende de o lead ter usado o mesmo email nos dois
--   sistemas. Onde não casar, campanha/anúncio ficam nulos e a linha cai em
--   "(sem atribuição)" na tabela — o total continua certo, só não se sabe de
--   qual anúncio veio.
--
-- ⚠️ `create or replace view` só aceita colunas NOVAS NO FIM. Por isso as três
--    entram ao final da lista, e não perto de `origem`, onde seriam mais
--    legíveis. Reordenar exigiria dropar a view e recriar as dependentes.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Agendamentos com anúncio
-- ----------------------------------------------------------------------------
create or replace view mkt_se.vw_agendamentos as

select
  'bitrix'                              as fonte,
  ta.deal_id::text                      as ref,
  ta.data_evento::date                  as data,
  case
    when ta.status = 'Realizado'                     then 'realizado'
    when ta.status in ('No-Show', 'No-Show Técnico') then 'no_show'
    when ta.status in ('Agendado', 'Aguardando Agendamento', 'Reagendado')
                                                     then 'pendente'
    else 'cancelado'
  end                                   as situacao,
  mkt_se.origem_campanha(ta.tags_de_origem) as origem,
  null::uuid                            as closer_id,
  null::bigint                          as lead_id,
  lb.campanha,
  lb.conjunto,
  lb.anuncio
from bitrix.timeline_agendamentos ta
left join bitrix.dados_raw d on d.id = ta.deal_id
left join lateral (
  select l.campanha, l.conjunto, l.anuncio
  from public.se_facebook_leads l
  where d.email is not null
    and lower(trim(l.email)) = lower(trim(d.email))
  order by l.data desc
  limit 1
) lb on true
where ta.funil = 'Sessão Estratégica'
  and ta.tipo  = '1o Agendamento'
  and ta.data_evento < mkt_se.corte_crm()

union all

select
  'crm'                                 as fonte,
  c.id::text                            as ref,
  m.primeira::date                      as data,
  case
    when m.realizadas > 0 then 'realizado'
    when m.no_shows   > 0 then 'no_show'
    when m.cancelados > 0 then 'cancelado'
    else 'pendente'
  end                                   as situacao,
  mkt_se.origem_campanha(coalesce(l.campanha, c.tag_origem)) as origem,
  c.closer_id,
  c.lead_id,
  l.campanha,
  l.conjunto,
  l.anuncio
from mkt_se.vw_crm_se c
left join public.se_facebook_leads l on l.id = c.lead_id
join lateral (
  select
    min(mm.scheduled_at)                                             as primeira,
    count(*) filter (where mm.outcome = 'realizada')                 as realizadas,
    count(*) filter (where mm.outcome = 'no_show')                   as no_shows,
    count(*) filter (where mm.outcome in ('cancelada', 'remarcada')) as cancelados
  from mkt_se.crm_meetings mm
  where mm.lead_id = c.id
  having count(*) > 0
) m on true
where m.primeira >= mkt_se.corte_crm();


-- ----------------------------------------------------------------------------
-- 2. Vendas com anúncio
-- ----------------------------------------------------------------------------
create or replace view mkt_se.vw_vendas as

select
  'bitrix'                              as fonte,
  d.id::text                            as ref,
  d.data_de_venda::date                 as data,
  d.opportunity_value                   as valor,
  lower(trim(d.email))                  as email,
  mkt_se.origem_campanha(coalesce(nullif(d.utm_campaign, ''), d.tags_de_origem)) as origem,
  d.closer_responsavel                  as closer,
  d.sdr_responsavel                     as sdr,
  lb.campanha,
  lb.conjunto,
  lb.anuncio
from bitrix.dados_raw d
left join lateral (
  select l.campanha, l.conjunto, l.anuncio
  from public.se_facebook_leads l
  where d.email is not null
    and lower(trim(l.email)) = lower(trim(d.email))
  order by l.data desc
  limit 1
) lb on true
where d.funil = 'Sessão Estratégica'
  and d.data_de_venda is not null
  and d.data_de_venda::date < mkt_se.corte_crm()

union all

select
  'crm'                                 as fonte,
  c.id::text                            as ref,
  c.sale_at::date                       as data,
  c.sale_amount                         as valor,
  c.email,
  mkt_se.origem_campanha(coalesce(l.campanha, c.tag_origem)) as origem,
  c.closer_id::text                     as closer,
  c.sdr_id::text                        as sdr,
  l.campanha,
  l.conjunto,
  l.anuncio
from mkt_se.vw_crm_se c
left join public.se_facebook_leads l on l.id = c.lead_id
where c.sale_at is not null
  and c.sale_at >= mkt_se.corte_crm();


-- ----------------------------------------------------------------------------
-- 3. fn_trafego — os três níveis numa chamada
--
--    O truque do UNION ALL por nível evita escrever a mesma agregação três
--    vezes: cada fonte devolve (nivel, chave, métricas) e o join final é por
--    (nivel, chave). Adicionar uma métrica é mexer em um lugar por fonte.
--
--    `qualif_50k` = % dos leads com renda >= 50 mil. NÃO é o %MQL: com o corte
--    em 20 mil, o MQL fica em ~99% e não separa anúncio bom de ruim. O corte
--    em 50 mil é o que mostra qual criativo atrai renda mais alta.
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
with ads as (
  select 'campanha' as nivel, campanha as chave,
         sum(gasto) g, sum(impressoes) imp, sum(cliques) cli,
         sum(video_3s) v3, sum(video_25) v25, sum(video_50) v50
  from mkt_se.vw_ads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and (p_incluir_rmkt or (not retargeting and origem <> 'Engajamento'))
  group by campanha
  union all
  select 'conjunto', conjunto,
         sum(gasto), sum(impressoes), sum(cliques),
         sum(video_3s), sum(video_25), sum(video_50)
  from mkt_se.vw_ads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and (p_incluir_rmkt or (not retargeting and origem <> 'Engajamento'))
  group by conjunto
  union all
  select 'anuncio', anuncio,
         sum(gasto), sum(impressoes), sum(cliques),
         sum(video_3s), sum(video_25), sum(video_50)
  from mkt_se.vw_ads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and (p_incluir_rmkt or (not retargeting and origem <> 'Engajamento'))
  group by anuncio
),
lds as (
  select 'campanha' as nivel, campanha as chave,
         count(*) n, count(*) filter (where renda_piso >= 50) q50
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
  group by campanha
  union all
  select 'conjunto', conjunto, count(*), count(*) filter (where renda_piso >= 50)
  from mkt_se.vw_leads
  where data between p_ini and p_fim and (p_origem is null or origem = p_origem)
  group by conjunto
  union all
  select 'anuncio', anuncio, count(*), count(*) filter (where renda_piso >= 50)
  from mkt_se.vw_leads
  where data between p_ini and p_fim and (p_origem is null or origem = p_origem)
  group by anuncio
),
agd as (
  select 'campanha' as nivel, campanha as chave, count(*) n
  from mkt_se.vw_agendamentos
  where data between p_ini and p_fim and (p_origem is null or origem = p_origem)
  group by campanha
  union all
  select 'conjunto', conjunto, count(*)
  from mkt_se.vw_agendamentos
  where data between p_ini and p_fim and (p_origem is null or origem = p_origem)
  group by conjunto
  union all
  select 'anuncio', anuncio, count(*)
  from mkt_se.vw_agendamentos
  where data between p_ini and p_fim and (p_origem is null or origem = p_origem)
  group by anuncio
),
vds as (
  select 'campanha' as nivel, campanha as chave, count(*) n, sum(valor) v
  from mkt_se.vw_vendas
  where data between p_ini and p_fim and (p_origem is null or origem = p_origem)
  group by campanha
  union all
  select 'conjunto', conjunto, count(*), sum(valor)
  from mkt_se.vw_vendas
  where data between p_ini and p_fim and (p_origem is null or origem = p_origem)
  group by conjunto
  union all
  select 'anuncio', anuncio, count(*), sum(valor)
  from mkt_se.vw_vendas
  where data between p_ini and p_fim and (p_origem is null or origem = p_origem)
  group by anuncio
),
chaves as (
  select nivel, chave from ads
  union select nivel, chave from lds
  union select nivel, chave from agd
  union select nivel, chave from vds
)
select
  k.nivel,
  coalesce(nullif(trim(k.chave), ''), '(sem atribuição)') as chave,
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
from chaves k
left join ads a using (nivel, chave)
left join lds l using (nivel, chave)
left join agd g using (nivel, chave)
left join vds v using (nivel, chave)
where k.chave is not null
order by k.nivel, coalesce(a.g, 0) desc;
$$;

revoke all on function mkt_se.fn_trafego(date, date, text, boolean) from public, anon, authenticated;
grant execute on function mkt_se.fn_trafego(date, date, text, boolean) to service_role;


-- ----------------------------------------------------------------------------
-- 4. Ponte no public
-- ----------------------------------------------------------------------------
create or replace function public.se_trafego(
  p_ini date, p_fim date, p_origem text default null, p_incluir_rmkt boolean default false
)
returns table (
  nivel text, chave text, investimento numeric, impressoes bigint, cliques bigint,
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
-- CONFERÊNCIA
-- ============================================================================
--   select * from mkt_se.fn_trafego('2026-08-01','2026-08-31') where nivel='campanha';
--
-- O total de investimento por nível tem de bater com o dos KPIs:
--   select nivel, round(sum(investimento),2) from mkt_se.fn_trafego('2026-08-01','2026-08-31')
--   group by 1;
--   select investimento from mkt_se.fn_kpis('2026-08-01','2026-08-31');
-- ============================================================================
