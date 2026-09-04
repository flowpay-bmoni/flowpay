-- FlowPay Supabase Schema & Migration
-- Project Ref: mxjbzexlnenooclmaawe
-- Relational persistence for FlowPay business orchestration, employees, payroll, missions, webhooks, audit logs,
-- user profiles, virtual cards, smart wallets, direct transfers, card transactions, pending approvals, and invoices.
-- Designed strictly following Supabase best practices (RLS, typed JSONB, performance indexes).

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.employees (
  id TEXT PRIMARY KEY,
  bmoni_user_id TEXT,
  partner_id TEXT NOT NULL,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  phone_number TEXT,
  country TEXT NOT NULL,          -- 'NG', 'MX', 'CA', 'US', etc.
  target_currency TEXT NOT NULL,  -- 'NGN', 'MXN', 'USD', 'EUR', etc.
  payroll_amount_minor INTEGER NOT NULL DEFAULT 0,
  payroll_currency TEXT,
  wallet_id TEXT,
  wallet_address TEXT,
  card_id TEXT,
  status TEXT NOT NULL DEFAULT 'CREATED', -- 'CREATED', 'WALLET_PENDING', 'KYC_PENDING', 'ONBOARDING', 'READY', 'FAILED', 'LINKED', 'ACTIVE'
  failed_stage TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.payroll_runs (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  total_usd_minor INTEGER NOT NULL,  -- minor units ($100.00 -> 10000)
  fee_usd_minor INTEGER NOT NULL DEFAULT 0,
  employee_count INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'COMPLETED', -- 'DRAFT', 'PREVIEW', 'COMPLETED', 'FAILED'
  reference TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  executed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.payroll_items (
  id TEXT PRIMARY KEY,
  payroll_run_id TEXT NOT NULL REFERENCES public.payroll_runs(id) ON DELETE CASCADE,
  employee_id TEXT NOT NULL,
  employee_name TEXT NOT NULL,
  country TEXT NOT NULL,
  target_currency TEXT NOT NULL,
  target_amount_minor INTEGER NOT NULL,
  usd_amount_minor INTEGER NOT NULL,
  exchange_rate NUMERIC(18,8) NOT NULL,
  status TEXT NOT NULL DEFAULT 'SUCCESS', -- 'SUCCESS', 'FAILED', 'PENDING'
  proposal_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.money_missions (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  rule_type TEXT NOT NULL, -- 'AUTO_SWEEP', 'SPEND_CAP', 'EMERGENCY_RESERVE', 'FX_TARGET'
  condition_json JSONB NOT NULL,
  action_json JSONB NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.audit_activity (
  id TEXT PRIMARY KEY,
  category TEXT NOT NULL, -- 'PERSONAL', 'BUSINESS', 'SYSTEM', 'AI'
  action TEXT NOT NULL,
  actor TEXT NOT NULL,
  details_json JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.webhook_events (
  id TEXT PRIMARY KEY,
  bmoni_event_id TEXT UNIQUE,
  event_type TEXT NOT NULL,
  payload_json JSONB NOT NULL,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.webhook_subscriptions (
  id TEXT PRIMARY KEY,
  partner_id TEXT NOT NULL,
  callback_url TEXT NOT NULL,
  secret_key TEXT,
  active BOOLEAN NOT NULL DEFAULT true,
  events JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Core New FlowPay Tables
CREATE TABLE IF NOT EXISTS public.users (
  id TEXT PRIMARY KEY,
  bmoni_user_id TEXT UNIQUE,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT NOT NULL,
  phone_number TEXT,
  account_type TEXT NOT NULL DEFAULT 'personal', -- 'personal', 'business', 'both'
  country TEXT NOT NULL DEFAULT 'US',
  company_name TEXT,
  company_role TEXT DEFAULT 'ADMIN',
  kyc_status TEXT NOT NULL DEFAULT 'unverified', -- 'unverified', 'pending', 'verified'
  national_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.virtual_cards (
  id TEXT PRIMARY KEY,
  bmoni_card_id TEXT,
  user_id TEXT NOT NULL,
  employee_id TEXT REFERENCES public.employees(id) ON DELETE SET NULL,
  smart_wallet_id TEXT NOT NULL,
  card_name TEXT NOT NULL,
  card_color TEXT NOT NULL DEFAULT '#F4B740',
  currency TEXT NOT NULL DEFAULT 'USD',
  card_type TEXT NOT NULL DEFAULT 'virtual',
  status TEXT NOT NULL DEFAULT 'ACTIVE', -- 'ACTIVE', 'BLOCKED', 'RESERVED', 'TERMINATED'
  last4 TEXT NOT NULL,
  masked_pan TEXT NOT NULL,
  expiration_date TEXT NOT NULL,
  monthly_spend_limit_minor BIGINT DEFAULT 0,
  is_reserved BOOLEAN NOT NULL DEFAULT false,
  proposal_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.smart_wallets (
  id TEXT PRIMARY KEY,
  bmoni_wallet_id TEXT,
  user_id TEXT NOT NULL,
  address TEXT NOT NULL,
  user_owner_address TEXT NOT NULL,
  currency TEXT NOT NULL, -- 'USDB', 'CNGN', 'MEXe', 'CADC', 'EURe'
  chain TEXT NOT NULL DEFAULT 'base-sepolia',
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.transfers (
  id TEXT PRIMARY KEY,
  proposal_id TEXT UNIQUE,
  user_id TEXT NOT NULL,
  recipient TEXT NOT NULL,
  recipient_address TEXT,
  amount_minor BIGINT NOT NULL,
  currency TEXT NOT NULL,
  funding_wallet_id TEXT NOT NULL,
  funding_currency TEXT NOT NULL,
  total_debit_minor BIGINT NOT NULL,
  exchange_rate NUMERIC(18, 8),
  fee_minor BIGINT DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'COMPLETED', -- 'PENDING_APPROVAL', 'PENDING_SIGNATURES', 'COMPLETED', 'FAILED'
  transaction_hash TEXT,
  purpose TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  executed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.card_transactions (
  id TEXT PRIMARY KEY,
  card_id TEXT NOT NULL REFERENCES public.virtual_cards(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  merchant_name TEXT NOT NULL,
  category TEXT NOT NULL,
  amount_major NUMERIC(12, 2) NOT NULL,
  currency TEXT NOT NULL DEFAULT 'USD',
  status TEXT NOT NULL DEFAULT 'COMPLETED',
  timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.pending_approvals (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  approval_type TEXT NOT NULL, -- 'MISSION_EXECUTION', 'TRANSFER', 'FX_CONVERSION', 'PAYROLL'
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  amount_minor BIGINT NOT NULL,
  currency TEXT NOT NULL,
  target_currency TEXT,
  target_amount_minor BIGINT,
  exchange_rate NUMERIC(18, 8),
  recipient TEXT,
  rule_id TEXT REFERENCES public.money_missions(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'PENDING', -- 'PENDING', 'APPROVED', 'REJECTED', 'EXPIRED'
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.invoices (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  invoice_number TEXT NOT NULL,
  client_name TEXT NOT NULL,
  client_email TEXT,
  amount_minor BIGINT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'USD',
  description TEXT,
  due_date TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'DRAFT', -- 'DRAFT', 'SENT', 'PAID', 'OVERDUE', 'CANCELLED'
  payment_link TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 2. Performance Indexes
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_employees_email ON public.employees(email);
CREATE INDEX IF NOT EXISTS idx_employees_bmoni_user_id ON public.employees(bmoni_user_id);
CREATE INDEX IF NOT EXISTS idx_employees_status ON public.employees(status);
CREATE INDEX IF NOT EXISTS idx_payroll_items_run ON public.payroll_items(payroll_run_id);
CREATE INDEX IF NOT EXISTS idx_payroll_items_employee ON public.payroll_items(employee_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON public.audit_activity(created_at);
CREATE INDEX IF NOT EXISTS idx_webhook_events_type ON public.webhook_events(event_type);

CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_bmoni_user_id ON public.users(bmoni_user_id);
CREATE INDEX IF NOT EXISTS idx_virtual_cards_user ON public.virtual_cards(user_id);
CREATE INDEX IF NOT EXISTS idx_virtual_cards_employee ON public.virtual_cards(employee_id);
CREATE INDEX IF NOT EXISTS idx_smart_wallets_user ON public.smart_wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_smart_wallets_address ON public.smart_wallets(address);
CREATE INDEX IF NOT EXISTS idx_transfers_user ON public.transfers(user_id);
CREATE INDEX IF NOT EXISTS idx_transfers_proposal ON public.transfers(proposal_id);
CREATE INDEX IF NOT EXISTS idx_card_tx_card_id ON public.card_transactions(card_id);
CREATE INDEX IF NOT EXISTS idx_pending_approvals_user ON public.pending_approvals(user_id, status);
CREATE INDEX IF NOT EXISTS idx_invoices_user ON public.invoices(user_id);

-- ---------------------------------------------------------------------------
-- 3. Row Level Security (RLS) - Supabase Standard
-- ---------------------------------------------------------------------------

ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.money_missions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_subscriptions ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.virtual_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.smart_wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.card_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pending_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;

-- Service role policies (full backend access)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'employees' AND policyname = 'service_role_employees_all') THEN
    CREATE POLICY service_role_employees_all ON public.employees FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'payroll_runs' AND policyname = 'service_role_payroll_runs_all') THEN
    CREATE POLICY service_role_payroll_runs_all ON public.payroll_runs FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'payroll_items' AND policyname = 'service_role_payroll_items_all') THEN
    CREATE POLICY service_role_payroll_items_all ON public.payroll_items FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'money_missions' AND policyname = 'service_role_money_missions_all') THEN
    CREATE POLICY service_role_money_missions_all ON public.money_missions FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'audit_activity' AND policyname = 'service_role_audit_activity_all') THEN
    CREATE POLICY service_role_audit_activity_all ON public.audit_activity FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'webhook_events' AND policyname = 'service_role_webhook_events_all') THEN
    CREATE POLICY service_role_webhook_events_all ON public.webhook_events FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'webhook_subscriptions' AND policyname = 'service_role_webhook_subs_all') THEN
    CREATE POLICY service_role_webhook_subs_all ON public.webhook_subscriptions FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'users' AND policyname = 'service_role_users_all') THEN
    CREATE POLICY service_role_users_all ON public.users FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'virtual_cards' AND policyname = 'service_role_virtual_cards_all') THEN
    CREATE POLICY service_role_virtual_cards_all ON public.virtual_cards FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'smart_wallets' AND policyname = 'service_role_smart_wallets_all') THEN
    CREATE POLICY service_role_smart_wallets_all ON public.smart_wallets FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'transfers' AND policyname = 'service_role_transfers_all') THEN
    CREATE POLICY service_role_transfers_all ON public.transfers FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'card_transactions' AND policyname = 'service_role_card_transactions_all') THEN
    CREATE POLICY service_role_card_transactions_all ON public.card_transactions FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'pending_approvals' AND policyname = 'service_role_pending_approvals_all') THEN
    CREATE POLICY service_role_pending_approvals_all ON public.pending_approvals FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'invoices' AND policyname = 'service_role_invoices_all') THEN
    CREATE POLICY service_role_invoices_all ON public.invoices FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Authenticated read policies (for frontend / authenticated clients)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'employees' AND policyname = 'authenticated_employees_read') THEN
    CREATE POLICY authenticated_employees_read ON public.employees FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'payroll_runs' AND policyname = 'authenticated_payroll_runs_read') THEN
    CREATE POLICY authenticated_payroll_runs_read ON public.payroll_runs FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'payroll_items' AND policyname = 'authenticated_payroll_items_read') THEN
    CREATE POLICY authenticated_payroll_items_read ON public.payroll_items FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'money_missions' AND policyname = 'authenticated_money_missions_read') THEN
    CREATE POLICY authenticated_money_missions_read ON public.money_missions FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'audit_activity' AND policyname = 'authenticated_audit_activity_read') THEN
    CREATE POLICY authenticated_audit_activity_read ON public.audit_activity FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'users' AND policyname = 'authenticated_users_read') THEN
    CREATE POLICY authenticated_users_read ON public.users FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'virtual_cards' AND policyname = 'authenticated_virtual_cards_read') THEN
    CREATE POLICY authenticated_virtual_cards_read ON public.virtual_cards FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'smart_wallets' AND policyname = 'authenticated_smart_wallets_read') THEN
    CREATE POLICY authenticated_smart_wallets_read ON public.smart_wallets FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'transfers' AND policyname = 'authenticated_transfers_read') THEN
    CREATE POLICY authenticated_transfers_read ON public.transfers FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'card_transactions' AND policyname = 'authenticated_card_transactions_read') THEN
    CREATE POLICY authenticated_card_transactions_read ON public.card_transactions FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'pending_approvals' AND policyname = 'authenticated_pending_approvals_read') THEN
    CREATE POLICY authenticated_pending_approvals_read ON public.pending_approvals FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'invoices' AND policyname = 'authenticated_invoices_read') THEN
    CREATE POLICY authenticated_invoices_read ON public.invoices FOR SELECT TO authenticated USING (true);
  END IF;
END $$;
