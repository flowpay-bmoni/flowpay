---
name: flowpay-core
description: >-
  Single source of truth and persistent memory for the FlowPay hackathon project.
  Consult this skill on every turn to understand what FlowPay is about, its system
  architecture, what has already been built, and what needs to be done next.
---

# FlowPay — Project Memory & Master Runbook

FlowPay is an intelligent financial operating layer built on top of BMONI infrastructure for the BMONI hackathon.
**Tagline**: *"Your money. Your rules. AI executes."*

---

## 📌 1. What the App is About

* **Core Problem**: Traditional payment rails across Africa and Latin America are fragmented, slow, and impose abusive FX and wire fees ($300–$400/month for distributed teams). Personal freelancers and global employers struggle with multi-currency conversion, compliance paperwork, and spend governance.
* **FlowPay Solution**: An autonomous financial operating system providing:
  * **Personal**: Multi-currency self-custody smart wallets, AI-powered "Money Missions" (e.g. 20% auto-sweep of international income to local savings, spending caps), and deterministic PIN-signed transfers.
  * **Business**: "One Employer, Many Countries, One Bill" aggregate payroll orchestrator. Employers invite remote team members (Nigeria, Mexico), see one aggregate USD bill, click once, and FlowPay fans out local currency disbursements (NGN, MXN) and virtual cards invisibly via BMONI rails.
* **10x Product Hook**: *"One Employer, Many Countries, One Bill"* — Fans out payment to employees in Nigeria (Bunch Dillon) and Mexico (Samson Jabo) in parallel with instant virtual cards, saving 96% in fees ($12 vs $340 typical wire fees).
* **Financial Safety Directives**:
  * AI is strictly advisory and **NEVER** directly executes money movement.
  * Invariant Pipeline: `Intent → Interpretation → Structured intent → Deterministic validation → Preview → Explicit approval → BMONI proposal → On-device signing → BMONI execution → Result → Activity`.
  * Private keys are created and protected strictly on-device in hardware Secure Enclaves via BMONI SDK. Private keys never leave the phone, are never sent to the backend, never sent to AI, and never logged.

---

## 🏗️ 2. Technical Architecture & Stack

| Layer | Technology | Status / Details |
| :--- | :--- | :--- |
| **Frontend (Mobile)** | Flutter (Dart), `bmoni_embedded_sdk: ^0.0.2`, `bkey_uikit: ^0.0.1`, `bmoni_embedded_wallets_cards: ^0.0.1`, Riverpod | Shared Foundation complete in `mobile/` |
| **Backend / API** | Node.js (v20+), Express, TypeScript (ESM) | Complete modular backend in `backend/` |
| **Database** | Supabase PostgreSQL (`mxjbzexlnenooclmaawe`) via Prisma ORM (`@prisma/client`) & Supabase MCP | Tables, indexes, and RLS deployed to live Supabase project |
| **Infrastructure** | BMONI Embedded REST Sandbox (`https://embedded-dev.bmoni.com`), Origin-only base URL | Integrated with client & raw HMAC webhooks |
| **BMONI Docs & Specs** | [bkey.mintlify.app](https://bkey.mintlify.app/) (LLM Index: [/llms.txt](https://bkey.mintlify.app/llms.txt)) | Official docs & API specs; prompt user for any required keys |
| **Provider Layer** | `DemoProvider` & `BMONIProvider` conforming to shared interfaces | Active with instant sandbox test personas |

---

## ✅ 3. What Has Been Done

* [x] **Project Scaffolding & Shared Foundation**:
  * Enforced workspace rules and AI agent protocol in [AGENTS.md](file:///AGENTS.md).
  * Provided central environment template in [.env.example](file:///.env.example).
  * Configured GitHub Actions CI workflow in [.github/workflows/build.yml](file:///.github/workflows/build.yml) targeting `main`, running on `macos-latest`, setting up Java 17 and Flutter, and building Android release APK and unsigned iOS release IPA.
* [x] **Backend Infrastructure (`backend/`)**:
  * Typed configuration in `config/env.ts` with strict origin-only URL parsing (strips `/v1` to prevent 404s).
  * Relational persistence in SQLite (`db/schema.sql`, `db/index.ts`) for employees, payroll runs, money missions, audit logs, and webhooks.
  * Central `Money` abstraction (`core/money.ts`) using integer minor units, zero float drift, and currency safety.
  * Production-grade BMONI client (`bmoni/client.ts`) with safe logging, structured error parsing (400 validation arrays, 401, 403, 409 idempotency recovery, 500 curve errors).
  * Webhook listener (`bmoni/webhooks.ts`, `routes/webhook.routes.ts`) verifying HMAC-SHA256 signatures over raw Buffer bytes in constant time.
  * Multi-country aggregate payroll engine (`modules/payroll/service.ts`, `routes/payroll.routes.ts`).
  * AI Financial Safety Engine (`modules/ai/interpreter.ts`, `modules/ai/validator.ts`) enforcing deterministic validation and previews.
  * Automated unit tests passing for Money arithmetic, HMAC verification, and AI safety guards.
* [x] **Mobile Flutter Foundation & Application Shell (`mobile/`)**:
  * Configured `pubspec.yaml` with BMONI Flutter ecosystem (`bmoni_embedded_sdk`, `bkey_uikit`, `bmoni_embedded_wallets_cards`, `crypto`).
  * Configured native Android (`mobile/android/`) and iOS (`mobile/ios/`) platform project trees with Gradle wrapper and build configurations.
  * Central Money abstraction (`lib/core/money/money.dart`).
  * Financial safety state models & signing coordinator (`lib/core/safety/`).
  * **BMONI Embedded SDK facade** (`lib/core/bmoni_sdk/bmoni_sdk_service.dart`) — wraps `bmoni_embedded_sdk: 0.0.2` with test-env fallback, salted PBKDF2 PIN digest, and 200ms native-platform timeout guards.
  * Provider abstraction interfaces: `WalletRepository`, `TransferRepository`, `CardRepository`, `EmployeeRepository`, `PayrollRepository`.
  * Deterministic `DemoProvider` implementations loaded with BMONI sandbox personas (Bunch Dillon BVN 99999999999, Samson Jabo BVN 22222222222).
  * Live `BMONIProvider` implementations communicating via backend proxy.
  * **13 FlowPay Design System Primitives (`lib/core/design_system/`)**:
    * `FlowPayTypography` with tabular monospaced numbers.
    * `FlowPaySpacing` with standard 8-point grid, presets, and border radii.
    * `FlowPayCard`, `FlowPayGlassCard`, `FlowPayStatCard`.
    * `FlowPayButton`, `FlowPayIconButton`.
    * `FlowPayTextField`, `FlowPayAmountField`.
    * `FlowPayBadge`, `FlowPayStatusBadge`.
    * `FlowPayAmountDisplay` (tabular numerals, integer/decimal split, sign, secondary FX label).
    * `FlowPayCurrencyDisplay` (flag/symbol, code, BMONI stablecoin token badge).
    * `FlowPayBottomSheet` & `showFlowPayBottomSheet()`.
    * `FlowPayDialog` & `showFlowPayConfirmDialog()`.
    * `FlowPayLoadingState`, `FlowPayErrorState`, `FlowPayEmptyState`.
  * **9 Shared App States (`FlowPayAppStatus` & `FlowPayStateView`)**: Loading, Success, Error, Empty, Pending, AwaitingApproval, Processing, Completed, Failed with zero duplicated styling.
  * **Dual Theme Engine (`lib/core/theme/`)**: `FlowPayTheme.dark()` and `FlowPayTheme.light()` with accessible WCAG contrast, context color resolvers, and dynamic `ThemeMode` toggling.
  * **Modular Navigation Architecture (`lib/core/navigation/`)**:
    * Prominent, unconfusing animated **Role Switcher** (`FlowPayRoleSwitcher`) in header (`[ 👤 Personal | 💼 Business ]`).
    * Decoupled `PersonalRoutes`, `BusinessRoutes`, `AppRoutes`, and `FlowPayRouter`.
    * Contextual bottom navigation bars reflecting mode-specific tabs and brand accents.
  * **FlowPay Business Employer Dashboard**:
    * Core value message: *"One Employer. Many Countries. One Bill."*
    * Domain state coordinator: `BusinessProvider` (`mobile/lib/core/state/business_provider.dart`) decoupling widgets from direct API calls with deterministic demo data.
    * 6 Employer metrics grid: Total payroll, employee count, countries, pending payroll, employee status, wallet/card status.
    * Employee Preview with rich model: Name, Country, Currency, Payroll amount, Onboarding status, Wallet status, Card status across Nigeria 🇳🇬 (NGN), Mexico 🇲🇽 (MXN), and Canada 🇨🇦 (CAD).
    * Primary action: Run Payroll (triggers on-device B-Key signing and multi-rail fan-out).
    * Secondary action: Add Employee (`AddEmployeeModal` with instant local wallet & card provisioning).
  * **Complete Screen Foundations**:
    * **Personal**: Dashboard, Wallets, Money Missions ("Your money. Your rules. AI executes."), Send Money with PIN approval, Personal Activity, Personal Security.
    * **Business**: Business Dashboard, Global Team Roster, Employee Detail, Multi-country Payroll Orchestrator ("One Employer, Many Countries, One Bill"), Corporate Audit.
  * Automated widget and shell tests passing with 100% success and 0 analyzer lints.
* [x] **B-Key / BMONI On-Device Wallet Integration** (Personal Feature — `lib/core/wallet/`, `lib/modules/personal/wallet_provisioning_screen.dart`):
  * **`bmoni_embedded_sdk: 0.0.2`** added to `pubspec.yaml`; SDK initialized at app startup in `main.dart` with 6-digit PIN policy.
  * **`WalletService` abstraction** (`lib/core/wallet/wallet_service.dart`) — clean interface with `initialize`, `hasWallet`, `createWallet`, `getWalletAddress`, `deleteWallet`, `hasPin`, `setPin`, `matchPin`, `changePin`, `removePin`. `BmoniWalletService` production implementation delegates to `BmoniSdkService`.
  * **`WalletState` model** — immutable, 4 named constructors (`noWallet`, `creating`, `ready`, `error`), `copyWith`, and computed bool getters.
  * **`WalletStateNotifier`** — Riverpod `StateNotifier` coordinating full provisioning lifecycle: load, create (with optional PIN), delete, graceful `walletAlreadyExists` recovery.
  * **Riverpod providers**: `walletServiceProvider` + `walletStateProvider` (overridable in tests).
  * **`WalletSigner` abstraction** (`lib/core/wallet/wallet_signer.dart`) — `signMessage` (EIP-191) and `signTransactionHash` (EIP-712 / ERC-4337). `BmoniWalletSigner` delegates to SDK; `SigningCancelledException` for user cancellations.
  * **`WalletPinAuthSheet`** (`lib/core/wallet/components/wallet_pin_auth_sheet.dart`) — secure modal bottom sheet with 6-dot PIN pad, animated fill, trust reassurance banner, error feedback, `onAuthorize` signing callback, and cancel without state leakage. Keys: `wallet_pin_cancel_button`, `pin_key_<digit>`, `pin_key_backspace`.
  * **`WalletProvisioningScreen`** (`lib/modules/personal/wallet_provisioning_screen.dart`) — 4-state `AnimatedSwitcher` (noWallet → creating → ready → error): benefit cards, hardware enclave specs, EIP-55 address display with clipboard copy, test-signing via PIN sheet, PIN-gated delete with confirmation dialog. Linked from `WalletsScreen` and `PersonalSecurityScreen`.
  * **Security invariants**: private keys never logged/transmitted; PIN only verified in-memory and via SDK; signing info excluded from logs.
  * **Test coverage** (`test/wallet_service_test.dart`, `test/wallet_provisioning_ui_test.dart`): 56 new tests (unit + widget). All 79 total Flutter tests passing (100%), 0 analyzer issues.
* [x] **Live Environment & Emulator Runtime Verification**:
  * **Backend Daemon**: Actively running on `http://localhost:4000` with BMONI sandbox integration and health checks passing.
  * **Toolchain Alignment**: Synchronized Gradle 8.14, Android Gradle Plugin 8.13.2, and Kotlin 2.2.20 for Flutter 3.47 compilation.
  * **Android Emulator**: Verified on `Pixel_3a_API_33_x86_64` (Android 13 / API 33) with Impeller OpenGLES backend.
  * **Live Flow Verified**: App boots directly into self-custody BMONI mode with interactive Personal/Business role switching and Money missions.
* [x] **App-Lock Authentication, Biometrics, and Personal/Business Mode Routing**:
  * Single-account two-mode foundation: confirmed one `bmoniUserId` holds both personal wallet and business/employer access.
  * System separation: App-level lock (`local_auth`) gates opening the app; BMONI on-device signing PIN (`bmoni_embedded_sdk`) authorizes transactions. Never conflated.
  * Native configuration: Android `FlutterFragmentActivity` and `USE_BIOMETRIC` permission; iOS `NSFaceIDUsageDescription` for Face ID.
  * Secure storage & caching: `AccountCapabilities` (`hasPersonalWallet`, `hasBusinessAccess`) stored in `flutter_secure_storage` with 15-minute TTL caching, in-memory resilient fallback layer, and instant invalidation.
  * Backend capabilities endpoints: `GET /api/auth/capabilities` and `GET /api/auth/users/:bmoniUserId/capabilities` active on port 4000.
  * Mode picker: `AccountModePickerModal` conforming to `design.md` §4.4 and `bkey_uikit` style with custom branded radio selectors.
  * Two independent navigation shells: `PersonalShell` (5 destinations: Overview, Wallets, Missions, Activity, Security) and `BusinessShell` (4 destinations: Dashboard, Team, Payroll, Audit) driven by Riverpod `currentAccountModeProvider`.
    * Full test suite passing: 13/13 mobile tests passed (100%), 11/11 backend tests passed (100%), with 0 analyzer lints.
* [x] **Supabase Cloud Database & MCP Integration**:
  * Authorized and linked to live Supabase project `mxjbzexlnenooclmaawe` via Supabase MCP.
  * Successfully deployed full relational schema of **14 tables** with 100% Row Level Security (RLS) and security policies for `service_role` and `authenticated` access:
    1. `public.users` (user accounts, personas, capabilities, KYC/KYB tier, business metadata).
    2. `public.employees` (multi-country workforce, BMONI wallet IDs, onboarding status).
    3. `public.smart_wallets` (ERC-4337 smart wallets, balances, currency rails: USDB, CNGN, CADC, EURe, GBPe, MEXe).
    4. `public.virtual_cards` (BMONI virtual Mastercard records, card tokens, PAN mask, spend limits, reservation status).
    5. `public.card_transactions` (card authorization, settlement, merchant data, fees).
    6. `public.transfers` (NL-initiated transfers, proposal IDs, debits, exchange rates, hashes).
    7. `public.payroll_runs` (multi-country aggregate payroll runs, 4-stage execution, savings calculations).
    8. `public.payroll_items` (individual employee payroll line items with destination stablecoins).
    9. `public.invoices` (aggregate payroll billing records, status, PDF references).
    10. `public.money_missions` (autonomous rules, sweep/save triggers, execution statistics).
    11. `public.pending_approvals` (dual-control governance, threshold-gated disbursements, expiration timers).
    12. `public.audit_activity` (tamper-evident corporate & personal audit ledger, JSON detail snapshots).
    13. `public.webhook_events` (raw HMAC-verified BMONI webhook payloads with idempotent replay protection).
    14. `public.webhook_subscriptions` (registered partner webhook listener endpoints and secret hashes).
  * Enforced foreign keys with `ON DELETE CASCADE` where applicable, and created performance indexes on all foreign keys, status columns, and lookup filters.
  * Verified Supabase Security Advisors (0 security warnings / 0 lints).
  * Synchronized Prisma ORM (`backend/prisma/schema.prisma`) with all 14 models and regenerated `@prisma/client`.
  * Auto-generated TypeScript types at `backend/src/db/supabase.types.ts` directly from live Supabase schema via `supabase.generate_typescript_types`.
  * Synchronized local SQL references in `backend/src/db/supabase_schema.sql` and `backend/src/db/schema.sql`.
  * Wired database persistence with `isPostgresDb()` environment-safe guards across:
    * `backend/src/routes/auth.routes.ts` (`signup`, `kyc`, `resolveCapabilities`).
    * `backend/src/modules/cards/service.ts` (`createVirtualCard`, `listCards`, `updateCardStatus`).
    * `backend/src/modules/wallets/service.ts` (`getWallets`, `createManagedWallet`).
    * `backend/src/modules/transfers/service.ts` (`executeTransfer`).
  * Full test suite passing: 69/69 backend tests passed (100%), 0 failures across 6 test suites.
* [x] **Signup Screen, Context-Aware KYC, and Personal vs Business Separation**:
  * **Onboarding & Signup Screen (`mobile/lib/modules/auth/signup_screen.dart`)**:
    * Clean BMoni Dark Obsidian aesthetic (`BMoniColors.offbrand950`, `brand500` magenta accents).
    * Universal Account Type selector: Personal (freelancers, smart wallets, money missions) vs Business (employers, aggregate one-bill payroll, company cards).
    * Dynamic form fields: Full legal name, email, country/currency selector (NG 🇳🇬, MX 🇲🇽, US 🇺🇸, CA 🇨🇦, GB 🇬🇧), phone, and 6-digit security PIN.
    * Business entity fields: Registered company name, registration number (RC/RFC/EIN), corporate role.
    * Quick Demo Autofill personas: Bunch Dillon (Personal) and FlowPay Global Ltd (Business).
  * **Context-Aware KYC Flow (`mobile/lib/modules/auth/kyc_screen.dart`)**:
    * Personal Tier 1 KYC: Country-specific government ID (BVN/NIN, CURP/RFC, SSN), Date of Birth, address, plus interactive facial biometric liveness simulation with radar scan and anti-spoofing validation adhering to BMONI specifications.
    * Business KYB: Corporate tax ID, registered office address, authorized signatory verification, and automated payroll disbursement rail readiness (NGN, MXN, USD).
  * **Enforced Account Separation in Application Shells**:
    * Strict capabilities derivation: Personal users receive `hasPersonalWallet: true, hasBusinessAccess: false` and render a high-contrast **Personal Account (Verified)** badge without the Business switcher.
    * Business users receive `hasPersonalWallet: false, hasBusinessAccess: true` and render the registered **Company Name & Admin** badge without the Personal switcher.
    * Sandbox Master demo accounts (`hasBothModes == true`) retain the dual `SegmentedRoleSwitch` for rapid hackathon testing.
    * Custom drawers provide personalized profile headers and contextual upgrade options ("Register Business Account" vs "Add Personal Wallet").
  * **Backend Auth Endpoints (`backend/src/routes/auth.routes.ts`)**:
    * `POST /api/auth/signup`: Registers personal/business accounts and resolves mode-specific capabilities.
    * `POST /api/auth/kyc`: Completes Tier 1/KYB verification with sandbox limits and disbursement rails.
    * `GET /api/auth/capabilities`: Dynamically derives capabilities for personal, business, or sandbox master IDs.
  * **BMONI End-to-End Auth Architecture (Signup -> KYC -> Set PIN -> App Lock / Expiration)**:
    * **Step 1: Universal Signup (`mobile/lib/modules/auth/signup_screen.dart`)**: Collects account type (Personal vs Business), name, email, phone, and country rails. No premature PIN entry.
    * **Step 2: Context-Aware KYC (`mobile/lib/modules/auth/kyc_screen.dart`)**: Tier 1 personal biometric scan & national ID or business KYB compliance & multi-rail payroll readiness. Seamlessly hands off to PIN setup.
    * **Step 3: Dedicated PIN Setup (`mobile/lib/modules/auth/set_pin_screen.dart`)**: Two-stage interactive 6-digit numeric entry (`Set PIN` -> `Confirm PIN`) adhering strictly to BMONI embedded guidelines. Provisions on-device wallet keypair via `BmoniSdkService.initWallet()`, sets salted PBKDF2 hash via `BmoniSdkService.setPin()`, and unlocks directly into the verified shell.
    * **App Lock & PIN Entry (`mobile/lib/core/auth/app_auth_gate.dart`)**: When locked, displays 6-digit PIN entry box directly on screen alongside Face ID / Fingerprint / Device Biometrics. Entering 6-digit PIN immediately unlocks into the session.
    * **Session Expiration & Re-Authentication (`mobile/lib/core/auth/app_auth_gate.dart` & `login_screen.dart`)**: Automatically detects expired session tokens; displays an amber `[ ⚠️ Authentication Expired ]` indicator allowing users to renew via 6-digit PIN, verify with biometrics, or log in anew via `LoginScreen`.
    * **Verification**: 18/18 mobile unit & widget tests passing (100%), 11/11 backend tests passing (100%), 0 analyzer issues. Tested live on Android emulator with screenshot proofs.
  * **Relational Database Migration to PostgreSQL**:
    * **Database Engine & Driver**: Installed `pg` and `@types/pg`; migrated from SQLite (`better-sqlite3`) to PostgreSQL connection pooling (`pg.Pool`).
    * **DDL Schema & Seeding (`backend/src/db/schema.sql` & `index.ts`)**: Automated DDL migration for `employees`, `payroll_runs`, `payroll_items`, `money_missions`, `audit_activity`, and `webhook_events`. Fixed syntax typo in schema file and seeded pre-verified BMONI sandbox personas.
    * **Async Route & Service Migration**: Converted all synchronous database queries across `employees`, `missions`, `payroll`, `activity`, and `webhooks` to asynchronous parameterized queries (`$1, $2, ...`), preventing SQL injection and float drift.
    * **Resilience & Config**: Configured `backend/.env` with local container on port 5435 (`flowpay-postgres`) and added SSL support for remote Supabase pooler URIs (`rejectUnauthorized: false`), alongside a non-crashing fallback for test runners.
    * **Live Endpoint Verification**: Verified `GET /api/employees`, `GET /api/missions`, `POST /api/payroll/execute`, `GET /api/payroll/runs`, and `GET /api/activity` against PostgreSQL. 11/11 backend tests passing (100%).
  * **Prisma ORM Integration (`backend/prisma/`)**:
    * Installed `prisma@6.19.3` + `@prisma/client@6.19.3`.
    * Created `backend/prisma/schema.prisma` mirroring all 6 PostgreSQL tables (`employees`, `payroll_runs`, `payroll_items`, `money_missions`, `audit_activity`, `webhook_events`) with proper `@map`/`@@map` decorators, `@db.Timestamptz`, relations, and indexes.
    * Replaced all raw `pg.Pool.query(...)` calls across 6 files with fully type-safe Prisma client methods (`findMany`, `findUnique`, `create`, `createMany`, `update`, `updateMany`, `count`).
    * Migrated files: `db/index.ts` (singleton client + seeding), `modules/employees/service.ts`, `modules/missions/service.ts`, `modules/payroll/service.ts`, `routes/activity.routes.ts`, `routes/payroll.routes.ts`, `bmoni/webhooks.ts`.
    * Added `db:push`, `db:migrate`, `db:studio` npm scripts.
    * Build: `npm run build` runs `prisma generate && tsc`. Zero TypeScript errors.
  * **FlowPay Business — Employee Management & 6-Stage BMONI Lifecycle**:
    * **6-Stage Lifecycle Architecture**: Implemented full deterministic transitions (`CREATED` → `WALLET_PENDING` → `KYC_PENDING` → `ONBOARDING` → `READY` → `FAILED`) with `failedStage` tracking.
    * **Corrected BMONI Endpoint Integration**: Switched user creation to official `POST /v1/users` with `{ firstName, lastName, email, phoneNumber }` returning `bmoniUserId` per BMONI documentation, eliminating legacy invite endpoints.
    * **Partner-Scoped Webhook Engine**: Implemented `POST /api/webhooks/subscribe` calling `POST /v1/webhooks/config` with explicit `partnerId`. Enhanced webhook dispatcher in `webhooks.ts` to process `onboarding.completed` (→ `READY`), `onboarding.failed` (→ `FAILED`), `kyc.action_required` (→ `KYC_PENDING`), `employee.linked`, and `employee.vba.registered`.
    * **Server-Side Validation**: Enforced strict validation on `POST /api/employees`: regex email formatting, non-empty names, ISO country allowlist (`NG`, `MX`, `CA`), and positive integer minor-unit payroll checks.
    * **bkey_uikit Form & Component Rebuild**:
      * `AddEmployeeModal`: Rebuilt using `BMoniTextFormField.filled()`, `SelectorBottomSheet<CountryOption>` via `BMoniBottomSheet.show()`, auto-resolved currency, `BMoniButton(variant: primary)`, and `BMoniToastOverlay`.
      * `EmployeesScreen`: Built with `bkey_uikit` `EmptyState` for zero-employee states, per-row flag emojis, payroll currency and amounts, 6-stage lifecycle badges, and wallet/card status indicators.
      * `EmployeeDetailScreen`: Built with Identity section, Financial section, BMONI on-chain linkage (`bmoniUserId`, EVM address), KYC compliance indicators (Pass/Fail/Pending — never exposes raw docs), and card freeze controls.
    * **Automated Unit Tests**: Added `backend/src/modules/employees/employee.test.ts` verifying all validation, countries, and currency rules. 18/18 tests passing (100%).
  * **FlowPay Business — Employee Onboarding (Nigeria & Mexico) [Model B]**:
    * **Strict Currency & Stablecoin Mapping**: Smart-wallet calls strictly take canonical stablecoin token codes (`CNGN` for Nigeria, `MEXe` for Mexico — never fiat `NGN`/`MXN`) encoded centrally in `backend/src/core/currencies.ts` and `mobile/lib/core/money/currency_mapping.dart`.
    * **Stage 2 (Smart Wallet Provisioning)**: On-device owner keypair generated via `BmoniEmbeddedSdk.initWallet()`, challenge requested via `POST /v1/users/{userId}/smart-wallets/owner-proof-challenges`, on-device PIN signed via `BmoniEmbeddedSdk.signMessage(challenge, pin)`, and managed wallet deployed via `POST /v1/users/{userId}/smart-wallets/create-managed`.
    * **Stage 3 (Country-Specific KYC)**: `GET /kyc/options` → document upload → `PATCH /kyc` → `GET /kyc/readiness` → `POST /kyc/activate`:
      * **Nigeria (`NG`)**: Strictly omits biometric selfie; requires BVN (11 digits, sandbox personas Bunch Dillon `95888168924`, Samson Jabo `22222222222`), Nigerian residential address, and EDD employment fields (`OCC_FIN_001`); activates KYC without body.
      * **Mexico (`MX`)**: Requires document + Sumsub biometric liveness selfie; requires CURP (18 chars), RFC (12-13 chars), maternal and paternal surnames, and Mexican address; activates KYC with `sumsubLevelName: "id-and-liveness"`.
    * **Stage 4 (Disbursement Rail Activation)**:
      * **Nigeria (`NG`)**: Calls `POST /v1/users/{userId}/onboarding/start-nigeria` with `bvn` and `ngnWalletAddress`.
      * **Mexico (`MX`)**: Enforces strict prerequisite where Etherfuse agreements must be fetched and signed via `GET /v1/users/{userId}/latam/mx/kyc/launch/agreements` (5-minute ephemeral JWT assertion) prior to calling `POST /v1/users/{userId}/latam/mx/kyc/activate` with `smartWalletId`.
    * **4-State Onboarding Model**: Structured state engine with states `Not Started` → `In Progress` → `Ready` → `Failed`. Displays progress against actual stages (Stage 2, Stage 3, Stage 4), tracks `failedStage` and `failureReason`, and provides interactive `Retry` and `Refresh Status` controls.
    * **Mobile Onboarding Wizard & Detail Tracking**:
      * `EmployeeOnboardingScreen`: Multi-stage interactive wizard with B-Key PIN signing sheet, distinct Nigeria vs Mexico forms, Etherfuse agreements signing sheet modal, and deterministic simulation fallback.
      * `EmployeeDetailScreen`: Added "Onboarding Progress (Actual Stages)" card displaying Stage 2, 3, and 4 cards, state badges, retry stage button, and refresh status icon.
    * **Automated Test Coverage**: 26/26 backend tests passing (100%), covering currency mapping, Stage 2 address validation, Nigeria BVN/address rules, Mexico CURP/RFC/surname rules, Etherfuse agreement prerequisites, and state calculations.
  * **FlowPay Business — Employee Wallet Control Center (`bmoni_embedded_wallets_cards`)**:
    * **Core Package Interfaces**: Implemented `WalletRepository` as a thin wrapper satisfying `bmoni_embedded_wallets_cards`'s actual contract:
      * `EmbeddedWalletReadDataSource` (`fetchWallets`, `fetchWalletDetail`, `fetchBalance`, `fetchTransactions`).
      * `EmbeddedWalletStorage` (using `InMemoryEmbeddedWalletStorage`).
      * `EmbeddedWalletBalanceCache` (using `InMemoryEmbeddedWalletBalanceCache`).
    * **Identical Contract Conformance Across Providers**: Both `BMONIProvider` (`BmoniWalletRepository`) and `DemoProvider` (`DemoWalletRepository`) satisfy the identical contract. `BMONIProvider` calls the real API (`GET /v1/users/{userId}/smart-wallets/account/wallets`, balances, transactions), and `DemoProvider` returns typed responses from deterministic sandbox data.
    * **Typed Failure Hierarchy**: Error handling branches strictly on typed `Either<EmbeddedFailure, T>` subclasses (`EmbeddedServerFailure`, `EmbeddedNetworkFailure`, `EmbeddedRateLimitFailure`, `EmbeddedNotFoundFailure`, `EmbeddedAuthenticationFailure`, `EmbeddedAuthorizationFailure`) without parsing error strings.
    * **Model-Aware Widgets**:
      * `EmbeddedWalletCard`: Wraps `BMoniWalletCard` with 6 built-in currency background art variants (`BMoniWalletType.ngn` for Nigeria NGN/CNGN, `BMoniWalletType.mxn` for Mexico MXN/MEXe, `BMoniWalletType.usd` for USDB, `BMoniWalletType.cad` for CADC, `BMoniWalletType.eur` for EURe, `BMoniWalletType.gbp` for GBPe). Dynamically selects the variant matching the employee's payroll currency.
      * `EmbeddedWalletTransactionsSection`: Composed recent-activity list with host-driven row builders applying `design.md` copy rules (never exposing raw event strings like `EMBEDDED_TX_PAYROLL_TRANSFER_V2`).
    * **App-Wide Riverpod State Management**: Screen tree is wired directly to Riverpod notifiers (`EmbeddedWalletListNotifier`, `EmbeddedWalletBalanceNotifier`, `EmbeddedWalletTransactionsNotifier`) via `walletListProvider`, `walletBalancesProvider`, and `walletTransactionsProvider`.
    * **Actions & Copy Rules**: Features `View Wallet` (specs modal with Base Sepolia chain details, ERC-4337 standard, and support debug EVM address copy button), `Transactions` (full paginated ledger sheet), and `Issue Card` (virtual Mastercard issuance modal routing into Prompt 12). Wallet address is strictly a debug/support detail, never exposed as primary UI.
    * **BMONI Security Architecture**: Documents that employee wallets use the identical on-device signing model as personal wallets — private keys never leave the device's Keystore/Secure Enclave via `BmoniEmbeddedSdk`.
    * **Backend & Automated Verification**: Mounted `/api/wallets/:walletId`, `GET /:walletId/balance`, `GET /:walletId/transactions`, and `POST /issue-card`. Added `backend/src/modules/wallets/wallets.test.ts`. All 31 backend tests passing (100%).


  * **FlowPay Personal Financial Dashboard ("Your money. Your rules. AI executes.")**:
    * **Portfolio & Balance Section**: Displays real-time multi-currency portfolio valuation ($37,671.00 USD primary), minor-unit integer precision (no float truncation/fake precision), secondary NGN rail valuation, available balance ($24,500.00), sandbox mode badge, and interactive privacy hide/reveal toggle.
    * **Primary AI Interaction ("What should your money do?")**: `AiCommandBar` built as an entry point into task-specific financial workflows (NOT a chatbot). Features interactive suggestion chips: "Allocate my $2,000", "Send $500 to my designer", and "Convert $1,000 to Naira".
    * **Pending Approvals Queue**: Prominently surfaces actions awaiting explicit B-Key signature (auto-sweep triggers, multi-currency transfers, FX conversions) with 6-digit PIN confirmation dialog.
    * **Quick Actions Row**: 3 primary actions: "Create Mission", "Send Money", and "View Wallets".
    * **Multi-Currency Smart Wallets Breakdown**: Renders verified balances and addresses for USD (USDB), NGN (CNGN), MXN (MEXe), and CAD (CADC) using shared wallet cards with one-tap clipboard copy.
    * **Recent Financial Activity Feed**: Shows real-time history across missions, transfers, card payments, and conversions with category badges.
  * **FlowPay Flagship Feature — Money Missions ("Tell your money what to do.")**:
    * **Full 8-Stage Financial Safety Pipeline**: Natural language → AI interpretation → structured intent (`MissionIntent`) → deterministic validation (`MissionValidator`) → preview modal ("Nothing moves until you approve.") → explicit user approval → BMONI operation proposal with 32-byte sha256 hash → B-Key hardware PIN signing via `WalletPinAuthSheet` → on-chain execution → activity ledger logging (`audit_activity`).
    * **Core Financial Directives Enforced**: AI NEVER directly moves money. AI output is untrusted input subjected to deterministic dual-sided validation (percentages strictly sum to 100%, amounts match, currencies in allowlist: USD, NGN, MXN, CAD, EUR).
    * **Typed Models & Schemas**: Implemented in Dart (`mobile/lib/core/missions/mission_intent.dart`) and TypeScript (`backend/src/modules/missions/types.ts`) with minor-unit integer precision (cents/kobo) and explicit allocation categories (`RESERVE_USD`, `CONVERT_EXPENSES_NGN`, `TAX_RESERVE`, `SAVINGS`, `CUSTOM`).
    * **Dual-Sided Deterministic Validation**: `ClientMissionValidator` (Dart) and `MissionValidator` (TypeScript) verifying 100% split totals, integer precision, allowed currencies, valid action types, and non-empty allocation targets.
    * **Backend AI & Mission Engine (`backend/src/modules/ai/mission_interpreter.ts`, `backend/src/modules/missions/`)**:
      * `MissionInterpreter`: Privacy sanitization stripping PII, structured output extraction via Gemini `gemini-2.5-flash`, resilient deterministic regex fallback parser for sandbox/offline execution, and immediate validator invocation.
      * `MoneyMissionService`: PostgreSQL/Prisma persistence, SHA-256 proposal hash calculation, B-Key signature verification, transactional state transition (`PROPOSED` → `EXECUTING` → `EXECUTED`), and audit activity logging.
      * Endpoints: `POST /api/ai/missions/interpret`, `GET /api/missions`, `POST /api/missions/propose`, `POST /api/missions/:id/execute`, `PATCH /api/missions/:id/toggle`.
    * **Mobile UI & Interactive Experience (`mobile/lib/modules/personal/`)**:
      * Primary heading: *"Tell your money what to do."* with tagline *"Your money. Your rules. AI executes."*.
      * Large NL input text field with live submit button.
      * 5 Suggested action chips: "Split incoming payment", "Save for a goal", "Convert currency", "Send money", "Reserve for taxes".
      * 3-Stage animated pipeline indicator: `Analyzing intent` → `Validating financial rules` → `Generating BMONI proposal`.
      * `MissionPreviewModal`: Displays incoming trigger amount ($2,000 incoming), full allocation breakdown (USD Reserve 30% / $600, NGN Expenses 50% / $1,000 equiv, Tax Reserve 20% / $400), reassurance banner *"Nothing moves until you approve."*, and Edit / Approve buttons.
      * B-Key Hardware PIN Signing: Integrates `WalletPinAuthSheet` with 6-digit numeric PIN pad for EIP-191 / B-Key hardware enclave signing.
      * Success Receipt Dialog: Shows celebration icon, transaction hash, BMONI confirmation, and done button.
      * Active Missions List: Custom `MissionCard` components with allocation pill badges, status indicator, last run timestamp, active toggle switch, and interactive ⚡ Run Now button.
    * **Automated Verification**:
  * **FlowPay Personal — Send Money Feature & Balance-Aware Routing ("Send $500 to my designer in Ghana.")**:
    * **Natural Language Entry & AI Intent Interpretation**:
      * Dedicated natural language prompt input with 4 instant suggestion chips ("Send $500 to my designer in Ghana", "Send $150 to bunch.dillon@example.ng", "Send ₦50,000 to Samson Jabo", "Send $1,200 to contractor in Mexico").
      * Gemini 2.5 Flash extraction (`backend/src/modules/ai/transfer_interpreter.ts`) producing typed `TransferIntent` (recipient, amount, amountMinor, currency, purpose) with deterministic regex fallback for offline/sandbox mode.
      * Full Zod schema validation (`backend/src/modules/transfers/validator.ts`) and Dart models (`mobile/lib/core/transfers/`).
    * **Balance-Aware Multi-Currency Smart Wallet Routing**:
      * Dynamic wallet balance inspection (`backend/src/modules/transfers/service.ts`, `DemoTransferRepository.inspectBalances`, `BmoniTransferRepository.inspectBalances`).
      * Auto-routing when direct currency is insufficient (e.g. user requests $500 USD, direct USD smart wallet has only $300 USD, sufficient NGN smart wallet has ₦6,820,000): FlowPay produces an NGN-funded payment with required NGN → USD conversion, deterministic exchange rate (1550.0 NGN/USD), network fee ($0.50), FX fee (15 bps), and total debit calculation without float drift.
    * **Premium Review Confirmation Screen (`TransferReviewModal`)**:
      * Displays: Recipient, Amount, Currency, Funding source, Conversion label & badge, Exchange rate, Fee breakdown, Total debit.
      * Prominent security reassurance banner: **"Nothing moves until you approve."** with subtext *"Zero AI money movement • On-device B-Key hardware PIN signature required"*.
      * Action buttons: `Edit` (dismisses modal to adjust inputs) and `Approve & Send` (advances to on-device PIN signing).
    * **Authentic BMONI On-Device Hardware PIN Signing**:
      * Invokes `WalletPinAuthSheet` with 6-digit numeric PIN pad.
      * Signs canonical 32-byte sha256 proposal hash on-device via `BmoniSdkService.signTransactionHash` / `bmoni_embedded_sdk` hardware enclave (EIP-191 / EIP-712). Zero fake signatures.
      * Submits signature to FlowPay backend (`POST /api/transfers/execute`), which calls BMONI proposal approval (`POST /v1/users/{userId}/smart-wallets/proposals/{proposalId}/approve`), broadcasts to EVM rails, and records the event in the PostgreSQL `audit_activity` ledger.
      * Presents celebratory receipt dialog (`TransferReceiptDialog`) displaying transaction hash, settlement details, and direct link to Activity.
    * **8 Human-Readable Failure Modes**:
      * Explicit enum `TransferErrorCode` mapped to clear human-readable messages: Insufficient funds, unsupported currency, invalid recipient, conversion unavailable, transfer failure, signature failure, proposal expiration, network failure.
    * **Automated Verification**:
      * Backend: All 29 unit tests passing (`pass 29, fail 0`).
      * Mobile: All 91 Flutter tests passing (`+91: All tests passed!`), `flutter analyze` clean with 0 warnings or errors.
  * **FlowPay Personal — Activity Ledger & Hardware Security Core**:
    * **Personal Activity Screen (`mobile/lib/modules/personal/personal_activity_screen.dart`)**:
      * Comprehensive activity ledger displaying: Transfers, Conversions, Mission executions, Wallet operations, Card transactions, Pending approvals, and Failures.
      * Interactive filter chips (All, Transfers, Conversions, Missions, Wallet Ops, Cards, Pending Approvals, Failures) and real-time counterparty/reference search bar.
      * 6 Required Statuses: Pending, Processing, Awaiting Approval, Completed, Failed, Cancelled (integrated with `FlowPayAppStatus.cancelled` and `FlowPayStatusBadge`).
      * Real-time Awaiting Approval counter with 1-tap inline B-Key PIN approval shortcut.
    * **Transaction Details Modal (`mobile/lib/modules/personal/components/activity_detail_modal.dart`)**:
      * Complete inspection view displaying: Amount, Currency (with BMONI token badge e.g. USDB, CNGN, MEXe, CADC), Source, Destination, Fee, Exchange Rate, Timestamp, FlowPay Reference (one-tap copy), and BMONI Reference (one-tap copy).
      * Strict Security Invariants: Never exposes private keys, never exposes signing payloads unnecessarily, and never exposes API credentials.
      * Reassurance callout: "Verified by On-Device B-Key Signer • Zero AI Money Movement".
      * Interactive approval flow for pending items invoking `WalletPinAuthSheet` with 6-digit numeric PIN pad.
    * **Personal Security Screen (`mobile/lib/modules/personal/personal_security_screen.dart`)**:
      * 3 Distinct Core Sections: **1. Wallet Security**, **2. Signing Security**, **3. Approval Rules**.
      * Prominently explains and enforces: **"Financial actions require your approval."** (AI is strictly advisory with zero custody or execution authority).
      * Live device indicators showing whether:
        * Wallet is initialized (`INITIALIZED` vs `NOT INITIALIZED`) with public EVM address and Hardware Keystore / Secure Enclave isolation.
        * Device signing is available (`AVAILABLE & ACTIVE` / `HARDWARE SECURED`) supporting EIP-191 personal message signing and EIP-712 structured proposal signing.
        * PIN protection is enabled (`PIN CONFIGURED (6 DIGITS)`) backed by salted PBKDF2-HMAC-SHA256 digests.
      * 4 Invariants of Financial Safety: Intent interpretation → Deterministic rule validation → Mandatory human preview → On-device B-Key hardware PIN signature.
      * Active approval policy threshold matrix (Transfers, Conversions, Missions, Card actions require strict PIN).
      * Honest Security Disclosure: Refuses to make unsupported claims; relies strictly on genuine on-device hardware cryptography and BMONI embedded rails.
    * **Automated Test Coverage & Verification**:
      * Added `test/personal_activity_test.dart` and `test/personal_security_test.dart`.
      * Updated `test/design_system_test.dart` covering all 10 shared states.
      * 99/99 Flutter tests passing (`+99: All tests passed!`), `flutter analyze` clean with 0 warnings or errors.
  * **FlowPay Personal Complete Feature Integration (Dashboard, Wallets, Missions, Send Money, Activity, Security)**:
    * **Single State Architecture & Unified AppShell**: Wired singleton `AppState` into `PersonalShell` and `BusinessShell` in `FlowPayApp` (`mobile/lib/app.dart`), fixing decoupled state instances and ensuring cross-tab reactivity.
    * **Cross-Tab Coordination & Navigation**: Created `personalTabIndexProvider` (`mobile/lib/core/navigation/personal_tab_provider.dart`) and wired `appState.personalTabIndex` with `notifyListeners()`. `PersonalShell` uses `IndexedStack` to preserve view state, and all dashboard quick actions ("Send Money", "Create Mission", "View Wallets") switch tabs seamlessly.
    * **Atomic Balance Synchronization**: Implemented `debitWallet` and `creditWallet` on `WalletRepository` and `DemoWalletRepository`. Executing a Send Money proposal or activating a Money Mission debits the funding wallet with minor-unit integer precision and notifies listeners.
    * **Unified Activity Ledger & Live Listeners**: `PersonalActivityScreen` and `WalletsScreen` register reactive listeners on `AppState`, automatically refreshing transactions and balances whenever actions settle. Both Send Money and Money Missions record verified entries into `ActivityRepository`.
    * **End-to-End Automated Integration Verification (`mobile/test/personal_integration_flow_test.dart`)**:
      * **Journey 1 (Open App → Balances → Tab Switching)**: Unlocks app, verifies multi-currency balances, switches tabs via bottom nav and dashboard quick actions.
      * **Journey 2 (Money Mission Full Flow)**: Enters NLP directive, verifies AI preview, approves, signs via 6-digit B-Key PIN, executes, and transitions directly to Activity tab.
      * **Journey 3 (Send Money Full Flow)**: Quick action opens Send Money, selects intent chip, inspects balances, opens review modal ("Nothing moves until you approve"), authorizes with B-Key PIN, settles, and navigates to Activity with debited wallet balance.
      * **Full Test Suite Status**: 102/102 mobile tests passing (100%), 29/29 backend tests passing (100%), 0 Dart analyzer warnings or lints.
  * **FlowPay Business — Virtual Employee Cards (BMONI Infrastructure & design.md §4.5)**:
    * **Virtual Cards Only**: Strictly scoped to virtual cards, omitting physical card flows.
    * **Verified BMONI Smart-Wallet Card Endpoints**:
      * Card Creation: `POST /v1/users/{userId}/cards` with `{ cardName, cardColor: '#F4B740', currency, type: 'virtual', smartWalletId, nin? }`.
      * Polling Sign Payload: `GET /v1/users/{userId}/smart-wallets/proposals/{proposalId}/sign-payload` (handles 409 "not ready yet" retry loops).
      * Proposal Submission: `POST /v1/users/{userId}/smart-wallets/proposals/{proposalId}/signatures` with `{ signature }`.
      * List Wallet Cards: `GET /v1/users/{userId}/smart-wallets/{smartWalletId}/cards` (strictly smart-wallet scoped, preserves reserved cards).
      * Card Detail & Sensitive: `GET /v1/users/{userId}/smart-wallets/{smartWalletId}/cards/{cardId}` and `.../sensitive` (unmasks PAN, CVV, expiry).
      * Card Status: `PUT /v1/users/{userId}/cards/{cardId}/status` with `{"status": "BLOCKED"}` or `"ACTIVE"` (exact uppercase, case-sensitive).
      * Card Transactions: `GET /v1/users/{userId}/cards/{cardId}/transactions` supporting `size` and `status` query filters.
    * **Auto-Approved Proposal Flow**: Issuance proposals are auto-approved by the proxy (`proposalStatus: PENDING_APPROVALS`), requiring zero separate `/approve` calls.
    * **Hardware Signing via `signTransactionHash()`**: Strictly signs 32-byte `hashToSign` with `BmoniSdkService.signTransactionHash()`, avoiding silent on-chain execution failures caused by `signMessage()`.
    * **First-Time Enrollment & Named E101 Error**: Catches `400 E101 — Card owner is not enrolled for cards yet` and presents a dedicated 11-digit Nigerian NIN input requirement banner rather than generic failure toasts.
    * **Reserved Card Visual State ("Issuing...")**: Cards with `isReserved: true` or `status: 'RESERVED'` are never hidden; rendered with amber-bronze surface, progress spinner, and "Issuing..." status badge.
    * **Dual Amount Format Parsing**: Card detail ledger parsed strictly as minor-unit string (`"250000"` = ₦2,500.00) and card transactions parsed strictly as major-unit numeric (`25.5` = $25.50) without cross-parsing.
    * **Amber Card-as-Object UI (design.md §4.5)**: `VirtualCardObject` rendered in FlowPay Amber (`#F4B740`), soft physical shadow `Color(0x1A0D2E2A)` blur 24 offset (0,8), tabular numerals, Mastercard glyphs, and contactless icon.
    * **Card Action Sheets**: `IssueVirtualCardSheet` (issuance with PIN signing) and `CardDetailSheet` (unmask sensitive details with 30s auto-hide timer, transaction list, and freeze/unfreeze toggle).
    * **Automated Test Coverage**: 43/43 backend unit & integration tests passing (100%), including 12 dedicated tests in `backend/src/modules/cards/cards.test.ts`.

  * **FlowPay Business — Global Payroll ("One Employer. Many Countries. One Bill.")**:
    * **Transfer Primitives Orchestration**: Payroll is custom FlowPay orchestration over BMONI's 4-call transfer proposal primitives (`transfers.md`):
      1. `POST /v1/users/{employerUserId}/smart-wallets/{smartWalletId}/proposals` with `{ proposal: { type: "TRANSFER", toUserId, amount, currency, description } }`.
      2. `POST /v1/users/{employerUserId}/smart-wallets/proposals/{proposalId}/approve`.
      3. `GET /v1/users/{employerUserId}/smart-wallets/proposals/{proposalId}/sign-payload` (polled: handles 404 for threshold pending and 409 for asynchronous preparation).
      4. `POST /v1/users/{employerUserId}/smart-wallets/proposals/{proposalId}/sign` with `{ signature: "0x..." }`.
    * **Raw-Hash secp256k1 Signing Requirement**: Validated against official BMONI test vector. Strictly signs raw 32-byte digest (`hashToSign`), never `typedData`, and never with EIP-191 personal sign prefix (`\x19Ethereum Signed Message:\n32`). Verified in unit tests using `ethers.SigningKey`.
    * **Recipient Rail Pre-Validation**: Pre-validates each employee's smart-wallet active rail status for their country's stablecoin (`CNGN` for Nigeria, `MEXe` for Mexico) and validates employer USD source wallet balance before allowing "Run Payroll".
    * **Cost Transparency & Review Confirmation**: Provides aggregate payroll preview showing employee count, distinct country count, total USD amount, and a 97% savings comparison ($10 BMONI fee vs $340 traditional SWIFT/wire fee). Requires explicit review confirmation sheet before triggering PIN authorization.
    * **4-Stage Timeline Stepper**: Visual execution progress through `Validated → Approved → Processing → Completed`. Live mode maps from BMONI proposal states (`PENDING_APPROVALS` → `PENDING_SIGNATURES` → `COMPLETED`); Demo mode executes deterministic progression across the 4 stages.
    * **Independent Failure Isolation & Granular Retry**: Multi-employee payouts run concurrently but isolated; an error on one employee's proposal does not block or fail others, resulting in `PARTIALLY_COMPLETED`. Failed proposals feature a dedicated "Retry Payout via Approve" action calling `approve` on that specific proposal.
    * **Automated Test Coverage**: 48/48 backend tests passing (100%), including 5 new tests in `backend/src/modules/payroll/payroll.test.ts` (test vector, currency mapping, preview with fee comparison, failure isolation, and retry).

  * **FlowPay Business — Payroll Activity & Corporate Audit (Prompts 10–13 Composition Layer)**:
    * **Composition Over Duplication**: Aggregated data across Prompts 10–13 repositories (`PayrollRepository`, `CardRepository`, `WalletRepository`, `ActivityRepository`) without invoking any new BMONI endpoints.
    * **Unified Canonical Model (`SharedTransactionModel`)**: Single model eliminating duplication across payroll runs, employee payments, virtual cards, and smart-wallet transfers, with tabular amount displays and secondary stablecoin currencies.
    * **bkey_uikit Component Reuse**: `ActivitySectionCard` container and `StatusText` badge used consistently across all views and detail sheets for unified visual status chips (`Draft`, `Pending Approval`, `Processing`, `Completed`, `Partially Completed`, `Failed`).
    * **Corporate Audit Screen (`BusinessActivityScreen`)**: 4-metric grid (Volume, Completed Runs, Active Cards, System Failures), 6 filter tabs (All, Payroll Runs, Employee Payments, Card Transactions, Wallet Operations, Failures), and fast search filtering.
    * **Payroll Run Record & Drill-Down (`PayrollRunDetailSheet`)**: Surfaces Payroll ID, Date, Employee count, Countries, USD equivalent, Fees, Status chip, fee savings banner ($330 / 97%), 4-stage execution timeline, and individual employee payments with destination stablecoins (`CNGN`, `MEXe`).
    * **Independent Failure Isolation & Granular Retry**: Isolates failed proposals, surfaces detailed error reasons, and provides an inline **"Retry Payout via Approve"** button invoking on-device B-Key PIN signing.
    * **Strict Secret Sanitization**: Fully verified that `hashToSign`, `signature`, private key material, and webhook secret keys are never exposed in UI or debug payloads.
    * **Automated Tests**: 54/54 backend tests passing (100%), including 5 dedicated tests in `backend/src/modules/payroll/audit.test.ts`.

---

## 🎯 4. What Needs to Be Done (Parallel Roadmap)

### Personal Track Owner
- [x] Build Personal Financial Dashboard with portfolio balance, AI command bar, pending approvals, multi-currency wallets, and money missions.
- [x] Implement on-device B-Key / BMONI wallet layer: `WalletService`, `WalletSigner`, `WalletPinAuthSheet`, `WalletProvisioningScreen`, 56 tests.
- [x] Implement Money Missions flagship end-to-end pipeline: NL interpretation, deterministic validation, preview sheet, B-Key PIN signing, active mission list with ⚡ Run Now manual triggers.
- [x] Implement Send Money feature with natural language entry, balance-aware smart routing, premium confirmation screen, "Nothing moves until you approve." trust banner, on-device B-Key signing, and activity logging.
- [x] Implement Personal Activity ledger with 7 filters, 6 statuses, transaction details modal, and zero credential leakage.
- [x] Implement Personal Security screen with 3 core sections (Wallet Security, Signing Security, Approval Rules), "Financial actions require your approval." enforcement, and hardware key indicators.
- [ ] Connect `PersonalDashboardScreen` to live real-time wallet balance polling with backend webhook sync.

### Business Track Owner
- [x] Implement FlowPay Business Employee Onboarding (Model B) for Nigeria (`NG`) and Mexico (`MX`) across Stage 2, Stage 3, and Stage 4 with 4-state lifecycle.
- [x] Implement FlowPay Business Virtual Employee Cards on BMONI rails (Amber Card-as-Object, `signTransactionHash`, E101 NIN enrollment, dual amount formatters, card actions).
- [x] Implement FlowPay Business Global Payroll ("One Employer. Many Countries. One Bill.") with 4-call proposal sequence, raw-hash signing, rail validation, 4-stage timeline, and granular retry.
- [x] Implement FlowPay Business Corporate Payroll Activity & Audit subsystem with composed repositories, bkey_uikit ActivitySectionCard and StatusText, shared transaction models, and failure retry.
- [ ] Add virtual card spend limit presets (Junior / Senior / Contractor dropdowns).
- [ ] Add PDF export / receipt sharing for aggregate payroll disbursement runs.

---

## 📂 5. Project Directory Structure

```text
flowpay/
├── AGENTS.md                                # Mandatory AI agent & team guidelines
├── .env.example                             # Environment variable configuration
├── .agents/
│   ├── skills/
│   │   ├── flowpay-core/SKILL.md            # Master memory (this file)
│   │   ├── bmoni-backend/SKILL.md           # Backend subsystem documentation
│   │   └── flowpay-mobile/SKILL.md          # Mobile Flutter subsystem documentation
│   └── resources/
│       ├── payroll_spec.txt                 # Global Payroll Cards specification
│       └── recon_spec.txt                   # BMONI Platform Reconnaissance
├── backend/                                 # Node.js + Express + TypeScript Backend
│   ├── package.json
│   ├── tsconfig.json
│   └── src/
│       ├── server.ts                        # Express bootstrap & route registration
│       ├── config/env.ts                    # Typed env validation & origin-only URL guard
│       ├── db/                              # SQLite schema, migrations & test persona seed
│       ├── core/                            # Central Money class, errors & types
│       ├── bmoni/                           # BMONI API client & raw HMAC webhook handler
│       ├── modules/                         # AI safety, payroll engine, employees, cards, wallets
│       └── routes/                          # REST endpoints + /webhooks/bmoni
└── mobile/                                  # Flutter Mobile Application
    ├── pubspec.yaml                         # bmoni_embedded_sdk, bkey_uikit, etc.
    └── lib/
        ├── main.dart                        # App entry & BMONI SDK initialization
        ├── app.dart                         # Shell with role & provider toggling
        ├── core/                            # Money, theme, safety, BMONI SDK wrapper, repos
        └── modules/
            ├── personal/                    # Personal dashboard, wallets, missions, send, security
            └── business/                    # Business dashboard, roster, detail, payroll, audit
```

---

## 👥 6. Developer Runbook

### Backend Commands
```bash
cd backend
npm install
npm run build      # Compile TypeScript & copy schema
npm test           # Run unit test suite (Money, Webhooks, AI Safety)
npm run dev        # Run with live reload via tsx
npm start          # Start compiled production server
```

### Mobile Commands
```bash
cd mobile
flutter pub get
flutter run
```
