-- ============================================================================
-- SE EMP — 00. Usuário de leitura nos bancos de ORIGEM
--
-- ⚠️ ESTE ARQUIVO NÃO RODA NO BUSINESS DATA.
--    A PARTE A roda no ANCHOR         (sfxbzfaxbbdjzuhzzrjc)
--    A PARTE B roda no BACKUP BASE QV (lacinxsvjdwalkchxyeo)
--    Rode cada parte no SQL Editor do projeto correspondente.
--
-- Por que existe:
--   O FDW precisa de uma conexão Postgres de verdade (não serve anon/service_role).
--   A senha do usuário `postgres` o Supabase só mostra na criação do projeto —
--   e resetá-la derrubaria toda conexão direta existente (no Backup QV isso
--   afetaria o outro setor).
--   Criando uma role própria, VOCÊ define a senha, ninguém é derrubado, e a
--   credencial que fica guardada no Business Data só consegue LER as tabelas
--   que combinamos. Se um dia precisar cortar: `drop role fdw_se;`.
--
-- ⚠️ Modelo com placeholder. Gere a versão real:  node scripts/gerar-sql.mjs
--    Preencha SENHA_FDW no .env.local antes.
-- ============================================================================


-- ============================================================================
-- PARTE A — rodar no ANCHOR (sfxbzfaxbbdjzuhzzrjc)
-- ============================================================================

create role fdw_se with login password '<<SENHA_FDW>>';

grant connect on database postgres to fdw_se;
grant usage   on schema core       to fdw_se;
grant select  on core.ads_metrics  to fdw_se;

-- Conferir: a role existe e enxerga a tabela?
select rolname, rolcanlogin from pg_roles where rolname = 'fdw_se';
select has_table_privilege('fdw_se', 'core.ads_metrics', 'select') as pode_ler;

-- ⚠️ RLS — a armadilha silenciosa desta etapa.
--    Se a tabela tiver Row Level Security ligada, a fdw_se não recebe erro:
--    recebe ZERO LINHAS. O espelho sincroniza "com sucesso" e vazio.
--    (O WEP não sofre com isso porque lê com service_role, que ignora RLS.)
select relname, relrowsecurity as rls_ligada
from pg_class where oid = 'core.ads_metrics'::regclass;

--    Se rls_ligada = true, libere a leitura para a role:
--
--      create policy fdw_se_leitura on core.ads_metrics
--        for select to fdw_se using (true);
--
--    Se rls_ligada = false, não precisa de nada.

-- Teste final (tem que devolver a contagem, não zero):
--   set role fdw_se;
--   select count(*) from core.ads_metrics;
--   reset role;


-- ============================================================================
-- PARTE B — rodar no BACKUP BASE QV (lacinxsvjdwalkchxyeo)
-- ============================================================================

create role fdw_se with login password '<<SENHA_FDW>>';

grant connect on database postgres to fdw_se;
grant usage   on schema public     to fdw_se;
grant select  on public.client_meetings,
                 public.meeting_attendance,
                 public.contratos_pharus to fdw_se;

-- Conferir os três privilégios de uma vez:
select t.tabela, has_table_privilege('fdw_se', t.tabela, 'select') as pode_ler
from (values ('public.client_meetings'),
             ('public.meeting_attendance'),
             ('public.contratos_pharus')) as t(tabela);

-- RLS nas três (mesma armadilha da Parte A):
select relname, relrowsecurity as rls_ligada
from pg_class
where oid in ('public.client_meetings'::regclass,
              'public.meeting_attendance'::regclass,
              'public.contratos_pharus'::regclass);

--    Para cada uma com rls_ligada = true:
--
--      create policy fdw_se_leitura on public.client_meetings
--        for select to fdw_se using (true);
--
--    (repetir trocando o nome da tabela)

-- Teste final:
--   set role fdw_se;
--   select count(*) from public.client_meetings;
--   reset role;


-- ============================================================================
-- DEPOIS DE RODAR AS DUAS PARTES
--
--   1. No .env.local, troque para a role nova:
--        USER_ANCHOR=fdw_se     SENHA_ANCHOR=<a mesma SENHA_FDW>
--        USER_QV=fdw_se         SENHA_QV=<a mesma SENHA_FDW>
--   2. node scripts/gerar-sql.mjs
--   3. Cole sql/.gerado/01_fdw.local.sql no Business Data.
--
-- Para desfazer, se precisar (em cada projeto de origem):
--   drop owned by fdw_se;
--   drop role fdw_se;
-- ============================================================================
