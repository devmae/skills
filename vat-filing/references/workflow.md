# Korean VAT workflow for a solo mobile-game business

## Contents

1. Scope and period
2. Evidence collection
3. Revenue classification
4. Foreign-currency conversion
5. Input VAT
6. Credits and deadline
7. Reconciliation and HomeTax handoff

## 1. Scope and period

Assume a Korean individual general taxpayer operating a one-person mobile-game business unless the current business registration shows otherwise. Employment income is outside the VAT return.

Use the legal VAT period, not a bank-deposit period:

| Filing | Revenue and purchase period |
|---|---|
| First final return | January 1 through June 30 |
| Second final return | July 1 through December 31 |

Confirm whether the task is an original return, amended return, or claim for reassessment before changing filed periods.

## 2. Evidence collection

Collect all evidence before calculation. If a platform has no activity, record zero activity and how it was verified.

| Area | Evidence | Primary use |
|---|---|---|
| HomeTax sales | `판매(결제)대행 매출자료` export | Reconcile domestic payment-agency data |
| Apple | Monthly Sales and Trends files | Gross customer price and customer country |
| Google Play | Monthly earnings/sales CSV | Charge, tax, fee, and buyer country |
| AdMob | Half-year transactions screen or monthly CSV | Finalized advertising earnings and adjustments |
| AppLovin | Half-year report or zero-activity confirmation | Direct advertising earnings only |
| Meta | Half-year statements screen or CSV | Finalized Audience Network earnings |
| Input VAT | Electronic tax invoices | Deductible invoice purchases |
| Input VAT | Business-card deductible detail | Card purchases after deductible-status review |
| Input VAT | Business-expense cash receipts | Deductible cash-receipt purchases |

HomeTax menu layouts change. Prefer the global menu search using the exact report name instead of relying on a brittle click path.

## 3. Revenue classification

### 3.1 Use gross customer consideration

Treat the customer's payment before platform commission as revenue. Record platform fee and settlement amount only as reconciliation information.

For Google, normally aggregate positive sale/charge and tax rows by buyer country. Keep Google fee separate. Review refunds, chargebacks, and adjustments individually.

For Apple, aggregate paid in-app-purchase rows as `Units × Customer Price`. Review negative Units, refunds, proceeds reasons, subscriptions, and product-type identifiers instead of assuming one identifier for every period.

### 3.2 Separate domestic and foreign by customer location

Use buyer country, country code, storefront, or equivalent transaction-level field. A foreign Apple legal-entity name in HomeTax does not prove that every related sale is foreign, and a domestic payment channel does not prove that every user is domestic.

Domestic consumer payments are taxable gross amounts including VAT. Foreign transactions are zero-rate candidates only after current legal requirements and evidence are checked.

### 3.3 Prevent HomeTax/platform duplication

HomeTax sales-agent data and platform reports can describe overlapping transactions with different approval timing or aggregation rules.

Use this decision order:

1. Identify direct domestic rows that appear only in HomeTax, such as OneStore or Samsung.
2. Identify platform rows also represented in a detailed Apple or Google report.
3. Exclude the overlapping HomeTax platform rows from the filing sum when the detailed report is used to split domestic and foreign sales.
4. Keep the excluded HomeTax amount in a reconciliation table with the difference and treatment.
5. Stop and investigate if no source can explain a material difference.

Do not force HomeTax and platform totals to match by changing exchange rates or inventing adjustments.

### 3.4 Advertising revenue

Use finalized monthly platform earnings, not remittance dates. Include balances below the payment threshold even if they will be paid in a later year.

For AdMob, distinguish:

- current-period finalized earnings;
- invalid-traffic adjustments belonging to the current period;
- prior-period adjustments posted in the current period;
- AppLovin bidding revenue already included inside AdMob;
- direct AppLovin revenue paid outside AdMob.

Record Meta and direct AppLovin zero activity explicitly when applicable.

## 4. Foreign-currency conversion

Verify the current VAT Act and Enforcement Decree before each filing. For foreign currency not converted or received by the supply time, use the legally required basic or arbitrated exchange rate at the supply time.

When the only reliable evidence is a finalized monthly report, a documented month-end supply-time convention may be used for the normalized calculation. Cite the official rate source and preserve the report's End Date.

Use Seoul Money Brokerage Services or another official source accepted for the filing. Store:

- exact date;
- currency;
- rate unit, especially 100 units for JPY or VND where applicable;
- rate;
- source URL.

Convert each source line as:

`KRW amount = floor(foreign amount × rate ÷ rate unit)`

If another rounding rule is legally required or consistently used in HomeTax for the current form, change the policy and document it.

## 5. Input VAT

Check all three channels even when two are zero:

1. electronic tax invoices;
2. business-card purchases;
3. business-expense cash receipts.

For business cards, the downloaded file may show the state before the user changes `선택불공제` to deductible. Use the final HomeTax summary screen as the controlling status and reconcile count, supply value, VAT, non-taxable value, and total.

Verify `supply + VAT + non-taxable = total` for every summarized row. Do not claim personal, exempt, non-business, or automatically nondeductible purchases merely because they were paid with a business card.

## 6. Credits and deadline

Search current primary law before using any credit. Do not copy the prior return's amount.

At minimum verify:

- electronic-filing tax credit amount and effective date;
- eligibility for the credit-card sales-slip issuance credit based on the registered business category;
- whether a credit can exceed tax payable or increase a refund;
- statutory deadline and weekend/holiday extension.

If business-category eligibility is unclear, default the optional card-issuance credit to zero and expose it as a review item instead of silently claiming it.

## 7. Reconciliation and HomeTax handoff

The workbook should expose these values near the top:

| Output | Calculation |
|---|---|
| Domestic taxable gross | Sum of included domestic customer payments |
| Taxable supply value | Filing-policy calculation from taxable gross |
| Output VAT | Filing-policy calculation from taxable gross |
| Zero-rate candidate supply | Sum of included converted foreign sales |
| Deductible input VAT | Sum of verified deductible channels |
| Tax before credits | Output VAT minus deductible input VAT |
| Expected payable/refund | Tax before credits minus verified credits |

Map the amounts to the current HomeTax form, then compare HomeTax's calculated result with the workbook. Treat a difference as a blocking reconciliation issue until explained.

After submission, save the final return PDF, filing receipt, payment slip, and the exact evidence set used.

