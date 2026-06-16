# Security Findings & Hardening Notes

Review date: 2025 (testnet / Lisk Sepolia build)

## Resolved
- Removed unused `firebase-database-rules.json` (had `.read: true` on `near_sync`, which would expose user location if accidentally deployed). Active rules `database.rules.json` require `auth != null`.
- Scrubbed a real-format 24-word BIP39 mnemonic from `backend/.env.example` (was in a comment).
- Verified no private keys, mnemonics, or `.env` files committed to git history.
- Added input validation (valid address + positive amount) on `/faucet/mint` and `/qris/payments`.

## Open / TODO (not yet fixed)

### HIGH — Unauthenticated operator endpoints
`backend/src/server.ts` exposes operator actions with no auth middleware:
- `POST /qris/v2/payments/:paymentId/release`
- `POST /qris/v2/payments/:paymentId/refund`

These call the backend operator wallet to release/refund escrow but only have a `// admin/operator only` comment — no actual check. Any caller can trigger them.

**Fix:** add an operator guard (e.g. `x-api-key` checked against `OPERATOR_API_KEY` env, or Firebase ID-token verification) on all state-changing operator routes. None of the 51 routes in `server.ts` currently enforce auth.

### MED — Release idempotency
`releasePayment()` does not check on-chain status before calling `release()`. A double call can submit a duplicate tx. Guard with a status check (skip if already RELEASED).

## Notes (not bugs)
- Firebase API keys in `google-services.json` / `firebase_options.dart` are **public by design** (shipped in client apps). Restrict them in the Firebase console (app + API restrictions) and rely on security rules — do not treat as secrets.
- `receipt.hash` usage is **correct** for ethers v6 (`.transactionHash` is the v5 spelling).
