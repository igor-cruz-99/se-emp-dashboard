-- ============================================================================
-- SE EMP — 02. Espelho das tabelas do CRM novo
--
-- ⚠️ RODAR NO BUSINESS DATA (rckpuebaiswrxzmywllv).
--    Sem senha aqui — cola direto, não precisa do gerador.
--    O servidor srv_qv já existe (criado no 01).
--
-- Contexto:
--   A `client_meetings` do 01 era a jornada PÓS-VENDA (Checkpoint, Kickoff…),
--   não a call de vendas — foi removida no 03. A call de vendas está aqui,
--   em `crm_meetings`, do CRM que entrou no ar em 03/08/2026. O CRM anterior
--   foi descontinuado e seus dados se perderam: por isso o funil do
--   agendamento pra baixo só existe a partir de agosto/2026.
--
--   `crm_meetings.lead_id` (uuid) NÃO liga na `se_facebook_leads` (id bigint).
--   A ponte é `crm_leads`, que tem o email:
--
--       se_facebook_leads.email  ─►  crm_leads.email  ─►  crm_meetings.lead_id
--
-- ⚠️ POR QUE AS TABELAS SÃO DECLARADAS À MÃO, e não por IMPORT FOREIGN SCHEMA:
--    a `crm_leads.hot_reason` usa um enum próprio (`public.crm_hot_reason`) que
--    só existe no banco de origem. O IMPORT tenta recriar o tipo aqui e falha
--    com `type "public.crm_hot_reason" does not exist` — derrubando a
--    transação inteira, sem importar nada.
--    Declarando à mão a gente (a) escolhe só as colunas que o funil usa e
--    (b) recebe qualquer enum como `text`, que é como ele viaja no protocolo.
--    Se aparecer coluna nova na origem, ela é simplesmente ignorada aqui.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 0. Limpar tentativa anterior
-- ----------------------------------------------------------------------------
drop table         if exists mkt_se.crm_leads;
drop table         if exists mkt_se.crm_meetings;
drop foreign table if exists ext_qv.crm_leads;
drop foreign table if exists ext_qv.crm_meetings;


-- ----------------------------------------------------------------------------
-- 1. Tabelas estrangeiras — só as colunas do funil
-- ----------------------------------------------------------------------------
create foreign table ext_qv.crm_leads (
  id                  uuid,
  funnel_id           uuid,
  sdr_id              uuid,
  closer_id           uuid,
  nome                text,
  email               text,
  telefone            text,
  origem              text,
  source              text,
  external_lead_id    text,
  meta_ads_data       jsonb,
  is_client           boolean,
  first_touch_at      timestamptz,   -- primeiro contato
  qualified_at        timestamptz,   -- qualificado pelo SDR
  agendado_at         timestamptz,   -- agendou a sessão
  won_at              timestamptz,   -- ganho
  lost_at             timestamptz,
  lost_reason         text,
  sale_at             timestamptz,   -- data da venda
  sale_amount         numeric,       -- valor da venda
  sale_product        text,
  sale_closer_id      uuid,
  sale_sdr_id         uuid,
  created_at          timestamptz,
  archived_at         timestamptz
)
server srv_qv
options (schema_name 'public', table_name 'crm_leads');

create foreign table ext_qv.crm_meetings (
  id                  uuid,
  lead_id             uuid,
  owner_id            uuid,          -- closer dono da agenda
  ghost_closer_id     uuid,
  scheduled_at        timestamptz,   -- quando a call está marcada
  outcome             text,          -- realizada | no_show | pendente | cancelada | remarcada
  completed_at        timestamptz,
  cancelled_at        timestamptz,
  created_at          timestamptz,   -- quando o agendamento foi criado
  source              text,
  gcal_owner_email    text,
  notas               text           -- traz o nome do evento e a faixa de renda
)
server srv_qv
options (schema_name 'public', table_name 'crm_meetings');


-- ----------------------------------------------------------------------------
-- 2. Espelhos locais
-- ----------------------------------------------------------------------------
create table mkt_se.crm_leads    as select * from ext_qv.crm_leads    with no data;
create table mkt_se.crm_meetings as select * from ext_qv.crm_meetings with no data;

alter table mkt_se.crm_leads    enable row level security;
alter table mkt_se.crm_meetings enable row level security;


-- ----------------------------------------------------------------------------
-- 3. Sincronização
--    Sem filtro: o recorte do SE é feito depois, pelo cruzamento com os leads
--    (é o email que define o que é nosso). Se `crm_leads` se mostrar grande,
--    passamos a filtrar aqui.
-- ----------------------------------------------------------------------------
create or replace function mkt_se.sync_crm()
returns text
language plpgsql
security definer
set search_path = mkt_se, ext_qv, public
as $$
declare
  a integer; b integer;
begin
  truncate mkt_se.crm_leads;
  insert into mkt_se.crm_leads select * from ext_qv.crm_leads;
  get diagnostics a = row_count;

  truncate mkt_se.crm_meetings;
  insert into mkt_se.crm_meetings select * from ext_qv.crm_meetings;
  get diagnostics b = row_count;

  return format('crm_leads=%s crm_meetings=%s', a, b);
end;
$$;


-- ----------------------------------------------------------------------------
-- 4. Primeira carga
-- ----------------------------------------------------------------------------
select mkt_se.sync_crm() as linhas;   -- crm_meetings deve vir 682


-- ----------------------------------------------------------------------------
-- 5. Índices e agendamento
-- ----------------------------------------------------------------------------
create index if not exists idx_crm_leads_email      on mkt_se.crm_leads (lower(email));
create index if not exists idx_crm_meetings_lead    on mkt_se.crm_meetings (lead_id);
create index if not exists idx_crm_meetings_sched   on mkt_se.crm_meetings (scheduled_at);

analyze mkt_se.crm_leads;
analyze mkt_se.crm_meetings;

select cron.schedule('se_sync_crm', '10-59/15 * * * *', $$select mkt_se.sync_crm()$$);

revoke all on all tables in schema mkt_se from anon, authenticated;


-- ============================================================================
-- 6. CONFERÊNCIA — a ponte funciona?
-- ============================================================================
select
  (select count(*) from public.se_facebook_leads)          as leads_se,
  (select count(*) from mkt_se.crm_leads)                  as leads_crm,
  (select count(distinct lower(l.email))
     from public.se_facebook_leads l
     join mkt_se.crm_leads c on lower(c.email) = lower(l.email))
                                                           as casaram,
  (select count(distinct m.lead_id)
     from mkt_se.crm_meetings m
     join mkt_se.crm_leads c on c.id = m.lead_id
     join public.se_facebook_leads l on lower(l.email) = lower(c.email))
                                                           as agendaram,
  (select count(*)
     from mkt_se.crm_leads c
     join public.se_facebook_leads l on lower(l.email) = lower(c.email)
    where c.sale_at is not null)                           as venderam;

-- Referência: 682 agendamentos no total (todos os funis da empresa).
-- Se "agendaram" for uma fração razoável disso, a ponte serve.
-- ============================================================================
