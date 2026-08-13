-- ============================================================================
-- SE EMP — 14. Índices de performance
--
-- ⚠️ RODAR NO BUSINESS DATA, uma linha de cada vez.
--
-- Sem eles a atribuição por email varre 13k leads × 767 agendamentos × 21k
-- deals sem índice nenhum — foi o que estourou o tempo limite na conferência.
-- O painel funciona sem isso; só fica lento em períodos longos.
--
-- ⚠️ `bitrix.timeline_agendamentos` e `bitrix.timeline_master` são VIEWS, não
--    tabelas — não aceitam índice ("cannot create index on relation ... this
--    operation is not supported for views"). Quem pode ser indexado é a tabela
--    que está por baixo delas, mas ela é de outro processo e não vamos mexer.
--    `bitrix.dados_raw` é tabela de verdade e aceita.
-- ============================================================================

-- Leads: usado no cruzamento por email (agendamentos e vendas da era Bitrix)
create index if not exists idx_leads_email_data
  on public.se_facebook_leads (lower(trim(email)), data desc);

-- Leads: usado no cruzamento por id (era CRM, via external_lead_id)
create index if not exists idx_leads_id
  on public.se_facebook_leads (id);

-- Deals da Bitrix: email (para achar o lead) e id (para casar com a timeline)
create index if not exists idx_bitrix_raw_email
  on bitrix.dados_raw (lower(trim(email)));

create index if not exists idx_bitrix_raw_id
  on bitrix.dados_raw (id);

analyze public.se_facebook_leads;
analyze bitrix.dados_raw;
