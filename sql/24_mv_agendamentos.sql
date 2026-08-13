-- ============================================================================
-- SE EMP — 24. vw_agendamentos vira materializada
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- O PROBLEMA
--   `vw_agendamentos` levava 6,3 s para ser lida. As outras três views do
--   painel levam ~0,4 s. Como TODOS os blocos passam por ela (KPIs, funil,
--   tráfego, ciclo, macro), ela sozinha definia a lentidão da página — e a
--   matriz macro, que a lê doze vezes, chegava a estourar o tempo limite.
--
--   Causa: a era planilha faz, para cada uma das 1.234 linhas, uma busca de
--   desfecho que cruza `bitrix.dados_raw` com `bitrix.timeline_agendamentos`.
--   Esta última é uma VIEW, então é reavaliada a cada linha.
--
-- A SOLUÇÃO
--   Materializar. O dado de origem só muda a cada sincronização (15 min), então
--   recalcular a cada leitura de página era desperdício puro. É o mesmo padrão
--   dos espelhos de ads e CRM.
--
--   `vw_agendamentos` continua existindo como fachada fina sobre a matriz —
--   assim nenhuma função que já a usa precisa ser alterada.
--
-- ⚠️ A definição do UNION passa a viver SÓ na materializada. A view virou
--    passagem. Mudanças na regra dos agendamentos vão aqui, não lá.
--
-- ⚠️ `rid` existe para o REFRESH CONCURRENTLY, que exige índice único. Sem o
--    CONCURRENTLY o refresh tranca a tabela por alguns segundos a cada 15 min,
--    e o painel congelaria junto.
-- ============================================================================

drop materialized view if exists mkt_se.mv_agendamentos cascade;

create materialized view mkt_se.mv_agendamentos as
with tudo as (

  -- ── era Bitrix: anterior a 2026 ───────────────────────────────────────────
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

  -- ── era planilha: 01/01/2026 a 31/07/2026 ─────────────────────────────────
  select
    'planilha',
    p.uid::text,
    to_date(p.data_sessao, 'DD/MM/YYYY'),
    coalesce(bx.situacao, 'sem_registro'),
    mkt_se.origem_campanha(p.origem),
    null::uuid,
    lb.id,
    lb.campanha,
    lb.conjunto,
    lb.anuncio,
    lower(trim(p.email))
  from mrk_backup_se.mkt_agendamento_2026 p
  left join lateral (
    select l.id, l.campanha, l.conjunto, l.anuncio
    from public.se_facebook_leads l
    where p.email is not null
      and lower(trim(l.email)) = lower(trim(p.email))
    order by l.data desc
    limit 1
  ) lb on true
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
    and p.data_sessao ~ '^\d{1,2}/\d{1,2}/\d{4}$'
    and to_date(p.data_sessao, 'DD/MM/YYYY') >= date '2026-01-01'
    and to_date(p.data_sessao, 'DD/MM/YYYY') <  mkt_se.corte_agenda()

  union all

  -- ── era CRM novo: 01/08/2026 em diante ────────────────────────────────────
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
  where m.primeira >= mkt_se.corte_agenda()
)
select row_number() over () as rid, * from tudo;


-- Único (exigido pelo REFRESH CONCURRENTLY) e os de consulta.
create unique index if not exists idx_mv_agend_rid    on mkt_se.mv_agendamentos (rid);
create index        if not exists idx_mv_agend_data   on mkt_se.mv_agendamentos (data);
create index        if not exists idx_mv_agend_email  on mkt_se.mv_agendamentos (email);
create index        if not exists idx_mv_agend_origem on mkt_se.mv_agendamentos (origem);

analyze mkt_se.mv_agendamentos;


-- ----------------------------------------------------------------------------
-- A view vira fachada — nada que a usa precisa mudar
-- ----------------------------------------------------------------------------
create or replace view mkt_se.vw_agendamentos as
select fonte, ref, data, situacao, origem, closer_id, lead_id,
       campanha, conjunto, anuncio, email
from mkt_se.mv_agendamentos;


-- ----------------------------------------------------------------------------
-- Atualização junto com os espelhos
-- ----------------------------------------------------------------------------
create or replace function mkt_se.refresh_agendamentos()
returns void
language sql
security definer
set search_path = mkt_se, public
as $$
  refresh materialized view concurrently mkt_se.mv_agendamentos;
$$;

select cron.schedule(
  'se_refresh_agendamentos',
  '12-59/15 * * * *',
  $$select mkt_se.refresh_agendamentos()$$
);

revoke all on all tables in schema mkt_se from anon, authenticated;

notify pgrst, 'reload schema';


-- ============================================================================
-- CONFERÊNCIA — mesmos números, em fração do tempo
-- ============================================================================
--   select count(*) from mkt_se.vw_agendamentos;          -- ~2.100, agora rápido
--
--   select to_char(data,'YYYY-MM') mes, fonte, count(*)
--   from mkt_se.vw_agendamentos where data >= '2026-01-01'
--   group by 1,2 order by 1;                              -- jun 247 · jul 254
--
-- Depois de mexer na regra dos agendamentos, atualizar na hora:
--   select mkt_se.refresh_agendamentos();
-- ============================================================================
