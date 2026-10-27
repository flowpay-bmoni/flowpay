<div align="center">

<img src="mobile/assets/images/flowpay_logo_256.png" width="88" alt="FlowPay" />

# FlowPay

### Pay anyone, anywhere. Settled in seconds.

**Cross-border payroll and personal money for people who work across borders, built on the Stellar network.**
One employer pays a team in the 🇺🇸 US, 🇨🇦 Canada, 🇲🇽 Mexico, 🇬🇧 UK and 🇳🇬 Nigeria in a **single atomic Stellar transaction**, signed on the employer's phone. FlowPay never holds a key.

[![Stellar Testnet](https://img.shields.io/badge/Stellar-Testnet-FDDA24?style=for-the-badge&logo=stellar&logoColor=black)](https://stellar.expert/explorer/testnet)
[![Soroban](https://img.shields.io/badge/Soroban-Payday%20guarantee-B7ACE8?style=for-the-badge)](#-soroban-payday-guarantee)
[![Non-custodial](https://img.shields.io/badge/Keys-On%20device-0F0F0F?style=for-the-badge)](#-security-model)
[![SEP-1 · 2 · 10 · 24](https://img.shields.io/badge/SEP-1%20·%202%20·%2010%20·%2024-00A7B5?style=for-the-badge)](#-what-we-use-from-stellar)
[![CI](https://github.com/flowpay-bmoni/flowpay/actions/workflows/ci.yml/badge.svg)](https://github.com/flowpay-bmoni/flowpay/actions/workflows/ci.yml)
[![Tests](https://img.shields.io/badge/Tests-309%20passing-12A150?style=for-the-badge)](#-tests)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-iOS%20·%20Android%20·%20Web-02569B?style=for-the-badge&logo=flutter&logoColor=white)](mobile/)

[**🔗 Live demo (testnet)**](https://flowpay-salawuolayiwolas-projects.vercel.app) · [**Watch it run**](#-watch-a-real-payroll-run) · [**Payday guarantee**](#-soroban-payday-guarantee) · [**On-chain proof**](#-dont-trust-us-check-the-ledger) · [**How it works**](#-how-it-works) · [**Stellar features used**](#-what-we-use-from-stellar) · [**Run it in 10 minutes**](#-run-it-yourself) · [**Road to mainnet**](#-road-to-mainnet)

<br/>

<img src="docs/screenshots/landing.png" width="180" alt="Landing" />&nbsp;
<img src="docs/screenshots/dashboard.png" width="180" alt="Personal dashboard" />&nbsp;
<img src="docs/screenshots/wallets.png" width="180" alt="Multi-currency wallets" />&nbsp;
<img src="docs/screenshots/audit.png" width="180" alt="Business audit log" />&nbsp;
<img src="docs/screenshots/passkey.png" width="180" alt="Confirm a payment with a passkey" />

<sub>Screens from the app's labelled demo mode. Live mode shows the same UI over your real testnet balances.</sub>

</div>

---

## ▶ Watch a real payroll run

<div align="center">
<img src="docs/demo/flowpay-payroll.gif" width="300" alt="FlowPay running a real payroll on Stellar testnet" />
</div>

**Unedited, 67 seconds, real testnet.** An employer unlocks FlowPay with their PIN and reviews a team in 🇬🇧 the UK, 🇲🇽 Mexico and 🇳🇬 Nigeria. They approve one bill (quoted at most **$298.10**) and sign it on the device. Each person then receives their exact salary in their own currency in **one atomic Stellar transaction**: [`08a8bc43…`](https://stellar.expert/explorer/testnet/tx/08a8bc432282b0eb2671783844c67f259fbe0c2d33c9b7d0fbf396d138fdafee) (actual cost $298.07, fee 0.00003 XLM). The video ends on that transaction in StellarExpert. [Full-quality MP4](docs/demo/flowpay-payroll.mp4)

---

## The problem

A startup in Austin employs a designer in Lagos, an engineer in Guadalajara and a writer in Manchester. Every month it pays three wires, three FX spreads and three sets of intermediary fees. The money arrives days later, and the employer can't see where it is in between. For the person in Lagos, a late or short salary isn't an inconvenience. It's rent.

## The FlowPay answer

**One employer. Many countries. One bill.** The employer funds payroll in USD. FlowPay builds **one Stellar transaction** containing a path payment for each employee. Each employee receives their **exact salary in their own currency**: ₦ for Nigeria, Mex$ for Mexico, £ for the UK. The transaction settles in about 5 seconds, and either **every employee is paid or nobody is**. There are no half-finished payroll runs and no "where is my money" tickets.

The same rails power a personal wallet for USD, CAD, MXN, GBP and NGN, with transfers, currency conversion, locked savings and plain-English money rules.

---

## 🔎 Don't trust us, check the ledger

Every row below is a real, successful transaction on **Stellar testnet**. FlowPay's backend built it, a user's device signed it, and it was then submitted to Horizon. The first row comes from the recording above. The rest come from our opt-in live test suites (`mobile/test/live/`), which assert the resulting on-chain balances.

| What happened | Stellar operations | Transaction |
| :--- | :--- | :--- |
| **The payroll in the video above.** The employer paid $298.07 USD from the web app; employees received **£78**, **Mex$1,750** and **₦150,000** | 3 × `path_payment_strict_receive`, atomic | [`08a8bc43…`](https://stellar.expert/explorer/testnet/tx/08a8bc432282b0eb2671783844c67f259fbe0c2d33c9b7d0fbf396d138fdafee) |
| **Payroll to 3 countries in one transaction.** The employer paid $297.80 USD. Employees received exactly **₦150,000**, **Mex$1,750** and **£78**. Fee: 300 stroops (0.00003 XLM). | 3 × `path_payment_strict_receive`, atomic | [`64fcedbc…`](https://stellar.expert/explorer/testnet/tx/64fcedbcd650f5394092d89b41e50a3a44eb32bb82d888c2553f7fbcea59d72a) |
| **A second payroll run**, same team, same guarantees | 3 × `path_payment_strict_receive` | [`7da85d6a…`](https://stellar.expert/explorer/testnet/tx/7da85d6a7f44647dd3498b986c493c8cf134c3f2eb69b4f4e46eabf5e4869bab) |
| **Money mission.** "Split $200: half to naira, half locked in savings for 30 days." Converts $100 → ₦154,517 **and** locks $100 that only the owner can claim, and only after the unlock date | `path_payment_strict_send` + `create_claimable_balance` (`not(before(t))` predicate) | [`c7eb118d…`](https://stellar.expert/explorer/testnet/tx/c7eb118da2f876bfbc9bba077bb94f149ec1de219bac14a785edb929c1eb1e22) |
| **Currency conversion to self.** Exactly $100 → Mex$1,743.53 through a USD/MXN liquidity pool | `path_payment_strict_send` | [`2ee6a07b…`](https://stellar.expert/explorer/testnet/tx/2ee6a07bb8c8a50eadcdf81b5f48f8f3c3d5f611c4541e2264bd0c118857575f) |
| **Cross-currency send.** The recipient gets exactly ₦10,000; the sender pays $6.47 | `path_payment_strict_receive` | [`14b58a5f…`](https://stellar.expert/explorer/testnet/tx/14b58a5fe2efb34b6e0c12be3036c3ed7b429b7b714396b89fbf877691c2b969) |
| **Payment through the live deployment.** $500 sent by email from the public web app ([live demo](https://flowpay-salawuolayiwolas-projects.vercel.app)) via the Render API | `payment` | [`ae103881…`](https://stellar.expert/explorer/testnet/tx/ae10388170c5b0e29e63df4963a58b658f4540ab3c91e6743b47d83bc3b0612f) |
| **Send by email.** $25 to a user looked up by email, resolved to their `G…` account | `payment` | [`24515f8b…`](https://stellar.expert/explorer/testnet/tx/24515f8b517acbfc818b939d05c9aefd4e8074fec9f8303198fae5b8f3a44797) |
| **Payday guarantee locked on Soroban.** An employer locked $20.11 for two employees in the PayrollVault contract until payday | `invoke_host_function` → `fund` | [`efe564e0…`](https://stellar.expert/explorer/testnet/tx/efe564e00b097c20946f87b7fe06cdf087bceb6826f56a251de4ee75a299be30) |
| **Early claim refused, then claimed on payday.** The contract rejected the employee's claim before payday; after it, she claimed her $10.05 | `claim` | [`b3aca055…`](https://stellar.expert/explorer/testnet/tx/b3aca055f9f5a6c790668c0161091d4f9d22b95440c7789239cd0e9d8e5d223a) |
| **Released by the employer on payday.** The other salary pushed to its employee (the contract can only pay the recorded employee) | `release` | [`4b21ba3a…`](https://stellar.expert/explorer/testnet/tx/4b21ba3add1dbadbd3019438eb06dfa1c629245683e8dba4c1a05e8686cd3599) |
| **Payment approved with a passkey.** $500 sent from the web app after the user confirmed with their passkey (WebAuthn PRF), with no PIN involved | `payment` | [`1e0c35c4…`](https://stellar.expert/explorer/testnet/tx/1e0c35c4a2e810186c03b7a239bcf0e1a5991e3b9aeec862453355be5e9c0196) |
| **First device-signed transaction.** Trustlines created by a key that exists only on the phone | `change_trust` × 2 | [`e1b1277a…`](https://stellar.expert/explorer/testnet/tx/e1b1277ae1f74f551b15b5b5437b69525596901e0163049b9f21589a60342955) |

PayrollVault contract: [`CDE7O3…DJJCYS`](https://stellar.expert/explorer/testnet/contract/CDE7O32BANGSQOZG4BBBKTWOOLM66H6EVALBLGJ3EAF5D7NMMNDJJCYS). FlowPay's testnet treasury: issuer [`GD3JY7…XWN433`](https://stellar.expert/explorer/testnet/account/GD3JY73LVFKPRAKV6QYLBKYBTDHP7WFVJQBQZVAWL5WT2FISH6XWN433) · distributor / market maker [`GBX5PM…MOS56`](https://stellar.expert/explorer/testnet/account/GBX5PMNBNNG5SJLK5QZHVLOSCGK6O3RNXJPYNM7JB7XOWQRYAZSMOS56).

> Stellar resets testnet periodically. If a link stops resolving, `npm run stellar:bootstrap` plus the live suites recreate everything from scratch. See [Run it yourself](#-run-it-yourself).

---

## 🔁 How it works

The device holds the key, the backend holds no secrets that belong to users, and Horizon is the source of truth.

```mermaid
sequenceDiagram
    autonumber
    participant D as 📱 Device (Flutter)
    participant B as 🖥️ FlowPay API (Node)
    participant H as ⭐ Horizon (testnet)

    D->>B: "Run payroll" (session JWT)
    B->>H: Load balances, find paths (USD → NGN / MXN / GBP)
    B-->>D: Proposal: unsigned XDR, ≤100 ops, worst-case cost, fee in XLM
    Note over D: User reviews the exact transaction,<br/>enters PIN → key decrypted in memory → ed25519 signature
    D->>B: Signed XDR
    B->>B: Hash(signed tx) == proposal ID? Single use? Same user? Not expired?
    B->>H: Submit
    alt Horizon: successful + hash
        H-->>B: ✅ COMPLETED, real hash stored, explorer link
    else Horizon: result_codes
        H-->>B: ❌ FAILED, with the real error
    else Timeout
        H-->>B: ⏳ PENDING, reconciled later by hash, never re-submitted blindly
    end
    B-->>D: Honest status
```

**Why the proposal ID is the transaction hash.** The backend can't be tricked into submitting a different transaction than the one the user reviewed. A swapped amount, destination or extra operation changes the hash, and the submission is rejected.

---

## ⭐ What we use from Stellar

| Stellar primitive | What FlowPay does with it |
| :--- | :--- |
| **Atomic multi-operation transactions** (≤100 ops) | Payroll for a whole team in one transaction: all paid or none. Larger teams are split into 100-op batches, each reported separately. |
| **`pathPaymentStrictReceive`** | "Employee gets exactly ₦150,000." The employer's USD cost is quoted live from path-finding with a 1% `sendMax` slippage cap. |
| **`pathPaymentStrictSend`** | "Convert exactly $100." Used for FX to self and for money-mission splits. |
| **Liquidity pools (AMM)** | USD/CAD, USD/MXN, USD/GBP and USD/NGN pools seeded at reference rates provide on-chain FX for test assets. |
| **Claimable balances + time predicates** | Locked savings vaults: `claimant = self`, `predicate = not(before(unlock))`. The lock is enforced by the ledger, not by our database. |
| **Issued assets + trustlines** | FlowPay-issued test USD/CAD/MXN/GBP/NGN. Codes and issuers are configuration, so mainnet swaps in real anchored assets without code changes. |
| **SEP-10** web authentication | The device proves ownership of its key to the anchor (challenge validated with a 60 s clock-skew grace). The anchor JWT never touches FlowPay's servers. |
| **SEP-24** interactive deposit/withdraw | "Add money" and "Cash out" through the anchor's own KYC and bank pages ([`testanchor.stellar.org`](https://testanchor.stellar.org), Circle testnet USDC). |
| **WebAuthn passkeys (PRF)** | Web wallets can be unlocked and payments confirmed with Face ID / fingerprint; the Stellar key is encrypted under the passkey's PRF secret. |
| **ed25519 message signing** | Passwordless login: the server issues a challenge, the device signs it with the wallet key, and the server issues a session token. |
| **Soroban smart contract** | The [payday guarantee](#-soroban-payday-guarantee): an employer locks next payday's payroll; it's paid on payday and can't be pulled back early. |
| **Stellar Asset Contract** | FlowPay USD wrapped for Soroban, so the contract holds and pays the same asset the app uses. |
| **SEP-1 `stellar.toml`** | Published at `/.well-known/stellar.toml`: FlowPay's federation server, accounts and test assets (marked `status="test"`). Running `stellar:bootstrap` with `FLOWPAY_HOME_DOMAIN` set points the issuer's `home_domain` at it, so explorers can show the assets' names. |
| **SEP-2 federation** | Opt-in payment addresses: claim `ada` and be paid at `ada*<FlowPay domain>` from any Stellar wallet. Only claimed names resolve, so the server can't be used to discover who has an account. |
| **Memos** | Payroll and transfer references (≤28 bytes) on every payment. |
| **Friendbot** | One-tap testnet activation (gated to `STELLAR_NETWORK=testnet`). |

---

## 🔒 Soroban payday guarantee

<div align="center">
<img src="docs/demo/flowpay-guarantee.gif" width="300" alt="FlowPay payday guarantee on Soroban testnet" />
</div>

**Recorded live on testnet ([full-quality MP4](docs/demo/flowpay-guarantee.mp4)).** The employer locks payday for two people ([`a701b364…`](https://stellar.expert/explorer/testnet/tx/a701b364b6ef7037f9f7cfbbc76d2600c6dd77dac2e6bc2d2856910e0de0fd22), fee 0.025 XLM). The employee sees *"Your pay is guaranteed"*. On payday she claims her $97.22 with her PIN ([`91b69720…`](https://stellar.expert/explorer/testnet/tx/91b69720eaef0d443558ea35266dcf6b8ebe4595b9fe368da224e11b49c562ce)), her balance updates, and the video ends on the contract call in StellarExpert. The wait for payday is cut; nothing else is edited.

Contractors abroad carry the risk of late or missing pay. FlowPay lets an employer **lock next payday's payroll in a Soroban smart contract** ([`contracts/payroll_vault`](contracts/payroll_vault/src/lib.rs)) ahead of time:

- **Employees can verify it.** The app shows "Your pay is guaranteed: $X, unlocks on <date>" with a link to the contract on-chain.
- **The employer can't take it back early.** Funds unlock at payday. The employer can recover only *unclaimed* salaries, and only 30 days after payday.
- **It can only go to the right person.** On payday each employee can `claim` their salary, or anyone, such as FlowPay's backend, can `release` it, but the contract only ever pays the employee recorded for it.
- **Signed on device, like everything else.** The backend simulates the contract call (footprint, fees, auth) and the employer's phone signs it.

| | |
| :--- | :--- |
| Contract | Rust, `soroban-sdk` 29, 7 KB WASM; 9 unit tests (incl. a full 100-person payroll within real network budgets) ([`test.rs`](contracts/payroll_vault/src/test.rs)) |
| Deployed (testnet) | [`CDE7O32B…`](https://stellar.expert/explorer/testnet/contract/CDE7O32BANGSQOZG4BBBKTWOOLM66H6EVALBLGJ3EAF5D7NMMNDJJCYS) holding FlowPay USD through its Stellar Asset Contract |
| Cost | Funding a guarantee ≈ **0.024 XLM** ([`ffdb831e…`](https://stellar.expert/explorer/testnet/tx/ffdb831e0625a45aaa9c5c340047a256085e9a9775a157e0c445c7ab9e6a6098)); claim/release ≈ 0.001 XLM. All salaries live in one storage entry, and the deployer pre-pays the contract's own rent, so employers never pay a warm-up. |
| Proven live | Lock → early claim refused → claim on payday → release, with on-chain balances asserted ([`stellar_guarantee_live_test.dart`](mobile/test/live/stellar_guarantee_live_test.dart)) |

**Honest limit:** salaries are reserved and paid in USD. The employee converts to local currency afterwards in the app; converting automatically at release would need an AMM contract call.

---

## 🤝 FlowPay and the Stellar Disbursement Platform

Stellar already has a great tool for bulk payouts: SDF's open-source [Stellar Disbursement Platform (SDP)](https://developers.stellar.org/platforms/stellar-disbursement-platform). We see FlowPay as complementary to it, not a replacement.

| | Stellar Disbursement Platform | FlowPay |
| :--- | :--- | :--- |
| **Built for** | Organizations running disbursement programs (aid, payouts at scale), self-hosted (Helm/Kubernetes) | A small employer with a remote team, who needs nothing to host and runs payroll from a phone or browser |
| **What recipients get** | Each disbursement pays out the one asset the admin selects (e.g. USDC) | Each employee gets **their exact salary in their own currency** (₦, Mex$, £, C$, $) via `path_payment_strict_receive`, with the whole team in one atomic transaction |
| **Onboarding** | CSV upload; recipients verify by phone OTP + an identity field, then register through SEP-24 or a passkey [embedded wallet](https://developers.stellar.org/docs/platforms/stellar-disbursement-platform/admin-guide/embedded-wallets) | Invite link bound to a verified email; the employee joins with a wallet whose key lives only on their device |
| **After payday** | Funds sit in the recipient's wallet | The same app is the employee's wallet: send, convert, lock savings and cash out through an anchor (SEP-24) |

**How they could work together:** SDP's passkey smart wallets are where we want FlowPay's web wallet to go (see the [road to mainnet](#-road-to-mainnet)), and an employer paying thousands of people could hand that run to an SDP deployment. FlowPay's own focus is the small-team, multi-currency payroll experience.

---

## ✨ Features

**Personal**
- **One wallet, five currencies.** USD · CAD · MXN · GBP · NGN, with balances read live from Horizon.
- **Send** to a `G…` address, an email, a phone number or a federation address (`name*domain`). Recipient resolution is strict: an ambiguous match is an error, never a guess.
- **Receive** with a payment address you choose (`ada*<FlowPay domain>`, SEP-2), or your raw address and a QR code.
- **Convert** between any pair at a live path-payment quote. The quote *is* the transaction you sign.
- **Money missions.** Describe a rule in plain English ("keep 30%, convert 50% to naira, lock 20% for tax"). FlowPay compiles it into Stellar operations and shows the exact transaction, and you approve it with your PIN. The AI interprets; it never signs.
- **See guaranteed pay** an employer locked for you on Soroban, and claim it on payday.
- **Bank in/out** through a Stellar anchor (SEP-24), with KYC handled by the anchor.

**Business**
- **Invite employees by link.** The employee joins with *their own* wallet. Invites are bound to the invited email (verified), single use, and only the SHA-256 hash of the token is stored.
- **Payroll preview = the real transactions.** It shows who gets paid, the exact local amounts, the worst-case USD cost and the network fee. Employees who can't be paid yet are listed with the reason instead of being dropped silently.
- **Payday guarantee (Soroban).** Lock next payday's salaries in a smart contract so your team can see their pay is reserved.
- **Pay-period guard.** Nobody is accidentally paid twice in the same period.
- **Audit log** of payroll runs, employee payments and wallet operations, each linked to its Stellar transaction.

---

## 🧭 Engineering principles

We treat testnet money like real money. Three rules run through the whole codebase and are written into [`AGENTS.md`](AGENTS.md) for every contributor, human or AI:

1. **A failed Stellar call is a failure.** No synthesized hashes, no `COMPLETED` without a Horizon response that says `successful: true` and carries a real hash, and no database row that implies success.
2. **A timeout is not a failure and not a success.** It is `PENDING`, reconciled by hash against Horizon.
3. **Keys never leave the device.** Not to our API, not to logs, not to the AI.

These rules were earned. This project began on a custodial provider, and the migration to Stellar surfaced (and removed) dozens of places where a failed call quietly returned something that *looked* successful. The full inventory is in [`.agents/skills/stellar/SKILL.md`](.agents/skills/stellar/SKILL.md#-bug-inventory-found-during-migration-fix-in-m7-unless-noted).

---

## 🔐 Security model

| Layer | How |
| :--- | :--- |
| **Keys** | Ed25519 keypair generated on device. Users are walked through saving their recovery key at sign-up (confirmed by re-typing its end) and reminded until they do. The seed is encrypted with **AES-256-GCM** under **PBKDF2-HMAC-SHA256** (PIN, 24-byte salt, 100k iterations) and stored in the OS keychain/keystore. A wrong PIN fails GCM authentication; no PIN hash exists to attack. Lockout starts after 5 failures. Recovery-key export/import is available. |
| **Passkeys (web)** | Optional and recommended in browsers: the wallet key is re-encrypted under a secret only the user's passkey can produce (**WebAuthn PRF** → HKDF-SHA256 → AES-256-GCM), and the PIN-encrypted copy is removed. Payments and unlocking use **Face ID / fingerprint**, and stolen storage can't be decrypted by another device's passkey. Verified in real Chrome with a virtual PRF authenticator: switch on → lock → unlock → a $500 testnet payment confirmed by passkey ([`1e0c35c4…`](https://stellar.expert/explorer/testnet/tx/1e0c35c4a2e810186c03b7a239bcf0e1a5991e3b9aeec862453355be5e9c0196)). |
| **Sessions** | HS256 JWTs (12 h), issued only at signup or after a signed ownership challenge. Identity comes **only** from the token, never from headers, query strings or bodies. Production refuses to start without a real secret. |
| **Transactions** | Proposal ID = transaction hash, single use, per user, with expiry. Signed payloads are never echoed back. |
| **Invites** | 48-hex tokens with only the hash stored. Acceptance requires the invited, verified email and a wallet whose ownership has been proven. The landing page is HTML-escaped. |

**Honest limits, and what we plan to do about them:**
- With a PIN, a 6-digit code can be brute-forced offline if the encrypted blob is ever exfiltrated. On phones it sits in the OS keychain/keystore behind a lockout. On **web**, browser storage is weaker, so web users can switch to a **passkey** (below) and the PIN-encrypted copy is deleted.
- Passkeys are bound to the website's domain. That's why switching requires a saved recovery key first, which is the way back if the domain or the passkey is ever lost.
- The test assets are FlowPay-issued and the liquidity pools are seeded by us. That makes them realistic plumbing, but they are not real money or real market rates.

---

## 🧱 Architecture

```
flowpay/
├── contracts/payroll_vault/    Soroban (Rust) payday-guarantee contract + tests
├── backend/                     Node 20 · TypeScript · Express · Prisma/Postgres (in-memory fallback)
│   └── src/
│       ├── stellar/             The Stellar layer: config, horizon (honest error mapping + reconcile),
│       │                        payments, batch (≤100-op atomic txs), proposals, directory,
│       │                        challenge, faucet, history, bootstrap
│       ├── auth/session.ts      JWT sessions + requireAuth
│       ├── modules/             transfers · payments · missions · employees · payroll · activity · ai · banks
│       └── routes/              REST API (below)
├── mobile/                      Flutter 3 · Riverpod: one codebase for iOS, Android and Web
│   └── lib/core/
│       ├── stellar/             Key vault (AES-GCM/PBKDF2), Horizon reads, activation, SEP-10/24 anchor client
│       ├── wallet/              WalletSigner: the only path to a signature (PIN always required)
│       ├── providers/stellar/   Stellar*Repository: live implementations, no silent fallbacks
│       └── providers/demo/      Demo*Repository: a clearly-labelled simulation mode
└── .agents/skills/              Living architecture docs (start with stellar/SKILL.md)
```

**API surface** (all user routes require a session token):

| Area | Endpoints |
| :--- | :--- |
| Auth | `POST /api/auth/signup` · `/challenge` · `/login` · `/email/send` · `/email/verify` · `GET /capabilities` · `GET/POST /handle` |
| SEP-1 / SEP-2 (public) | `GET /.well-known/stellar.toml` · `GET /federation?q=…&type=name\|id` |
| Stellar | `GET /api/stellar/config` · `/accounts/:id` · `/accounts/:id/payments` · `POST /transactions` · `GET /transactions/:hash` |
| Wallets | `GET /api/wallets` · `/balances` · `/transactions` · `POST /challenge` · `/register` |
| Transfers | `POST /api/transfers/interpret` · `/recipient` · `/propose` · `/execute` · `GET /rates` |
| Batch payments | `POST /api/payments/batch/propose` · `/execute` |
| Missions | `GET/POST /api/missions` · `POST /:id/prepare` · `/:id/execute` |
| Employees | `GET/POST /api/employees` · `GET /invite/:token` · `POST /invite/:token/accept` · `/:id/resend-invite` · `PATCH /:id` |
| Payroll | `GET /api/payroll/preview` · `POST /execute` · `GET /runs` · `/runs/:id` |
| Payday guarantee | `POST /api/payroll/guarantees/propose` · `/execute` · `GET /guarantees` · `/guarantees/mine` · `POST /guarantees/:id/claim` · `/claim/execute` · `/guarantees/:id/release` |
| Health | `GET /api/health` · `/api/health/stellar` |

`POST` endpoints that submit to the network return **200** COMPLETED, **202** PENDING, or **4xx** FAILED with Horizon `result_codes` translated into plain language.

---

## 🚀 Run it yourself

**Just want to try it?** Open the [live demo](https://flowpay-salawuolayiwolas-projects.vercel.app). Create an account, choose a PIN, and you get a testnet wallet with test USD (no real money). The API runs on Render's free tier, so the first request after a quiet period can take ~50 s while it wakes up.

**Prerequisites:** Node 20+, Flutter 3.24+, and an internet connection to reach Stellar testnet. Postgres is optional: without it the backend runs in memory.

```bash
git clone https://github.com/flowpay-bmoni/flowpay.git && cd flowpay

# 1 · Backend
cd backend
npm install
npm run stellar:bootstrap   # creates YOUR testnet issuer + market maker, issues 5 assets,
                            # seeds 4 liquidity pools, writes keys to backend/.env (gitignored)
npm run build && npm test   # 106 tests
DATABASE_URL=postgresql://none:none@127.0.0.1:1/none \
DEV_ECHO_EMAIL_CODES=true PORT=4000 npm start       # in-memory DB, email codes echoed (dev only)

# 2 · App (new terminal)
cd mobile
flutter pub get
flutter test                # 194 tests
flutter run -d chrome --dart-define=FLOWPAY_API_URL=http://localhost:4000
```

Sign up, choose a PIN and your wallet is created on the device. Activate it to get testnet XLM, trustlines and test USD, and you can send, convert and run payroll for real on testnet.

**Soroban contract (optional):**

```bash
cargo install --locked stellar-cli     # or: brew install stellar-cli
cd contracts && cargo test && stellar contract build    # 9 tests, then the WASM
cd ../backend && npm run stellar:deploy-vault           # deploys + writes STELLAR_PAYROLL_VAULT_ID
```

**Prove it end to end against testnet.** These seven suites create users, sign on a device key and assert on-chain balances:

```bash
cd backend && DATABASE_URL=postgresql://none:none@127.0.0.1:1/none DEV_ECHO_EMAIL_CODES=true PORT=4099 node dist/server.js &
cd mobile  && LIVE_STELLAR=1 FLOWPAY_API=http://localhost:4099 flutter test test/live --concurrency=1
```

<details>
<summary><b>Environment variables</b></summary>

| Variable | Purpose |
| :--- | :--- |
| `STELLAR_NETWORK` | `testnet` (default) or `public` |
| `STELLAR_HORIZON_URL`, `STELLAR_FRIENDBOT_URL` | Override the endpoints |
| `STELLAR_ASSET_ISSUER`, `STELLAR_ISSUER_SECRET`, `STELLAR_DISTRIBUTOR_SECRET` | Written by `stellar:bootstrap`. Never commit them. |
| `STELLAR_ASSET_USD` … `_NGN` | Optional per-asset `CODE:ISSUER` overrides (e.g. real anchored assets on mainnet) |
| `SOROBAN_RPC_URL`, `STELLAR_PAYROLL_VAULT_ID` | Soroban RPC (defaults to SDF's testnet RPC) and the deployed PayrollVault (written by `stellar:deploy-vault`) |
| `FLOWPAY_HOME_DOMAIN` | Domain for `stellar.toml` and payment addresses (`name*domain`). Defaults to the host serving the request. |
| `FLOWPAY_JWT_SECRET` | **Required in production** (≥32 random chars) |
| `DATABASE_URL` | Postgres. An unreachable URL means in-memory mode. |
| `DEV_ECHO_EMAIL_CODES` | `true` returns verification codes in API responses. Refused when `NODE_ENV=production`. |
| `SMTP_*` / `RESEND_API_KEY` / `MAILGUN_*` | Email delivery for verification codes and invites |
| `PAYSTACK_SECRET_KEY` | Nigerian bank account-name resolution |
| `GEMINI_API_KEY` | Plain-English rule interpretation (optional; the rules engine works without it) |

Mobile `--dart-define`s: `FLOWPAY_API_URL`, `STELLAR_NETWORK`.

Database: schema changes for the Stellar migration are in `backend/prisma/sql/2026-10-2*_*.sql`. Apply them in order before deploying against an existing database.
</details>

---

## 🧪 Tests

| Suite | Count | What it covers |
| :--- | :--- | :--- |
| Soroban contract (`cargo test`) | **9** | Funding rules, no payout before payday, exactly-once claim/release, reclaim only after grace, auth, storage rent window, 100-person budget |
| Backend unit (`npm test`) | **106** | Horizon error mapping, PENDING on timeout, proposal hash binding, batch splitting, payroll eligibility, invite security, session tokens, federation privacy, `stellar.toml` contents, guarantee proposals and Soroban status mapping |
| App (`flutter test`) | **194** | Key vault crypto (signatures verified with the SDK), passkey vault (PRF), wallet lifecycle, PIN/passkey gating, every screen, demo vs live separation |
| CI | every push and PR | Both suites run on GitHub Actions ([`ci.yml`](.github/workflows/ci.yml)) |
| Live testnet (`LIVE_STELLAR=1`) | **7 suites** | Transfers, FX, missions + locked savings, employee invites (impostor → 403, unverified email blocked), multi-country payroll, SEP-10/24, Soroban payday guarantee |

---

## 🚩 Road to mainnet

FlowPay was built so that going live is mostly configuration plus partnerships, not a rewrite.

- [x] Non-custodial wallets, atomic payroll, path-payment FX, locked savings and SEP-10/24 on testnet
- [ ] **Real anchored assets.** Point `STELLAR_ASSET_*` at anchored USDC and local-currency anchors in each corridor (NG, MX, CA, UK)
- [ ] **SEP-31 + SEP-38** for regulated cross-border payouts with firm quotes, and **SEP-12** for reusable KYC
- [x] **Passkeys on web**: Face ID / fingerprint instead of a PIN, with the key encrypted under the passkey (WebAuthn PRF)
- [ ] Passkeys on native apps (platform PRF), and Soroban passkey smart wallets once FlowPay's FX/payroll can run on Soroban AMMs
- [x] **Payday guarantee on Soroban**: employers pre-fund, employees see the guarantee ([details](#-soroban-payday-guarantee))
- [ ] Convert to local currency on release (AMM contract call)
- [ ] Recovery-key backup during onboarding, and a persisted contacts book for plain-English payments
- [ ] Production deploy (web on Vercel, API on Render), audit, then mainnet

---

## 📍 Project status

| Milestone | |
| :--- | :--- |
| M1 Stellar core · M2 on-device keys · M3 wallets, transfers, missions, FX | ✅ |
| M4 employees · M5 atomic payroll · M6 anchors and honest KYC | ✅ |
| M7 removal of the previous custodial provider · M8 real authentication + end-to-end live tests | ✅ |
| M9 Stellar-inspired redesign + visual QA | ✅ |
| M11 Soroban payday guarantee (contract, API, app, live test) | ✅ |
| M10 public deploy: web app on Vercel, API on Render, both on testnet | ✅ |

The development history and every decision are recorded in [`.agents/skills/stellar/SKILL.md`](.agents/skills/stellar/SKILL.md).

<div align="center">
<br/>

**FlowPay**: your money, your rules, your approval.<br/>
<sub>Built on <a href="https://stellar.org">Stellar</a>. Testnet only: no real funds are moved.</sub>

</div>
