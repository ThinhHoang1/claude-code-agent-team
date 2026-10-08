# Team board

## Blockers

<!-- The TaskCompleted gate reads this section. -->

- [qa 2026-01-02] **B-1 · Checkout E2E fails on retry path** — `POST /orders` returns 500 after the second retry.
  Repro: `npm run e2e -- checkout-retry`. Owner: developer.
- [architect 2026-01-03] **B-2 · Cache key collides across tenants** — see decision D-4.

## Decisions

- [tech-lead] D-1 · Retries are bounded at 3.

## Closed

- [qa] B-0 · Login spinner never stops — fixed in abc1234.
