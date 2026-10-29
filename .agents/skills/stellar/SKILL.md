---
name: stellar
description: >-
  Technical documentation and operational runbook for FlowPay's Stellar network layer
  (accounts, assets, path payments, payroll batches, anchors). Reference this skill
  before touching any money-movement code in backend/src/stellar or mobile/lib/core/stellar.
---

# Subsystem: Stellar Network Layer

FlowPay was originally built on BMONI. As of 2026-10-26 it is being migrated to run
entirely on the **Stellar network** (branch `feat/stellar-migration`). BMONI is being
removed completely.

## 📌 1. What This Subsystem is About

* **Purpose**: Every wallet, balance, transfer, FX conversion and payroll payout in FlowPay
  is a real Stellar operation. The backend reads chain state and *builds* unsigned
  transactions; the device *signs* them; the backend (or device) *submits* them to Horizon.
* **Locked decisions (2026-10-26, from the product owner)**:
  | Decision | Choice |
  | :--- | :--- |
  | Network | **Testnet** (`Test SDF Network ; September 2015`, `https://horizon-testnet.stellar.org`). Mainnet is a config switch later. |
  | Custody | **Non-custodial, on-device.** Ed25519 keypair generated on the phone/browser, encrypted with the user's PIN, stored in secure storage. Secret key never reaches the backend, the AI, or logs. |
  | Currencies | **USD, CAD, MXN, GBP, NGN.** Nigeria stays, Paystack NUBAN resolution stays. |
  | Cards | **Removed.** Stellar has no card issuing; cards module is deleted, not mocked. |
* **Asset model (testnet)**: FlowPay runs its own testnet *issuer* account that issues
  `USD`, `CAD`, `MXN`, `GBP`, `NGN` test stablecoins, and a *distributor/market-maker*
  account that seeds constant-product liquidity pools (`USD/<X>`) at reference FX rates, so
  cross-currency payments are native Stellar **path payments** (`pathPaymentStrictReceive`).
  Asset codes + issuers are config-driven (`STELLAR_ASSETS`), so mainnet swaps in real
  anchor assets (e.g. Circle USDC) without code changes.
* **Payroll ("One Employer, Many Countries, One Bill")**: one Stellar transaction holding
  up to 100 path-payment operations — the employer pays in USD, each employee receives
  their local asset, and the whole batch is **atomic** (all succeed or none). Batches > 100
  are split into multiple transactions and reported per-batch.
* **Cash-out / KYC**: Stellar anchors via SEP-10 (auth), SEP-12 (KYC), SEP-24 (interactive
  deposit/withdraw), SEP-38 (quotes). Testnet anchor: `testanchor.stellar.org`.
* **Key dependencies**: `@stellar/stellar-sdk` (backend, Node), `stellar_flutter_sdk`
  (mobile + Flutter web), Horizon REST, Friendbot (testnet XLM funding).

## 🔒 2. Money-Safety Rules (Stellar edition of AGENTS.md)

* A failed Horizon submit / anchor call **must surface as a failure**. Never synthesize a
  transaction hash, account ID, or `SUCCESS` status.
* Only a Horizon response with `successful: true` and a real `hash` may produce a
  `COMPLETED` record. Every completed record stores the real hash and links to
  `https://stellar.expert/explorer/testnet/tx/<hash>`.
* Timeouts on submit are **ambiguous, not failed**: record `PENDING`, then reconcile by
  hash against Horizon before reporting a final status (never resubmit blindly — same
  sequence number protects against double-spend, but the UI must not claim either outcome).
* Testnet funding (Friendbot XLM + FlowPay test-asset faucet) is allowed **only** when
  `STELLAR_NETWORK=testnet`, and is labeled as test funds in the UI.
* Demo mode (`ProviderMode.demo`) remains a separate, clearly-labeled simulation path.

## 🏗️ 3. File Structure (target)

* `backend/src/stellar/config.ts` — network, Horizon URL, passphrase, asset registry.
* `backend/src/stellar/horizon.ts` — typed Horizon client wrapper with honest error mapping.
* `backend/src/stellar/accounts.ts` — load account, balances, trustline status, friendbot.
* `backend/src/stellar/payments.ts` — build unsigned payment / path-payment XDR, find paths, submit signed XDR.
* `backend/src/stellar/payroll.ts` — batch builder (≤100 ops/tx), atomic payroll.
* `backend/src/stellar/anchors.ts` — SEP-10/12/24/38 client.
* `backend/scripts/stellar-bootstrap.ts` — creates issuer + distributor, issues assets, seeds pools.
* `mobile/lib/core/stellar/` — keypair vault (PIN-encrypted), transaction signer, Horizon reads.
* `mobile/lib/core/providers/stellar/` — `Stellar*Repository` implementations of the existing repository interfaces.

## ✅ 4. What Has Been Done

* [x] **M0 — Plan & foundation**: branch `feat/stellar-migration`, decisions recorded, AGENTS.md rules rewritten for Stellar, this skill created. Baseline before migration: backend 122/122 tests, Flutter 198/198 tests, analyzer clean.

* [x] **M1 — Stellar backend core**:
  * `backend/src/stellar/config.ts` (network + asset registry, `assetFor`, explorer URLs), `amount.ts` (Money ↔ 7-dp strings; quotes round UP), `horizon.ts` (`StellarHorizon` + injectable `HorizonGateway`; `mapHorizonError` → `STELLAR_TX_FAILED` with human messages from result codes, `StellarSubmitTimeoutError` = PENDING; `reconcile(hash)`), `accounts.ts` (summary, Friendbot, unsigned trustline XDR), `bootstrap.ts`.
  * Routes `backend/src/routes/stellar.routes.ts` mounted at `/api/stellar`: `GET /config`, `GET /accounts/:id`, `POST /accounts/:id/fund`, `POST /accounts/:id/trustlines`, `POST /transactions {signedXdr}` (200 COMPLETED / 202 PENDING / 4xx FAILED), `GET /transactions/:hash`.
  * **Live testnet treasury** created by `npm run stellar:bootstrap` (idempotent): issuer `GD3JY73LVFKPRAKV6QYLBKYBTDHP7WFVJQBQZVAWL5WT2FISH6XWN433`, distributor `GBX5PMNBNNG5SJLK5QZHVLOSCGK6O3RNXJPYNM7JB7XOWQRYAZSMOS56`; USD/CAD, USD/MXN, USD/GBP, USD/NGN pools seeded with $1M per side. Verified path quote: 500,000 NGN ← 446.51 CAD via USD.
  * 17 new unit tests (`src/stellar/stellar.test.ts`); backend total 139/139.

* [x] **M2 — On-device keys & signing**:
  * `mobile/lib/core/stellar/stellar_key_vault.dart` — `StellarKeyVault`: ed25519 keypair generated on device (`stellar_flutter_sdk` 3.8.0); seed encrypted with AES-256-GCM under PBKDF2-HMAC-SHA256(PIN, 24-byte salt, 100k iters) (`cryptography` 2.9.0); blob in `flutter_secure_storage` (iOS `first_unlock_this_device`). Wrong PIN = GCM auth failure (no PIN hash exists). Lockout after 5 failures, 30s doubling. Recovery-key export/import. Storage errors PROPAGATE (`StellarVaultException.storageFailure`).
  * `stellar_network.dart` — testnet/public selection via `--dart-define=STELLAR_NETWORK`.
  * `WalletService` → `StellarWalletService` (`createWallet({pin})`, `importWallet`, `exportRecoveryKey`, PIN-gated `deleteWallet`); `WalletSigner` → `StellarWalletSigner` (`signTransactionXdr`, ed25519 `signMessage`/`signTransactionHash`, PIN always required).
  * `BmoniSdkService` and the `bmoni_embedded_sdk` dependency removed; all 14 call sites rewired. New `CreatePinSheet`.
  * Tests: `test/flutter_test_config.dart` gives every test a fresh in-memory vault; `test/helpers/test_wallet.dart`; `test/wallet_service_test.dart` rewritten around real crypto (signatures verified with the SDK). Opt-in live test `test/live/stellar_live_test.dart` (`LIVE_STELLAR=1`) — verified device-signed trustline tx accepted on testnet (`e1b1277a…`). Flutter 179/179, analyzer clean, `flutter build web` OK.
  * **Security note (honest limits)**: a 6-digit PIN has 10^6 combinations, so the KDF alone cannot stop an offline brute force if the encrypted blob is exfiltrated; protection relies on OS keychain/keystore + lockout. On **web**, secure storage is browser storage — weaker. Planned: optional longer passphrase on web, and recovery-key backup prompt in onboarding (M7/M8).

* [x] **M3a — Wallets & transfers**:
  * Backend: `stellar/challenge.ts` (HMAC'd, 5-min, single-use ownership challenge; ed25519 verify), `stellar/directory.ts` (user ↔ account link; **strict** recipient resolution: G-address, federation `name*domain`, exact email/phone/full-name; ambiguous → error), `stellar/payments.ts` (live funding quotes via path-finding, 1% sendMax slippage cap, unsigned payment / `pathPaymentStrictReceive` with ≤28-byte memo), `stellar/faucet.ts` (testnet-only test funds, anti-farming threshold), `stellar/history.ts` (Horizon payments → normalized history).
  * `modules/transfers/service.ts` rewritten: proposal ID = tx hash; execute requires signed-tx hash == proposal (no swapping), single use, per-user; COMPLETED only on Horizon success; PENDING (202) on timeout; FAILED recorded with result codes. Fake in-memory wallet ledger (`modules/wallets/service.ts`) **deleted**; wallet routes read the chain.
  * Routes: `/api/wallets` (GET, `/balances`, `/challenge`, `/register` [requires signed challenge], `/transactions`), `/api/transfers` (`/interpret`, `/recipient`, `/inspect-balances`, `/propose`, `/execute`, `/rates` [live]), `/api/stellar/accounts/:id/payments`, `/api/stellar/accounts/:id/faucet`.
  * Prisma: `User.stellarAccountId` — **apply `backend/prisma/sql/2026-10-26_add_stellar_account_id.sql` to Supabase before deploying** (not applied to prod by the agent).
  * Mobile: `core/stellar/stellar_api.dart`, `stellar_activation.dart` (link → create → trustlines → test USD, each step honest & re-runnable), `providers/stellar/stellar_wallet_repo.dart` + `stellar_transfer_repo.dart` (no fallbacks), `ApiException` + 45s timeouts in `FlowPayApiClient`, `ReceiveSheet` (real address + QR via `qr_flutter` 4.1.0, testnet "Get test funds"), activation in `SetPinScreen` + "Activate wallet" state in Wallets, send-money signs the real XDR, receipt shows PENDING + explorer link.
  * Signup/KYC no longer send PII to BMONI.
  * Verified live (`test/live/stellar_transfer_live_test.dart`): two users activated; $25 USD by email (`24515f8b…`); ₦10,000 funded from USD via path payment (`14b58a5f…`); on-chain balances asserted. Backend 141/141, Flutter 179/179 (+2 opt-in live), analyzer clean.

* [x] **M3b — Missions, AI operator & FX convert**:
  * `stellar/batch.ts` — ONE atomic tx from "legs" (≤100 ops): `to: recipient|'self'`, `mode: exact_receive|exact_send`, optional `lockUntil` → payment / `pathPaymentStrictReceive` / `pathPaymentStrictSend` / `createClaimableBalance` (claimant = self, predicate `not(before(unlock))` = Stellar-native locked savings). Worst-case spend per currency checked against balances. `stellar/proposals.ts` — generic `ProposalStore` + `submitProposal` (hash match, per-user, single use, expiry). `HorizonGateway.strictSendPaths` added.
  * `modules/payments/batch_service.ts` + `/api/payments/batch/{propose,execute}` (202 PENDING on timeout). `modules/activity/record.ts` shared activity writer.
  * Missions rewritten (`modules/missions/service.ts`): **per-user** (new `money_missions.user_id`, apply `prisma/sql/2026-10-26_missions_user_id.sql`), no demo seeding for live users; propose = save rule + build first run; `/api/missions/:id/prepare` + `/execute {proposalId, signedXdr}`; HOLD-only rules activate without a tx. Allocation mapping: HOLD → none, CONVERT_FX → path payment to self, SWEEP_VAULT → convert + 30-day claimable balance, TRANSFER → pay recipient.
  * Mobile: `MissionRun` contract; `StellarMissionRepository`; missions screen signs the real run XDR (activation + "Run this rule now"); `StellarFinancialExecutionProvider` (`settlesAtomically`) → AI operator plans settle as one tx; `StellarBatchApi`; FX modal rewritten (live quote = proposal, any pair of USD/CAD/MXN/GBP/NGN, "at least" amount); approvals require the real PIN; live approval repo refuses instead of returning `true`.
  * Verified live (`test/live/stellar_missions_live_test.dart`): FX $100→MXN (`2ee6a07b…`); mission convert + locked savings in one tx (`c7eb118d…`), claimable balance asserted on Horizon. Backend 147/147, Flutter 180/180 (+3 opt-in live).

* [x] **M4 — Employees on Stellar**:
  * Backend `modules/employees/service.ts` rewritten (no BMONI): **employer-scoped** via `biz_<employerUserId>`; countries US/CA/MX/GB/NG; status INVITED → READY → SUSPENDED (constrained transitions); invite = 48-hex token, only its **SHA-256 hash stored** (`employees.invite_token_hash`, `invite_expires_at`, `linked_user_id` — apply `prisma/sql/2026-10-26_employee_invites.sql`); lookup **by token only**; accept requires same email as invite AND a proven Stellar account (wallet registration), single use; resend rotates the token. `onboarding.service.ts` (BMONI KYC/rails) deleted. Routes: `GET/POST /api/employees`, `GET /invite/:token` (JSON or **HTML-escaped** landing page), `POST /invite/:token/accept`, `POST /link-wallet` (alias), `POST /:id/resend-invite`, `PATCH /:id`.
  * Mobile: slimmed `EmployeeRepository` (list/get/create/resendInvite/getInviteDetails/acceptInvite/setEmployeeStatus); `StellarEmployeeRepository`; `EmployeeDetailScreen` rewritten (invite link copy/rotate, Stellar account + explorer, suspend/resume); `EmployeeOnboardingScreen` (employer-assisted BMONI KYC on the employer's phone) deleted; add-employee modal offers all 5 countries, no fake USD equivalent, no "test onboarding as employee" on the employer device; `InviteLink` parser; web `/invite/<token>` opens prefilled signup (signed out) or `AcceptInviteSheet` (signed in); "Join your employer's payroll" on Security screen; set-PIN accepts the invite after activation.
  * Verified live (`test/live/stellar_employees_live_test.dart`): invite by token only (email → 404), impostor with another email → 403, real employee joins with their own activated wallet. Backend 121/121, Flutter 179/179 (+4 opt-in live).

* [x] **M5 — Atomic multi-country payroll**:
  * `modules/payroll/service.ts` rewritten: preview = the real transactions. READY employees whose wallets can receive their currency become `exact_receive` legs funded from the employer's USD; ≤100 per atomic batch (split above); unpayable employees SKIPPED with reason (not joined / suspended / wallet inactive / currency not enabled); real employer balance; worst-case USD; network fee in XLM; insufficient balance → no batches to sign. Execute submits each signed batch: COMPLETED / PENDING / FAILED per batch, run COMPLETED only if all settled; single submission; employer-scoped; signed payloads never echoed back. Prisma `payroll_runs.employer_user_id`, `payroll_items.transaction_hash`, `error_reason` — apply `prisma/sql/2026-10-26_payroll_stellar.sql`. Routes: `GET /api/payroll/preview`, `POST /execute {runId, signed}`, `GET /runs`, `GET /runs/:id`.
  * Mobile: `PayrollBatchModel`, `PayrollRunModel.fromJson` (missing → UNKNOWN/0, never COMPLETED/$24,500), `StellarPayrollRepository`, `BusinessProvider.signPayrollBatches` (signs every batch XDR; demo verifies PIN only), payroll screen submits signed batches; per-employee retry replaced by "run payroll again" (batches are atomic); invented "Saved $330 (97%) vs SWIFT" replaced by the real Stellar network fee.
  * Verified live (`test/live/stellar_payroll_live_test.dart`): ₦150,000 + Mex$1,750 + £78 to three employees in ONE tx (`64fcedbc…`) for $297.82; on-chain balances asserted exact. Backend 114/114, Flutter 178/178 (+5 opt-in live).

* [x] **M6 — Anchors & KYC**:
  * `mobile/lib/core/stellar/anchors/anchor_service.dart` — client-side anchor flows (backend never sees anchor JWTs, keys or bank details): `AnchorConfig.forNetwork` (testnet: Circle testnet USDC via `testanchor.stellar.org`; mainnet: empty until licensed partners are configured), SEP-10 (`getChallenge` → `validateChallenge` with 60s clock-skew grace → vault-signed → JWT), USDC trustline on demand, SEP-24 interactive deposit/withdraw, status polling, and the exact withdrawal payment (anchor account + memo + amount) signed on device.
  * `CashInOutScreen` ("Bank" quick action on Wallets): PIN → anchor login → anchor's own page (KYC + bank details) via `url_launcher` 6.3.2 → live status → "Send X USDC" for withdrawals. Wallets "Convert" now opens the converter (it used to just switch tabs).
  * **KYC made honest**: in-app identity form = `pending` (`markKycSubmitted`), backend `/api/auth/kyc` returns `SUBMITTED` with `verification: 'anchor'` and stores `pending`; login no longer forces `verified`. Real identity verification is done by the anchor.
  * Verified live (`test/live/stellar_anchor_live_test.dart`): wrong PIN never reaches the anchor; SEP-10 JWT issued; trustline idempotent; SEP-24 deposit + withdraw sessions opened; status read back (`incomplete`).

* [x] **M7 — BMONI and cards removed**:
  * Backend: deleted `src/bmoni/*` (client, webhooks), webhook + webhook-config routes, `modules/cards`, `core/currencies.ts`, BMONI errors/`sanitizeBmoniError`, BMONI env (incl. the hardcoded API key) and the personal SMTP default, dead validator fee/rate code (`getExchangeRate` silently returned 1.0 for unknown pairs). `/api/health` reports the Stellar network; new `/api/health/stellar`. **Startup no longer seeds fake users/employees/missions into the database**; in-memory activity log no longer starts with fake entries. Auth: capabilities return `userId`; signup no longer writes `bmoni_user_id`; business currency covers CA/GB. Legacy `bmoni_*` columns and card/webhook tables are left in place (data-preserving); `prisma/sql/OPTIONAL_drop_bmoni_legacy.sql` drops them if you choose. Backend tests no longer call BMONI over the network. 91/91.
  * Mobile: deleted `packages/bmoni_embedded_*`, card repositories/sheets/demo data, `BmoniExecutionProvider` (invented fallback balances), `CurrencyMapping`; `ProviderMode.live`; `providers/live/*`; `BMoni*` widgets → `FlowPay*`; `bmoniUserId` → `flowpayUserId`, `bmoniReference` → `networkReference` (JSON still reads legacy keys; storage key kept so sessions survive); currency tokens are ISO codes (legacy tokens still parsed); all BMONI/B-Key copy rewritten. **Activity "Approve" accepted any PIN and marked items completed** — now the PIN is verified and live pending items are reconciled against Stellar by hash. 178/178.

* [x] **M8 — Real authentication + end-to-end verification**:
  * `backend/src/auth/session.ts`: HS256 session JWTs (FLOWPAY_JWT_SECRET, 12h), `requireAuth` middleware, `authedUserId(req)`. Identity now comes ONLY from the token — `x-user-id`/`userId` in body/query are ignored everywhere. Protected: wallets, transfers, payments, missions, payroll, activity, ai, banks, employees (except public `GET /invite/:token`), auth session/kyc/capabilities/email.
  * **Login = proof of wallet key**: `POST /api/auth/challenge {accountId}` → device signs with PIN-unlocked key → `POST /api/auth/login {accountId, message, signature}` → token. No password; the PIN never leaves the device. New device: restore wallet from recovery key, then sign in. Signup returns a token, IDs are server-generated, duplicate emails → 409.
  * **Email verification** (`POST /api/auth/email/send`, `/email/verify {code}`; hashed, 10 min, 5 attempts; `users.email_verified` — apply `prisma/sql/2026-10-26_email_verified.sql`) required before accepting an employee invite. `DEV_ECHO_EMAIL_CODES=true` returns codes in responses for local testing only (refused in production).
  * Activity feed queries the actor's own rows in the DB (was: global top-100 then fuzzy in-memory filtering). Payroll pay-period guard: employees paid in the last 25 days are skipped unless `?includeRecentlyPaid=true`.
  * Mobile: `FlowPayApiClient.sessionToken` (Bearer on every call, restored at startup, cleared on logout, renewed whenever the app is unlocked with the PIN); `WalletLogin`; new `LoginScreen` (unlock vs restore-from-recovery-key, PIN checked on-device first); signup stops on server errors instead of inventing a local user; invite acceptance opens after sign-in and walks through email verification.
  * **Verified live — all 6 opt-in suites pass against testnet with auth enforced** (`flutter test test/live --concurrency=1` with `LIVE_STELLAR=1`, backend run with `DEV_ECHO_EMAIL_CODES=true`): payroll NG/MX/GB in one tx, USD + NGN transfers, FX, mission with locked savings, employee invite (impostor 403, unverified email blocked, unauthenticated 401), anchor SEP-10/24. Backend 95/95, Flutter 179/179.

## 🐞 Bug inventory (found during migration, fix in M7 unless noted)

* ~~Fixed in M8~~: **no API authentication** (identity from `?userId=`/`x-user-id`, default sandbox master); **login checked only the email** (PIN ignored) and returned a fake token `flowpay_jwt_<id>`; **signup accepted a client-chosen userId and upserted over existing users** (account takeover); **public open mail relay** `/api/mail/send` (+ `/otp`, `/invite` for phishing-grade emails) — removed; email ownership never verified (invite hijack); activity feed missed users' events beyond a global top-100; payroll could pay the same period twice; mail test asserted a personal Gmail address.
* Hardcoded, inconsistent FX (`1550` NGN, `17` vs `17.5` MXN) in transfers/payroll/missions — replaced by Horizon path quotes in M3/M4.
* ~~Fixed in M2~~: BMONI signer used a hardcoded PIN `'123456'` when none was passed; web/native "wallets" fell back to one shared fake address `0x71C8…` and synthesized signatures; PIN set/change/remove errors swallowed; app-lock PIN stored in plaintext (now salted PBKDF2, or vault-verified); **logout deleted the wallet** (would destroy funds); set-PIN screen fabricated an auth token `flowpay_jwt_<id>` and showed "wallet linked to payroll" even when linking failed; employer-assisted onboarding created the employee's wallet on the employer's device; security/provisioning screens displayed & copied a fake address when no wallet existed; tests approved payments with a 4-digit PIN.
* `personal_provider.approveAction` signs a hardcoded constant hash and discards the signature (signing theatre) — replace with real Stellar tx in M3.
* Employer-assisted onboarding (`EmployeeOnboardingScreen` stage 2) now refuses until the employee has created their own wallet — redesign in M5.
* New-device login: user has no local wallet → needs "restore from recovery key" UX (M7/M8).
* ~~Fixed in M3a~~: backend `executeTransfer` fabricated tx hashes + COMPLETED for any non-BMONI proposal, credited an in-memory ledger, and **invented recipients** (name contains "bunch" → hardcoded Nigerian user; unknown names → `usr_<name>`); mobile live wallet repo showed invented balances ($24,500 etc.) on any error, signed with `'0x_signed_challenge_placeholder'`, debit/credit always `true`; mobile transfer repo returned `'EXECUTED'`/`'0x_bmoni_onchain_settled'`, fixed proposal hash fallback, hardcoded fees, prompt parser defaulted to **$500**; `TransferExecutionResult.fromJson` defaulted status to COMPLETED; fuzzy recipient match (`fullName.includes`); unauthenticated `/api/wallets/register` could redirect anyone's incoming funds; "Receive" sheet credited arbitrary amounts from nowhere; wallets screen spinner hung forever on error, invented a 15% "reserved" split, and showed "Waffiyyi Fashola" on every user's card; `validateIntent` errors were 500s; EUR accepted/GBP rejected; no HTTP timeouts; signup/KYC sent PII to BMONI with fabricated defaults (DOB 1992-04-18, "14 Admiralty Way").
* ~~Fixed in M6~~: KYC was self-certified (always VERIFIED with $10k–$1M limits); Wallets "Convert" didn't open the converter.
* ~~Fixed in M3b~~: mission execution moved no money (recorded COMPLETED, invented a transfer to "Mary Fashola (Mom)" with ref `rail_tx_active`, manual trigger signed a hardcoded hash); missions not user-scoped and every user saw seeded demo missions; mission toggle returned a fabricated "active" mission on failure; AI-operator non-send actions used the demo provider in live mode with fake tx hashes and PIN fallback `'000000'`; FX conversion moved no money (fixed 1550 rate, $1,000 default); approvals signed a constant hash and live approve returned `true`; **mobile serialized mission enums as `CONVERTFX`/`SWEEPVAULT`/`SPLITINCOMING` so every live mission proposal was rejected** (masked by the old fallback).
* ~~Fixed in M5~~: payroll preview showed hardcoded personas, every employer saw every employee, balance hardcoded $24,500, fees/97% savings invented, hardcoded FX, US/GB employees dropped; mobile signed one hash per employee then sent only the first signature (and the screen signed a constant hash); per-employee retry passed the signature as the PIN so it never ran; item status defaulted to COMPLETED.
* ~~Fixed in M4~~: every employer saw every employee; invite lookup by **email or employee id issued a fresh token** (with unverified signup emails → salary hijack); invite landing page had **stored XSS**; invites lived only in memory; employer-assisted onboarding created employee wallets on the employer device; add-employee labelled every non-NG employee "Mexico" and invented a $2,000 USD equivalent; only NG/MX selectable.
* `MissionRuntimeEngine.processEvent` is a local simulation only reachable from tests (not wired into live UI).
* Open items: AI-operator beneficiaries ("mom") still come from the demo beneficiary list in live mode (they only resolve if they are real emails/phones/G-addresses) — needs a persisted contacts store; recovery-key backup should be prompted during onboarding; the web build stores the PIN-encrypted key in browser storage (weaker than mobile keychains).
* AI operator beneficiaries ("mom", "dad") come from `DemoBeneficiaryRepository` even in live mode; on Stellar they resolve only if they are exact emails/phones/G-addresses → needs a real beneficiaries store (M7).
* `backend/.env` points at the **production Supabase DB**; local runs/tests must override `DATABASE_URL` (live tests use an unreachable URL → in-memory).
* `FlowPayApiClient` defaults userId to `usr_flowpay_sandbox_master` (M7 auth).
* `Currency.fromCode` silently maps unknown codes to USD (Stellar layer uses strict `stellarCurrencyFor`; audit remaining callers in M7).
* `config/env.ts` ships a real BMONI API key and a personal SMTP address as defaults — removed in M6.

## 🎯 5. Milestone Plan (each milestone = one pushed commit set, tests green)

* [x] **M1 — Stellar backend core** (see §4).
* [x] **M2 — On-device keys & signing** (see §4).
* [x] **M3a — Wallets & transfers** (see §4).
* [x] **M3b — Missions, AI operator & FX convert on Stellar** (see §4).
* [x] **M4 — Employees on Stellar** (see §4).
* [x] **M5 — Atomic multi-country payroll** (see §4).
* [x] **M6 — Anchors & KYC** (see §4).
* [x] **M7 — Remove BMONI entirely** (see §4).
* [x] **M8 — Auth, end-to-end tests & bug sweep** (see §4).
* [x] **M9 — Redesign & visual bug sweep** (Stellar design language, verified by screenshots of every screen in dark + light):
  * **Tokens** (`mobile/lib/core/theme/`): off-black `#0F0F0F` / paper `#F9F9F9` neutrals, **gold `#FDDA24`** primary actions
    (`onGold` text), teal `#00818B`/`#00A7B5` accents, lilac `#B7ACE8` for AI. Low-radius geometry (cards 12, hero 16,
    inputs 10, sheets 20), pill buttons. Lora serif for display (`headline`, `heroSerif`), uppercase `eyebrow`.
    Context helpers `selectedOf` / `onSelectedOf` / `accentTextOf` — use them instead of light-only tokens on surfaces
    that also render in dark mode.
  * **Screens**: new landing (grid + gold glow, "BUILT ON STELLAR"), theme-aware signup cards/country picker, web splash +
    manifest. Balance hero card is teal→black; card-era "Holder"/"Exp Date" rows hidden.
  * **Honesty fixes found during visual QA**:
    * Business audit screen rendered a **hardcoded fake list** (Polygon, "Virtual Mastercard", $38.5k payroll) for every
      account — now reads `BusinessProvider.auditActivities` (demo repo in demo mode, Stellar-backed live), with loading,
      error (+retry) and empty states. `LiveBusinessAuditRepository` no longer swallows activity-load errors.
    * `TransactionStatusX.fromString` mapped unknown statuses (incl. camelCase `awaitingApproval`) to **COMPLETED** — now
      parses camelCase and defaults unknown/null to `processing`; `cancelled` is never completed.
    * Security screen claimed "Your account is secured · BANK-GRADE ENCRYPTION" with no wallet/PIN; biometric row was
      hardcoded ENABLED. Now driven by the vault + `AppLockService.canAuthenticate()`.
    * Card remnants removed from business UI (metrics tile, employee "Card:" chips, "virtual cards" copy); business
      country metric computed from employees.
    * Recipient parsing recognises Stellar account IDs (`G[A-Z2-7]{55}`) instead of EVM `0x…`; pasted addresses resolve
      as **unverified** `stellar_account` beneficiaries. Demo data uses checksum-valid G-addresses and 64-hex hashes.
  * **Preview harness** `mobile/lib/main_preview.dart` (dev-only, never shipped): renders one screen with demo data —
    `flutter build web -t lib/main_preview.dart -o build/preview`, then `?screen=dashboard|wallets|send|missions|activity|security|bank|business|team|payroll|audit&theme=dark|light`.
  * Tests: 179 pass / 6 opt-in live skipped; analyzer clean.
* [x] **M10 — Web deploy & docs**:
  * [x] README rewritten for the Stellar build (on-chain proof table with verified testnet tx hashes, signing flow,
        Stellar primitives map, security model + honest limits, setup, env reference); screenshots in `docs/screenshots/`.
  * [x] Production refuses to start with the public default `FLOWPAY_JWT_SECRET` (or any secret < 32 chars) —
        **set it on Render before the next deploy or the API will not boot**.
  * [x] Business hero card: hardcoded "Traditional Wire ~$340" comparison removed.
  * [x] **Real payroll recorded through the web UI** (`docs/demo/flowpay-payroll.{gif,mp4}`, tx `08a8bc43…`). Driving it
        live exposed and fixed: UK employees labelled Canada, 0/N "onboarded" for joined (READY) employees, team-wallet
        count using the employer's wallets, invented "Saved (97%)" in live mode, 16-dp rates, "$0.00 / no payroll" while
        the first preview is still being quoted, two overflowing rows. Country name/flag now from
        `EmployeeModel.nameForCountry` / `flagForCountry`.
  * [x] **Quick wins for ecosystem reviewers**: MIT `LICENSE`; GitHub Actions `ci.yml` (backend build + 100 tests,
        app analyze + 180 tests, every push/PR, fully offline); README section positioning FlowPay vs SDF's Stellar
        Disbursement Platform (complementary).
  * [x] **SEP-1 + SEP-2** (`backend/src/stellar/federation.ts`, `routes/federation.routes.ts`): `/.well-known/stellar.toml`
        (only FlowPay-issued assets, `status="test"` on testnet) and `/federation` (type=name|id). Payment names are
        **opt-in** (`POST /api/auth/handle`, requires linked wallet, `users.stellar_handle` — apply
        `prisma/sql/2026-10-27_stellar_handle.sql`); unclaimed users/emails are never discoverable. Own-domain names resolve
        locally when sending. Home domain = `FLOWPAY_HOME_DOMAIN` or the request host. App: Receive sheet claims/shows
        `name*domain`. **After deploying**, run `FLOWPAY_HOME_DOMAIN=<render host> npm run stellar:bootstrap` locally to
        set the issuer `home_domain` (idempotent).
  * [x] **Render is live on the Stellar build** (2026-10-27, `main` @ `1f72d10`, https://flowpay-k2wn.onrender.com):
        `/api/health` → `stellarNetwork: testnet`, `/.well-known/stellar.toml` + `/federation` public, Soroban vault set.
        Verified end to end against the deployed API (live transfer suite: `a4303f31…`, `929e79fb…`). Issuer
        `home_domain` = `flowpay-k2wn.onrender.com` (`6f3c4a0b…`). Render runs without a database (in-memory; data resets
        on restart/spin-down) — apply `prisma/sql/2026-10-2*_*.sql` before pointing it at Supabase. Render's Mailgun is a
        sandbox domain (can only email authorised recipients). Note: the service had been deploying a stale commit
        (`88afd1b`) until `main` was merged; deploys now auto-run from `main`.
  * [ ] Deploy web (Vercel, `build-web.sh`) + API (Render) from this branch; apply `backend/prisma/sql/2026-10-26_*.sql`
        to Supabase (ask the owner first); update `FLOWPAY_API_URL` if the API URL changes.

* [x] **M11 — Soroban payday guarantee**:
  * [x] `contracts/payroll_vault` (soroban-sdk 29.0.1, protocol 29): `fund` (employer auth, 1–100 employees, unlock in
        future) / `claim` (employee auth) / `release` (anyone; only ever pays the recorded employee) / `reclaim` (employer,
        only 30 days after payday) / `payroll` / `salary`. 7 Rust tests; CI job `contracts`.
  * [x] Backend `stellar/soroban.ts` (injectable RPC gateway, honest COMPLETED/FAILED/PENDING, plain-language contract
        errors), `modules/payroll/guarantee_service.ts`, routes `/api/payroll/guarantees/*`; 6 tests. Guarantees are
        tracked in memory (chain is the source of truth for amounts/paid state).
  * [x] App: `PaydayGuaranteeSection` (Payroll screen) and `GuaranteedPayCard` (personal dashboard); demo simulation.
  * [x] Built with `stellar contract build` (stellar-cli 28.1 via `cargo install --locked stellar-cli`; Homebrew on macOS
        Monterey would compile LLVM from source). Deployed by `npm run stellar:deploy-vault`: USD SAC
        `CBP4JEE7…GG4E6N2`, **PayrollVault `CC7FY73K6K44J5UFOGAPEDGNNF44OOM22LXO7EMGRAXPIQYIKS3GBSSF`**.
  * [x] Live test `test/live/stellar_guarantee_live_test.dart`: fund `ec382dc0…`, early claim refused, claim `c0c02e77…`,
        release `1420c9b8…`, balances asserted. First deployment rented storage to max TTL (fund 14.79 XLM); fixed to
        payday + 30 days (fund 4.53 XLM; claim/release ~0.001 XLM).
  * Render needs `STELLAR_PAYROLL_VAULT_ID` (and `SOROBAN_RPC_URL` optional) after deploy. Possible follow-ups: one storage
        entry per payroll to cut rent further; convert to local currency on release via an AMM.
  * Honest limits: salaries are reserved and paid in USD (the employee converts afterwards); converting on release would
        need an AMM contract call.

* [x] **M12 — Wallet safety & cheaper guarantee**:
  * Recovery-key backup: `RecoveryKeyBackupScreen` after a NEW wallet at sign-up (confirm by re-typing the last 4 chars;
        "later" allowed), Security "Recovery key" (SAVED / NOT SAVED, PIN-gated reveal via
        `RecoveryKeyBackupScreen.revealWithPin`), dashboard `RecoveryBackupReminder`. Vault flag
        `flowpay_stellar_vault_backed_up` = public key of the backed-up wallet (import ⇒ backed up; delete clears).
  * PayrollVault v3: salaries in a `Map` inside the single payroll entry (paid → 0). The ~4.4 XLM "funding fee" was a
        one-time warm-up (contract code+instance rent for 60 days); steady-state funding is **0.024 XLM**
        (`ffdb831e…`). `stellar:deploy-vault` now pre-pays that rent (ExtendFootprintTTL; `--extend-only` to top up).
        Current vault **`CDE7O32BANGSQOZG4BBBKTWOOLM66H6EVALBLGJ3EAF5D7NMMNDJJCYS`** — update Render's
        `STELLAR_PAYROLL_VAULT_ID`. Re-run `--extend-only` within ~60 days if no guarantees are funded meanwhile.

* [x] **Payday-guarantee recording** (`docs/demo/flowpay-guarantee.{gif,mp4}`; fund `a701b364…` 0.025 XLM, claim
        `91b69720…`). Filming exposed + fixed: `WalletPinAuthSheet` used the light paper colour in dark mode (title
        white-on-white) — now theme-aware; dashboard balance stale after claiming — `GuaranteedPayCard.onClaimed` refreshes.
        Testnet-only "In 2 minutes (testnet)" payday choice for demos.

* [x] **M13 — Passkey key vault (web)** (owner chose this over Soroban smart wallets: contract accounts can't use the
        classic path payments / pools / claimable balances FlowPay is built on):
  * `web/passkey.js` (WebAuthn bridge, PRF required at registration) + `core/stellar/passkey/` (`PasskeyAuthenticator`,
        web impl via `dart:js_interop`, unsupported stub on native). Dart SDK minimum raised to 3.3.
  * Vault blob v2 `kdf: webauthn-prf-hkdf` (PRF output → HKDF-SHA256 → AES-256-GCM); `enablePasskey` requires saved
        recovery key + PIN and deletes the PIN-encrypted copy; `disablePasskey` → new PIN. Unlock/sign with the sentinel
        `StellarKeyVault.passkey` as the `pin` argument (every existing call site works unchanged). Cancels never count as
        failed attempts.
  * UI: Security "Face ID / passkey" (only where supported), PIN sheet "Confirm with passkey", lock screen "Unlock with
        passkey" (one prompt: sign-in both proves the user and renews the session; local check only if offline).
  * Verified in real Chrome with CDP `WebAuthn.addVirtualAuthenticator({hasPrf:true})`: bridge (32-byte, salt-stable PRF),
        enable → lock → unlock → $500 testnet payment confirmed by passkey (`1e0c35c4…`). Fixed along the way: FlowPayButton
        labels overflowed at phone width (now ellipsize); PIN wording/badges/duplicate biometric button in passkey mode.
  * Native apps still use PIN + OS keychain (PRF on native needs a platform plugin — follow-up).

* [x] **M10 deployed (2026-10-28)**: web app on Vercel — https://flowpay-salawuolayiwolas-projects.vercel.app
        (project "flowpay", builds from the fork `OlayiwolaSherrifSalawu/flowpay` main; Root Directory `./`;
        `vercel.json`: `framework: null`, `bash build-web.sh` with Flutter 3.47.2, `rewrites` SPA fallback — the old file
        mixed `routes`+`headers`, which Vercel rejects). Deployment Protection off. `flowpay-stellar.vercel.app` was chosen but
        is not attached yet (DEPLOYMENT_NOT_FOUND) — passkeys bind to whichever domain users register on, so settle it early.
        Verified: assets, `/invite/*` deep links, wasm MIME, CORS to Render, and a real $500 payment through the live site +
        API (`ae103881…`).

## 🛠️ 6. Runbook & Verification

```bash
# Testnet health
curl -s https://horizon-testnet.stellar.org/ | head
# Inspect any account / tx
open https://stellar.expert/explorer/testnet/account/<G...>
# Backend tests
cd backend && npm run build && npm test
# Mobile
cd mobile && flutter analyze && flutter test
```
