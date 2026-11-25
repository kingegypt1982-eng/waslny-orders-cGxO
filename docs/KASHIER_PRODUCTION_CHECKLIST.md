# Kashier — production checklist & sandbox runbook (Phase 3)

No credentials, tunnel hostnames, or `.env` values appear in this document.
Replace `<TUNNEL_HOST>` and other angle-bracket placeholders locally; never
commit the filled-in `.env`. All API paths below are relative to `/api/v1`.

## 1. One tunnel, two public URLs

The API is the only public surface needed for payment callbacks. Point one
HTTPS tunnel at the API port (3000 by default) and register these two URLs in
`apps/api/.env` (operator-owned values — not in source code):

| Env key | Shape | Purpose |
| --- | --- | --- |
| `KASHIER_WEBHOOK_URL` | `https://<TUNNEL_HOST>/api/v1/webhooks/kashier` | Sent as `serverWebhook` on every session; server-to-server events. |
| `KASHIER_REDIRECT_URL` | `https://<TUNNEL_HOST>/api/v1/payment-return` | Payer's browser after checkout; static bilingual page, no JWT required. |

`resolvePaymentReturnUrl()` now uses a valid `KASHIER_REDIRECT_URL` **verbatim**
(path and query included). Only when it is missing/invalid does it fall back to
an allow-listed request `Origin`, then `CLIENT_ORIGIN`, both appending
`/api/v1/payment-return`. Do not point the redirect at the old Flutter hash
route: one tunnel serves the webhook and the return page.

After changing `.env`, the API must be restarted by whoever owns that terminal.
The tunnel must stay up until every webhook/retry has been observed.

## 2. Production gates

- `NODE_ENV=production` requires `KASHIER_WEBHOOK_URL`, `CORS_ORIGINS`, a
  non-default `JWT_SECRET`/`ADMIN_PASSWORD`; the test-only Kashier host is
  rejected outside development (`main.ts`, `secret-guard.ts`).
- `KASHIER_BASE_URL`, `KASHIER_MERCHANT_ID`, `KASHIER_API_KEY`,
  `KASHIER_SECRET_KEY`, `KASHIER_REDIRECT_URL` are all mandatory at boot.
  The HMAC key for webhooks is the **Payment API key**, never the secret key.
- TLS terminates at the tunnel/reverse proxy. CORS lists only the real mobile
  and admin origins; no wildcard in production.
- `GET /api/v1/payment-return` is intentionally public and cache-free
  (`Cache-Control: no-store`). It carries only the AR/EN "return to the app"
  message; it performs no redirect, no query parsing, and no DB access.

## 3. Webhook & money invariants (already implemented, covered by tests)

- Public `POST /api/v1/webhooks/kashier` with header `x-kashier-signature`.
  Bad signature → `401 {"statusCode":401,"message":"Unauthorized"}` before any
  DB work; generic body, no signature/HMAC/key detail. Valid signature →
  `200 {"acknowledged":true}` including unknown refs, replays, and silent
  branches (logs carry ref/outcome only).
- Signature: `signatureKeys` sorted alphabetically, values RFC-3986 encoded,
  constant-time hex comparison with the Payment API key.
- Amounts are **major units** (a real sandbox `amount: 50` means `50 EGP`).
  Both the webhook amount and stored `chargeAmount` are normalized to exactly
  two decimals with `Prisma.Decimal`; currency must match. The wallet is
  credited with `creditAmount` (net after fee), never the gross charge.
- `claimAndCredit()` is the single write path for webhook and reconciler:
  conditional `updateMany` (one winner), wallet increment, one unique `TOP_UP`
  ledger row, unique `providerTransactionId`. Replays and 409-style races do
  not move money twice.
- Confirmation query must report `SUCCESS` before crediting. Unreachable or
  intermediate inquiry leaves the row untouched and still answers 200; the
  periodic reconciler (every 60s, non-overlapping) rechecks bounded batches of
  PENDING rows aged 30s–60min plus UNCONFIRMED-failed rows younger than 7 days.
- Genuine payment failures are terminal. Only `FAILED` rows whose reason is the
  old units mismatch / unconfirmed inquiry are eligible for governed replay.

## 4. Sandbox runbook (user-side)

1. Start the tunnel to the API and set the two URLs from §1 in `.env`; restart
   the API. Confirm `GET /api/v1/payment-return` returns the AR/EN page and
   `GET /api/v1/webhooks/kashier` is reachable from outside (a GET will 404;
   that still proves routing).
2. Sign in as an approved captain in the mobile app, open the wallet, and
   request a top-up within the configured min/max. Note the reference shown in
   the new admin **Top-ups** page (`/topups`); use the status filter there.
3. Open the checkout URL, pay with a Kashier sandbox card, and let the browser
   return. It should display "ارجع للتطبيق، تأكيد الدفع بيتم تلقائياً" /
   "Return to the app — payment confirmation is automatic.".
4. In the API logs look for `kashier webhook charged ref=... status=PENDING`
   (or `reprocessed` for an eligible old mismatch row). No key, signature, or
   card data is logged. The admin page should move to **Succeeded** and the
   captain wallet balance should rise by the net credit only.
5. If the webhook was missed, leave the row alone: the reconciler retries it on
   its next cycle. If an old `FAILED` row keeps the recorded mismatch reason,
   re-send the event from the Kashier dashboard — the row does not recover by
   itself, and no manual DB write is part of this runbook.

## 5. Database confirmation — only after the user has paid

This is read-only; do not seed, update, or reset anything. Run after a real
sandbox payment and paste the reference from the admin page:

```sql
SELECT id, status, "creditAmount", "chargeAmount", "feeAmount",
       "providerTransactionId", "paidAt", "failureReason"
FROM "TopUp"
WHERE "providerOrderRef" = '<REFERENCE_FROM_ADMIN_PAGE>';
```

Expected: `status = SUCCEEDED`, `paidAt` set, `providerTransactionId` set, and
one matching wallet transaction:

```sql
SELECT id, type, amount, currency, "createdAt"
FROM "WalletTransaction"
WHERE "topUpId" = '<TOPUP_ID_FROM_PREVIOUS_QUERY>' AND type = 'TOP_UP';
```

Exactly one `TOP_UP` row with the net amount means the credit is idempotent.
If `status = FAILED` with `Amount or currency mismatch`, capture the ref and
re-send the event (or reconcile a PENDING row) rather than editing the DB.

## 6. Known limits

- No live Kashier payment, tunnel, webhook delivery, or Postgres concurrency
  test was executed in this repository run; only mocked-network Jest/Vitest
  suites and static builds were run.
- Throttler is global (100 req/min), including webhooks. A burst of retries can
  meet 429; this did not cause the diagnosed incident but should be monitored.
- FCM push delivery and native Google sign-in setup are outside these phases.
