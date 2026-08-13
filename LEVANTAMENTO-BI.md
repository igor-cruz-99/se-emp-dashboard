# Levantamento do BI atual — Sessão Estratégica (SE EMP)

Origem: `C:\Users\Admin\Desktop\QV\SE-EMP - Dashboad geral.pbix` (8,5 MB, mod. 06/08/2026).

O `.pbix` é um zip. Foi possível ler **estrutura, tabelas, colunas, medidas e páginas**.
**Não** foi possível ler o **DAX** das medidas nem as **linhas de dados** — o `DataModel`
vem comprimido em XPress9 (formato fechado da Microsoft). As regras de negócio abaixo
vieram do Igor, não do arquivo.

---

## 1. Regras de negócio (confirmadas pelo Igor)

| Conceito | Regra |
|---|---|
| **MQL** | Lead com `renda >= 20.000` |
| **Total Agendamentos Únicos** | Dedup por **email** — o mesmo lead pode agendar várias vezes, conta 1 |
| **Calls Realizadas** / **Total Agendas** | Vêm de tabela em **outro projeto Supabase** |
| **Total Vendas Pharus** | Vem de tabela em **outro projeto Supabase** |
| **Hook Rate** / **% Retenção** | Métricas de **vídeo do anúncio** (Meta Ads) |

## 2. Identidade

- Nome: **Sessão Estratégica** (SE EMP)
- Modelo: **funil perpétuo** (não é lançamento) → sem `tag`/`inicio_cap`/`final_cap`
- Fontes de lead: **Forms Nativo**, **InLead**, **Typeform**, **Google Ads**, outras
- Sem páginas, sem pesquisa (ao contrário do WEP)
- Cores: cinza escuro, azul royal fluorescente, detalhes em branco

---

## 3. Modelo de dados do BI (27 tabelas)

### Fatos

| Tabela | Papel | Colunas vistas |
|---|---|---|
| `fMétricas_Ads` | Meta Ads | `Custo`, `Impressions`, `Campaign Name`, `Ad Set Name`, `Ad Name` |
| `fGoogleAds` | Google Ads | `Impressions`, `Campaign/Ad Set/Ad Name` |
| `fse_facebook_leads` | Leads | `email`, `nome`, `renda`, `renda_de_investimento`, `tag_origem`, `id_formulario`, `anuncio`, `campanha`, `conjunto`, `data 2`, `Hora`, `hora redonda` |
| `fAgendamentos` | Agendas | `Nome`, `Email`, `Origem`, `Nome SDR`, `Closer`, `Data Entrada`, `Hora Entrada`, `Campanha_FB 2`, `Anuncio_FB 2`, `Anuncio_Conjunto` |
| `fVendas` | Vendas | `data_de_venda`, `Data Criação`, `Data Agendamento`, `utm_content`, `title`, `Tempo Cria p Agen`, `Tempo Agen p Venda`, `Tempo Cria p Venda` |
| `fBotãoQuiz` | Cliques no botão (InLead) | — |
| `fAgendas`, `fPáginas`, `fDados_raw`, `fAds-Thumbs`, `ads_hora`, `RetencaoEixos` | apoio | — |

### Dimensões

`dCalendário` (`Data`, `DiaSemana`) · `dHora` (`Hora_ID`) · `dCampanhas` · `dConjunto` ·
`dAnúncio` · `dEmails` · `dTag_ID` (`id_formulario` → origem) · `dMétricas`

### Metas

`fMetas` + `Metas D` / `Metas M` / `Metas S` (diária / mensal / semanal), colunas:
`INVESTIMENTO`, `MQL`, `AGENDAMENTOS`, `CALLS`, `VENDAS`, `FATURAMENTO`.
Medidas de meta: `P <x>` (previsto) e `G. <x>` (gap/atingimento).

---

## 4. Funil medido

```
Impressões → Cliques → Leads → MQL → Agendamentos → Calls Realizadas → Vendas → Faturamento
```

**Taxas:** `%LEADS`, `%MQL`, `% Agen`, `%Compa` (comparecimento), `%Conv. Pharus`
**Custos:** `CPM`, `CPC`, `CPL`, `CPMQL`, `$Cust/Agen`, `$ Cust/Call`, `CAC`
**Vídeo:** `Hook Rate`, `% Retenção`
**InLead:** `Contagem Leads Botão`, `MQL Clicks`, `%Clicks Botão`, `%MQL Clicks`, `%InLead`

## 5. Medidas duplicadas por origem (o anti-padrão a eliminar)

O BI cria uma medida por fonte em vez de tratar origem como dimensão:

`Leads Forms Nativo` · `Leads InLead` · `Leads Google` · `CPL forms` · `CPL InLead` ·
`CPL Google` · `Investimento Forms Nativo` · `Investimento InLead` · `Investimento Google` ·
`CPMQL fn` · `CPMQL il` · `CPC InLead` · `CPC Google` · `CPVP Google` · `Cliques Google` ·
`Video Plays Google`

→ No Postgres vira **`fn_kpis(p_origem)`** + `group by origem`. Uma RPC no lugar de ~16 medidas.

---

## 6. Páginas do BI (14) → blocos do dashboard novo

| Página | Visuais | Vira |
|---|---|---|
| Metas | 6 cards + 7 shapes | Metas embutidas nos `KpiCard` |
| Métricas Geral | 24 cards | **Grid de KPIs** (com filtro de origem) |
| Métricas VSL | 24 cards | idem (duplicata) |
| Duplicata de Métricas HP | 24 cards | idem (duplicata) |
| Matriz geral | pivot + combo | **`TrafficTable`** + série diária |
| Matriz de Anúncios InLead | 3 pivots | `TrafficTable` filtrada |
| Matriz de Anúncios Forms | 3 pivots | `TrafficTable` filtrada |
| Ciclo de vendas | tabela | **Bloco de ciclo** (criação→agend.→venda) |
| Agendamentos | tabela | **Tabela de agendamentos** (SDR/Closer/origem) |
| Google ads | pivot + 7 cards | `TrafficTable` filtrada |
| Origem1 | 12 cards + 2 tabelas | **Bloco "Desempenho por fonte"** |
| Métricas Inlead | 10 cards + pivot | KPIs filtrados por origem |
| Leads | col/linha/barra | **`ChartCard`** série diária + heatmap hora × dia-da-semana |
| Página 1 | tabela | descartar (rascunho) |

**14 páginas → ~7 blocos numa tela só.**

---

## 7. Pendências

1. **Qual tabela mora em qual projeto Supabase** (ver decisão de arquitetura — join entre projetos).
2. `Metas D/S/M`: o painel mostra as três granularidades ou só a mensal?
3. Hex exatos da identidade visual + logo.
