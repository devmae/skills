# Normalized VAT input schema

## Contents

1. Top-level fields
2. Filing and policy
3. Sales
4. Exchange rates
5. Input VAT
6. Reconciliation and checklist
7. Validation rules

## 1. Top-level fields

The builder accepts one UTF-8 JSON object with these required keys:

| Key | Type | Purpose |
|---|---|---|
| `schema_version` | integer | Must be `1` |
| `filing` | object | Period, filing title, deadline |
| `policy` | object | Rounding and tax-credit assumptions |
| `domestic_sales` | array | Included and excluded domestic-source rows |
| `foreign_sales` | array | Foreign-currency and already-KRW zero-rate candidates |
| `exchange_rates` | array | Date/currency rate lookup |
| `input_vat` | array | Verified deductible channel summaries |
| `reconciliations` | array | Overlap and source-difference audit rows |
| `checklist` | array | Filing evidence and completion state |
| `official_sources` | array | Current law and exchange-rate URLs |

## 2. Filing and policy

`filing` fields:

| Field | Type | Example |
|---|---|---|
| `year` | integer | `2026` |
| `period_label` | string | `제1기 확정` |
| `start_date` | `YYYY-MM-DD` | `2026-01-01` |
| `end_date` | `YYYY-MM-DD` | `2026-06-30` |
| `due_date` | `YYYY-MM-DD` | `2026-07-27` |
| `taxpayer_label` | string | `개인 일반과세자` |

`policy` fields:

| Field | Type | Meaning |
|---|---|---|
| `taxable_supply_method` | string | Currently `gross_divide_1_1_floor` |
| `vat_rate` | number | Current standard VAT rate as a decimal, normally `0.1` |
| `foreign_rounding` | string | Currently `floor_each_line` |
| `electronic_filing_credit_krw` | number | Current verified credit |
| `card_sales_credit_krw` | number | Use zero until eligibility is verified |
| `card_sales_credit_note` | string | Reason for applying or not applying |
| `foreign_supply_timing_note` | string | Document the supply-time convention |

## 3. Sales

Each `domestic_sales` row requires:

`id`, `platform`, `source`, `gross_krw`, `include`, `filing_category`, `evidence`, and `note`.

Each `foreign_sales` row requires:

`id`, `supply_date`, `platform`, `revenue_type`, `country`, `currency`, `amount`, `include`, `rate_class`, `evidence`, and `note`.

Use `rate_class: "lookup"` for foreign currency and `rate_class: "krw"` for a platform report already denominated in KRW. The builder inserts a 1:1 KRW rate automatically.

IDs must be unique and stable within the filing, such as `apple-2026-01-jp-iap`.

Use `include: false` for a visible excluded adjustment or duplicate. Do not delete it from the audit trail.

## 4. Exchange rates

Each row requires:

`date`, `currency`, `unit`, `rate`, `source`, `source_url`, and `note`.

The date and currency pair must be unique. Every included foreign sale with `rate_class: "lookup"` must match one rate row exactly.

## 5. Input VAT

Each row requires:

`id`, `channel`, `period`, `count`, `supply_krw`, `vat_krw`, `non_taxable_krw`, `total_krw`, `deductible`, `status`, `evidence`, and `note`.

The builder checks:

`supply_krw + vat_krw + non_taxable_krw = total_krw`

Only rows with `deductible: true` enter the deductible input-VAT total.

## 6. Reconciliation and checklist

Each `reconciliations` row requires `label`, `amount_krw`, `treatment`, and `note`.

Each `checklist` row requires `area`, `evidence`, `status`, and `action`.

Each `official_sources` row requires `label`, `url`, and `checked_date`.

## 7. Validation rules

The builder rejects the input when:

- required top-level arrays are missing;
- a date is invalid or outside the filing period where applicable;
- an amount is not numeric;
- a sale ID or input-VAT ID is duplicated;
- an included foreign sale has no exact rate match;
- a rate unit is zero or negative;
- an input-VAT row does not balance;
- a credit is negative;
- the filing start is after the filing end.

Warnings do not stop workbook generation but must appear in the `근거·체크` sheet. Typical warnings include an empty platform, a zero evidence row, an excluded adjustment, or a reconciliation difference.
