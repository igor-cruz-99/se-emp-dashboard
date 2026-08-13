-- ============================================================================
-- SE EMP — 16. Ciclo de vendas
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- Uma linha por VENDA, mostrando o caminho do lead no tempo:
--   criação do lead → agendamento da sessão → venda
-- e os três intervalos entre essas datas.
--
-- REGRAS DEFINIDAS COM O IGOR
--   • Só aparece quem COMPROU.
--   • O período da página recorta pela DATA DA VENDA.
--   • "Data Criação" é quando o lead entrou na se_facebook_leads
--     (`created_at`, não `data`: divergem em 566 dos 13.152 registros).
--
-- ⚠️ Os tempos são calculados, não guardados. No Postgres é subtração de datas
--    direto — o Power BI mantinha três colunas manuais para isso, que
--    desatualizavam sozinhas.
--
-- Este arquivo também acrescenta colunas que faltavam nas views:
--   vw_crm_se       + nome
--   vw_agendamentos + email   (para casar venda com agendamento)
--   vw_vendas       + nome
-- `create or replace view` só aceita coluna nova NO FIM — por isso elas entram
-- ao final da lista, e não perto das colunas parecidas.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. vw_crm_se + nome
-- ----------------------------------------------------------------------------
create or replace view mkt_se.vw_crm_se as
select
  c.id,
  mkt_se.so_numero(c.external_lead_id)     as lead_id,
  lower(trim(c.email))                     as email,
  c.created_at,
  c.qualified_at,
  c.agendado_at,
  c.sale_at,
  c.sale_amount,
  c.sale_product,
  c.closer_id,
  c.sdr_id,
  c.meta_ads_data->>'tag_origem'           as tag_origem,
  c.meta_ads_data->>'id_formulario'        as id_formulario,
  c.nome
from mkt_se.crm_leads c
where c.funnel_id = '3063703b-6d38-4095-bb92-7b35ca53dc10'::uuid
   or c.meta_ads_data->>'funil' = 'Sessão Estratégica'
   or exists (
        select 1 from public.se_facebook_leads l
        where l.id = mkt_se.so_numero(c.external_lead_id)
      );


-- ----------------------------------------------------------------------------
-- 2. vw_agendamentos + email
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
  lb.anuncio,
  lower(trim(d.email))                  as email
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
  'crm',
  c.id::text,
  m.primeira::date,
  case
    when m.realizadas > 0 then 'realizado'
    when m.no_shows   > 0 then 'no_show'
    when m.cancelados > 0 then 'cancelado'
    else 'pendente'
  end,
  mkt_se.origem_campanha(coalesce(l.campanha, c.tag_origem)),
  c.closer_id,
  c.lead_id,
  l.campanha,
  l.conjunto,
  l.anuncio,
  c.email
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
-- 3. vw_vendas + nome
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
  lb.anuncio,
  d.title                               as nome
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
  'crm',
  c.id::text,
  c.sale_at::date,
  c.sale_amount,
  c.email,
  mkt_se.origem_campanha(coalesce(l.campanha, c.tag_origem)),
  c.closer_id::text,
  c.sdr_id::text,
  l.campanha,
  l.conjunto,
  l.anuncio,
  c.nome
from mkt_se.vw_crm_se c
left join public.se_facebook_leads l on l.id = c.lead_id
where c.sale_at is not null
  and c.sale_at >= mkt_se.corte_crm();


-- ----------------------------------------------------------------------------
-- 4. fn_ciclo_vendas
--
--    O agendamento buscado é o PRIMEIRO do lead (por email), venha de qualquer
--    período: o ciclo é do lead, não da janela de filtro. Se recortássemos o
--    agendamento pelo período também, uma venda de agosto cujo agendamento foi
--    em julho apareceria sem data de agendamento e com o tempo em branco.
-- ----------------------------------------------------------------------------
drop function if exists mkt_se.fn_ciclo_vendas(date, date, text);

create or replace function mkt_se.fn_ciclo_vendas(
  p_ini    date,
  p_fim    date,
  p_origem text default null
)
returns table (
  nome              text,
  anuncio           text,
  data_criacao      date,
  data_agendamento  date,
  data_venda        date,
  dias_cria_agen    integer,
  dias_agen_venda   integer,
  dias_cria_venda   integer
)
language sql
stable
as $$
select
  coalesce(nullif(trim(l.nome), ''), nullif(trim(v.nome), ''), '(sem nome)') as nome,
  coalesce(nullif(trim(l.anuncio), ''), nullif(trim(v.anuncio), ''), '(sem atribuição)') as anuncio,
  l.created_at::date                       as data_criacao,
  a.data                                   as data_agendamento,
  v.data                                   as data_venda,
  (a.data - l.created_at::date)::integer   as dias_cria_agen,
  (v.data - a.data)::integer               as dias_agen_venda,
  (v.data - l.created_at::date)::integer   as dias_cria_venda
from mkt_se.vw_vendas v

-- lead que originou a venda (o mais antigo com aquele email — é o primeiro
-- contato, que é onde o ciclo começa)
left join lateral (
  select l2.nome, l2.anuncio, l2.created_at
  from public.se_facebook_leads l2
  where v.email is not null
    and lower(trim(l2.email)) = v.email
  order by l2.created_at
  limit 1
) l on true

-- primeiro agendamento daquele lead, de qualquer período
left join lateral (
  select a2.data
  from mkt_se.vw_agendamentos a2
  where a2.email is not null
    and a2.email = v.email
  order by a2.data
  limit 1
) a on true

where v.data between p_ini and p_fim
  and (p_origem is null or v.origem = p_origem)
order by v.data desc, nome;
$$;

revoke all on function mkt_se.fn_ciclo_vendas(date, date, text) from public, anon, authenticated;
grant execute on function mkt_se.fn_ciclo_vendas(date, date, text) to service_role;


-- ----------------------------------------------------------------------------
-- 5. Ponte no public
-- ----------------------------------------------------------------------------
create or replace function public.se_ciclo_vendas(
  p_ini date, p_fim date, p_origem text default null
)
returns table (
  nome text, anuncio text, data_criacao date, data_agendamento date,
  data_venda date, dias_cria_agen integer, dias_agen_venda integer,
  dias_cria_venda integer
)
language sql
stable
security definer
set search_path = mkt_se, public
as $$ select * from mkt_se.fn_ciclo_vendas(p_ini, p_fim, p_origem); $$;

revoke all on function public.se_ciclo_vendas(date, date, text) from public, anon, authenticated;
grant execute on function public.se_ciclo_vendas(date, date, text) to service_role;

notify pgrst, 'reload schema';


-- ============================================================================
-- CONFERÊNCIA — a contagem tem de bater com as vendas dos KPIs
-- ============================================================================
--   select count(*) from mkt_se.fn_ciclo_vendas('2026-08-01','2026-08-31');
--   select vendas   from mkt_se.fn_kpis('2026-08-01','2026-08-31');
--
--   select * from mkt_se.fn_ciclo_vendas('2026-01-01','2026-06-30') limit 20;
-- ============================================================================
