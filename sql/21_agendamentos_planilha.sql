-- ============================================================================
-- SE EMP — 21. Agendamentos de 2026 passam a vir da planilha
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- POR QUÊ
--   A Bitrix entregava 58 agendamentos em junho e ZERO em julho — ela foi
--   sendo abandonada e parou de ser alimentada. A planilha carregada em
--   `mrk_backup_se.mkt_agendamento_2026` cobre jan–ago/2026 completo e bate
--   com o que o BI mostrava (junho 247, julho 254).
--
-- AS TRÊS ERAS DE AGENDAMENTO
--   até 31/12/2025  → Bitrix        (histórico anterior a 2026)
--   01/01–31/07/26  → planilha      (a fonte completa do ano)
--   01/08/26 em diante → CRM novo   (a operação atual, com desfecho real)
--
--   ⚠️ O corte da planilha para o CRM é 01/08, diferente do `corte_crm()`
--   (01/07) que continua valendo para VENDAS. São eventos diferentes com
--   histórias diferentes: as vendas do CRM já existem desde julho, os
--   agendamentos dele só a partir de agosto.
--
-- ⚠️ A PLANILHA NÃO TEM DESFECHO
--   `situacao` é "Agendada" em 4.689 das 4.691 linhas. Então o realizado/
--   no-show de jan–jul é buscado na Bitrix pelo email; onde não houver,
--   a situação fica 'sem_registro'.
--   Consequência: o comparecimento desses meses é calculado sobre uma base
--   MENOR que o total de agendamentos. É o mais honesto possível — inventar
--   'pendente' inflaria o denominador e derrubaria a taxa artificialmente.
--
-- ⚠️ NÍVEL DE SESSÃO, não de pessoa: uma linha por sessão marcada. O mesmo
--   lead que remarcou aparece duas vezes. Isso permite derivar os dois
--   números que o BI mostrava — "Agendamentos" (sessões) e "Agendas"
--   (pessoas únicas, via count distinct email). O contrário não seria
--   possível: de um total deduplicado não se recupera o bruto.
-- ============================================================================

-- Onde a planilha entrega a vez ao CRM novo.
create or replace function mkt_se.corte_agenda()
returns date
language sql
immutable
as $$
  select date '2026-08-01';
$$;


create or replace view mkt_se.vw_agendamentos as

-- ── era Bitrix: só o que é anterior a 2026 ──────────────────────────────────
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
  lb.id                                 as lead_id,
  lb.campanha,
  lb.conjunto,
  lb.anuncio,
  lower(trim(d.email))                  as email
from bitrix.timeline_agendamentos ta
left join bitrix.dados_raw d on d.id = ta.deal_id
left join lateral (
  select l.id, l.campanha, l.conjunto, l.anuncio
  from public.se_facebook_leads l
  where d.email is not null
    and lower(trim(l.email)) = lower(trim(d.email))
  order by l.data desc
  limit 1
) lb on true
where ta.funil = 'Sessão Estratégica'
  and ta.tipo  = '1o Agendamento'
  and ta.data_evento < date '2026-01-01'

union all

-- ── era planilha: 01/01/2026 até 31/07/2026 ─────────────────────────────────
select
  'planilha'                            as fonte,
  p.uid::text                           as ref,
  to_date(p.data_sessao, 'DD/MM/YYYY')  as data,
  coalesce(bx.situacao, 'sem_registro') as situacao,
  mkt_se.origem_campanha(p.origem)      as origem,
  null::uuid                            as closer_id,
  lb.id                                 as lead_id,
  lb.campanha,
  lb.conjunto,
  lb.anuncio,
  lower(trim(p.email))                  as email
from mrk_backup_se.mkt_agendamento_2026 p

-- anúncio de origem, pelo email do lead
left join lateral (
  select l.id, l.campanha, l.conjunto, l.anuncio
  from public.se_facebook_leads l
  where p.email is not null
    and lower(trim(l.email)) = lower(trim(p.email))
  order by l.data desc
  limit 1
) lb on true

-- desfecho, buscado na Bitrix pelo mesmo email
left join lateral (
  select case
           when ta2.status = 'Realizado'                     then 'realizado'
           when ta2.status in ('No-Show', 'No-Show Técnico') then 'no_show'
         end as situacao
  from bitrix.dados_raw d2
  join bitrix.timeline_agendamentos ta2 on ta2.deal_id = d2.id
  where p.email is not null
    and lower(trim(d2.email)) = lower(trim(p.email))
    and ta2.tipo = '1o Agendamento'
    and ta2.status in ('Realizado', 'No-Show', 'No-Show Técnico')
  order by ta2.data_evento desc
  limit 1
) bx on true

where p.funil ilike '%estrat%'
  -- guarda a conversão: a coluna é texto e uma data malformada derrubaria a view
  and p.data_sessao ~ '^\d{1,2}/\d{1,2}/\d{4}$'
  and to_date(p.data_sessao, 'DD/MM/YYYY') >= date '2026-01-01'
  and to_date(p.data_sessao, 'DD/MM/YYYY') <  mkt_se.corte_agenda()

union all

-- ── era CRM novo: 01/08/2026 em diante ──────────────────────────────────────
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
where m.primeira >= mkt_se.corte_agenda();


-- ============================================================================
-- CONFERÊNCIA
-- ============================================================================
-- Mês a mês, com a fonte visível. Nenhum mês pode ter duas fontes.
-- Esperado: jun 247 · jul 254 (era 58 e 0).
--
--   select to_char(data,'YYYY-MM') as mes, fonte,
--          count(*) as sessoes,
--          count(distinct email) as pessoas,
--          count(*) filter (where situacao='realizado')    as realizados,
--          count(*) filter (where situacao='no_show')      as no_shows,
--          count(*) filter (where situacao='sem_registro') as sem_desfecho
--   from mkt_se.vw_agendamentos
--   where data >= '2026-01-01'
--   group by 1,2 order by 1;
-- ============================================================================
