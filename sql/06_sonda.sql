-- ============================================================================
-- SE EMP — 06. Sonda de leitura (ferramenta de desenvolvimento)
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- PARA QUE SERVE
--   Deixa o Claude conferir o banco por script, em vez de te pedir para abrir
--   o SQL Editor e colar o resultado a cada pergunta. Só isso — não faz parte
--   do painel e pode ser removida quando o desenvolvimento acabar.
--
-- POR QUE ELA É SEGURA (e onde estão os limites)
--   1. É STABLE. O Postgres PROÍBE INSERT/UPDATE/DELETE/DDL dentro de função
--      não-volátil — tentar devolve "is not allowed in a non-volatile
--      function". Ou seja: só leitura, garantido pelo motor, não pela boa
--      intenção de quem chama.
--   2. O EXECUTE é revogado de anon e authenticated. Só a service_role chama.
--   3. A service_role já pode ler tudo pelo PostgREST de qualquer jeito —
--      esta função não amplia o que quem tem a chave consegue ver. Ela só
--      permite agregação (count, group by, join), que a API REST não faz.
--
--   ⚠️ Mesmo assim: é um endpoint que executa SQL vindo de fora. Se a
--      service_role vazar, ele facilita a vida de quem a tiver. Quando o
--      painel estiver pronto:  drop function mkt_se.q(text);
-- ============================================================================

create or replace function mkt_se.q(sql text)
returns jsonb
language plpgsql
stable                      -- ⚠️ é o que impede escrita; não trocar por volatile
security invoker
as $$
declare
  resultado jsonb;
begin
  execute format('select coalesce(jsonb_agg(t), ''[]''::jsonb) from (%s) t', sql)
    into resultado;
  return resultado;
end;
$$;

revoke all on function mkt_se.q(text) from public, anon, authenticated;
grant execute on function mkt_se.q(text) to service_role;

-- Teste:
select mkt_se.q('select count(*) as linhas from mkt_se.vw_agendamentos');
