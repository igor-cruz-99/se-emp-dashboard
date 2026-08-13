# Roadmap — Dashboard Sessão Estratégica

## Pronto

- **KPIs, funil, série diária** (`fn_kpis`, `fn_serie_diaria`)
- **Metas** com cor por atingimento (`mkt_se.metas`, editável por SQL)
- **Seção Origem**: origem dos leads · investimento por origem · rosca de renda
- **Seção Análise**: tráfego por campanha → conjunto → anúncio (busca, mapa de
  calor, ordenação, total) · ciclo de vendas · perfil do lead (dia da semana e
  horário)
- **Matriz de visão macro**: ano mês a mês + combo leads × CPL. Não segue o
  filtro de período (hook próprio, busca uma vez)
- **Agendamentos de 2026 vindos da planilha** (`mrk_backup_se.mkt_agendamento_2026`,
  4.691 linhas carregadas do CSV): junho saiu de 58 → 247 e julho de 0 → 254
- **`mv_agendamentos` materializada** + `pg_cron`: a view levava 6,3 s e
  segurava a página inteira; agora 0,5 s

Os quatro blocos batem entre si — conferido: KPIs e os três níveis da tabela de
tráfego dão o mesmo investimento, leads, agendamentos e vendas.

## Próximo

- **Bloco de qualificação no tempo**: a rosca mostra o mix de renda do período;
  falta a evolução mês a mês e o cruzamento com origem.
- **Normalizar `renda_de_investimento`**: a coluna mistura duas perguntas de
  versões diferentes do formulário (reserva acumulada e aporte mensal), em ~20
  grafias. Separar em `reserva_faixa` e `aporte_mensal_faixa`, classificando
  pela escala do número, não pelo texto. Falta a lista completa de valores
  distintos de `renda_de_investimento` e `disposto_a_investir`.

## Pendências com o Igor

- [ ] **Denominador da conversão.** Está em `vendas ÷ agendamentos` (5,3% em
      agosto, contra a meta de 10%). Se for sobre leads, o real é ~1% e a meta
      muda junto.
- [ ] **`logo.png`** em `public/` — hoje há um "SE" em texto no Login.
- [x] ~~Export de julho/2026~~ — resolvido pelo CSV da planilha de agendamentos.
- [ ] **Desfecho (realizado/no-show) de jun–jul/2026.** A planilha só traz
      "Agendada"; a Bitrix já não era alimentada. O comparecimento desses meses
      sai de 8 e 7 casos em 247 e 254 — o badge fica sem cor por isso. Se
      existir export do CRM antigo com status, fecha.
- [ ] **Leads: linha ou pessoa?** Hoje conta linhas. Em janeiro são 2.065
      registros para 1.822 emails únicos; mudar sobe o CPL ~13%.
- [x] ~~**`VITE_DEV_SKIP_AUTH` e `DEV_SKIP_AUTH` em `1`**~~ — não é risco de
      publicação: o front tranca em `import.meta.env.DEV` (some do bundle) e o
      `api/dashboard.ts` tranca em `NODE_ENV !== 'production'`. Conferido no
      bundle de produção e na URL publicada: cai no login. As duas variáveis
      podem ficar em `1` no `.env.local` sem afetar a Vercel.
- [x] ~~**Deploy na Vercel**~~ — ver "Publicação" abaixo.
- [ ] **Rotacionar a `service_role`** do Business Data (ver dívidas técnicas).
- [x] ~~**Rodar `sql/30_fechar_sondas.sql`**~~ — feito em 13/08/2026. Conferido:
      `se_q` devolve 404 (PGRST202) e as RPCs do painel seguem em 200.
- [ ] **Ligar o GitHub na conta Vercel** para voltar o deploy automático —
      hoje é manual (`npx vercel --prod`). Ver "Publicação".

## Publicação

- Repositório: `igor-cruz-99/se-emp-dashboard` (**público**, mesma razão do WEP:
  na conta Hobby, repo privado bloqueia deploy quando o autor do commit não é
  membro da conta Vercel).
- Projeto Vercel: `igorcruz-2142s-projects/se-emp-dashboard`.
- URL: <https://se-emp-dashboard.vercel.app>
- Variáveis em Production e Preview: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE`,
  `SUPABASE_AUTH_URL`, `SUPABASE_AUTH_ANON_KEY`, `VITE_SUPABASE_AUTH_URL`,
  `VITE_SUPABASE_AUTH_ANON_KEY`, `DASHBOARD_ALLOWED_DOMAINS`.
  **`DEV_SKIP_AUTH` não está lá e não deve ir.**

⚠️ **O deploy NÃO é automático.** `vercel git connect` falhou com "You need to
add a Login Connection to your GitHub account first" — a conta Vercel não tem
o GitHub ligado como método de login. Enquanto isso não for feito no painel da
Vercel, `git push` publica no GitHub mas **não republica o site**. Para publicar
uma versão nova:

```
npm run build && npx vercel --prod
```

## Armadilhas já encontradas (não repetir)

- **`join ... using (k)` descarta linha com chave NULA** — em SQL, `null = null`
  não é verdadeiro. Isso escondeu uma venda inteira da tabela de tráfego, sem
  erro nenhum. Sempre normalizar a chave para um rótulo antes de agrupar.
- **Ads e leads escrevem o nome da campanha diferente** (underscore × espaço).
  Todo cruzamento entre os dois lados passa por `mkt_se.norm_chave()`.
- **Filtro de retargeting tem de ser igual em todas as RPCs.** Um bloco
  contando diferente do outro derruba a confiança no painel inteiro.
- **Conferir todo bloco novo contra o `fn_kpis`** antes de dar por pronto. Os
  três bugs acima só apareceram assim.
- **`bitrix.timeline_agendamentos` e `timeline_master` são views** — não aceitam
  índice.
- **O SQL Editor roda o script inteiro numa transação.** Um erro no fim desfaz o
  começo; por isso os arquivos com partes arriscadas ficam separados.

## Dívidas técnicas conhecidas

- **`sql/08_ponte_public.sql` repete a lista de colunas** das `fn_*`. Mudou o
  retorno no `07` ou no `10`? Tem que mudar a ponte junto, senão quebra com
  "return type mismatch". Existe porque o "Exposed schemas" deste projeto
  Supabase não aceita schemas novos.
- **`mkt_se.q(sql)` e `public.se_q(sql)`** são ferramentas de desenvolvimento
  (executam SELECT vindo de fora, com trava `STABLE`). ⚠️ A `se_q` é
  `security definer` e pertence ao `postgres`: quem consegue chamá-la roda
  comando **com poder de dono do banco**, não com o poder de quem chamou. Só a
  `service_role` tem execute, e ela não está na allowlist do `api/dashboard.ts`
  — mas a `service_role` passou pelo histórico de conversa. A `mkt_se.q` é o
  caso menor (não é definer, e o `mkt_se` não está exposto na API), porém está
  com execute para `anon`/`authenticated`: vira SQL aberto no dia em que
  alguém expuser o schema. **Fechar com `sql/30_fechar_sondas.sql`.**
- **A `service_role` do Business Data e as senhas dos bancos de origem**
  passaram pelo histórico de conversa. Vale rotacionar a `service_role` antes de
  publicar.
