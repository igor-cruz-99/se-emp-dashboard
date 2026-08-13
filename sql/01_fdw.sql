-- ============================================================================
-- SE EMP (Sessão Estratégica) — 01. FDW + espelhos
--
-- ⚠️ RODAR NO PROJETO **BUSINESS DATA** (rckpuebaiswrxzmywllv).
--    Não rodar no Anchor nem no Backup QV — eles só são LIDOS.
--
-- Arquitetura:
--
--   Anchor (sfxbzfaxbbdjzuhzzrjc)          Backup BASE QV (lacinxsvjdwalkchxyeo)
--   core.ads_metrics                       public.client_meetings
--         │                                public.meeting_attendance
--         │  postgres_fdw                  public.contratos_pharus
--         │                                      │  postgres_fdw
--         ▼                                      ▼
--   ┌──────────────────── BUSINESS DATA (hub) ────────────────────┐
--   │  public.se_facebook_leads   ← leads, nativo daqui           │
--   │  mkt_se.ads / meetings / attendance / contratos ← espelhos  │
--   │  mkt_se.vw_* / fn_*         ← views e RPCs do painel        │
--   └─────────────────────────────────────────────────────────────┘
--
-- Por que espelhar em vez de consultar ao vivo pelo FDW:
--   o Anchor está com a RAM sobrecarregada. Espelhando, ele recebe UMA consulta
--   a cada 15 min em vez de uma por carregamento do painel.
--
-- ⚠️ NÃO cole ESTE arquivo no SQL Editor — ele é o modelo, sem as senhas.
--    Preencha o .env.local e gere a versão pronta:  node scripts/gerar-sql.mjs
--    Cole a que sai em  sql/.gerado/01_fdw.local.sql  (essa fica fora do git).
-- ⚠️ Depois de rodar, LIMPAR O HISTÓRICO do SQL Editor — as senhas ficam nele.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 0. Extensões
-- ----------------------------------------------------------------------------
create extension if not exists postgres_fdw;
create extension if not exists pg_cron;


-- ----------------------------------------------------------------------------
-- 1. Schemas
--    mkt_se     → nossos objetos (espelhos, views, RPCs)
--    ext_anchor → tabelas estrangeiras do Anchor  (não consultar direto!)
--    ext_qv     → tabelas estrangeiras do Backup QV (não consultar direto!)
-- ----------------------------------------------------------------------------
create schema if not exists mkt_se;
create schema if not exists ext_anchor;
create schema if not exists ext_qv;


-- ----------------------------------------------------------------------------
-- 2. Servidores estrangeiros
--
--    HOST: a conexão direta do Supabase é IPv6-only. Se o projeto não tiver o
--    add-on de IPv4, usar o host do POOLER (Supavisor) em modo session:
--
--      direta : db.<ref>.supabase.co                 porta 5432  user 'postgres'
--      pooler : aws-0-<regiao>.pooler.supabase.com   porta 5432  user 'postgres.<ref>'
--
--    Achar o valor certo em: Project Settings → Database → Connection string.
--    Começar pela DIRETA; se der timeout, trocar pelo pooler (e ajustar o user
--    no user mapping para 'postgres.<ref>').
-- ----------------------------------------------------------------------------
create server if not exists srv_anchor
  foreign data wrapper postgres_fdw
  options (host '<<HOST_ANCHOR>>', port '5432', dbname 'postgres');

create server if not exists srv_qv
  foreign data wrapper postgres_fdw
  options (host '<<HOST_QV>>', port '5432', dbname 'postgres');


-- ----------------------------------------------------------------------------
-- 3. Credenciais (user mapping)
--    A senha fica guardada dentro do banco. Só superuser vê o valor
--    (pg_user_mappings esconde de quem não é dono). Ainda assim: é credencial
--    cruzada entre projetos — saiba que ela existe.
-- ----------------------------------------------------------------------------
create user mapping if not exists for postgres
  server srv_anchor
  options (user '<<USER_ANCHOR>>', password '<<SENHA_ANCHOR>>');

create user mapping if not exists for postgres
  server srv_qv
  options (user '<<USER_QV>>', password '<<SENHA_QV>>');


-- ----------------------------------------------------------------------------
-- 4. Importar as tabelas estrangeiras
--    LIMIT TO garante que só o que precisamos entre — nada de arrastar o
--    schema inteiro de um projeto que é de outro setor.
-- ----------------------------------------------------------------------------
import foreign schema core
  limit to (ads_metrics)
  from server srv_anchor into ext_anchor;

import foreign schema public
  limit to (client_meetings, meeting_attendance, contratos_pharus)
  from server srv_qv into ext_qv;


-- ----------------------------------------------------------------------------
-- 5. Espelhos locais
--    Criados a partir da estrutura remota (WITH NO DATA), então acompanham
--    as colunas reais sem precisarmos listá-las à mão.
--    São cópias EXATAS — nada de coluna derivada aqui, senão o INSERT ... SELECT *
--    quebra quando a origem ganhar uma coluna. Derivações vivem nas views (02).
-- ----------------------------------------------------------------------------
create table if not exists mkt_se.ads        as select * from ext_anchor.ads_metrics       with no data;
create table if not exists mkt_se.meetings   as select * from ext_qv.client_meetings       with no data;
create table if not exists mkt_se.attendance as select * from ext_qv.meeting_attendance    with no data;
create table if not exists mkt_se.contratos  as select * from ext_qv.contratos_pharus      with no data;


-- ----------------------------------------------------------------------------
-- 6. Sincronização
--
--    ⚠️ REGRA DE OURO: o WHERE só pode usar operadores NATIVOS do Postgres
--    (>=, ilike, ~*). O postgres_fdw só empurra esses para o banco remoto.
--    Se usarmos uma função nossa no WHERE, o filtro roda LOCALMENTE — ou seja,
--    a tabela inteira do Anchor atravessa a rede. É exatamente o que não
--    podemos fazer com um banco sem RAM.
--
--    Filtro de ads (definido a partir do levantamento das campanhas):
--      • data >= 2026-01-01        → só o ano corrente; antes disso está fora
--      • campanha ~* '(^|[^a-z0-9])se[_-]'
--            "SE" como TOKEN do nome, não como pedaço solto.
--            Pega  GNB_SE_CAPTACAO, ls-SE-CAPTACAO, AF_SE_EMP, [_SE_EMP]…
--            Ignora GNB_IS_SDA_EMP_* (era o vazamento do filtro '%gnb%' do BI:
--            2 campanhas de SDA, R$ 2.716 inflando o investimento).
--            Não confunde com SEMELHANTES nem SEAL (ali o SE vem antes de letra).
--
--    O RMKT é espelhado DE PROPÓSITO e excluído depois, nas views/RPCs.
--    Descartar aqui seria irreversível; são 234 linhas, custo zero.
-- ----------------------------------------------------------------------------
create or replace function mkt_se.sync_ads()
returns integer
language plpgsql
security definer
set search_path = mkt_se, ext_anchor, public
as $$
declare
  n integer;
begin
  truncate mkt_se.ads;
  insert into mkt_se.ads
  select *
  from ext_anchor.ads_metrics
  where data >= date '2026-01-01'
    and campanha ~* '(^|[^a-z0-9])se[_-]';
  get diagnostics n = row_count;
  return n;
end;
$$;

create or replace function mkt_se.sync_qv()
returns text
language plpgsql
security definer
set search_path = mkt_se, ext_qv, public
as $$
declare
  a integer; b integer; c integer;
begin
  truncate mkt_se.meetings;
  insert into mkt_se.meetings select * from ext_qv.client_meetings;
  get diagnostics a = row_count;

  truncate mkt_se.attendance;
  insert into mkt_se.attendance select * from ext_qv.meeting_attendance;
  get diagnostics b = row_count;

  truncate mkt_se.contratos;
  insert into mkt_se.contratos select * from ext_qv.contratos_pharus;
  get diagnostics c = row_count;

  return format('meetings=%s attendance=%s contratos=%s', a, b, c);
end;
$$;


-- ----------------------------------------------------------------------------
-- 7. Primeira carga — rodar e conferir os números antes de agendar
-- ----------------------------------------------------------------------------
select mkt_se.sync_ads()  as linhas_ads;   -- ~4.071 com corte em 2025-12-23; menos com o corte de 2026
select mkt_se.sync_qv()   as linhas_qv;    -- esperado: meetings=8084 attendance=4446 contratos=152


-- ----------------------------------------------------------------------------
-- 8. Índices (só depois da primeira carga, para o planner ter estatística)
-- ----------------------------------------------------------------------------
create index if not exists idx_ads_data      on mkt_se.ads (data);
create index if not exists idx_ads_campanha  on mkt_se.ads (campanha);
create index if not exists idx_ads_anuncio   on mkt_se.ads (anuncio);

analyze mkt_se.ads;
analyze mkt_se.meetings;
analyze mkt_se.attendance;
analyze mkt_se.contratos;


-- ----------------------------------------------------------------------------
-- 9. Agendamento (pg_cron) — a cada 15 min, defasados para não competirem
--    ⚠️ Só habilitar depois que o passo 7 tiver rodado limpo.
-- ----------------------------------------------------------------------------
select cron.schedule('se_sync_ads', '*/15 * * * *', $$select mkt_se.sync_ads()$$);
select cron.schedule('se_sync_qv',  '5-59/15 * * * *', $$select mkt_se.sync_qv()$$);

-- Acompanhar as execuções:
--   select * from cron.job;
--   select * from cron.job_run_details order by start_time desc limit 20;
-- Desligar, se precisar:
--   select cron.unschedule('se_sync_ads');


-- ----------------------------------------------------------------------------
-- 10. Trancar (o painel lê pela API com service_role; anon não lê nada)
-- ----------------------------------------------------------------------------
revoke all on schema ext_anchor, ext_qv from anon, authenticated;
revoke all on schema mkt_se           from anon, authenticated;
revoke all on all tables in schema mkt_se from anon, authenticated;


-- ============================================================================
-- CONFERÊNCIA — rodar depois e comparar com o BI
-- ============================================================================
-- Volume e período do espelho de ads:
--   select count(*), count(distinct anuncio), min(data), max(data),
--          round(sum(gasto)::numeric,2) from mkt_se.ads;
--   -- esperado: ~2.821 linhas | 2025-12-28 → hoje | ~R$ 357.632
--   -- (o BI marcava R$ 360.348 porque incluía as 2 campanhas do SDA)
--
-- O RMKT entrou (deve ter ~234 linhas):
--   select count(*) from mkt_se.ads where campanha ~* 'rmkt';
--
-- Nenhuma campanha de outro produto passou:
--   select distinct campanha from mkt_se.ads order by 1;
--
-- Tamanho das tabelas do Backup QV (se contratos vier muito grande,
-- passamos a filtrar na sincronização em vez de copiar tudo):
--   select 'meetings', count(*) from mkt_se.meetings
--   union all select 'attendance', count(*) from mkt_se.attendance
--   union all select 'contratos',  count(*) from mkt_se.contratos;
-- ============================================================================
