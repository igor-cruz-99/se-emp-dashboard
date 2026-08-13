-- ============================================================================
-- SE EMP — 27. Agenda o espelho de ads + tira o aquecimento da conta
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- ============================================================================
-- PARTE 1 — O ESPELHO DE ADS NUNCA FOI AGENDADO
-- ============================================================================
--   `cron.job` tinha só `se_sync_crm` e `se_refresh_agendamentos`. O
--   `se_sync_ads` e o `se_sync_qv` estavam no bloco 9 do 01_fdw.sql, que ficou
--   para "depois de conferir a primeira carga" — e nunca foi rodado.
--
--   Consequência: o espelho de ads só era atualizado quando alguém chamava
--   `sync_ads()` à mão. Os dados congelaram na última chamada manual, no meio
--   de 12/08:
--       11/08  espelho R$ 1.715,09  ·  Anchor R$ 1.715,09   ✓
--       12/08  espelho R$ 2.122,51  ·  Anchor R$ 3.511,11   ✗
--       13/08  espelho —            ·  Anchor R$ 1.406,09   ✗
--
--   ⚠️ Por isso o erro aparecia só nos últimos dois dias: tudo anterior tinha
--   sido capturado numa carga manual e estava correto. É o tipo de falha que
--   não dá erro em lugar nenhum — o painel mostra números plausíveis, só
--   velhos. A conferência com o gestor foi o que pegou.
-- ----------------------------------------------------------------------------

-- Idempotente: se um dia isso rodar duas vezes, não cria job duplicado.
select cron.unschedule('se_sync_ads') where exists (select 1 from cron.job where jobname = 'se_sync_ads');
select cron.unschedule('se_sync_qv')  where exists (select 1 from cron.job where jobname = 'se_sync_qv');

-- Minuto 0 e 30: os outros jobs do SE já ocupam :10 e :12 de cada quarto de
-- hora. Espaçar evita que quatro sincronizações caiam no mesmo instante.
select cron.schedule('se_sync_ads', '0,30 * * * *', $$select mkt_se.sync_ads()$$);
select cron.schedule('se_sync_qv',  '3,33 * * * *', $$select mkt_se.sync_qv()$$);

-- E atualiza agora, sem esperar o próximo ciclo.
select mkt_se.sync_ads() as linhas_ads;
select mkt_se.sync_qv()  as linhas_qv;


-- ============================================================================
-- PARTE 2 — AQUECIMENTO NÃO ENTRA
-- ============================================================================
--   Decisão do gestor: campanha de RMKT entra no cálculo; campanha de
--   AQUECIMENTO, não. No nome das campanhas isso aparece como [ENGAJAMENTO]:
--       `[CP] [F1] [_SE_EMP] [AGENDADOS] [ENGAJAMENTO] [VV] [IG] ...`
--       R$ 2.405,57 · jan–fev/2026 · mira quem JÁ É agendado
--
--   No arquivo 26 eu tinha incluído essa campanha junto com o retargeting, por
--   julgar que era a mesma natureza. Era, mas a decisão do gestor separa as
--   duas: retargeting busca quem não converteu; aquecimento fala com quem já
--   está na base. Só o primeiro é custo de aquisição.
--
--   Agora as duas regras são INDEPENDENTES:
--     • retargeting  → controlado por `p_incluir_rmkt` (default true = conta)
--     • aquecimento  → sempre fora, sem parâmetro
-- ----------------------------------------------------------------------------

-- A marcação vira função própria, para a regra existir num lugar só.
create or replace function mkt_se.eh_aquecimento(p text)
returns boolean
language sql
immutable
as $$
  select coalesce(p ~* '(aquecimento|engajamento)', false);
$$;

-- vw_ads ganha a coluna; quem filtra passa a usá-la em vez de comparar o
-- rótulo de origem (que podia mudar e quebrar o filtro em silêncio).
create or replace view mkt_se.vw_ads as
select
  a.data,
  a.account_name,
  a.campanha,
  a.conjunto,
  a.anuncio,
  a.ad_id,
  mkt_se.origem_campanha(a.campanha) as origem,
  mkt_se.eh_retargeting(a.campanha)  as retargeting,
  a.gasto,
  a.alcance,
  a.impressoes,
  a.cliques,
  a.link_cliques,
  a.landing_page_views,
  a.video_plays,
  a.video_3s,
  a."video_25%" as video_25,
  a."video_50%" as video_50,
  a."video_75%" as video_75,
  a."video_100%" as video_100,
  case when a.impressoes > 0
       then round(100.0 * a.video_3s / a.impressoes, 1) end as hook_pct,
  case when a.video_3s > 0
       then round(100.0 * a."video_25%" / a.video_3s, 1) end as hold_pct,
  case when a.impressoes > 0
       then round(100.0 * a."video_50%" / a.impressoes, 1) end as retencao_pct,
  mkt_se.eh_aquecimento(a.campanha) as aquecimento
from mkt_se.ads a;

notify pgrst, 'reload schema';


-- ============================================================================
-- CONFERÊNCIA
-- ============================================================================
-- 1) Os jobs existem e o espelho alcançou hoje:
--   select jobname, schedule from cron.job where jobname like 'se_%';
--   select max(data) from mkt_se.ads;          -- tem de ser a data de hoje
--
-- 2) Espelho x origem nos últimos dias (as duas colunas têm de ser iguais):
--   select e.data, e.g as espelho, o.g as anchor from
--     (select data, round(sum(gasto)::numeric,2) g from mkt_se.ads
--       where data >= current_date - 3 group by 1) e
--   full join
--     (select data, round(sum(gasto)::numeric,2) g from ext_anchor.ads_metrics
--       where data >= current_date - 3 and campanha ~* '(^|[^a-z0-9])se[_-]'
--       group by 1) o on e.data = o.data order by 1;
--
-- 3) O aquecimento está marcado:
--   select campanha, round(sum(gasto)::numeric,2) from mkt_se.vw_ads
--    where aquecimento group by 1;
-- ============================================================================
