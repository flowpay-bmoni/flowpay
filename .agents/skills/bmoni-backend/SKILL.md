---
name: bmoni-backend
description: >-
  Provides operational instructions, architecture, and technical documentation for the
  FlowPay backend service, BMONI API client, webhook handler, and payroll engine.
---

# Subsystem: FlowPay Backend & BMONI Integration

## 1. Overview & Purpose
- **What it does**: Acts as the secure financial relay between the FlowPay Flutter client and the BMONI financial infrastructure.
- **Why it exists**: The Flutter client must **NEVER** hold partner API keys. The backend holds partner credentials, executes BMONI API calls, verifies incoming webhooks with HMAC-SHA256, stores FlowPay business metadata in SQLite, and orchestrates multi-country payroll.
- **Key dependencies**: `express`, `better-sqlite3`, `zod`, `dotenv`.
- **Official BMONI Documentation**: [bkey.mintlify.app](https://bkey.mintlify.app/) (Index: [/llms.txt](https://bkey.mintlify.app/llms.txt)).
- **API Key Protocol**: Never use fake placeholder API keys. When live BMONI partner credentials or webhook secrets are required for an implementation, always prompt the user directly.

---

## 2. Key Files & Architecture
- `src/config/env.ts`: Typed environment validation. Enforces origin-only BMONI base URL (`https://embedded-dev.bmoni.com`) by stripping any trailing `/v1`.
- `src/db/`: Supabase PostgreSQL connection (`index.ts`, `prisma/schema.prisma`) and relational schemas (`schema.sql`, `supabase_schema.sql`, `supabase.types.ts`). Deploys 14 relational tables with 100% RLS coverage (`users`, `employees`, `smart_wallets`, `virtual_cards`, `card_transactions`, `transfers`, `payroll_runs`, `payroll_items`, `invoices`, `money_missions`, `pending_approvals`, `audit_activity`, `webhook_events`, `webhook_subscriptions`). Includes `isPostgresDb()` guard for zero-error test isolation.
- `src/core/money.ts`: Central `Money` abstraction. Guarantees integer minor-unit calculations with zero floating-point arithmetic.
- `src/bmoni/client.ts`: Safe BMONI REST client handling timeouts, safe logging, structured error responses, `createEmployeeUser` (`POST /v1/users`), and `subscribeWebhook` (`POST /v1/webhooks/config`).
- `src/bmoni/webhooks.ts`: Constant-time HMAC-SHA256 verification using raw Buffer request bodies, dispatching 6-stage lifecycle transitions (`onboarding.completed`, `onboarding.failed`, `kyc.action_required`, `employee.linked`, `employee.vba.registered`).
- `src/core/currencies.ts`: Canonical registry mapping fiat currency codes (`NGN`, `MXN`, `USD`, `CAD`) to BMONI stablecoins (`CNGN`, `MEXe`, `USDB`, `CADC`). Enforces that smart-wallet calls strictly take stablecoins.
- `src/modules/employees/onboarding.service.ts`: End-to-end multi-stage orchestration for Employee Onboarding (Model B) across Stage 2 (owner proof challenges & managed wallet deployment), Stage 3 (country-specific KYC for Nigeria vs Mexico), Stage 4 (Mexico Etherfuse agreements & rail activation), and 4-state lifecycle calculation.
- `src/routes/employees.routes.ts`: Exposes 11 onboarding REST endpoints for challenges, wallet creation, KYC options, document upload, submission, activation, Mexico agreements, rail activation, status, retry, and webhook simulation.
- `src/modules/payroll/service.ts`: "One Employer, Many Countries, One Bill" aggregate payroll orchestrator.
- `src/modules/ai/`: Natural language intent interpreter powered by Google Gemini (`@google/genai` with `gemini-2.5-flash`) using strict JSON Schema structured outputs, with deterministic fallback and financial safety validation. Includes `mission_interpreter.ts` for parsing money directives.
- `src/modules/missions/`: Money Missions backend subsystem:
  - `types.ts`: Strongly typed interfaces (`MissionIntent`, `MissionAllocation`, `MissionStatus`, `MissionProposalPayload`, etc.).
  - `validator.ts`: Deterministic `MissionValidator` ensuring 100% split totals, minor-unit positive amounts, allowlisted currencies (`USD`, `NGN`, `MXN`, `CAD`, `EUR`), and allowed action types.
  - `service.ts`: `MoneyMissionService` managing mission proposals with SHA-256 hashes, B-Key signature verification, transactional execution, and audit logging into `audit_activity`. Includes resilient `isPostgresDb()` environment guard, self-derived `MoneyMissionRecord` Prisma types, and persistent in-memory fallback for offline sandbox operation.
  - Routes (`src/routes/missions.routes.ts`, `src/routes/ai.routes.ts`): `POST /api/ai/missions/interpret`, `GET /api/missions`, `POST /api/missions/propose`, `POST /api/missions/:id/execute`, `PATCH /api/missions/:id/toggle`.

---

## 3. What Has Been Done
- [x] Node.js + Express + TypeScript scaffolding with strict ESM mode.
- [x] Complete BMONI API client with endpoints for users (`POST /v1/users`), smart wallets, cards, transfers, and partner-scoped webhooks.
- [x] Raw Buffer HMAC webhook receiver mounted before JSON body parser with 6-stage lifecycle transitions.
- [x] PostgreSQL database migration with connection pooling and automated DDL schema migrations.
- [x] Multi-country payroll fanout service and relational persistence.
- [x] Employee management engine with server-side validation and lifecycle status filtering.
- [x] Money Missions backend engine with AI NL interpretation, deterministic validation, proposal generation with SHA-256 hash, and B-Key signature verification.
- [x] Multi-stage Employee Onboarding Engine (`modules/employees/onboarding.service.ts`) for Nigeria (`NG`) and Mexico (`MX`):
  - Canonical fiat-to-stablecoin mapping (`CNGN`, `MEXe`).
  - Stage 2 smart wallet challenge and deployment proxy.
  - Stage 3 country-branched KYC (BVN/EDD for NG, CURP/RFC/surnames/Sumsub selfie for MX).
  - Stage 4 Etherfuse agreement launch & rail activation.
  - 4-state status calculation (`Not Started`, `In Progress`, `Ready`, `Failed`), retry stage, and webhook simulation.
- [x] Smart Wallets & Embedded Contracts endpoints (`GET /api/wallets/:walletId`, `GET /:walletId/balance`, `GET /:walletId/transactions`, `POST /issue-card`) adhering to BMONI standard routes and `design.md` copy rules.
- [x] Automated backend coverage for Money math, HMAC verification, AI safety, employee validation, onboarding, Money Missions, transfers, smart wallets, and cards (`npm test`).

---

## 4. What Needs to Be Done
- [ ] Connect live BMONI partner key when issued.
- [x] Subscribe live webhook URL via `POST /api/webhooks/subscribe` (`POST /v1/webhooks/config` with explicit `partnerId`).
- [ ] Add PDF payslip generation endpoint for completed payroll runs.

---

## 5. Usage & Verification
```bash
cd backend
npm run build
npm test
npm start
```
Health check:
```bash
curl http://localhost:4000/api/health
```
