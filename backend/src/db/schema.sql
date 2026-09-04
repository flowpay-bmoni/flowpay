-- FlowPay Postgres Schema: Relational persistence for FlowPay metadata, business orchestration, and audit logs

CREATE TABLE IF NOT EXISTS employees (
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
  status TEXT NOT NULL DEFAULT 'CREATED', -- 6 stages: 'CREATED', 'WALLET_PENDING', 'KYC_PENDING', 'ONBOARDING', 'READY', 'FAILED'
  failed_stage TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payroll_runs (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  total_usd_minor INTEGER NOT NULL,  -- integer minor units ($100.00 -> 10000)
  fee_usd_minor INTEGER NOT NULL DEFAULT 0,
  employee_count INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'COMPLETED', -- 'DRAFT', 'PREVIEW', 'COMPLETED', 'FAILED'
  reference TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  executed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payroll_items (
  id TEXT PRIMARY KEY,
  payroll_run_id TEXT NOT NULL REFERENCES payroll_runs(id) ON DELETE CASCADE,
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

CREATE TABLE IF NOT EXISTS money_missions (
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

CREATE TABLE IF NOT EXISTS audit_activity (
  id TEXT PRIMARY KEY,
  category TEXT NOT NULL, -- 'PERSONAL', 'BUSINESS', 'SYSTEM', 'AI'
  action TEXT NOT NULL,
  actor TEXT NOT NULL,
  details_json JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS webhook_events (
  id TEXT PRIMARY KEY,
  bmoni_event_id TEXT UNIQUE,
  event_type TEXT NOT NULL,
  payload_json JSONB NOT NULL,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS webhook_subscriptions (
  id TEXT PRIMARY KEY,
  partner_id TEXT NOT NULL,
  callback_url TEXT NOT NULL,
  secret_key TEXT,
  active BOOLEAN NOT NULL DEFAULT true,
  events JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  bmoni_user_id TEXT UNIQUE,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT NOT NULL,
  phone_number TEXT,
  account_type TEXT NOT NULL DEFAULT 'personal',
  country TEXT NOT NULL DEFAULT 'US',
  company_name TEXT,
  company_role TEXT DEFAULT 'ADMIN',
  kyc_status TEXT NOT NULL DEFAULT 'unverified',
  national_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS virtual_cards (
  id TEXT PRIMARY KEY,
  bmoni_card_id TEXT,
  user_id TEXT NOT NULL,
  employee_id TEXT REFERENCES employees(id) ON DELETE SET NULL,
  smart_wallet_id TEXT NOT NULL,
  card_name TEXT NOT NULL,
  card_color TEXT NOT NULL DEFAULT '#F4B740',
  currency TEXT NOT NULL DEFAULT 'USD',
  card_type TEXT NOT NULL DEFAULT 'virtual',
  status TEXT NOT NULL DEFAULT 'ACTIVE',
  last4 TEXT NOT NULL,
  masked_pan TEXT NOT NULL,
  expiration_date TEXT NOT NULL,
  monthly_spend_limit_minor BIGINT DEFAULT 0,
  is_reserved BOOLEAN NOT NULL DEFAULT false,
  proposal_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS smart_wallets (
  id TEXT PRIMARY KEY,
  bmoni_wallet_id TEXT,
  user_id TEXT NOT NULL,
  address TEXT NOT NULL,
  user_owner_address TEXT NOT NULL,
  currency TEXT NOT NULL,
  chain TEXT NOT NULL DEFAULT 'base-sepolia',
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS transfers (
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
  status TEXT NOT NULL DEFAULT 'COMPLETED',
  transaction_hash TEXT,
  purpose TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  executed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS card_transactions (
  id TEXT PRIMARY KEY,
  card_id TEXT NOT NULL REFERENCES virtual_cards(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  merchant_name TEXT NOT NULL,
  category TEXT NOT NULL,
  amount_major NUMERIC(12, 2) NOT NULL,
  currency TEXT NOT NULL DEFAULT 'USD',
  status TEXT NOT NULL DEFAULT 'COMPLETED',
  timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pending_approvals (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  approval_type TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  amount_minor BIGINT NOT NULL,
  currency TEXT NOT NULL,
  target_currency TEXT,
  target_amount_minor BIGINT,
  exchange_rate NUMERIC(18, 8),
  recipient TEXT,
  rule_id TEXT REFERENCES money_missions(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'PENDING',
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS invoices (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  invoice_number TEXT NOT NULL,
  client_name TEXT NOT NULL,
  client_email TEXT,
  amount_minor BIGINT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'USD',
  description TEXT,
  due_date TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'DRAFT',
  payment_link TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indices for performance
CREATE INDEX IF NOT EXISTS idx_employees_email ON employees(email);
CREATE INDEX IF NOT EXISTS idx_employees_bmoni_user_id ON employees(bmoni_user_id);
CREATE INDEX IF NOT EXISTS idx_employees_status ON employees(status);
CREATE INDEX IF NOT EXISTS idx_payroll_items_run ON payroll_items(payroll_run_id);
CREATE INDEX IF NOT EXISTS idx_payroll_items_employee ON payroll_items(employee_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_activity(created_at);
CREATE INDEX IF NOT EXISTS idx_webhook_events_type ON webhook_events(event_type);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_bmoni_user_id ON users(bmoni_user_id);
CREATE INDEX IF NOT EXISTS idx_virtual_cards_user ON virtual_cards(user_id);
CREATE INDEX IF NOT EXISTS idx_virtual_cards_employee ON virtual_cards(employee_id);
CREATE INDEX IF NOT EXISTS idx_smart_wallets_user ON smart_wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_smart_wallets_address ON smart_wallets(address);
CREATE INDEX IF NOT EXISTS idx_transfers_user ON transfers(user_id);
CREATE INDEX IF NOT EXISTS idx_transfers_proposal ON transfers(proposal_id);
CREATE INDEX IF NOT EXISTS idx_card_tx_card_id ON card_transactions(card_id);
CREATE INDEX IF NOT EXISTS idx_pending_approvals_user ON pending_approvals(user_id, status);
CREATE INDEX IF NOT EXISTS idx_invoices_user ON invoices(user_id);