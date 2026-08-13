-- ============================================================================
-- SE EMP — 09. Corrige a data do agendamento na era CRM
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- O QUE ESTAVA ERRADO
--   A era CRM datava o agendamento por `crm_leads.agendado_at`. Esse campo foi
--   preenchido em MASSA na migração: das 70 sessões do SE, praticamente todas
--   ficaram carimbadas em agosto, inclusive as marcadas antes. A `crm_meetings`
--   mostra o mesmo padrão — 380 reuniões criadas de uma vez em 01/08/2026.
--
--   A era Bitrix, por outro lado, usa `data_evento`: a data em que a sessão
--   ACONTECE. As duas metades do funil estavam medindo coisas diferentes, e a
--   emenda das séries ficaria com um degrau artificial em agosto.
--
-- A CORREÇÃO
--   Na era CRM o agendamento passa a ser datado pelo `scheduled_at` da PRIMEIRA
--   reunião do lead — mesmo significado do `data_evento` da Bitrix.
--   Conferido antes: as 70 sessões do SE têm reunião registrada, então nenhuma
--   se perde na troca.
--
--   O desfecho continua vindo do conjunto das reuniões do lead (não só da
--   primeira): quem remarcou e compareceu conta como realizado.
--
-- ⚠️ Efeito colateral esperado: agendamento marcado para data futura passa a
--    aparecer no futuro (a crm_meetings tem sessões até 31/08). Isso é
--    desejável — mostra o pipeline à frente —, mas o painel não deve somar
--    esses dias ao "realizado" do período corrente.
-- ============================================================================

create or replace view mkt_se.vw_agendamentos as

-- ── era Bitrix (até 30/06/2026) ─────────────────────────────────────────────
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
  null::bigint                          as lead_id
from bitrix.timeline_agendamentos ta
where ta.funil = 'Sessão Estratégica'
  and ta.tipo  = '1o Agendamento'
  and ta.data_evento < mkt_se.corte_crm()

union all

-- ── era CRM novo (de 01/07/2026) ────────────────────────────────────────────
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
  c.lead_id
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


-- ============================================================================
-- CONFERÊNCIA
-- ============================================================================
--   select to_char(data,'YYYY-MM') as mes, fonte, count(*) as agend,
--          count(*) filter (where situacao='realizado') as calls,
--          count(*) filter (where situacao='pendente')  as pendentes
--   from mkt_se.vw_agendamentos group by 1,2 order by 1;
--
-- Esperado: agosto deixa de ter tudo concentrado e passa a distribuir pelas
-- datas reais das sessões, inclusive as marcadas para depois de hoje.
-- ============================================================================
