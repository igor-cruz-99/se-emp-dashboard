-- ============================================================================
-- SE EMP — 03. Remove os espelhos que não servem ao painel
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, pode colar direto.
--
-- Motivo:
--   `client_meetings` (8.084) e `meeting_attendance` (4.446) são a jornada
--   PÓS-VENDA do cliente (Checkpoint 1..16, Kickoff, Implementação…), não a
--   call de vendas. A call está em `crm_meetings`, importada no 02.
--   São 12.530 linhas sendo copiadas a cada 15 min sem serem usadas.
--
--   `contratos_pharus` fica: são 152 linhas e serve de conferência contra o
--   `sale_amount` da crm_leads.
-- ============================================================================

-- 1. sync_qv passa a cuidar só de contratos
create or replace function mkt_se.sync_qv()
returns text
language plpgsql
security definer
set search_path = mkt_se, ext_qv, public
as $$
declare
  c integer;
begin
  truncate mkt_se.contratos;
  insert into mkt_se.contratos select * from ext_qv.contratos_pharus;
  get diagnostics c = row_count;
  return format('contratos=%s', c);
end;
$$;

-- 2. Fora os espelhos locais
drop table if exists mkt_se.meetings;
drop table if exists mkt_se.attendance;

-- 3. Fora as tabelas estrangeiras (para de manter conexão com elas)
drop foreign table if exists ext_qv.client_meetings;
drop foreign table if exists ext_qv.meeting_attendance;

-- 4. Conferir
select mkt_se.sync_qv() as agora;   -- esperado: contratos=152

select table_name
from information_schema.tables
where table_schema in ('mkt_se', 'ext_qv')
order by table_schema, table_name;
-- esperado em mkt_se: ads, contratos, crm_leads, crm_meetings
-- esperado em ext_qv: ads? não — só contratos_pharus, crm_leads, crm_meetings
