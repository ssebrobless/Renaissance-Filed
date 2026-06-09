# Roadmap — from "proven on one business" to "anyone can use it"

Renaissance Filed already works: it ran a real contractor's books for a year and
reconciled to the bank to the penny. This document is the honest path from there to a
version a stranger can download and use to leave QuickBooks Desktop — without losing the
thing that makes it good (it's small, local, free, and yours).

## Guiding principle

Stay minimalist on purpose. The goal is **the simplest correct books for a small service
business**, not a QuickBooks clone. No payroll, no inventory, no multi-user, no cloud.
When a business outgrows this, it graduates to QuickBooks Online or Xero — and that's fine.

## The market context

Intuit is sunsetting **QuickBooks Desktop** (2024 is the final version; support ends by
Sept 30, 2027), pushing everyone to a **QuickBooks Online subscription**. A large cohort
of small, simple businesses wants out of the subscription/cloud model. That migration is
the use case this project is built around.

The constraint that shapes the import design: QuickBooks Desktop **exports lists**
(chart of accounts, customers, vendors) cleanly to **IIF**, but **will not export
transactions** to IIF. Transactions only come out via the **Journal report → CSV/Excel**
(the full double-entry journal; large files must be exported in monthly/quarterly chunks).

---

## Architectural decision: a double-entry posting layer (ADR-001)

**Decision:** introduce a real double-entry ledger and derive all financial statements
from it, rather than continuing to derive reports ad-hoc from the operational tables.

**Context:** today each operational action (invoice, payment, expense, deposit, bill)
writes to its own table, and reports are computed by bespoke queries. The formal Balance
Sheet / Trial Balance shown in the app are *imported QuickBooks snapshots*, not computed.
There is no journal of debits and credits. This works for one business that was reconciled
by hand, but it is not a legitimate, self-checking accounting system.

**Decision detail:** add a `journal_lines` table — `(txn_kind, txn_id, account_id, date,
debit, credit, memo)`. Every operational write **also posts balanced debit/credit lines**
(sum of debits = sum of credits for every transaction). All statements derive from
`journal_lines`. A one-time backfill posts existing data into the ledger.

**Why:**
- The Balance Sheet **balances by construction** (Assets = Liabilities + Equity always).
- QuickBooks' Journal export maps **1:1** onto journal lines, making transaction import clean.
- Tests get a single powerful invariant: *every transaction nets to zero, and the trial
  balance is always balanced.*
- It is the difference between "a checkbook with reports" and "a real accounting program."

**Rejected alternative:** derive each statement section separately and use a balancing
"plug" for equity. Faster, but it hides errors and keeps the "not a real GL" caveat. Not
worth it for software that handles people's money.

---

## The work, in recommended order

### 1. Unit test suite — *do this first* · ~1 week
A safety net before any refactor. Add an SPM `testTarget` (Swift Testing). Port the
`RenaissanceHarness` proof scenarios (money-in, money-out, job-costing, report
correctness, bank reconciliation) into **fast unit tests** against a temporary SQLite
database — no GUI required. The harness already encodes the exact expected numbers; this
moves them into `swift test` so every change is checked in seconds.

### 2. Double-entry posting layer + self-computed statements · ~3–4 weeks
Implements ADR-001. Add `journal_lines`; post balanced entries on every operational write;
backfill existing data. Then compute:
- **Profit & Loss** = journal lines on income/expense accounts over a period.
- **Balance Sheet** = balances by account type; equity includes retained earnings
  (accumulated net income). Verified to balance, with any imbalance surfaced loudly.

Brand-new users (no QuickBooks history) finally get real year-end statements.

### 3. Generalized QuickBooks import + reconciliation check · ~2–3 weeks
Replace the bespoke `RenaissanceTransfer` pipeline with standard inputs:
- **Phase A — Lists:** import **IIF** (chart of accounts, customers, vendors), reusing
  the app's existing IIF format knowledge in reverse.
- **Phase B — Transactions:** import the **Journal report CSV**, mapping each row to a
  posting in the ledger (clean because of the posting layer). Accept multiple chunked
  files to handle QB's export row limits.
- **Reconciliation check:** after import, prove **"your imported ending bank balance and
  net income match your QuickBooks Balance Sheet ✓."** This is the penny-level confidence
  check that makes a migration trustworthy — and almost no free tool offers it.

### 4. Create-company onboarding · ~1 week
A first-run wizard (shown when the database is empty): company info, a chart-of-accounts
template (general / contractor / freelancer), optional opening balances, and a fork:
**"Start fresh"** vs **"Import from QuickBooks"** (→ item 3).

---

## Dependencies

```
1 (tests) ──► everything (safety net)
2 (posting layer) ──► 3 (import) and the computed statements
2 ──► 3 ──► 4 (onboarding's "import" path)
```

Roughly **8–11 weeks** of focused work for a genuinely install-and-use v1. Contributions
toward any item are welcome — see the issues tracker.
