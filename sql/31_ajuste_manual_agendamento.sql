-- ============================================================================
-- SE EMP — 31. Incluir à mão um agendamento que faltou na planilha
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- ONDE ESTE AJUSTE ENTRA — E POR QUE NÃO NO BACKUP QV
--   A `mrk_backup_se.mkt_agendamento_2026` **é nossa** e vive no Business
--   Data. Ela nasceu como `public.se_agendamento_carga`, recebeu o CSV e foi
--   movida de schema (sql/20, passo 3). Nenhum `sync_*` escreve nela: o
--   `sync_qv()` só mexe em `mkt_se.meetings`, `mkt_se.attendance` e
--   `mkt_se.contratos`. Ou seja, o que for escrito aqui FICA.
--
--   ⚠️ Não é o caso de editar no Backup BASE QV. Aquele projeto é de outro
--   setor e o combinado é só leitura — e, para 2026, o painel nem lê de lá:
--   lê desta tabela. Editar na origem daria trabalho e não mudaria a tela.
--
--   A regra geral, para as próximas vezes:
--     sessão até 31/12/2025      → Bitrix (não editar; é histórico)
--     sessão de 01/01 a 31/07/26 → AQUI   (era da planilha)
--     sessão de 01/08/26 adiante → CRM novo — corrigir NO CRM, que é a
--                                  operação viva; o espelho recolhe sozinho
--
-- ⚠️ RISCO ÚNICO DESTE CAMINHO: se um dia a planilha for recarregada do zero
--   (sql/20 dá `drop table`), as linhas manuais somem junto. Se isso for
--   acontecer, recarregue e rode este arquivo de novo — por isso ele fica
--   versionado, e não como comando solto no editor.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- O AJUSTE
--   Sessão de 27/07/2026 de fmurillo2004@hotmail.com, que não veio na planilha.
--
--   Nome, telefone, origem e renda NÃO são digitados: saem do próprio cadastro
--   do lead. Digitar à mão abriria espaço para escrever a origem de um jeito
--   que o `origem_campanha()` não reconhece — e a linha cairia em
--   "Não identificado" sem ninguém notar.
--
--   Este lead tem DUAS entradas (22/07 e 26/07). O `order by data desc` pega a
--   de 26/07, que é a que antecede a sessão — a mesma escolha que a view faz
--   ao atribuir campanha/conjunto/anúncio.
-- ----------------------------------------------------------------------------
insert into mrk_backup_se.mkt_agendamento_2026
  (data, hora_entrada, funil, origem, nome, email, telefone, data_sessao, renda)
select
  to_char(l.data, 'DD/MM/YYYY'),
  l.hora::text,
  'Sessão Estratégica',
  l.tag_origem,
  l.nome,
  l.email,
  l.telefone,
  '27/07/2026',
  l.renda
from public.se_facebook_leads l
where lower(trim(l.email)) = 'fmurillo2004@hotmail.com'
  and l.data <= date '2026-07-27'
  -- Guarda contra rodar duas vezes: se já existir sessão desse email nesse
  -- dia, não insere nada.
  and not exists (
    select 1 from mrk_backup_se.mkt_agendamento_2026 a
    where lower(trim(a.email)) = 'fmurillo2004@hotmail.com'
      and a.data_sessao = '27/07/2026'
  )
order by l.data desc
limit 1;


-- ----------------------------------------------------------------------------
-- A tabela materializada precisa ser reconstruída — senão a tela só muda no
-- próximo ciclo do cron (15 min).
-- ----------------------------------------------------------------------------
select mkt_se.refresh_agendamentos();


-- ============================================================================
-- O QUE ESPERAR NA TELA
-- ============================================================================
--   • "Agendamentos" de julho sobe de 254 para 255.
--   • "Agendas" (pessoas únicas) sobe junto SÓ se este lead não tiver outra
--     sessão em julho.
--   • O comparecimento de julho NÃO muda: a `situacao` desta linha é ignorada
--     de propósito — a view busca o desfecho na Bitrix pelo email e, não
--     achando, marca 'sem_registro', que fica fora da base do cálculo. Não dá
--     para afirmar que compareceu sem registro dizendo isso.
--   • A atribuição (campanha/conjunto/anúncio) sai do lead de 26/07:
--     `ls-SE-CAPTACAO-FORMS-NATIVO-JOAO-bid-advantage`, origem "Forms Nativo".
--
-- CONFERÊNCIA
--   select count(*) from mkt_se.mv_agendamentos
--    where data between '2026-07-01' and '2026-07-31';        -- 255
--
--   select data, situacao, origem, campanha from mkt_se.mv_agendamentos
--    where email = 'fmurillo2004@hotmail.com';
-- ============================================================================
