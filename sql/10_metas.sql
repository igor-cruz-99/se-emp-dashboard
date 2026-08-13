-- ============================================================================
-- SE EMP — 10. Metas + troca de No-Show por Comparecimento
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- Duas mudanças:
--   1. Tabela de metas, lida pelo painel para colorir os badges dos cards.
--   2. fn_kpis passa a devolver `pct_comparecimento` (realizadas sobre as que
--      tiveram desfecho). Trocar no-show por comparecimento inverte o sentido:
--      vira "maior é melhor", que é como o gestor lê.
--
-- ⚠️ Ao mexer no retorno de fn_kpis é obrigatório recriar public.se_kpis
--    junto — por isso as duas estão no mesmo arquivo. Se só uma for aplicada,
--    a ponte quebra com "return type mismatch".
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Metas
--    `direcao` diz para que lado o número é bom. Sem isso o painel pintaria
--    CPL de verde quando ele SOBE — o erro clássico de métrica de custo.
-- ----------------------------------------------------------------------------
create table if not exists mkt_se.metas (
  chave         text primary key,
  rotulo        text    not null,
  valor         numeric not null,
  direcao       text    not null check (direcao in ('maior', 'menor')),
  formato       text    not null check (formato in ('moeda', 'percentual', 'numero')),
  atualizado_em timestamptz not null default now()
);

alter table mkt_se.metas enable row level security;

insert into mkt_se.metas (chave, rotulo, valor, direcao, formato) values
  ('cpl',                'CPL',            50, 'menor', 'moeda'),
  ('pct_mql',            '%MQL',           80, 'maior', 'percentual'),
  ('pct_comparecimento', 'Comparecimento', 70, 'maior', 'percentual'),
  ('pct_conversao',      'Conversão',      10, 'maior', 'percentual')
on conflict (chave) do update
  set rotulo  = excluded.rotulo,
      valor   = excluded.valor,
      direcao = excluded.direcao,
      formato = excluded.formato,
      atualizado_em = now();


-- ----------------------------------------------------------------------------
-- 2. fn_kpis com comparecimento
--
--    pct_comparecimento = realizadas / (realizadas + no_show)
--    O denominador exclui as pendentes de propósito: sessão que ainda não
--    aconteceu não é ausência. Contá-la derrubaria o comparecimento sempre que
--    houvesse agenda futura — e a crm_meetings tem sessões até 31/08.
--
--    Referência de sanidade: Bitrix 74,2% · CRM 73,4%. Eras e sistemas
--    diferentes chegando ao mesmo número.
--
--    pct_conversao = vendas / agendamentos.
--    ⚠️ Definição a confirmar: sobre LEADS daria 0,58% hoje (meta 10% seria
--    inatingível); sobre AGENDAMENTOS dá 12,9%, coerente com a meta.
-- ----------------------------------------------------------------------------
drop function if exists mkt_se.fn_kpis(date, date, text, boolean);

create or replace function mkt_se.fn_kpis(
  p_ini           date,
  p_fim           date,
  p_origem        text    default null,
  p_incluir_rmkt  boolean default false
)
returns table (
  dias integer, investimento numeric, impressoes bigint, cliques bigint,
  leads bigint, mql bigint, agendamentos bigint, calls bigint, no_shows bigint,
  pendentes bigint, vendas bigint, faturamento numeric,
  ctr numeric, pct_leads numeric, pct_mql numeric, pct_agend numeric,
  pct_comparecimento numeric, pct_no_show numeric, pct_conversao numeric,
  cpm numeric, cpc numeric, cpl numeric, cpmql numeric,
  cpa numeric, ccall numeric, cac numeric, roas numeric
)
language sql
stable
as $$
with ads as (
  select
    coalesce(sum(gasto), 0)      as investimento,
    coalesce(sum(impressoes), 0) as impressoes,
    coalesce(sum(cliques), 0)    as cliques
  from mkt_se.vw_ads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and (p_incluir_rmkt or (not retargeting and origem <> 'Engajamento'))
),
lead as (
  select count(*) as leads, count(*) filter (where mql) as mql
  from mkt_se.vw_leads
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
    and (p_incluir_rmkt or not retargeting)
),
agen as (
  select
    count(*)                                       as agendamentos,
    count(*) filter (where situacao = 'realizado') as calls,
    count(*) filter (where situacao = 'no_show')   as no_shows,
    count(*) filter (where situacao = 'pendente')  as pendentes
  from mkt_se.vw_agendamentos
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
),
vend as (
  select count(*) as vendas, coalesce(sum(valor), 0) as faturamento
  from mkt_se.vw_vendas
  where data between p_ini and p_fim
    and (p_origem is null or origem = p_origem)
)
select
  (p_fim - p_ini + 1)::integer,
  round(a.investimento::numeric, 2),
  a.impressoes, a.cliques, l.leads, l.mql,
  g.agendamentos, g.calls, g.no_shows, g.pendentes,
  v.vendas, round(v.faturamento::numeric, 2),

  round(100.0 * a.cliques      / nullif(a.impressoes, 0),           2),
  round(100.0 * l.leads        / nullif(a.cliques, 0),              2),
  round(100.0 * l.mql          / nullif(l.leads, 0),                2),
  round(100.0 * g.agendamentos / nullif(l.mql, 0),                  2),
  round(100.0 * g.calls        / nullif(g.calls + g.no_shows, 0),   2),  -- comparecimento
  round(100.0 * g.no_shows     / nullif(g.calls + g.no_shows, 0),   2),  -- no-show
  round(100.0 * v.vendas       / nullif(g.agendamentos, 0),         2),  -- conversão

  round(1000 * a.investimento  / nullif(a.impressoes, 0),   2),
  round(a.investimento         / nullif(a.cliques, 0),      2),
  round(a.investimento         / nullif(l.leads, 0),        2),
  round(a.investimento         / nullif(l.mql, 0),          2),
  round(a.investimento         / nullif(g.agendamentos, 0), 2),
  round(a.investimento         / nullif(g.calls, 0),        2),
  round(a.investimento         / nullif(v.vendas, 0),       2),
  round(v.faturamento          / nullif(a.investimento, 0), 2)
from ads a, lead l, agen g, vend v;
$$;

revoke all on function mkt_se.fn_kpis(date, date, text, boolean) from public, anon, authenticated;
grant execute on function mkt_se.fn_kpis(date, date, text, boolean) to service_role;


-- ----------------------------------------------------------------------------
-- 3. Pontes no public (assinatura tem de acompanhar a de cima)
-- ----------------------------------------------------------------------------
drop function if exists public.se_kpis(date, date, text, boolean);

create or replace function public.se_kpis(
  p_ini date, p_fim date, p_origem text default null, p_incluir_rmkt boolean default false
)
returns table (
  dias integer, investimento numeric, impressoes bigint, cliques bigint,
  leads bigint, mql bigint, agendamentos bigint, calls bigint, no_shows bigint,
  pendentes bigint, vendas bigint, faturamento numeric,
  ctr numeric, pct_leads numeric, pct_mql numeric, pct_agend numeric,
  pct_comparecimento numeric, pct_no_show numeric, pct_conversao numeric,
  cpm numeric, cpc numeric, cpl numeric, cpmql numeric,
  cpa numeric, ccall numeric, cac numeric, roas numeric
)
language sql
stable
security definer
set search_path = mkt_se, public
as $$ select * from mkt_se.fn_kpis(p_ini, p_fim, p_origem, p_incluir_rmkt); $$;

create or replace function public.se_metas()
returns table (chave text, rotulo text, valor numeric, direcao text, formato text)
language sql
stable
security definer
set search_path = mkt_se, public
as $$ select chave, rotulo, valor, direcao, formato from mkt_se.metas order by chave; $$;

revoke all on function public.se_kpis(date, date, text, boolean) from public, anon, authenticated;
revoke all on function public.se_metas()                         from public, anon, authenticated;
grant execute on function public.se_kpis(date, date, text, boolean) to service_role;
grant execute on function public.se_metas()                         to service_role;

notify pgrst, 'reload schema';


-- ============================================================================
-- CONFERÊNCIA
-- ============================================================================
--   select * from mkt_se.metas;
--   select * from mkt_se.fn_kpis('2026-08-01', '2026-08-12');
-- ============================================================================
