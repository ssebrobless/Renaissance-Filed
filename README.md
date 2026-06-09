# Renaissance Filed

**A free, local, own-your-data desktop bookkeeping app for small service businesses and contractors.**

Renaissance Filed is a native macOS bookkeeping program built for the smallest end of
the market: solo operators, freelancers, 1099 contractors, and micro service businesses.
It runs entirely on your own Mac — **no subscription, no cloud account, no monthly fee,
and your books never leave your computer.**

It was built and proven on one real business (a tile-installation contractor) before
being open-sourced. The financial workflows it ships with are the ones that business
actually used every day, reconciled to the bank to the penny.

> **Status: real and working, but early.** This is honest open source, not a polished
> product. It has been battle-tested on a single live business; it is **not yet a
> turnkey install-and-go replacement for everyone.** See [Where it's at](#where-its-at)
> and [Roadmap](#roadmap) before relying on it for your books.

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
- **Reports** — operational cash summary, A/R & A/P aging, job profitability, payee
  spend, customer statements.
- **Document archive** and a few quality-of-life helpers (mail triage, scanned
  order-sheet capture).
- **Print / Save-PDF / email** for invoices, estimates, checks, and reports.

## What it deliberately does *not* do

This is minimalist **on purpose**. It does **not** include payroll, automated sales tax,
inventory, multi-currency, multi-user/cloud access, or a full audit-grade general ledger.
Those are exactly the features that make "big" accounting software complex and expensive —
the things people at this end of the market are trying to get away from. If you need them,
you've outgrown this tool (and that's fine — see [The honest ceiling](#the-honest-ceiling)).

## Where it's at

Honest about the internals, because it's your money:

- **Accounting model:** it is *not* a full double-entry general ledger. Reports are
  derived from the operational tables (invoices, expenses, deposits, payments) — a
  cash-leaning, "QuickBooks-style" model. What it computes (cash P&L, A/R/A/P aging, job
  profitability, bank reconciliation) has been verified correct to the penny on a real
  business. It does **not yet compute its own formal Balance Sheet / Trial Balance** —
  those, where shown, are imported snapshots.
- **Migration:** the included import path was built around one specific QuickBooks
  Desktop export. A **generalized importer** (standard QB IIF/CSV) is on the roadmap.
- **Onboarding:** there is no create-a-company wizard yet. A new user can set company
  info in Settings and start entering data, but the guided first-run flow is roadmap.
- **Tests:** there is no unit-test suite yet. Verification today is done by the
  `RenaissanceHarness` QA tool (see below).

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
correct to the penny. It's how the financial core was certified. End users never need it.

## Roadmap

The path from "proven on one business" to "anyone can use it":

1. **Generalized QuickBooks import** (standard IIF/CSV) + a "your imported balance matches
   your last QuickBooks statement ✓" reconciliation check.
2. **Self-computed P&L and Balance Sheet**, so a from-scratch user gets real year-end
   statements.
3. **Create-company / first-run onboarding.**
4. **A unit-test suite.**

Contributions toward any of these are welcome.

## License

[MIT](LICENSE) © 2026 Sebastian Robles.

## A note on privacy

This repository contains **no real financial data.** It was scrubbed before publishing:
no real company name, bank account, customer, or vendor information ships with the source.
Your books live only in your own app's local database, never in this repo.
