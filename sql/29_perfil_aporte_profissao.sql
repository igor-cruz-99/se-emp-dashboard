-- ============================================================================
-- SE EMP — 29. Perfil do lead ganha aporte mensal e profissão
--
-- ⚠️ RODAR NO BUSINESS DATA. Sem senha, cola direto.
--
-- Dois recortes novos na seção "Perfil do lead", vindos de campos que já
-- estavam em `se_facebook_leads` mas nunca tinham sido expostos:
--
--   `disposto_a_investir` → quanto o lead diz que consegue aportar POR MÊS.
--   `profissao`           → lista fechada de 9 opções + 'Outro'.
--
-- ⚠️ `disposto_a_investir` NÃO é renda nem reserva. É o aporte mensal — a
--    mesma confusão que já apareceu em `renda_de_investimento` (ver a pendência
--    de normalização no ROADMAP). Por isso o rótulo na tela é "Aporte mensal
--    declarado", não "renda": chamar de renda faria o gestor comparar com a
--    rosca de faixa de renda ao lado, que mede outra coisa.
--
-- Os dois campos estão LIMPOS na origem — nenhuma variante de grafia, porque
-- vêm de select fechado no formulário. Conferido em 13/08/2026:
--   aporte:    5 valores + 135 nulos
--   profissão: 9 valores + 'Outro' + 118 nulos
-- Não precisa de normalizador; se um dia entrar texto livre, isso muda.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. vw_leads passa a carregar os dois campos
--    `create or replace view` só aceita coluna NOVA no fim — por isso vão
--    depois de `retargeting` em vez de perto de `renda`, onde caberiam melhor.
-- ----------------------------------------------------------------------------
create or replace view mkt_se.vw_leads as
select
  l.id,
  l.data,
  l.hora,
  lower(trim(l.email))                 as email,
  l.nome,
  l.telefone,
  l.campanha,
  l.conjunto,
  l.anuncio,
  l.tag_origem,
  l.id_formulario,
  l.funil,
  l.renda,
  mkt_se.piso_renda(l.renda)           as renda_piso,
  case
    when mkt_se.piso_renda(l.renda) is null then 'Não informado'
    when mkt_se.piso_renda(l.renda) >= 100  then '100k+'
    when mkt_se.piso_renda(l.renda) >= 50   then '50–100k'
    when mkt_se.piso_renda(l.renda) >= 30   then '30–50k'
    when mkt_se.piso_renda(l.renda) >= 20   then '20–29k'
    else '<20k'
  end                                  as faixa_renda,
  coalesce(mkt_se.piso_renda(l.renda) >= 20, false) as mql,
  case
    when l.campanha is not null and l.campanha <> ''
      then mkt_se.origem_campanha(l.campanha)
    else mkt_se.origem_campanha(l.tag_origem)
  end                                  as origem,
  mkt_se.eh_retargeting(l.campanha)    as retargeting,
  -- Vazio vira NULL aqui, num lugar só: assim quem consome não precisa
  -- lembrar de testar `<> ''` além de `is not null`.
  nullif(trim(l.disposto_a_investir), '') as aporte_mensal,
  nullif(trim(l.profissao), '')           as profissao
from public.se_facebook_leads l
where l.email is not null
  and l.email <> '';


-- ----------------------------------------------------------------------------
-- 2. Ordem do aporte
--    Dado ORDINAL: o gráfico tem de ir do menor para o maior, não por volume.
--    'Não consigo poupar' é o piso da escala (aporte zero), não uma categoria
--    "sem resposta" — quem marcou isso respondeu.
-- ----------------------------------------------------------------------------
create or replace function mkt_se.ordem_aporte(p text)
returns integer
language sql
immutable
as $$
  select case p
    when 'Não consigo poupar'          then 0
    when 'Até R$ 2.000'                then 1
    when 'Entre R$ 2.000 e R$ 5.000'   then 2
    when 'Entre R$ 5.000 e R$ 10.000'  then 3
    when 'Acima de R$ 10.000'          then 4
    else 99  -- opção nova no formulário cai no fim em vez de sumir
  end;
$$;


-- ----------------------------------------------------------------------------
-- 3. fn_perfil_lead devolve também 'aporte' e 'profissao'
--
--    ⚠️ Muda o TIPO DE RETORNO (entra a coluna `rotulo`), então precisa de
--    drop antes do create — `create or replace` não altera assinatura de
--    retorno. Como a ponte no public depende dela, as duas caem juntas.
--
--    Por que na mesma função e não numa nova: são quatro recortes do MESMO
--    conjunto de leads, com o mesmo filtro. Separar em duas RPCs dobraria as
--    idas ao banco e abriria espaço para os filtros divergirem em silêncio —
--    exatamente o tipo de erro que já custou caro neste projeto.
--
--    `rotulo` é NULL em 'dia_semana'/'hora'/'sem_hora': lá quem nomeia é o
--    front (nome do dia, "14:00"), a partir de `ordem`.
-- ----------------------------------------------------------------------------
drop function if exists public.se_perfil_lead(date, date, text[]);
drop function if exists mkt_se.fn_perfil_lead(date, date, text[]);

create function mkt_se.fn_perfil_lead(
  p_ini     date,
  p_fim     date,
  p_origens text[] default null
)
returns table (
  tipo   text,
  ordem  integer,
  rotulo text,
  leads  bigint
)
language sql
stable
as $$
with base as (
  select data, hora, aporte_mensal, profissao
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
),
-- aporte: sem vazios, na ordem da escala
aporte as (
  select aporte_mensal as r, mkt_se.ordem_aporte(aporte_mensal) as ordem, count(*) as n
  from base
  where aporte_mensal is not null
  group by 1, 2
),
-- profissão: sem vazios, do mais frequente para o menos
prof as (
  select
    profissao as r,
    count(*)  as n,
    (row_number() over (order by count(*) desc, profissao))::integer as ordem
  from base
  where profissao is not null
  group by 1
)
select 'dia_semana', d.ordem, null::text, coalesce(x.n, 0)
from generate_series(0, 6) as d(ordem)
left join dias x on x.ordem = d.ordem

union all

select 'hora', h.ordem, null::text, coalesce(y.n, 0)
from generate_series(0, 23) as h(ordem)
left join horas y on y.ordem = h.ordem

union all

select 'sem_hora', 0, null::text, count(*)
from base
where hora is null or hora = time '00:00:00'

union all

select 'aporte', a.ordem, a.r, a.n from aporte a

union all

select 'profissao', p.ordem, p.r, p.n from prof p

order by 1, 2;
$$;

revoke all on function mkt_se.fn_perfil_lead(date, date, text[]) from public, anon, authenticated;
grant execute on function mkt_se.fn_perfil_lead(date, date, text[]) to service_role;


-- ----------------------------------------------------------------------------
-- 4. Ponte no public
--    ⚠️ A lista de colunas tem de ser redeclarada inteira — `returns setof
--    mkt_se.fn_perfil_lead` não existe para função que devolve table.
-- ----------------------------------------------------------------------------
create function public.se_perfil_lead(
  p_ini date, p_fim date, p_origens text[] default null
)
returns table (tipo text, ordem integer, rotulo text, leads bigint)
language sql
stable
security definer
set search_path = mkt_se, public
as $$ select * from mkt_se.fn_perfil_lead(p_ini, p_fim, p_origens); $$;

revoke all on function public.se_perfil_lead(date, date, text[]) from public, anon, authenticated;
grant execute on function public.se_perfil_lead(date, date, text[]) to service_role;

notify pgrst, 'reload schema';


-- ============================================================================
-- CONFERÊNCIA
-- ============================================================================
-- 1) Os quatro recortes existem e os dois novos somam <= leads do período:
--   select tipo, sum(leads) from mkt_se.fn_perfil_lead('2026-08-01','2026-08-31')
--    group by 1 order by 1;
--   select leads from mkt_se.fn_kpis('2026-08-01','2026-08-31');
--   -- 'dia_semana' tem de bater exato com fn_kpis.
--   -- 'aporte' e 'profissao' ficam ABAIXO: são os que responderam.
--
-- 2) Nenhuma opção caiu no balde 99 (formulário mudou?):
--   select * from mkt_se.fn_perfil_lead('2026-01-01', current_date)
--    where tipo = 'aporte' and ordem = 99;
--   -- tem de vir vazio
-- ============================================================================
