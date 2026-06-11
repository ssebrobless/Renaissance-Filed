# Renaissance Filed

**A free, local, own-your-data desktop bookkeeping app for small service businesses and contractors.**

Renaissance Filed is a native macOS bookkeeping program built for the smallest end of
the market: solo operators, freelancers, 1099 contractors, and micro service businesses.
It runs entirely on your own Mac — **no subscription, no cloud account, no monthly fee,
and your books never leave your computer.**

It was built and proven on one real business (a tile-installation contractor) before
being open-sourced. The financial workflows it ships with are the ones that business
actually used every day, reconciled to the bank to the penny.

> **Status: the roadmap is delivered.** What began as "proven on one business, but
> early" is now a complete double-entry bookkeeping app with its own tested ledger,
> self-computed financial statements, a full QuickBooks migration path, and first-run
> onboarding — all backed by an automated test suite. It has been validated on a real
> live business (a tile contractor), including migrating that business's books onto it.
> It's still deliberately small — see [The honest ceiling](#the-honest-ceiling) — and
> still primarily proven on that one business, so review your numbers before relying on it.

---

## Why this exists

Intuit is discontinuing **QuickBooks Desktop** — 2024 is the final version, support ends
by September 30, 2027, and bank feeds, payroll tax tables, and security patches stop when
it does. The official path forward is **QuickBooks Online**, a per-company-file
*subscription* that a lot of small operators simply don't want: recurring cost, cloud
only, no real ownership of their own data.

Renaissance Filed is the opposite of that: a one-time, local, you-own-it desktop app for
people whose books are simple and who just want to keep doing what they were doing.

## What it does today

- **Customers & vendors** — a QuickBooks-style customer center and payee list.
- **Estimates → invoices** — including progress invoicing off an estimate.
- **Sales receipts** and **customer payments**, with undeposited-funds → deposit flow.
- **Expenses & check writing**, **bills**, and **bill payments**.
- **Job costing** — profitability per job (genuinely useful for contractors).
- **1099 tracking** for subcontractors.
- **Bank reconciliation** against a real statement.
- **Double-entry ledger** — every operational action posts balanced debits and credits
  to a real journal, and the books always balance by construction.
- **Self-computed financial statements** — a true Profit & Loss and a Balance Sheet
  derived from the ledger (the Balance Sheet balances by construction), alongside A/R &
  A/P aging, job profitability, payee spend, and customer statements.
- **QuickBooks migration** — import your chart of accounts, customers, and vendors (IIF)
  and your full transaction history (Journal-report CSV, in as many chunks as QuickBooks
  splits it into), then a one-click check that confirms an imported balance matches your
  last QuickBooks statement to the penny. For books that won't reconstruct cleanly, a
  **mid-year cutover** lets you start from opening balances and go forward.
- **First-run onboarding** — a guided wizard: company info, a starter chart of accounts
  (general / contractor / freelancer), and optional opening balances.
- **Document archive** and a few quality-of-life helpers (mail triage, scanned
  order-sheet capture).
- **Print / Save-PDF / email** for invoices, estimates, checks, and reports.

## What it deliberately does *not* do

This is minimalist **on purpose**. It does **not** include payroll, automated sales tax,
inventory, multi-currency, or multi-user/cloud access.
Those are exactly the features that make "big" accounting software complex and expensive —
the things people at this end of the market are trying to get away from. If you need them,
you've outgrown this tool (and that's fine — see [The honest ceiling](#the-honest-ceiling)).

## Where it's at

Honest about the internals, because it's your money:

- **Accounting model:** a real **double-entry general ledger**. Every operational write
  (invoice, payment, deposit, expense, bill, bill payment, sales receipt, customer
  credit) posts balanced journal lines as it happens, and the same rules backfill a
  whole-ledger rebuild — so live posting and a rebuild are identical by construction. The
  app computes **its own Profit & Loss and Balance Sheet** from the ledger; the Balance
  Sheet balances by construction (equity includes retained earnings). The operational
  reports (A/R/A/P aging, job profitability, bank reconciliation) remain and have been
  verified to the penny on a real business.
- **Migration:** a generalized importer for standard QuickBooks Desktop exports — chart
  of accounts / customers / vendors via **IIF**, transactions via the **Journal-report
  CSV** (multiple chunked files supported), plus a reconciliation check. For books whose
  migrated history won't reconstruct cleanly, a **mid-year cutover** records opening
  balances so the statements are correct from a chosen date forward. All from Settings.
- **Onboarding:** a first-run wizard — company info, a starter chart-of-accounts template,
  and optional opening balances.
- **Tests:** an automated suite (Swift Testing) covers the money-in/out flows, the
  posting layer, the computed statements, the QuickBooks importers, onboarding, and the
  cutover migration. The `RenaissanceHarness` QA tool (below) additionally drives the
  live app end-to-end.

## The honest ceiling

Renaissance Filed is built for the *small* end and is proud of it. The moment you need
concurrent users, payroll for W-2 employees, audited financial statements, or
sales-tax/inventory complexity, you've outgrown it — graduate to QuickBooks Online or
Xero, the same way bigger businesses graduate from QuickBooks to NetSuite. Trying to be
everything to everyone is the trap this app is explicitly avoiding.

## Requirements

- macOS 13 (Ventura) or newer
- Swift toolchain / Xcode 15+ command-line tools (to build from source)

## Build and run

```bash
swift build
swift run RenaissanceLedger
```

To produce a signed `.app` bundle: `bash scripts/package_app.sh` (self-signs ad-hoc by
default; see the script for using your own signing identity).

## Developer / QA tool: RenaissanceHarness

`RenaissanceHarness` is a **developer tool, not an end-user feature.** It drives the app
through macOS Accessibility and runs "prove" probes that seed a sandbox copy of the books
and assert the money-in, money-out, job-costing, report, and bank-reconciliation math is
correct to the penny. It complements the unit-test suite (`swift test`) by exercising the
real, running app end-to-end. End users never need it.

## Roadmap

The path from "proven on one business" to "anyone can use it" is **delivered**. Full
detail, including the architectural decisions behind the double-entry posting layer
(ADR-001) and the mid-year cutover migration (ADR-002), is in
**[docs/ROADMAP.md](docs/ROADMAP.md)**.

- ✅ **Unit-test suite** — the safety net.
- ✅ **Double-entry posting layer + self-computed P&L and Balance Sheet** — real,
  always-balancing statements, derived from the ledger.
- ✅ **Generalized QuickBooks import** — IIF lists + chunked Journal-report CSV + a
  "your imported balance matches your last QuickBooks statement ✓" reconciliation check.
- ✅ **Create-company / first-run onboarding.**
- ✅ **Mid-year opening-balance cutover migration** — for books that can't be rebuilt
  faithfully from imperfect history.

What's left is hardening rather than features: validating the Journal-CSV parser against
more real-world QuickBooks exports, and the usual polish. Contributions welcome — see the
[issues tracker](../../issues).

## License

[MIT](LICENSE) © 2026 Sebastian Robles.

## A note on privacy

This repository contains **no real financial data.** It was scrubbed before publishing:
no real company name, bank account, customer, or vendor information ships with the source.
Your books live only in your own app's local database, never in this repo.
