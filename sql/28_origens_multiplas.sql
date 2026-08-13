-- ============================================================================
-- SE EMP — 28. Filtro de origem vira múltipla escolha + aquecimento fora
--
-- ⚠️ RODAR NO BUSINESS DATA, DEPOIS do 27 (ele cria a coluna `aquecimento`
--    na vw_ads, que estas funções passam a usar).
--
-- DUAS MUDANÇAS
--
-- 1. `p_origem text` vira `p_origens text[]`
--    O filtro do topo da tela deixa de ser "uma origem por vez" e vira caixas
--    de seleção. Passar null continua significando "todas".
--    ⚠️ O tipo do parâmetro mudou, então a assinatura antiga precisa ser
--    dropada antes — `create or replace` não troca tipo de argumento, ele
--    criaria uma SOBRECARGA, e aí a chamada da API ficaria ambígua.
--
-- 2. Aquecimento sai da conta, sempre
--    Decisão do gestor: RMKT entra, AQUECIMENTO não. Eram uma coisa só no
--    arquivo 26 — agora são independentes:
--      • retargeting → `p_incluir_rmkt` (default true, conta)
--      • aquecimento → sempre fora, sem parâmetro
--    São R$ 2.405,57 em jan–fev/2026, e zero leads (é campanha de vídeo para
--    quem já é agendado), então só o investimento muda.
--
-- ⚠️ Gerado a partir das definições que estavam no banco (`pg_get_functiondef`)
--    e transformado por script — não reescrito à mão. São 16 funções; copiar
--    manualmente perderia alguma correção anterior.
-- ============================================================================


drop function if exists mkt_se.fn_ciclo_vendas(date, date, text);
drop function if exists mkt_se.fn_formularios(date, date, text);
drop function if exists mkt_se.fn_kpis(date, date, text, boolean);
drop function if exists mkt_se.fn_origem(date, date, boolean);
drop function if exists mkt_se.fn_perfil_lead(date, date, text);
drop function if exists mkt_se.fn_renda(date, date, text);
drop function if exists mkt_se.fn_serie_diaria(date, date, text, boolean);
drop function if exists mkt_se.fn_trafego(date, date, text, boolean);
drop function if exists public.se_ciclo_vendas(date, date, text);
drop function if exists public.se_formularios(date, date, text);
drop function if exists public.se_kpis(date, date, text, boolean);
drop function if exists public.se_origem(date, date, boolean);
drop function if exists public.se_perfil_lead(date, date, text);
drop function if exists public.se_renda(date, date, text);
drop function if exists public.se_serie_diaria(date, date, text, boolean);
drop function if exists public.se_trafego(date, date, text, boolean);


CREATE OR REPLACE FUNCTION mkt_se.fn_ciclo_vendas(p_ini date, p_fim date, p_origens text[] DEFAULT NULL::text[])
 RETURNS TABLE(nome text, anuncio text, data_criacao date, data_agendamento date, data_venda date, dias_cria_agen integer, dias_agen_venda integer, dias_cria_venda integer)
 LANGUAGE sql
 STABLE
AS $function$
select
  coalesce(nullif(trim(l.nome), ''), nullif(trim(v.nome), ''), '(sem nome)') as nome,
  coalesce(nullif(trim(l.anuncio), ''), nullif(trim(v.anuncio), ''), '(sem atribuição)') as anuncio,
  l.created_at::date                       as data_criacao,
  a.data                                   as data_agendamento,
  v.data                                   as data_venda,
  (a.data - l.created_at::date)::integer   as dias_cria_agen,
  (v.data - a.data)::integer               as dias_agen_venda,
  (v.data - l.created_at::date)::integer   as dias_cria_venda
from mkt_se.vw_vendas v

-- lead que originou a venda (o mais antigo com aquele email — é o primeiro
-- contato, que é onde o ciclo começa)
left join lateral (
  select l2.nome, l2.anuncio, l2.created_at
  from public.se_facebook_leads l2
  where v.email is not null
    and lower(trim(l2.email)) = v.email
  order by l2.created_at
  limit 1
) l on true

-- primeiro agendamento daquele lead, de qualquer período
left join lateral (
  select a2.data
  from mkt_se.vw_agendamentos a2
  where a2.email is not null
    and a2.email = v.email
  order by a2.data
  limit 1
) a on true

where v.data between p_ini and p_fim
  and (p_origens is null or v.origem = any(p_origens))
order by v.data desc, nome;
$function$;


CREATE OR REPLACE FUNCTION mkt_se.fn_formularios(p_ini date, p_fim date, p_origens text[] DEFAULT NULL::text[])
 RETURNS TABLE(formulario text, leads bigint, pct numeric, investimento numeric, cpl numeric)
 LANGUAGE sql
 STABLE
AS $function$
with ads as (
  select mkt_se.norm_chave(campanha) k, sum(gasto) g
  from mkt_se.vw_ads
  where data between p_ini and p_fim
    and (p_origens is null or origem = any(p_origens))
  group by 1
),
lds as (
  select
    mkt_se.norm_chave(campanha) k,
    coalesce(nullif(trim(id_formulario), ''), '(sem formulário)') as formulario,
    count(*) as n
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origens is null or origem = any(p_origens))
  group by 1, 2
),
-- total de leads por campanha, para saber a fatia de cada formulário
tot as (
  select k, sum(n) as n_total from lds group by k
),
rateio as (
  select
    l.formulario,
    sum(l.n)                                     as leads,
    sum(coalesce(a.g, 0) * l.n / t.n_total)      as investimento
  from lds l
  join tot t on t.k is not distinct from l.k
  left join ads a on a.k is not distinct from l.k
  group by l.formulario
),
-- gasto de campanha que não gerou lead: não há como ratear
sobra as (
  select coalesce(sum(a.g), 0) as g
  from ads a
  where not exists (select 1 from tot t where t.k is not distinct from a.k)
),
juntado as (
  select formulario, leads, investimento from rateio
  union all
  select '(não rateado)', 0::bigint, s.g from sobra s where s.g > 0
)
select
  formulario,
  leads,
  round(100.0 * leads / nullif(sum(leads) over (), 0), 1),
  round(investimento::numeric, 2),
  round(investimento / nullif(leads, 0), 2)
from juntado
order by leads desc, investimento desc;
$function$;


CREATE OR REPLACE FUNCTION mkt_se.fn_kpis(p_ini date, p_fim date, p_origens text[] DEFAULT NULL::text[], p_incluir_rmkt boolean DEFAULT true)
 RETURNS TABLE(dias integer, investimento numeric, impressoes bigint, cliques bigint, leads bigint, mql bigint, agendamentos bigint, agendas bigint, calls bigint, no_shows bigint, pendentes bigint, sem_registro bigint, vendas bigint, faturamento numeric, ctr numeric, pct_leads numeric, pct_mql numeric, pct_agend numeric, pct_comparecimento numeric, pct_no_show numeric, pct_conversao numeric, cpm numeric, cpc numeric, cpl numeric, cpmql numeric, cpa numeric, ccall numeric, cac numeric, roas numeric)
 LANGUAGE sql
 STABLE
AS $function$
with ads as (
  select
    coalesce(sum(gasto), 0)      as investimento,
    coalesce(sum(impressoes), 0) as impressoes,
    coalesce(sum(cliques), 0)    as cliques
  from mkt_se.vw_ads
  where data between p_ini and p_fim
    and (p_origens is null or origem = any(p_origens))
    and (p_incluir_rmkt or not retargeting)
    and not aquecimento
),
lead as (
  select count(*) as leads, count(*) filter (where mql) as mql
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origens is null or origem = any(p_origens))
    and (p_incluir_rmkt or not retargeting)
),
agen as (
  select
    count(*)                                            as agendamentos,  -- sessões
    count(distinct email)                               as agendas,       -- pessoas
    count(*) filter (where situacao = 'realizado')      as calls,
    count(*) filter (where situacao = 'no_show')        as no_shows,
    count(*) filter (where situacao = 'pendente')       as pendentes,
    count(*) filter (where situacao = 'sem_registro')   as sem_registro
  from mkt_se.vw_agendamentos
  where data between p_ini and p_fim
    and (p_origens is null or origem = any(p_origens))
),
vend as (
  select count(*) as vendas, coalesce(sum(valor), 0) as faturamento
  from mkt_se.vw_vendas
  where data between p_ini and p_fim
    and (p_origens is null or origem = any(p_origens))
)
select
  (p_fim - p_ini + 1)::integer,
  round(a.investimento::numeric, 2),
  a.impressoes, a.cliques, l.leads, l.mql,
  g.agendamentos, g.agendas, g.calls, g.no_shows, g.pendentes, g.sem_registro,
  v.vendas, round(v.faturamento::numeric, 2),

  round(100.0 * a.cliques      / nullif(a.impressoes, 0),           2),
  round(100.0 * l.leads        / nullif(a.cliques, 0),              2),
  round(100.0 * l.mql          / nullif(l.leads, 0),                2),
  round(100.0 * g.agendamentos / nullif(l.mql, 0),                  2),
  round(100.0 * g.calls        / nullif(g.calls + g.no_shows, 0),   2),
  round(100.0 * g.no_shows     / nullif(g.calls + g.no_shows, 0),   2),
  round(100.0 * v.vendas       / nullif(g.agendamentos, 0),         2),

  round(1000 * a.investimento  / nullif(a.impressoes, 0),   2),
  round(a.investimento         / nullif(a.cliques, 0),      2),
  round(a.investimento         / nullif(l.leads, 0),        2),
  round(a.investimento         / nullif(l.mql, 0),          2),
  round(a.investimento         / nullif(g.agendamentos, 0), 2),
  round(a.investimento         / nullif(g.calls, 0),        2),
  round(a.investimento         / nullif(v.vendas, 0),       2),
  round(v.faturamento          / nullif(a.investimento, 0), 2)
from ads a, lead l, agen g, vend v;
$function$;


CREATE OR REPLACE FUNCTION mkt_se.fn_origem(p_ini date, p_fim date, p_incluir_rmkt boolean DEFAULT true)
 RETURNS TABLE(origem text, investimento numeric, leads bigint, mql bigint, agendamentos bigint, calls bigint, vendas bigint, faturamento numeric, cpl numeric, cpmql numeric, cpa numeric, cac numeric, pct_mql numeric, pct_agend numeric)
 LANGUAGE sql
 STABLE
AS $function$
with base as (
  select origem from mkt_se.vw_ads
    where data between p_ini and p_fim
  union
  select origem from mkt_se.vw_leads
    where data between p_ini and p_fim
),
a as (
  select origem, sum(gasto) as investimento
  from mkt_se.vw_ads
  where data between p_ini and p_fim
    and (p_incluir_rmkt or not retargeting)
    and not aquecimento
  group by origem
),
l as (
  select origem, count(*) as leads, count(*) filter (where mql) as mql
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_incluir_rmkt or not retargeting)
  group by origem
),
g as (
  select origem,
         count(*) as agendamentos,
         count(*) filter (where situacao = 'realizado') as calls
  from mkt_se.vw_agendamentos
  where data between p_ini and p_fim
  group by origem
),
v as (
  select origem, count(*) as vendas, sum(valor) as faturamento
  from mkt_se.vw_vendas
  where data between p_ini and p_fim
  group by origem
)
select
  b.origem,
  round(coalesce(a.investimento, 0)::numeric, 2),
  coalesce(l.leads, 0),
  coalesce(l.mql, 0),
  coalesce(g.agendamentos, 0),
  coalesce(g.calls, 0),
  coalesce(v.vendas, 0),
  round(coalesce(v.faturamento, 0)::numeric, 2),
  round(a.investimento / nullif(l.leads, 0), 2),
  round(a.investimento / nullif(l.mql, 0), 2),
  round(a.investimento / nullif(g.agendamentos, 0), 2),
  round(a.investimento / nullif(v.vendas, 0), 2),
  round(100.0 * l.mql / nullif(l.leads, 0), 2),
  round(100.0 * g.agendamentos / nullif(l.mql, 0), 2)
from base b
left join a using (origem)
left join l using (origem)
left join g using (origem)
left join v using (origem)
order by coalesce(a.investimento, 0) desc;
$function$;


CREATE OR REPLACE FUNCTION mkt_se.fn_perfil_lead(p_ini date, p_fim date, p_origens text[] DEFAULT NULL::text[])
 RETURNS TABLE(tipo text, ordem integer, leads bigint)
 LANGUAGE sql
 STABLE
AS $function$
with base as (
  select data, hora
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origens is null or origem = any(p_origens))
),
-- dia da semana: 0 = domingo … 6 = sábado
dias as (
  select extract(dow from data)::integer as ordem, count(*) as n
  from base
  group by 1
),
-- horário: descarta o 00:00:00 exato e arredonda o resto para a hora cheia
horas as (
  select
    (
      (extract(hour from hora)::integer
        + case when extract(minute from hora) >= 30 then 1 else 0 end)
      % 24
    ) as ordem,
    count(*) as n
  from base
  where hora is not null
    and hora <> time '00:00:00'
  group by 1
)
select 'dia_semana', d.ordem, coalesce(x.n, 0)
from generate_series(0, 6) as d(ordem)
left join dias x on x.ordem = d.ordem

union all

select 'hora', h.ordem, coalesce(y.n, 0)
from generate_series(0, 23) as h(ordem)
left join horas y on y.ordem = h.ordem

union all

select 'sem_hora', 0, count(*)
from base
where hora is null or hora = time '00:00:00'

order by 1, 2;
$function$;


CREATE OR REPLACE FUNCTION mkt_se.fn_renda(p_ini date, p_fim date, p_origens text[] DEFAULT NULL::text[])
 RETURNS TABLE(faixa text, ordem integer, leads bigint, pct numeric)
 LANGUAGE sql
 STABLE
AS $function$
with base as (
  select faixa_renda, renda_piso
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origens is null or origem = any(p_origens))
),
agrupado as (
  select
    faixa_renda                        as faixa,
    coalesce(min(renda_piso), 999)     as ordem,
    count(*)                           as leads
  from base
  group by faixa_renda
)
select
  a.faixa,
  a.ordem::integer,
  a.leads,
  round(100.0 * a.leads / nullif(sum(a.leads) over (), 0), 1)
from agrupado a
order by a.ordem;
$function$;


CREATE OR REPLACE FUNCTION mkt_se.fn_serie_diaria(p_ini date, p_fim date, p_origens text[] DEFAULT NULL::text[], p_incluir_rmkt boolean DEFAULT false)
 RETURNS TABLE(data date, investimento numeric, impressoes bigint, cliques bigint, leads bigint, mql bigint, agendamentos bigint, calls bigint, vendas bigint, faturamento numeric)
 LANGUAGE sql
 STABLE
AS $function$
select
  d.dia,
  round(coalesce(a.gasto, 0)::numeric, 2),
  coalesce(a.impressoes, 0),
  coalesce(a.cliques, 0),
  coalesce(l.leads, 0),
  coalesce(l.mql, 0),
  coalesce(g.agendamentos, 0),
  coalesce(g.calls, 0),
  coalesce(v.vendas, 0),
  round(coalesce(v.faturamento, 0)::numeric, 2)
from generate_series(p_ini, p_fim, interval '1 day') as d(dia)

left join (
  select data,
         sum(gasto) as gasto,
         sum(impressoes) as impressoes,
         sum(cliques) as cliques
  from mkt_se.vw_ads
  where data between p_ini and p_fim
    and (p_origens is null or origem = any(p_origens))
    and (p_incluir_rmkt or not retargeting)
    and not aquecimento
  group by data
) a on a.data = d.dia::date

left join (
  select data,
         count(*) as leads,
         count(*) filter (where mql) as mql
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origens is null or origem = any(p_origens))
    and (p_incluir_rmkt or not retargeting)
  group by data
) l on l.data = d.dia::date

left join (
  select data,
         count(*) as agendamentos,
         count(*) filter (where situacao = 'realizado') as calls
  from mkt_se.vw_agendamentos
  where data between p_ini and p_fim
    and (p_origens is null or origem = any(p_origens))
  group by data
) g on g.data = d.dia::date

left join (
  select data,
         count(*) as vendas,
         sum(valor) as faturamento
  from mkt_se.vw_vendas
  where data between p_ini and p_fim
    and (p_origens is null or origem = any(p_origens))
  group by data
) v on v.data = d.dia::date

order by d.dia;
$function$;


CREATE OR REPLACE FUNCTION mkt_se.fn_trafego(p_ini date, p_fim date, p_origens text[] DEFAULT NULL::text[], p_incluir_rmkt boolean DEFAULT true)
 RETURNS TABLE(nivel text, chave text, campanha_pai text, conjunto_pai text, investimento numeric, impressoes bigint, cliques bigint, leads bigint, agendamentos bigint, vendas bigint, faturamento numeric, cpl numeric, cac numeric, qualif_50k numeric, hook numeric, hold numeric, body numeric)
 LANGUAGE sql
 STABLE
AS $function$
with
-- identificador único da linha: nível + pais + chave, tudo normalizado
ads_base as (
  select campanha, conjunto, anuncio, gasto, impressoes, cliques,
         video_3s, video_25, video_50
  from mkt_se.vw_ads
  where data between p_ini and p_fim
    and (p_origens is null or origem = any(p_origens))
    and (p_incluir_rmkt or not retargeting)
    and not aquecimento
),
ads as (
  select 'campanha' as nivel,
         'campanha||' || coalesce(mkt_se.norm_chave(campanha), '~') as id,
         max(campanha) nome, null::text pai_c, null::text pai_j,
         sum(gasto) g, sum(impressoes) imp, sum(cliques) cli,
         sum(video_3s) v3, sum(video_25) v25, sum(video_50) v50
  from ads_base group by 1, 2
  union all
  select 'conjunto',
         'conjunto|' || coalesce(mkt_se.norm_chave(campanha), '~')
                     || '|' || coalesce(mkt_se.norm_chave(conjunto), '~'),
         max(conjunto), max(campanha), null,
         sum(gasto), sum(impressoes), sum(cliques),
         sum(video_3s), sum(video_25), sum(video_50)
  from ads_base group by 1, 2
  union all
  select 'anuncio',
         'anuncio|' || coalesce(mkt_se.norm_chave(campanha), '~')
                    || '|' || coalesce(mkt_se.norm_chave(conjunto), '~')
                    || '|' || coalesce(mkt_se.norm_chave(anuncio), '~'),
         max(anuncio), max(campanha), max(conjunto),
         sum(gasto), sum(impressoes), sum(cliques),
         sum(video_3s), sum(video_25), sum(video_50)
  from ads_base group by 1, 2
),
leads_base as (
  select campanha, conjunto, anuncio, renda_piso
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origens is null or origem = any(p_origens))
    and (p_incluir_rmkt or not retargeting)
),
lds as (
  select 'campanha' as nivel,
         'campanha||' || coalesce(mkt_se.norm_chave(campanha), '~') as id,
         max(campanha) nome, null::text pai_c, null::text pai_j,
         count(*) n, count(*) filter (where renda_piso >= 50) q50
  from leads_base group by 1, 2
  union all
  select 'conjunto',
         'conjunto|' || coalesce(mkt_se.norm_chave(campanha), '~')
                     || '|' || coalesce(mkt_se.norm_chave(conjunto), '~'),
         max(conjunto), max(campanha), null,
         count(*), count(*) filter (where renda_piso >= 50)
  from leads_base group by 1, 2
  union all
  select 'anuncio',
         'anuncio|' || coalesce(mkt_se.norm_chave(campanha), '~')
                    || '|' || coalesce(mkt_se.norm_chave(conjunto), '~')
                    || '|' || coalesce(mkt_se.norm_chave(anuncio), '~'),
         max(anuncio), max(campanha), max(conjunto),
         count(*), count(*) filter (where renda_piso >= 50)
  from leads_base group by 1, 2
),
agd_base as (
  select campanha, conjunto, anuncio
  from mkt_se.vw_agendamentos
  where data between p_ini and p_fim
    and (p_origens is null or origem = any(p_origens))
),
agd as (
  select 'campanha||' || coalesce(mkt_se.norm_chave(campanha), '~') as id, count(*) n
  from agd_base group by 1
  union all
  select 'conjunto|' || coalesce(mkt_se.norm_chave(campanha), '~')
                     || '|' || coalesce(mkt_se.norm_chave(conjunto), '~'), count(*)
  from agd_base group by 1
  union all
  select 'anuncio|' || coalesce(mkt_se.norm_chave(campanha), '~')
                    || '|' || coalesce(mkt_se.norm_chave(conjunto), '~')
                    || '|' || coalesce(mkt_se.norm_chave(anuncio), '~'), count(*)
  from agd_base group by 1
),
vds_base as (
  select campanha, conjunto, anuncio, valor
  from mkt_se.vw_vendas
  where data between p_ini and p_fim
    and (p_origens is null or origem = any(p_origens))
),
vds as (
  select 'campanha||' || coalesce(mkt_se.norm_chave(campanha), '~') as id,
         count(*) n, sum(valor) v
  from vds_base group by 1
  union all
  select 'conjunto|' || coalesce(mkt_se.norm_chave(campanha), '~')
                     || '|' || coalesce(mkt_se.norm_chave(conjunto), '~'),
         count(*), sum(valor)
  from vds_base group by 1
  union all
  select 'anuncio|' || coalesce(mkt_se.norm_chave(campanha), '~')
                    || '|' || coalesce(mkt_se.norm_chave(conjunto), '~')
                    || '|' || coalesce(mkt_se.norm_chave(anuncio), '~'),
         count(*), sum(valor)
  from vds_base group by 1
),
chaves as (
  select id, max(nivel) nivel, max(nome) nome, max(pai_c) pai_c, max(pai_j) pai_j
  from (
    select id, nivel, nome, pai_c, pai_j from ads
    union all
    select id, nivel, nome, pai_c, pai_j from lds
  ) t
  group by id
)
select
  c.nivel,
  coalesce(nullif(trim(c.nome), ''), '(sem atribuição)'),
  nullif(trim(c.pai_c), ''),
  nullif(trim(c.pai_j), ''),
  round(coalesce(a.g, 0)::numeric, 2),
  coalesce(a.imp, 0)::bigint,
  coalesce(a.cli, 0)::bigint,
  coalesce(l.n, 0)::bigint,
  coalesce(g.n, 0)::bigint,
  coalesce(v.n, 0)::bigint,
  round(coalesce(v.v, 0)::numeric, 2),
  round(nullif(a.g, 0) / nullif(l.n, 0), 2),
  round(nullif(a.g, 0) / nullif(v.n, 0), 2),
  round(100.0 * l.q50 / nullif(l.n, 0), 1),
  round(100.0 * a.v3  / nullif(a.imp, 0), 1),
  round(100.0 * a.v25 / nullif(a.v3, 0), 1),
  round(100.0 * a.v50 / nullif(a.imp, 0), 1)
from chaves c
left join ads a using (id)
left join lds l using (id)
left join agd g using (id)
left join vds v using (id)
order by c.nivel, coalesce(a.g, 0) desc;
$function$;


CREATE OR REPLACE FUNCTION public.se_ciclo_vendas(p_ini date, p_fim date, p_origens text[] DEFAULT NULL::text[])
 RETURNS TABLE(nome text, anuncio text, data_criacao date, data_agendamento date, data_venda date, dias_cria_agen integer, dias_agen_venda integer, dias_cria_venda integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'mkt_se', 'public'
AS $function$ select * from mkt_se.fn_ciclo_vendas(p_ini, p_fim, p_origens); $function$;


CREATE OR REPLACE FUNCTION public.se_formularios(p_ini date, p_fim date, p_origens text[] DEFAULT NULL::text[])
 RETURNS TABLE(formulario text, leads bigint, pct numeric, investimento numeric, cpl numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'mkt_se', 'public'
AS $function$ select * from mkt_se.fn_formularios(p_ini, p_fim, p_origens); $function$;


CREATE OR REPLACE FUNCTION public.se_kpis(p_ini date, p_fim date, p_origens text[] DEFAULT NULL::text[], p_incluir_rmkt boolean DEFAULT true)
 RETURNS TABLE(dias integer, investimento numeric, impressoes bigint, cliques bigint, leads bigint, mql bigint, agendamentos bigint, agendas bigint, calls bigint, no_shows bigint, pendentes bigint, sem_registro bigint, vendas bigint, faturamento numeric, ctr numeric, pct_leads numeric, pct_mql numeric, pct_agend numeric, pct_comparecimento numeric, pct_no_show numeric, pct_conversao numeric, cpm numeric, cpc numeric, cpl numeric, cpmql numeric, cpa numeric, ccall numeric, cac numeric, roas numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'mkt_se', 'public'
AS $function$ select * from mkt_se.fn_kpis(p_ini, p_fim, p_origens, p_incluir_rmkt); $function$;


CREATE OR REPLACE FUNCTION public.se_origem(p_ini date, p_fim date, p_incluir_rmkt boolean DEFAULT true)
 RETURNS TABLE(origem text, investimento numeric, leads bigint, mql bigint, agendamentos bigint, calls bigint, vendas bigint, faturamento numeric, cpl numeric, cpmql numeric, cpa numeric, cac numeric, pct_mql numeric, pct_agend numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'mkt_se', 'public'
AS $function$ select * from mkt_se.fn_origem(p_ini, p_fim, p_incluir_rmkt); $function$;


CREATE OR REPLACE FUNCTION public.se_perfil_lead(p_ini date, p_fim date, p_origens text[] DEFAULT NULL::text[])
 RETURNS TABLE(tipo text, ordem integer, leads bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'mkt_se', 'public'
AS $function$ select * from mkt_se.fn_perfil_lead(p_ini, p_fim, p_origens); $function$;


CREATE OR REPLACE FUNCTION public.se_renda(p_ini date, p_fim date, p_origens text[] DEFAULT NULL::text[])
 RETURNS TABLE(faixa text, ordem integer, leads bigint, pct numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'mkt_se', 'public'
AS $function$ select * from mkt_se.fn_renda(p_ini, p_fim, p_origens); $function$;


CREATE OR REPLACE FUNCTION public.se_serie_diaria(p_ini date, p_fim date, p_origens text[] DEFAULT NULL::text[], p_incluir_rmkt boolean DEFAULT false)
 RETURNS TABLE(data date, investimento numeric, impressoes bigint, cliques bigint, leads bigint, mql bigint, agendamentos bigint, calls bigint, vendas bigint, faturamento numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'mkt_se', 'public'
AS $function$ select * from mkt_se.fn_serie_diaria(p_ini, p_fim, p_origens, p_incluir_rmkt); $function$;


CREATE OR REPLACE FUNCTION public.se_trafego(p_ini date, p_fim date, p_origens text[] DEFAULT NULL::text[], p_incluir_rmkt boolean DEFAULT true)
 RETURNS TABLE(nivel text, chave text, campanha_pai text, conjunto_pai text, investimento numeric, impressoes bigint, cliques bigint, leads bigint, agendamentos bigint, vendas bigint, faturamento numeric, cpl numeric, cac numeric, qualif_50k numeric, hook numeric, hold numeric, body numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'mkt_se', 'public'
AS $function$ select * from mkt_se.fn_trafego(p_ini, p_fim, p_origens, p_incluir_rmkt); $function$;


notify pgrst, 'reload schema';


-- ============================================================================
-- CONFERÊNCIA
-- ============================================================================
-- Nenhuma sobrecarga sobrou (cada função tem de aparecer UMA vez):
--   select p.proname, count(*) from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname in ('mkt_se','public') and p.proname like any(array['fn_%','se_%'])
--   group by 1 having count(*) > 1;
--
-- Múltipla escolha funciona:
--   select leads from mkt_se.fn_kpis('2026-01-01','2026-12-31');                        -- todas
--   select leads from mkt_se.fn_kpis('2026-01-01','2026-12-31', array['Forms Nativo']); -- só uma
--   select leads from mkt_se.fn_kpis('2026-01-01','2026-12-31',
--          array['Forms Nativo','Quiz','Typeform','Landing Page','Outros']);            -- sem VSL
--
-- Aquecimento fora do investimento:
--   select investimento from mkt_se.fn_kpis('2026-01-01','2026-12-31');
--   -- ~R$ 452.578 (os R$ 454.984 do arquivo 26 menos os R$ 2.405 de aquecimento)
-- ============================================================================
