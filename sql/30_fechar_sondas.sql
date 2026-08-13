-- ============================================================================
-- SE EMP — 30. Fecha as sondas de desenvolvimento antes de publicar
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- O QUE SÃO AS SONDAS
--   `mkt_se.q(sql)` e `public.se_q(sql)` recebem um SELECT em texto e devolvem
--   o resultado em json. Foram criadas em sql/06_sonda.sql para eu conferir o
--   banco sem depender de você abrir o SQL Editor e colar o resultado a cada
--   pergunta. Serviram bem — foi por elas que saíram quase todas as
--   conferências deste projeto.
--
-- POR QUE ELAS NÃO PODEM FICAR
--   `public.se_q` é SECURITY DEFINER e pertence ao `postgres`. Ou seja:
--   executa o texto recebido COM PODER DE DONO DO BANCO, não com o poder de
--   quem chamou. O `public` está no Exposed schemas, então ela é alcançável
--   pela API REST — hoje só pela service_role, que é o único papel com
--   execute.
--
--   Isso quer dizer que a service_role deixa de ser "lê tudo ignorando RLS" e
--   passa a ser "roda qualquer comando como dono". A diferença importa: a
--   primeira lê, a segunda apaga.
--
--   ⚠️ E a service_role deste projeto foi colada numa conversa. Enquanto ela
--   não for rotacionada, quem tiver aquele texto tem esse poder. Rotacionar
--   resolve o vazamento; remover a sonda resolve o tamanho do estrago.
--
--   `mkt_se.q` é o caso menor: NÃO é security definer (roda como quem chamou)
--   e o schema `mkt_se` não está exposto na API, então hoje é inalcançável.
--   Mas ela está com execute para `anon` e `authenticated` — quer dizer que no
--   dia em que alguém expuser o `mkt_se` no Exposed schemas, vira SQL aberto
--   para qualquer visitante com a chave pública. É uma armadilha esperando
--   uma configuração futura. Sai junto.
--
-- O QUE SE PERDE
--   Eu perco a leitura direta do banco: as conferências voltam a depender de
--   você rodar no SQL Editor e colar o resultado. Se um dia precisarmos de
--   novo, é só rodar o sql/06_sonda.sql outra vez — em desenvolvimento, e
--   fechar de novo antes de publicar.
-- ============================================================================

drop function if exists public.se_q(text);
drop function if exists mkt_se.q(text);

notify pgrst, 'reload schema';


-- ============================================================================
-- CONFERÊNCIA — as duas têm de sumir
-- ============================================================================
--   select n.nspname, p.proname
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where p.proname in ('q', 'se_q');
--   -- tem de vir vazio
-- ============================================================================
