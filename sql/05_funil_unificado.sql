-- ============================================================================
-- SE EMP — 05. Funil unificado (Bitrix + CRM novo)
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- O PROBLEMA QUE ESTE ARQUIVO RESOLVE
--   A operação trocou de CRM no meio de 2026. Nenhuma das duas fontes cobre
--   o ano inteiro:
--       Bitrix    23/08/2025 → 26/06/2026   (bitrix.* , já no Business Data)
--       CRM novo  jun/2026   → hoje         (mkt_se.crm_* , espelho do QV)
--
--   ⚠️ DATA DE CORTE: 2026-07-01.
--      Bitrix vale ATÉ 30/06. CRM novo vale DE 01/07 em diante.
--      As duas rodaram juntas em junho — sem o corte, todo agendamento de
--      junho entraria duas vezes e o CAC sairia pela metade.
--
-- COMO CADA ERA IDENTIFICA O QUE É SESSÃO ESTRATÉGICA
--   Bitrix   : coluna `funil = 'Sessão Estratégica'` (explícita)
--   CRM novo : três critérios em OU, que na conferência bateram entre si
--              (2.380 / 2.382 / 2.395 — praticamente o mesmo conjunto):
--                a) funnel_id = sessao_estrategica
--                b) meta_ads_data->>'funil' = 'Sessão Estratégica'
--                c) external_lead_id aponta para um id da se_facebook_leads
--
-- VALIDAÇÃO CRUZADA
--   Comparecimento na Bitrix : 377 / (377+118+13) = 74,2%
--   Comparecimento no CRM    : 168 / (168+61)     = 73,4%
--   Duas eras, dois sistemas, mesmo número. É o que dá confiança na união.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 0. Auxiliares
-- ----------------------------------------------------------------------------

-- Converte texto para bigint SÓ quando é numérico, senão devolve null.
-- Existe porque `external_lead_id` é polimórfico: para lead do SE ele é o id
-- da se_facebook_leads ('12335'), mas para outras fontes é outra coisa
-- ('HP0705523330', uma transação Hotmart).
-- ⚠️ Um `where external_lead_id ~ '^[0-9]+$' and external_lead_id::bigint = x`
--    NÃO é seguro: o Postgres não garante avaliar o regex antes do cast e
--    estoura com `invalid input syntax for type bigint`. O CASE de dentro
--    desta função garante a ordem.
create or replace function mkt_se.so_numero(p text)
returns bigint
language sql
immutable
as $$
  select case when p ~ '^[0-9]+$' then p::bigint end;
$$;

-- Data em que a Bitrix para e o CRM novo assume.
create or replace function mkt_se.corte_crm()
returns date
language sql
immutable
as $$
  select date '2026-07-01';
$$;


-- ----------------------------------------------------------------------------
-- 1. vw_crm_se — os leads do CRM novo que são Sessão Estratégica
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
  c.meta_ads_data->>'id_formulario'        as id_formulario
from mkt_se.crm_leads c
where c.funnel_id = '3063703b-6d38-4095-bb92-7b35ca53dc10'::uuid
   or c.meta_ads_data->>'funil' = 'Sessão Estratégica'
   or exists (
        select 1 from public.se_facebook_leads l
        where l.id = mkt_se.so_numero(c.external_lead_id)
      );


-- ----------------------------------------------------------------------------
-- 2. vw_agendamentos — uma linha por 1º agendamento, nas duas eras
--
--    "1º agendamento" já entrega a deduplicação por pessoa que o negócio pede:
--    o mesmo lead pode remarcar várias vezes, mas só tem um primeiro.
-- ----------------------------------------------------------------------------
create or replace view mkt_se.vw_agendamentos as

-- ── era Bitrix (até 30/06/2026) ─────────────────────────────────────────────
select
  'bitrix'                              as fonte,
  ta.deal_id::text                      as ref,
  ta.data_evento::date                  as data,
  case
    when ta.status = 'Realizado'                        then 'realizado'
    when ta.status in ('No-Show', 'No-Show Técnico')    then 'no_show'
    when ta.status in ('Agendado', 'Aguardando Agendamento', 'Reagendado')
                                                        then 'pendente'
    else 'cancelado'
  end                                   as situacao,
  -- tags_de_origem é TEXT com cara de array ('{"InLead SE-EMP"}'), não text[].
  -- O normalizador é regex, então a string inteira serve — sem desempacotar.
  mkt_se.origem_campanha(ta.tags_de_origem) as origem,
  null::uuid                            as closer_id,
  null::bigint                          as lead_id
from bitrix.timeline_agendamentos ta
where ta.funil = 'Sessão Estratégica'
  and ta.tipo  = '1o Agendamento'
  and ta.data_evento < mkt_se.corte_crm()

union all

-- ── era CRM novo (de 01/07/2026) ────────────────────────────────────────────
-- O agendamento vem de crm_leads.agendado_at (um por lead = o primeiro).
-- A situação vem da crm_meetings, que só existe a partir de 03/08/2026 —
-- antes disso o agendamento aparece como 'pendente' por falta de registro,
-- não por estar realmente pendente.
select
  'crm'                                 as fonte,
  c.id::text                            as ref,
  c.agendado_at::date                   as data,
  case
    when m.realizadas > 0 then 'realizado'
    when m.no_shows   > 0 then 'no_show'
    when m.cancelados > 0 then 'cancelado'
    else 'pendente'
  end                                   as situacao,
  mkt_se.origem_campanha(coalesce(l.campanha, c.tag_origem)) as origem,
  c.closer_id,
  c.lead_id
from mkt_se.vw_crm_se c
left join public.se_facebook_leads l on l.id = c.lead_id
left join lateral (
  select
    count(*) filter (where mm.outcome = 'realizada')                as realizadas,
    count(*) filter (where mm.outcome = 'no_show')                  as no_shows,
    count(*) filter (where mm.outcome in ('cancelada', 'remarcada')) as cancelados
  from mkt_se.crm_meetings mm
  where mm.lead_id = c.id
) m on true
where c.agendado_at is not null
  and c.agendado_at >= mkt_se.corte_crm();


-- ----------------------------------------------------------------------------
-- 3. vw_vendas — uma linha por venda, nas duas eras
--
--    ⚠️ `bitrix.dados_raw.cash_collected` vem como '22000|BRL' (texto com a
--    moeda colada). Usamos `opportunity_value`, que já é numérico. Se um dia
--    o cash for necessário, extrair com split_part(cash_collected,'|',1).
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
  d.sdr_responsavel                     as sdr
from bitrix.dados_raw d
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
  c.sdr_id::text                        as sdr
from mkt_se.vw_crm_se c
left join public.se_facebook_leads l on l.id = c.lead_id
where c.sale_at is not null
  and c.sale_at >= mkt_se.corte_crm();


-- ============================================================================
-- CONFERÊNCIA — rodar e olhar a virada de junho para julho
-- ============================================================================
-- Agendamentos mês a mês, com a fonte visível (não pode ter mês com as duas):
--   select to_char(data,'YYYY-MM') as mes, fonte,
--          count(*) as agendamentos,
--          count(*) filter (where situacao = 'realizado') as realizados,
--          count(*) filter (where situacao = 'no_show')   as no_shows
--   from mkt_se.vw_agendamentos group by 1,2 order by 1,2;
--
-- Vendas mês a mês:
--   select to_char(data,'YYYY-MM') as mes, fonte,
--          count(*) as vendas, round(sum(valor)::numeric,2) as faturamento
--   from mkt_se.vw_vendas group by 1,2 order by 1,2;
--
-- Origem classificou? ('Outros'/'Não identificado' alto = regra faltando)
--   select origem, count(*) from mkt_se.vw_agendamentos group by 1 order by 2 desc;
-- ============================================================================
