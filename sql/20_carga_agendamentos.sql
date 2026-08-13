-- ============================================================================
-- SE EMP — 20. Tabela para a carga do CSV de agendamentos
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- POR QUE A TABELA NASCE NO `public`
--   O PostgREST deste projeto só enxerga `public, bl_test, dw_bitrix,
--   contracts_app` — a exposição de novos schemas não é aplicada (mesmo
--   problema que nos levou às pontes `se_*` no arquivo 08). Como a carga é
--   feita pela API, a tabela precisa nascer num schema alcançável.
--   Depois de carregada, o passo 3 lá embaixo a move para o backup.
--
--   A alternativa seria criar uma função de ESCRITA no public para servir de
--   ponte — mas um endpoint que insere dados vindos de fora é bem mais
--   arriscado que uma tabela temporária, e ficaria no banco para sempre.
--
-- O QUE ESTE CSV RESOLVE
--   Ele cobre jan–ago/2026 e é a única fonte com JULHO (254 agendamentos de
--   Sessão Estratégica). Também corrige junho: 247 contra os 58 que a Bitrix
--   truncada entregava.
--   ⚠️ NÃO traz comparecimento (`situacao` é "Agendada" em 4.689 de 4.691)
--   nem venda (`comprou` vazio em todas as linhas de SE). Ele conserta a
--   contagem de agendamentos, e só isso.
--
-- Colunas em text, iguais às de `mrk_backup_se.mkt_agendamento`, para as duas
-- poderem ser unidas depois sem conversão.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PASSO 1 — rodar ANTES da carga
-- ----------------------------------------------------------------------------
drop table if exists public.se_agendamento_carga;

create table public.se_agendamento_carga (
  uid                 uuid primary key default gen_random_uuid(),
  data                text,
  hora_entrada        text,
  funil               text,
  origem              text,
  nome                text,
  email               text,
  telefone            text,
  data_sessao         text,
  hora_sessao         text,
  closer              text,
  situacao            text,
  observacoes         text,
  comprou             text,
  produto             text,
  data_de_compra      text,
  telefone_closer     text,
  data_lembrete_1     text,
  lembrete_1_enviado  text,
  data_lembrete_2     text,
  lembrete_2_enviado  text,
  recuperacao_sdr     text,
  nome_sdr            text,
  renda               text
);

alter table public.se_agendamento_carga enable row level security;

-- A carga entra pela API com a service_role, que ignora RLS.
-- anon/authenticated não têm nada aqui.
revoke all on table public.se_agendamento_carga from anon, authenticated;
grant all  on table public.se_agendamento_carga to service_role;

notify pgrst, 'reload schema';


-- ============================================================================
-- PASSO 2 — a carga (eu rodo):  node scripts/carregar-agendamentos.mjs
-- ============================================================================
-- Conferir depois:
--   select count(*) from public.se_agendamento_carga;                 -- 4691
--   select count(*) from public.se_agendamento_carga
--    where funil ilike '%estrat%';                                    -- 1234


-- ============================================================================
-- PASSO 3 — mover para o backup (rodar DEPOIS da carga)
-- ============================================================================
-- alter table public.se_agendamento_carga set schema mrk_backup_se;
-- alter table mrk_backup_se.se_agendamento_carga rename to mkt_agendamento_2026;
--
-- ⚠️ Tabela NOVA de propósito: a `mkt_agendamento` existente cobre
--    nov/2024–jan/2026 e pode ser usada por outra coisa. Não mexemos nela.
-- ============================================================================
