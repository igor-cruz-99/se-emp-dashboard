# Dashboard — Sessão Estratégica (SE EMP)

Painel de tráfego e funil da Sessão Estratégica. React + Vite + TypeScript +
Tailwind v4, dados no Supabase, protegidos por uma função serverless que valida
a sessão antes de consultar o banco.

## Rodar

```bash
npm install
npm run dev          # http://localhost:5185
```

Precisa de um `.env.local` (copie de `.env.example`). Ele **não** vai para o git.

| variável | para que serve |
|---|---|
| `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE` | Business Data — só no servidor, **nunca** com prefixo `VITE_` |
| `VITE_SUPABASE_AUTH_URL` / `VITE_SUPABASE_AUTH_ANON_KEY` | projeto de auth (funcionários), usado só no login |
| `SUPABASE_AUTH_URL` / `SUPABASE_AUTH_ANON_KEY` | os mesmos, para o porteiro validar o token |
| `DASHBOARD_ALLOWED_DOMAINS` / `_EMAILS` | quem pode entrar — estar logado não basta |
| `HOST_*` / `USER_*` / `SENHA_*` / `SENHA_FDW` | só para gerar os SQL de infraestrutura |
| `VITE_DEV_SKIP_AUTH` + `DEV_SKIP_AUTH` | `1` pula o login em dev. **Voltar para `0` antes de publicar** |

## Arquitetura

```
                        LOGIN
Navegador ─────────────────────────► Supabase AUTH (funcionários)
    │
    │      DADOS (com o token da sessão)
    └──► /api/dashboard ──valida──► Business Data (service_role)
         (serverless)               RPCs se_* no schema public
```

O navegador nunca toca o banco de dados. Todo cálculo mora em RPC no Postgres.

### De onde vêm os dados

Três projetos Supabase, unificados no **Business Data** por `postgres_fdw` +
`pg_cron` (espelhos atualizados a cada 15 min):

| origem | conteúdo | como chega |
|---|---|---|
| **Anchor** `sfxbz…` | `core.ads_metrics` (tráfego de toda a Quarta Via) | espelho filtrado para o SE |
| **Business Data** `rckpu…` | `se_facebook_leads`, schema `bitrix` (CRM antigo) | nativo |
| **Backup BASE QV** `lacin…` | `crm_leads`, `crm_meetings`, `contratos_pharus` | espelho |

O Anchor está com a RAM sobrecarregada: por isso espelhamos em vez de consultar
ao vivo — ele recebe uma consulta a cada 15 min, não uma por carregamento.

## ⚠️ Limites conhecidos dos dados

- **Julho/2026 não tem agendamento nem venda.** A Bitrix parou em 26/06 e o CRM
  novo começou em 01/08 — nenhum sistema registrou o mês. O painel avisa na tela
  quando o período selecionado cruza essa lacuna.
- **Junho/2026 está pela metade**: 58 agendamentos, só 3 com desfecho.
- **Topo de funil (investimento, leads, CPL) está íntegro** o ano todo.
- **`%MQL` fica em ~99%**: com as faixas de renda atuais, quase todo lead passa
  do corte de 20 mil. O sinal útil está no mix de faixas, não no total.

## Banco

Os arquivos em `sql/` são o histórico da modelagem — rodar em ordem num banco
novo. Os que têm `<<PLACEHOLDER>>` precisam do gerador:

```bash
npm run sql          # lê .env.local, escreve sql/.gerado/*.local.sql
```

| # | arquivo | onde roda |
|---|---|---|
| 00 | `roles_remotos` | Parte A no Anchor, Parte B no Backup QV |
| 01 | `fdw` | Business Data |
| 02 | `fdw_crm` | Business Data |
| 03 | `limpeza_espelhos` | Business Data |
| 04 | `views` | Business Data |
| 05 | `funil_unificado` | Business Data |
| 06 | `sonda` | Business Data (ferramenta de dev, removível) |
| 07 | `rpcs` | Business Data |
| 08 | `ponte_public` | Business Data |
| 09 | `ajuste_data_agendamento` | Business Data |
| 10 | `metas` | Business Data |

Conferir o banco sem abrir o SQL Editor:

```bash
npm run check "select * from mkt_se.fn_kpis('2026-08-01','2026-08-12')"
```

## Metas

Editáveis no banco, sem redeploy:

```sql
update mkt_se.metas set valor = 45 where chave = 'cpl';
```

A coluna `direcao` (`maior`/`menor`) é o que faz o CPL ficar verde quando
**cai** — sem ela o painel premiaria o custo subindo.

## Estrutura

```
src/
├── components/   ui · kpi · funnel · charts · layout
├── pages/        Dashboard · Login
├── hooks/        useAuth · useDashboardData
├── lib/          queries (todo fetch) · supabase (só auth) · devAuth
├── utils/        format (pt-BR) · metaColor
└── types/        contratos das RPCs
api/dashboard.ts  o porteiro
sql/              modelagem do banco
scripts/          gerar-sql · check
```
