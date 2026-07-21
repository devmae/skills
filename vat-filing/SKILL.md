---
name: vat-filing
description: Prepare and verify Korean VAT returns for a sole-proprietor mobile-game business with Google Play, Apple App Store, OneStore, Samsung Galaxy Store, AdMob, AppLovin, Meta advertising revenue, and business-card input VAT. Use when collecting half-year VAT evidence, reconciling HomeTax sales-agent data, separating domestic taxable sales from foreign zero-rate candidates, converting foreign currency, creating the filing calculation workbook, or guiding final HomeTax entry and verification.
---

# VAT Filing

## Required reading

Read [references/workflow.md](references/workflow.md) before classifying or calculating any filing. Read [references/input-schema.md](references/input-schema.md) before creating or editing the normalized JSON input.

Read [CONTEXT.md](CONTEXT.md) only when reconciling the user's historical method or using the verified 2026 first-half case as a regression baseline.

## Workflow

1. Fix the filing period, taxpayer type, filing type, and legal deadline.
2. Collect source files for every active platform and all three input-VAT channels. Record explicit zero activity instead of silently omitting a platform.
3. Normalize verified values into the JSON schema. Keep source filenames and classification notes with each value.
4. Reconcile HomeTax sales-agent data against platform reports. Never add both sources blindly.
5. Verify current law, filing-form fields, tax credits, and exchange rates from official primary sources. Do not reuse a prior period's rates or credit amounts without verification.
6. Generate the calculation workbook with `scripts/build_vat_workbook.mjs` using the spreadsheet runtime provided by Codex.
7. Inspect key formulas, scan spreadsheet errors, render every sheet, and reconcile the result with source totals.
8. Guide HomeTax entry from the `신고요약` sheet. Compare HomeTax's calculated tax with the workbook before submission.
9. After filing, save the receipt, return PDF, payment slip, submitted attachments, normalized JSON, and final workbook together.

## Non-negotiable rules

- Recognize platform revenue when it is finalized for the reporting period, not only when cash is remitted.
- Use customer country or another transaction-level location field for domestic/foreign classification. Do not classify by the platform entity name alone.
- Use the customer's gross consideration as revenue. Track platform commission separately; do not net it against sales.
- Treat foreign sales as `영세율 후보` until the legal requirement and evidence are confirmed for the filing period.
- Convert unpaid foreign currency at the supply-time rate required by current law. When a platform supplies only a monthly finalized report, document the chosen month-end convention.
- Separate current-period earnings from prior-period adjustments, invalid-traffic corrections, refunds, and chargebacks.
- Claim input VAT only after business relevance and the HomeTax deductible status are both verified.
- Mark missing or ambiguous evidence as provisional. Do not present a provisional calculation as final.
- Keep every derived workbook amount formula-driven and auditable.

## Normalized input

Copy `assets/filing-input.example.json` to a writable working directory and replace its values with the current period. Validate all required fields using the rules in [references/input-schema.md](references/input-schema.md).

Do not modify the bundled example in place. Keep the period-specific JSON beside the source evidence and final workbook.

## Workbook generation

Use the `spreadsheets` skill whenever generating or modifying the workbook.

Run the builder from a writable directory that contains a `node_modules` junction to the `node_modules` path returned by `codex_app__load_workspace_dependencies`. Copy or link `scripts/build_vat_workbook.mjs` into that working directory before execution so standard package resolution finds `@oai/artifact-tool`.

```powershell
node build_vat_workbook.mjs --input filing-input.json --output outputs/<run-id>/vat-filing.xlsx --preview-dir outputs/<run-id>/previews
```

Use `--validate-only` to check the JSON without producing a workbook.

The script must exit non-zero for missing rates, invalid dates, unbalanced input-VAT rows, duplicate foreign-sale IDs, or missing required sections.

## Completion gate

Complete the task only when all conditions hold:

- Every active platform is included or explicitly marked zero.
- HomeTax and platform-report overlap has an explicit treatment.
- Domestic taxable gross, zero-rate candidate supply, and deductible input VAT reconcile to source evidence.
- Current tax credits and filing deadline have official-source support.
- Workbook formula-error scan returns zero matches.
- Every workbook sheet passes a visual check.
- The user receives the expected payable/refund amount, the assumptions that could change it, and the next HomeTax action.

