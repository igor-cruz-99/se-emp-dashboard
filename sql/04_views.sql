-- ============================================================================
-- SE EMP — 04. Views e normalizadores
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- Tudo que o painel lê passa por aqui. As RPCs (05) consultam estas views,
-- nunca as tabelas cruas — assim uma mudança de regra é um único lugar.
--
-- Fontes:
--   mkt_se.ads              espelho do Anchor, já filtrado (SE, 2026+)
--   public.se_facebook_leads nativo do Business Data
--   mkt_se.crm_leads        espelho do CRM: agendado_at, sale_at, sale_amount
--   mkt_se.crm_meetings     espelho do CRM: outcome (realizada/no_show)
--
-- ⚠️ COBERTURA: a integração com o CRM foi ligada em jun/2026 e só ficou
--    completa em jul/2026 (99,9% dos leads do SE viram card). Antes disso,
--    agendamento e venda NÃO EXISTEM na origem — não são zero de performance,
--    são zero de dado. O painel precisa deixar isso explícito.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Normalizadores
-- ----------------------------------------------------------------------------

-- Origem do lead, deduzida do nome da campanha.
-- A mesma regra vale para ads e para leads — assim os dois lados sempre
-- classificam igual, e não dependemos do preenchimento de tag_origem.
--
-- ⚠️ A ordem dos CASE importa: 'TYPEFORM' contém 'FORM'. Se 'forms' viesse
--    antes, toda campanha de Typeform seria classificada como Forms Nativo.
create or replace function mkt_se.origem_campanha(p text)
returns text
language sql
immutable
as $$
  select case
    when p is null or p = ''             then 'Não identificado'
    when p ~* 'typeform'                 then 'Typeform'
    when p ~* 'typebot'                  then 'Typebot'
    -- InLead é o produto de quiz — mesma origem, nome comercial diferente
    when p ~* '(quiz|inlead)'            then 'Quiz'
    when p ~* 'forms'                    then 'Forms Nativo'
    when p ~* '(^|[^a-z])type([^a-z]|$)' then 'Typeform'
    when p ~* '(^|[^a-z])vsl([^a-z]|$)'  then 'VSL'
    when p ~* '(lp|landing)'             then 'Landing Page'
    when p ~* 'engajamento'              then 'Engajamento'
    else 'Outros'
  end;
$$;

-- Retargeting: as campanhas escrevem tanto 'RMKT' quanto 'RETARGETING'.
-- Fica no espelho, mas sai das métricas de captação (CPL, CPMQL, CAC).
create or replace function mkt_se.eh_retargeting(p text)
returns boolean
language sql
immutable
as $$
  select coalesce(p ~* '(rmkt|retargeting)', false);
$$;

-- Piso da faixa de renda, em milhares.
-- A renda é texto e vem escrita de várias formas:
--   'Entre R$30 a R$50 mil' · 'Entre R$ 20 a R$ 29 mil' · 'Acima de R$100 mil'
-- Pegar o PRIMEIRO número da string resolve todas as variações de espaçamento
-- de uma vez — comparar o texto exato criaria categoria fantasma para cada
-- grafia nova que o formulário inventar.
create or replace function mkt_se.piso_renda(p text)
returns integer
language sql
immutable
as $$
  select nullif((regexp_match(coalesce(p, ''), '(\d+)'))[1], '')::integer;
$$;


-- ----------------------------------------------------------------------------
-- 2. vw_ads — tráfego com origem, retargeting e métricas de vídeo
-- ----------------------------------------------------------------------------
create or replace view mkt_se.vw_ads as
select
  a.data,
  a.account_name,
  a.campanha,
  a.conjunto,
  a.anuncio,
  a.ad_id,
  mkt_se.origem_campanha(a.campanha) as origem,
  mkt_se.eh_retargeting(a.campanha)  as retargeting,
  a.gasto,
  a.alcance,
  a.impressoes,
  a.cliques,
  a.link_cliques,
  a.landing_page_views,
  a.video_plays,
  a.video_3s,
  a."video_25%" as video_25,
  a."video_50%" as video_50,
  a."video_75%" as video_75,
  a."video_100%" as video_100,
  -- Hook: % das impressões que assistiram 3s (o gancho pegou?)
  case when a.impressoes > 0
       then round(100.0 * a.video_3s / a.impressoes, 1) end as hook_pct,
  -- Hold: % de quem viu 3s e chegou a 25% (segurou depois do gancho?)
  case when a.video_3s > 0
       then round(100.0 * a."video_25%" / a.video_3s, 1) end as hold_pct,
  -- Retenção: % das impressões que chegaram à metade do vídeo
  case when a.impressoes > 0
       then round(100.0 * a."video_50%" / a.impressoes, 1) end as retencao_pct
from mkt_se.ads a;


-- ----------------------------------------------------------------------------
-- 3. vw_leads — leads com faixa de renda, MQL e origem
--    MQL = renda >= 20 mil (regra do negócio).
--    Atenção: com as faixas atuais isso marca ~98,7% dos leads. O sinal útil
--    para o gestor é o MIX de faixas, exposto em faixa_renda.
-- ----------------------------------------------------------------------------
create or replace view mkt_se.vw_leads as
select
  l.id,
  l.data,
  l.hora,
  lower(trim(l.email))                 as email,
  l.nome,
  l.telefone,
  l.campanha,
  l.conjunto,
  l.anuncio,
  l.tag_origem,
  l.id_formulario,
  l.funil,
  l.renda,
  mkt_se.piso_renda(l.renda)           as renda_piso,
  case
    when mkt_se.piso_renda(l.renda) is null then 'Não informado'
    when mkt_se.piso_renda(l.renda) >= 100  then '100k+'
    when mkt_se.piso_renda(l.renda) >= 50   then '50–100k'
    when mkt_se.piso_renda(l.renda) >= 30   then '30–50k'
    when mkt_se.piso_renda(l.renda) >= 20   then '20–29k'
    else '<20k'
  end                                  as faixa_renda,
  coalesce(mkt_se.piso_renda(l.renda) >= 20, false) as mql,
  -- A origem sai da campanha do anúncio, mesma regra usada em vw_ads.
  -- Quando o lead não tem campanha (entrada orgânica/manual), cai em tag_origem.
  -- O tag_origem também passa pelo normalizador: ele vem com sufixo do produto
  -- ('InLead SE-EMP', 'Forms Nativo - SE EMP', 'Landing Page Institucional - SE')
  -- e sem normalizar cada sufixo viraria uma categoria própria no gráfico.
  case
    when l.campanha is not null and l.campanha <> ''
      then mkt_se.origem_campanha(l.campanha)
    else mkt_se.origem_campanha(l.tag_origem)
  end                                  as origem,
  mkt_se.eh_retargeting(l.campanha)    as retargeting
from public.se_facebook_leads l
where l.email is not null
  and l.email <> '';


-- ----------------------------------------------------------------------------
-- 4. vw_funil — o lead do SE ligado ao que aconteceu no CRM
--
--    A ponte é o EMAIL: se_facebook_leads → crm_leads → crm_meetings.
--    Só lead do SE entra (é o inner join que faz o recorte — nada de filtrar
--    por nome de evento, que muda toda hora).
--
--    Agendamento e venda vêm de crm_leads (histórico desde jun/2026).
--    Comparecimento vem de crm_meetings (só desde 03/08/2026).
-- ----------------------------------------------------------------------------
create or replace view mkt_se.vw_funil as
select
  l.email,
  l.data                as data_lead,
  l.origem,
  l.campanha,
  l.conjunto,
  l.anuncio,
  l.faixa_renda,
  l.mql,
  l.retargeting,
  c.id                  as crm_lead_id,
  c.agendado_at,
  c.qualified_at,
  c.sale_at,
  c.sale_amount,
  c.sale_product,
  c.closer_id,
  c.sdr_id,
  m.realizadas,
  m.no_shows,
  m.primeira_call
from mkt_se.vw_leads l
join mkt_se.crm_leads c
  on lower(trim(c.email)) = l.email
left join lateral (
  select
    count(*) filter (where mm.outcome = 'realizada') as realizadas,
    count(*) filter (where mm.outcome = 'no_show')   as no_shows,
    min(mm.scheduled_at) filter (where mm.outcome = 'realizada') as primeira_call
  from mkt_se.crm_meetings mm
  where mm.lead_id = c.id
) m on true;


-- ============================================================================
-- CONFERÊNCIA
-- ============================================================================
-- Origem classificou tudo? ('Outros' alto = regra faltando)
--   select origem, count(*), round(sum(gasto)::numeric,2) as gasto
--   from mkt_se.vw_ads group by 1 order by 3 desc;
--
-- Mesma coisa do lado dos leads:
--   select origem, count(*) from mkt_se.vw_leads group by 1 order by 2 desc;
--
-- Mix de renda (o sinal que o MQL sozinho não dá):
--   select faixa_renda, count(*), count(*) filter (where mql) as sao_mql
--   from mkt_se.vw_leads group by 1 order by 2 desc;
--
-- O funil, mês a mês — deve ficar coerente só de jul/2026 em diante:
--   select to_char(data_lead,'YYYY-MM') as mes,
--          count(*) as leads_no_crm,
--          count(*) filter (where agendado_at is not null) as agendaram,
--          count(*) filter (where sale_at is not null)     as venderam,
--          round(sum(sale_amount)::numeric,2)              as faturamento
--   from mkt_se.vw_funil group by 1 order by 1;
-- ============================================================================
