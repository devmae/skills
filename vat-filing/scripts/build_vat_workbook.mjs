import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

function parseArgs(argv) {
  const args = { validateOnly: false };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === "--validate-only") args.validateOnly = true;
    else if (token === "--input") args.input = argv[++i];
    else if (token === "--output") args.output = argv[++i];
    else if (token === "--preview-dir") args.previewDir = argv[++i];
    else if (token === "--help") args.help = true;
    else throw new Error(`Unknown argument: ${token}`);
  }
  return args;
}

function usage() {
  return [
    "Usage:",
    "  node build_vat_workbook.mjs --input filing-input.json --output result.xlsx [--preview-dir previews]",
    "  node build_vat_workbook.mjs --input filing-input.json --validate-only",
  ].join("\n");
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function parseDate(value, label) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error(`${label} must be YYYY-MM-DD: ${value}`);
  }
  const [year, month, day] = value.split("-").map(Number);
  const result = new Date(year, month - 1, day);
  if (result.getFullYear() !== year || result.getMonth() !== month - 1 || result.getDate() !== day) {
    throw new Error(`${label} is not a valid date: ${value}`);
  }
  return result;
}

function assertFiniteNumber(value, label) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new Error(`${label} must be a finite number`);
  }
}

function assertString(value, label) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${label} must be a non-empty string`);
  }
}

function assertArray(value, label) {
  if (!Array.isArray(value)) throw new Error(`${label} must be an array`);
}

function assertUniqueIds(rows, label) {
  const seen = new Set();
  rows.forEach((row, index) => {
    assertString(row.id, `${label}[${index}].id`);
    if (seen.has(row.id)) throw new Error(`${label} contains duplicate id: ${row.id}`);
    seen.add(row.id);
  });
}

function validateInput(data) {
  const warnings = [];
  if (!isObject(data)) throw new Error("Input must be a JSON object");
  if (data.schema_version !== 1) throw new Error("schema_version must be 1");

  for (const key of ["filing", "policy"]) {
    if (!isObject(data[key])) throw new Error(`${key} must be an object`);
  }
  for (const key of ["domestic_sales", "foreign_sales", "exchange_rates", "input_vat", "reconciliations", "checklist", "official_sources"]) {
    assertArray(data[key], key);
  }

  const start = parseDate(data.filing.start_date, "filing.start_date");
  const end = parseDate(data.filing.end_date, "filing.end_date");
  parseDate(data.filing.due_date, "filing.due_date");
  if (start > end) throw new Error("filing.start_date must not be after filing.end_date");
  assertFiniteNumber(data.filing.year, "filing.year");
  assertString(data.filing.period_label, "filing.period_label");
  assertString(data.filing.taxpayer_label, "filing.taxpayer_label");

  if (data.policy.taxable_supply_method !== "gross_divide_1_1_floor") {
    throw new Error("policy.taxable_supply_method must be gross_divide_1_1_floor");
  }
  if (data.policy.foreign_rounding !== "floor_each_line") {
    throw new Error("policy.foreign_rounding must be floor_each_line");
  }
  assertFiniteNumber(data.policy.vat_rate, "policy.vat_rate");
  if (data.policy.vat_rate <= 0 || data.policy.vat_rate >= 1) throw new Error("policy.vat_rate must be between 0 and 1");
  for (const key of ["electronic_filing_credit_krw", "card_sales_credit_krw"]) {
    assertFiniteNumber(data.policy[key], `policy.${key}`);
    if (data.policy[key] < 0) throw new Error(`policy.${key} must not be negative`);
  }
  assertString(data.policy.card_sales_credit_note, "policy.card_sales_credit_note");
  assertString(data.policy.foreign_supply_timing_note, "policy.foreign_supply_timing_note");

  assertUniqueIds(data.domestic_sales, "domestic_sales");
  data.domestic_sales.forEach((row, index) => {
    for (const key of ["platform", "source", "filing_category", "evidence"]) assertString(row[key], `domestic_sales[${index}].${key}`);
    assertFiniteNumber(row.gross_krw, `domestic_sales[${index}].gross_krw`);
    if (row.gross_krw < 0) throw new Error(`domestic_sales[${index}].gross_krw must not be negative`);
    if (typeof row.include !== "boolean") throw new Error(`domestic_sales[${index}].include must be boolean`);
  });

  const rateKeys = new Set();
  data.exchange_rates.forEach((row, index) => {
    parseDate(row.date, `exchange_rates[${index}].date`);
    assertString(row.currency, `exchange_rates[${index}].currency`);
    assertFiniteNumber(row.unit, `exchange_rates[${index}].unit`);
    assertFiniteNumber(row.rate, `exchange_rates[${index}].rate`);
    if (row.unit <= 0 || row.rate <= 0) throw new Error(`exchange_rates[${index}] unit and rate must be positive`);
    assertString(row.source, `exchange_rates[${index}].source`);
    assertString(row.source_url, `exchange_rates[${index}].source_url`);
    const key = `${row.date}|${row.currency.toUpperCase()}`;
    if (rateKeys.has(key)) throw new Error(`exchange_rates contains duplicate date/currency: ${key}`);
    rateKeys.add(key);
  });

  assertUniqueIds(data.foreign_sales, "foreign_sales");
  data.foreign_sales.forEach((row, index) => {
    const date = parseDate(row.supply_date, `foreign_sales[${index}].supply_date`);
    if (date < start || date > end) throw new Error(`foreign_sales[${index}] is outside the filing period`);
    for (const key of ["platform", "revenue_type", "country", "currency", "rate_class", "evidence"]) assertString(row[key], `foreign_sales[${index}].${key}`);
    assertFiniteNumber(row.amount, `foreign_sales[${index}].amount`);
    if (typeof row.include !== "boolean") throw new Error(`foreign_sales[${index}].include must be boolean`);
    const currency = row.currency.toUpperCase();
    if (!new Set(["lookup", "krw"]).has(row.rate_class)) throw new Error(`foreign_sales[${index}].rate_class must be lookup or krw`);
    if (row.rate_class === "krw" && currency !== "KRW") throw new Error(`foreign_sales[${index}] rate_class krw requires currency KRW`);
    if (row.include && row.rate_class === "lookup" && !rateKeys.has(`${row.supply_date}|${currency}`)) {
      throw new Error(`Missing exchange rate for included foreign sale ${row.id}: ${row.supply_date} ${currency}`);
    }
    if (!row.include) warnings.push(`감사 추적용 제외 외화행: ${row.id}`);
  });

  assertUniqueIds(data.input_vat, "input_vat");
  data.input_vat.forEach((row, index) => {
    for (const key of ["channel", "period", "status", "evidence"]) assertString(row[key], `input_vat[${index}].${key}`);
    for (const key of ["count", "supply_krw", "vat_krw", "non_taxable_krw", "total_krw"]) {
      assertFiniteNumber(row[key], `input_vat[${index}].${key}`);
      if (row[key] < 0) throw new Error(`input_vat[${index}].${key} must not be negative`);
    }
    if (typeof row.deductible !== "boolean") throw new Error(`input_vat[${index}].deductible must be boolean`);
    if (row.supply_krw + row.vat_krw + row.non_taxable_krw !== row.total_krw) {
      throw new Error(`input_vat row does not balance: ${row.id}`);
    }
  });

  data.reconciliations.forEach((row, index) => {
    for (const key of ["label", "treatment", "note"]) assertString(row[key], `reconciliations[${index}].${key}`);
    assertFiniteNumber(row.amount_krw, `reconciliations[${index}].amount_krw`);
  });
  data.checklist.forEach((row, index) => {
    for (const key of ["area", "evidence", "status", "action"]) assertString(row[key], `checklist[${index}].${key}`);
  });
  data.official_sources.forEach((row, index) => {
    for (const key of ["label", "url", "checked_date"]) assertString(row[key], `official_sources[${index}].${key}`);
    parseDate(row.checked_date, `official_sources[${index}].checked_date`);
  });

  if (data.domestic_sales.length === 0) warnings.push("국내 매출 행이 없습니다");
  if (data.foreign_sales.length === 0) warnings.push("국외 매출 행이 없습니다");
  if (data.input_vat.length === 0) warnings.push("매입세액 행이 없습니다");
  if (data.reconciliations.length === 0) warnings.push("중복·대조 행이 없습니다");
  if (data.official_sources.length === 0) warnings.push("공식 출처가 없습니다");

  return warnings;
}

function toDate(value) {
  return parseDate(value, "date");
}

function excelColumn(index) {
  let n = index;
  let result = "";
  while (n > 0) {
    n -= 1;
    result = String.fromCharCode(65 + (n % 26)) + result;
    n = Math.floor(n / 26);
  }
  return result;
}

const args = parseArgs(process.argv.slice(2));
if (args.help) {
  console.log(usage());
  process.exit(0);
}
if (!args.input) throw new Error(`--input is required\n${usage()}`);
if (!args.validateOnly && !args.output) throw new Error(`--output is required unless --validate-only is used\n${usage()}`);

const inputPath = path.resolve(args.input);
const data = JSON.parse(await fs.readFile(inputPath, "utf8"));
const warnings = validateInput(data);
console.log(JSON.stringify({ status: "valid", input: inputPath, warnings }, null, 2));
if (args.validateOnly) process.exit(0);

const outputPath = path.resolve(args.output);
const previewDir = args.previewDir ? path.resolve(args.previewDir) : null;
await fs.mkdir(path.dirname(outputPath), { recursive: true });
if (previewDir) await fs.mkdir(previewDir, { recursive: true });

const wb = Workbook.create();
const summary = wb.worksheets.add("신고요약");
const domestic = wb.worksheets.add("국내매출");
const foreign = wb.worksheets.add("외화매출");
const inputVat = wb.worksheets.add("매입세액");
const rates = wb.worksheets.add("환율");
const basis = wb.worksheets.add("근거·체크");

const C = {
  navy: "#16324F", teal: "#0F766E", paleBlue: "#EAF3F8", paleTeal: "#E6F4F1",
  paleGold: "#FFF7E0", paleRed: "#FDECEC", paleGreen: "#EAF7EE", white: "#FFFFFF",
  ink: "#1F2937", muted: "#64748B", grid: "#D6E1E8", blue: "#2563EB",
};
const wonFmt = '#,##0"원";[Red]-#,##0"원";0"원"';
const numFmt = '#,##0;[Red]-#,##0;0';
const amountFmt = '#,##0.00;[Red]-#,##0.00;0.00';
const rateFmt = '#,##0.00';
const dateFmt = 'yyyy-mm-dd';

function title(sheet, range, text) {
  const r = sheet.getRange(range);
  r.merge();
  r.values = [[text]];
  r.format = { fill: C.navy, font: { color: C.white, bold: true, size: 18 }, verticalAlignment: "center" };
  r.format.rowHeight = 30;
}

function note(sheet, range, text, fill = C.paleGold) {
  const r = sheet.getRange(range);
  r.merge();
  r.values = [[text]];
  r.format = { fill, font: { color: C.ink, italic: true }, wrapText: true, verticalAlignment: "center", borders: { preset: "outside", style: "thin", color: C.grid } };
  r.format.rowHeight = 34;
}

function section(sheet, range, text) {
  const r = sheet.getRange(range);
  r.merge();
  r.values = [[text]];
  r.format = { fill: C.paleBlue, font: { color: C.navy, bold: true, size: 12 }, verticalAlignment: "center" };
  r.format.rowHeight = 23;
}

function header(range) {
  range.format = { fill: C.teal, font: { color: C.white, bold: true }, horizontalAlignment: "center", verticalAlignment: "center", wrapText: true, borders: { preset: "all", style: "thin", color: C.grid } };
  range.format.rowHeight = 30;
}

function grid(range) {
  range.format.borders = { preset: "all", style: "thin", color: C.grid };
  range.format.verticalAlignment = "center";
}

function finishSheet(sheet, widths) {
  sheet.showGridLines = false;
  Object.entries(widths).forEach(([column, width]) => { sheet.getRange(`${column}:${column}`).format.columnWidth = width; });
  const used = sheet.getUsedRange();
  used.format.wrapText = true;
  used.format.autofitRows();
}

// Policy and evidence sheet first, because calculation formulas reference it.
title(basis, "A1:F2", `${data.filing.year}년 ${data.filing.period_label} 신고 근거와 체크`);
note(basis, "A4:F4", "노란색 행은 보수적 판단 또는 재검토 항목입니다. 공식 출처의 확인일이 오래됐으면 신고 전에 다시 검증하세요.");
section(basis, "A6:F6", "계산 정책");
basis.getRange("A7:A12").values = [
  ["부가가치세율"], ["전자신고 세액공제"], ["신용카드 발행세액공제"],
  ["외화 공급시기"], ["카드 공제 판단"], ["과세표준 계산방법"],
];
basis.getRange("B7:B12").values = [
  [data.policy.vat_rate], [data.policy.electronic_filing_credit_krw], [data.policy.card_sales_credit_krw],
  [data.policy.foreign_supply_timing_note], [data.policy.card_sales_credit_note], [data.policy.taxable_supply_method],
];
basis.getRange("C7:C12").values = [
  ["신고기간 현재 법령 확인"], ["현재 법령 확인값"], ["업종 적격성 확인값"],
  ["실제 입금일과 분리"], ["불명확하면 0원"], ["총결제액에서 공급가액·세액 산출"],
];
grid(basis.getRange("A7:C12"));
basis.getRange("A7:A12").format = { fill: C.paleBlue, font: { bold: true, color: C.navy }, borders: { preset: "all", style: "thin", color: C.grid } };
basis.getRange("B7").format.numberFormat = "0.0%";
basis.getRange("B8:B9").format.numberFormat = wonFmt;
basis.getRange("A9:C9").format.fill = C.paleGold;

section(basis, "A15:F15", "증빙 체크리스트");
basis.getRange("A16:D16").values = [["구분", "근거", "상태", "다음 행동"]];
header(basis.getRange("A16:D16"));
const checklistRows = data.checklist.length ? data.checklist : [{ area: "(없음)", evidence: "", status: "미입력", action: "확인" }];
const checklistStart = 17;
const checklistEnd = checklistStart + checklistRows.length - 1;
basis.getRange(`A${checklistStart}:D${checklistEnd}`).values = checklistRows.map((r) => [r.area, r.evidence, r.status, r.action]);
grid(basis.getRange(`A${checklistStart}:D${checklistEnd}`));

const sourceSectionRow = checklistEnd + 3;
section(basis, `A${sourceSectionRow}:F${sourceSectionRow}`, "공식 출처");
basis.getRange(`A${sourceSectionRow + 1}:C${sourceSectionRow + 1}`).values = [["항목", "URL", "확인일"]];
header(basis.getRange(`A${sourceSectionRow + 1}:C${sourceSectionRow + 1}`));
const sourceRows = data.official_sources.length ? data.official_sources : [{ label: "(없음)", url: "", checked_date: data.filing.end_date }];
const sourceStart = sourceSectionRow + 2;
const sourceEnd = sourceStart + sourceRows.length - 1;
basis.getRange(`A${sourceStart}:C${sourceEnd}`).values = sourceRows.map((r) => [r.label, r.url, toDate(r.checked_date)]);
grid(basis.getRange(`A${sourceStart}:C${sourceEnd}`));
basis.getRange(`B${sourceStart}:B${sourceEnd}`).format.font = { color: C.blue, underline: true };
basis.getRange(`C${sourceStart}:C${sourceEnd}`).format.numberFormat = dateFmt;

const warningSectionRow = sourceEnd + 3;
section(basis, `A${warningSectionRow}:F${warningSectionRow}`, "검증 경고");
const warningRows = warnings.length ? warnings : ["자동 검증 경고 없음"];
const warningStart = warningSectionRow + 1;
const warningEnd = warningStart + warningRows.length - 1;
basis.getRange(`A${warningStart}:F${warningEnd}`).merge(true);
basis.getRange(`A${warningStart}:A${warningEnd}`).values = warningRows.map((r) => [r]);
basis.getRange(`A${warningStart}:F${warningEnd}`).format = { fill: warnings.length ? C.paleGold : C.paleGreen, borders: { preset: "all", style: "thin", color: C.grid } };
basis.freezePanes.freezeRows(6);
finishSheet(basis, { A: 23, B: 45, C: 24, D: 34, E: 18, F: 18 });

// Exchange-rate sheet.
const normalizedRates = [...data.exchange_rates.map((r) => ({ ...r, currency: r.currency.toUpperCase() }))];
for (const sale of data.foreign_sales.filter((r) => r.rate_class === "krw")) {
  const keyExists = normalizedRates.some((r) => r.date === sale.supply_date && r.currency === "KRW");
  if (!keyExists) normalizedRates.push({ date: sale.supply_date, currency: "KRW", unit: 1, rate: 1, source: sale.evidence, source_url: "내부 원화 보고서", note: "이미 KRW로 표시" });
}
normalizedRates.sort((a, b) => a.date.localeCompare(b.date) || a.currency.localeCompare(b.currency));
if (normalizedRates.length === 0) normalizedRates.push({ date: data.filing.end_date, currency: "KRW", unit: 1, rate: 1, source: "내부", source_url: "내부", note: "외화거래 없음" });

title(rates, "A1:G2", `${data.filing.year}년 ${data.filing.period_label} 적용 환율`);
note(rates, "A3:G3", "외화매출의 공급일·통화와 정확히 일치하는 환율만 사용합니다. JPY·VND 등 100통화 단위 여부를 반드시 확인하세요.", C.paleGreen);
rates.getRange("A4:G4").values = [["적용일", "통화", "환율단위", "기준환율", "출처", "URL", "비고"]];
header(rates.getRange("A4:G4"));
const rateStart = 5;
const rateEnd = rateStart + normalizedRates.length - 1;
rates.getRange(`A${rateStart}:G${rateEnd}`).values = normalizedRates.map((r) => [toDate(r.date), r.currency, r.unit, r.rate, r.source, r.source_url, r.note ?? ""]);
grid(rates.getRange(`A${rateStart}:G${rateEnd}`));
rates.getRange(`A${rateStart}:A${rateEnd}`).format.numberFormat = dateFmt;
rates.getRange(`C${rateStart}:C${rateEnd}`).format.numberFormat = numFmt;
rates.getRange(`D${rateStart}:D${rateEnd}`).format.numberFormat = rateFmt;
rates.freezePanes.freezeRows(4);
finishSheet(rates, { A: 15, B: 10, C: 12, D: 14, E: 19, F: 50, G: 22 });

// Domestic sales.
title(domestic, "A1:H2", `${data.filing.year}년 ${data.filing.period_label} 국내 과세매출`);
note(domestic, "A4:H4", "포함=1인 행만 신고 합계에 들어갑니다. 홈택스와 플랫폼 보고서가 겹치면 한쪽을 포함=0으로 남겨 중복 제거 근거를 보존하세요.");
domestic.getRange("A6:H6").values = [["ID", "플랫폼", "원천", "총결제액", "포함", "신고구분", "근거", "메모"]];
header(domestic.getRange("A6:H6"));
const domesticRows = data.domestic_sales.length ? data.domestic_sales : [{ id: "no-domestic-sales", platform: "(없음)", source: "확인", gross_krw: 0, include: false, filing_category: "국내 과세", evidence: "무매출", note: "" }];
const domStart = 7;
const domEnd = domStart + domesticRows.length - 1;
domestic.getRange(`A${domStart}:H${domEnd}`).values = domesticRows.map((r) => [r.id, r.platform, r.source, r.gross_krw, r.include ? 1 : 0, r.filing_category, r.evidence, r.note ?? ""]);
grid(domestic.getRange(`A${domStart}:H${domEnd}`));
domestic.getRange(`D${domStart}:D${domEnd}`).format.numberFormat = wonFmt;
domestic.getRange(`E${domStart}:E${domEnd}`).format.horizontalAlignment = "center";
const domTotal = domEnd + 3;
domestic.getRange(`A${domTotal}:C${domTotal + 3}`).values = [
  ["국내 과세 총결제액", "포함=1 합계", null],
  ["과세 공급가액", "총결제액 ÷ (1+세율), 원 미만 절사", null],
  ["매출세액", "총결제액 × 세율 ÷ (1+세율), 원 미만 절사", null],
  ["절사 차이", "총결제액 - 공급가액 - 매출세액", null],
];
domestic.getRange(`B${domTotal}:C${domTotal + 3}`).merge(true);
domestic.getRange(`D${domTotal}:D${domTotal + 3}`).formulas = [
  [`=SUMIFS(D${domStart}:D${domEnd},E${domStart}:E${domEnd},1)`],
  [`=ROUNDDOWN(D${domTotal}/(1+'근거·체크'!$B$7),0)`],
  [`=ROUNDDOWN(D${domTotal}*'근거·체크'!$B$7/(1+'근거·체크'!$B$7),0)`],
  [`=D${domTotal}-D${domTotal + 1}-D${domTotal + 2}`],
];
domestic.getRange(`A${domTotal}:D${domTotal + 3}`).format = { fill: C.paleBlue, font: { bold: true, color: C.navy }, borders: { preset: "all", style: "thin", color: C.grid } };
domestic.getRange(`D${domTotal}:D${domTotal + 3}`).format.numberFormat = wonFmt;

const reconSection = domTotal + 6;
section(domestic, `A${reconSection}:H${reconSection}`, "중복·대조 내역");
domestic.getRange(`A${reconSection + 1}:D${reconSection + 1}`).values = [["구분", "금액", "처리", "메모"]];
header(domestic.getRange(`A${reconSection + 1}:D${reconSection + 1}`));
const reconRows = data.reconciliations.length ? data.reconciliations : [{ label: "(없음)", amount_krw: 0, treatment: "대조 없음", note: "" }];
const reconStart = reconSection + 2;
const reconEnd = reconStart + reconRows.length - 1;
domestic.getRange(`A${reconStart}:D${reconEnd}`).values = reconRows.map((r) => [r.label, r.amount_krw, r.treatment, r.note]);
grid(domestic.getRange(`A${reconStart}:D${reconEnd}`));
domestic.getRange(`B${reconStart}:B${reconEnd}`).format.numberFormat = wonFmt;
domestic.freezePanes.freezeRows(6);
finishSheet(domestic, { A: 28, B: 16, C: 25, D: 16, E: 9, F: 15, G: 24, H: 34 });

// Foreign sales.
title(foreign, "A1:M2", `${data.filing.year}년 ${data.filing.period_label} 영세율 후보 매출`);
note(foreign, "A4:M4", `${data.policy.foreign_supply_timing_note}. 실제 입금일과 분리하며, 포함=0 행은 감사 추적용으로만 남습니다.`);
foreign.getRange("A6:M6").values = [["ID", "공급일", "플랫폼", "수익구분", "국가", "통화", "외화금액", "환율단위", "기준환율", "포함", "원화금액", "근거", "메모"]];
header(foreign.getRange("A6:M6"));
const foreignRows = data.foreign_sales.length ? data.foreign_sales : [{ id: "no-foreign-sales", supply_date: data.filing.end_date, platform: "(없음)", revenue_type: "무매출", country: "해외", currency: "KRW", amount: 0, include: false, rate_class: "krw", evidence: "무매출 확인", note: "" }];
const foreignStart = 7;
const foreignEnd = foreignStart + foreignRows.length - 1;
foreign.getRange(`A${foreignStart}:M${foreignEnd}`).values = foreignRows.map((r) => [r.id, toDate(r.supply_date), r.platform, r.revenue_type, r.country, r.currency.toUpperCase(), r.amount, null, null, r.include ? 1 : 0, null, r.evidence, r.note ?? ""]);
foreign.getRange(`H${foreignStart}`).formulas = [[`=SUMIFS('환율'!$C$${rateStart}:$C$${rateEnd},'환율'!$A$${rateStart}:$A$${rateEnd},B${foreignStart},'환율'!$B$${rateStart}:$B$${rateEnd},F${foreignStart})`]];
foreign.getRange(`H${foreignStart}:H${foreignEnd}`).fillDown();
foreign.getRange(`I${foreignStart}`).formulas = [[`=SUMIFS('환율'!$D$${rateStart}:$D$${rateEnd},'환율'!$A$${rateStart}:$A$${rateEnd},B${foreignStart},'환율'!$B$${rateStart}:$B$${rateEnd},F${foreignStart})`]];
foreign.getRange(`I${foreignStart}:I${foreignEnd}`).fillDown();
foreign.getRange(`K${foreignStart}`).formulas = [[`=IF(J${foreignStart}=1,ROUNDDOWN(G${foreignStart}*I${foreignStart}/H${foreignStart},0),0)`]];
foreign.getRange(`K${foreignStart}:K${foreignEnd}`).fillDown();
grid(foreign.getRange(`A${foreignStart}:M${foreignEnd}`));
foreign.getRange(`B${foreignStart}:B${foreignEnd}`).format.numberFormat = dateFmt;
foreign.getRange(`G${foreignStart}:G${foreignEnd}`).format.numberFormat = amountFmt;
foreign.getRange(`H${foreignStart}:H${foreignEnd}`).format.numberFormat = numFmt;
foreign.getRange(`I${foreignStart}:I${foreignEnd}`).format.numberFormat = rateFmt;
foreign.getRange(`K${foreignStart}:K${foreignEnd}`).format.numberFormat = wonFmt;
foreign.getRange(`A${foreignStart}:M${foreignEnd}`).conditionalFormats.addCustom(`=$J${foreignStart}=0`, { fill: C.paleRed });
const foreignTotal = foreignEnd + 2;
foreign.getRange(`A${foreignTotal}:J${foreignTotal}`).merge();
foreign.getRange(`A${foreignTotal}:J${foreignTotal}`).values = [["영세율 후보 공급가액 합계"]];
foreign.getRange(`A${foreignTotal}:J${foreignTotal}`).format = { fill: C.navy, font: { color: C.white, bold: true }, horizontalAlignment: "right" };
foreign.getRange(`K${foreignTotal}:M${foreignTotal}`).merge();
foreign.getRange(`K${foreignTotal}`).formulas = [[`=SUM(K${foreignStart}:K${foreignEnd})`]];
foreign.getRange(`K${foreignTotal}:M${foreignTotal}`).format = { fill: C.navy, font: { color: C.white, bold: true, size: 13 }, numberFormat: wonFmt, horizontalAlignment: "right" };

const platforms = [...new Set(foreignRows.map((r) => r.platform))];
const platformSection = foreignTotal + 3;
foreign.getRange(`J${platformSection}:K${platformSection}`).values = [["플랫폼", "원화 합계"]];
header(foreign.getRange(`J${platformSection}:K${platformSection}`));
platforms.forEach((platform, index) => {
  const row = platformSection + 1 + index;
  foreign.getRange(`J${row}`).values = [[platform]];
  foreign.getRange(`K${row}`).formulas = [[`=SUMIFS($K$${foreignStart}:$K$${foreignEnd},$C$${foreignStart}:$C$${foreignEnd},J${row})`]];
});
const platformEnd = platformSection + platforms.length;
grid(foreign.getRange(`J${platformSection + 1}:K${platformEnd}`));
foreign.getRange(`K${platformSection + 1}:K${platformEnd}`).format.numberFormat = wonFmt;
foreign.freezePanes.freezeRows(6);
finishSheet(foreign, { A: 30, B: 14, C: 12, D: 20, E: 9, F: 9, G: 13, H: 11, I: 13, J: 9, K: 16, L: 25, M: 34 });

// Input VAT.
title(inputVat, "A1:L2", `${data.filing.year}년 ${data.filing.period_label} 공제 매입세액`);
note(inputVat, "A4:L4", "공제=1인 행만 매입세액 합계에 들어갑니다. 각 행은 공급가액+세액+비과세=합계가 일치해야 합니다.", C.paleGreen);
inputVat.getRange("A6:L6").values = [["ID", "채널", "기간", "건수", "공급가액", "세액", "비과세", "합계", "공제", "상태", "근거", "메모"]];
header(inputVat.getRange("A6:L6"));
const inputRows = data.input_vat.length ? data.input_vat : [{ id: "no-input-vat", channel: "(없음)", period: `${data.filing.start_date}~${data.filing.end_date}`, count: 0, supply_krw: 0, vat_krw: 0, non_taxable_krw: 0, total_krw: 0, deductible: false, status: "무매입", evidence: "확인", note: "" }];
const inputStart = 7;
const inputEnd = inputStart + inputRows.length - 1;
inputVat.getRange(`A${inputStart}:L${inputEnd}`).values = inputRows.map((r) => [r.id, r.channel, r.period, r.count, r.supply_krw, r.vat_krw, r.non_taxable_krw, r.total_krw, r.deductible ? 1 : 0, r.status, r.evidence, r.note ?? ""]);
grid(inputVat.getRange(`A${inputStart}:L${inputEnd}`));
inputVat.getRange(`D${inputStart}:D${inputEnd}`).format.numberFormat = numFmt;
inputVat.getRange(`E${inputStart}:H${inputEnd}`).format.numberFormat = wonFmt;
const inputTotal = inputEnd + 2;
inputVat.getRange(`A${inputTotal}:C${inputTotal}`).merge();
inputVat.getRange(`A${inputTotal}:C${inputTotal}`).values = [["공제대상 합계"]];
inputVat.getRange(`D${inputTotal}:H${inputTotal}`).formulas = [[
  `=SUMIFS(D${inputStart}:D${inputEnd},I${inputStart}:I${inputEnd},1)`,
  `=SUMIFS(E${inputStart}:E${inputEnd},I${inputStart}:I${inputEnd},1)`,
  `=SUMIFS(F${inputStart}:F${inputEnd},I${inputStart}:I${inputEnd},1)`,
  `=SUMIFS(G${inputStart}:G${inputEnd},I${inputStart}:I${inputEnd},1)`,
  `=SUMIFS(H${inputStart}:H${inputEnd},I${inputStart}:I${inputEnd},1)`,
]];
inputVat.getRange(`I${inputTotal}:L${inputTotal}`).merge();
inputVat.getRange(`I${inputTotal}:L${inputTotal}`).values = [["홈택스 최종 공제상태 대조"]];
inputVat.getRange(`A${inputTotal}:L${inputTotal}`).format = { fill: C.navy, font: { color: C.white, bold: true }, borders: { preset: "all", style: "thin", color: C.grid } };
inputVat.getRange(`D${inputTotal}`).format.numberFormat = numFmt;
inputVat.getRange(`E${inputTotal}:H${inputTotal}`).format.numberFormat = wonFmt;
inputVat.freezePanes.freezeRows(6);
finishSheet(inputVat, { A: 28, B: 20, C: 23, D: 9, E: 14, F: 13, G: 12, H: 14, I: 9, J: 16, K: 24, L: 28 });

// Summary created last so all referenced ranges are known.
title(summary, "A1:H2", `${data.filing.year}년 ${data.filing.period_label} 부가가치세 신고 요약`);
note(summary, "A4:H4", "이 계산은 정상 신고용 검토안입니다. 홈택스 자동계산 결과와 다르면 제출하지 말고 중복·공제·세액공제부터 다시 대조하세요.", C.paleGreen);
section(summary, "A6:D6", "핵심 계산");
summary.getRange("A7:A16").values = [
  ["국내 과세 총결제액"], ["과세 공급가액"], ["매출세액"], ["영세율 후보 공급가액"], ["공제 매입세액"],
  ["공제 전 납부세액"], ["전자신고 세액공제"], ["신용카드 발행세액공제"], ["예상 납부(+)·환급(-)"], ["판정"],
];
summary.getRange("B7:B15").formulas = [
  [`='국내매출'!D${domTotal}`], [`='국내매출'!D${domTotal + 1}`], [`='국내매출'!D${domTotal + 2}`],
  [`='외화매출'!K${foreignTotal}`], [`='매입세액'!F${inputTotal}`], ["=B9-B11"],
  ["='근거·체크'!B8"], ["='근거·체크'!B9"], ["=B12-B13-B14"],
];
summary.getRange("B16").formulas = [["=IF(B15>0,\"납부 예상\",IF(B15<0,\"환급 예상\",\"납부세액 없음\"))"]];
summary.getRange("A7:B16").format.borders = { preset: "all", style: "thin", color: C.grid };
summary.getRange("A7:A16").format = { fill: C.paleBlue, font: { bold: true, color: C.navy }, borders: { preset: "all", style: "thin", color: C.grid } };
summary.getRange("B7:B15").format.numberFormat = wonFmt;
summary.getRange("B15").format = { fill: C.paleGold, font: { bold: true, color: C.navy, size: 14 }, numberFormat: wonFmt, borders: { preset: "all", style: "medium", color: C.teal } };
summary.getRange("B16").format = { fill: C.paleGreen, font: { bold: true, color: C.teal }, horizontalAlignment: "center" };

section(summary, "E6:H6", "신고 정보");
summary.getRange("E7:F12").values = [
  ["납세자 구분", data.filing.taxpayer_label], ["과세기간", `${data.filing.start_date} ~ ${data.filing.end_date}`],
  ["신고기한", toDate(data.filing.due_date)], ["부가가치세율", null], ["외화 공급시기", data.policy.foreign_supply_timing_note],
  ["카드 발행공제", data.policy.card_sales_credit_note],
];
summary.getRange("F10").formulas = [["='근거·체크'!B7"]];
grid(summary.getRange("E7:F12"));
summary.getRange("E7:E12").format = { fill: C.paleTeal, font: { bold: true, color: C.teal }, borders: { preset: "all", style: "thin", color: C.grid } };
summary.getRange("F9").format.numberFormat = dateFmt;
summary.getRange("F10").format.numberFormat = "0.0%";

section(summary, "A19:H19", "홈택스 입력 가이드");
summary.getRange("A20:F20").values = [["신고 화면", "항목", "공급가액/금액", "세액", "상태", "메모"]];
header(summary.getRange("A20:F20"));
summary.getRange("A21:B26").values = [
  ["과세표준 및 매출세액", "신용카드·현금영수증 발행분"], ["과세표준 및 매출세액", "영세율 기타"],
  ["그 밖의 공제매입세액", "검증된 공제매입"], ["경감·공제세액", "전자신고 세액공제"],
  ["경감·공제세액", "신용카드 발행세액공제"], ["납부세액", "예상 납부세액"],
];
summary.getRange("C21:D26").formulas = [
  ["=B8", "=B9"], ["=B10", "=0"], ["='매입세액'!E" + inputTotal, "=B11"],
  ["=B13", "=0"], ["=B14", "=0"], ["=B15", "=0"],
];
summary.getRange("E21:E26").values = [["입력"], ["입력"], ["입력/불러오기"], ["자동/확인"], [data.policy.card_sales_credit_krw === 0 ? "미적용" : "적용"], ["자동계산 확인"]];
summary.getRange("F21:F26").values = [
  ["국내 과세 총결제액에서 산출"], ["증빙 충족 여부 최종 확인"], ["공제=1 합계"],
  ["현재 법령값 확인"], [data.policy.card_sales_credit_note], ["홈택스 값과 대조"],
];
grid(summary.getRange("A21:F26"));
summary.getRange("C21:D26").format.numberFormat = wonFmt;
summary.getRange("G20:H26").merge();
summary.getRange("G20:H26").values = [[`신고 전 마지막 확인\n\n1. 영세율 증빙 첨부\n2. 세액공제 현재값 확인\n3. 홈택스 계산값 대조\n4. 접수증·신고서 PDF 저장\n\n법정기한: ${data.filing.due_date}`]];
summary.getRange("G20:H26").format = { fill: C.paleGold, font: { bold: true, color: C.navy }, wrapText: true, verticalAlignment: "center", borders: { preset: "all", style: "medium", color: C.teal } };
summary.freezePanes.freezeRows(4);
finishSheet(summary, { A: 24, B: 22, C: 17, D: 14, E: 20, F: 36, G: 18, H: 18 });

const keyCheck = await wb.inspect({ kind: "region", sheetId: "신고요약", range: "A6:F16", maxChars: 6000 });
console.log("KEY_CHECK");
console.log(keyCheck.ndjson ?? keyCheck);
const errors = await wb.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 300 }, summary: "final formula error scan", maxChars: 10000 });
const errorText = errors.ndjson ?? JSON.stringify(errors);
console.log("ERROR_CHECK");
console.log(errorText);
if (/\"kind\":\"match\"/.test(errorText)) throw new Error("Formula errors found; workbook was not exported");

if (previewDir) {
  for (const sheetName of ["신고요약", "국내매출", "외화매출", "매입세액", "환율", "근거·체크"]) {
    const preview = await wb.render({ sheetName, autoCrop: "all", scale: 1, format: "png" });
    const safeName = sheetName.replace(/[·]/g, "_");
    await fs.writeFile(path.join(previewDir, `${safeName}.png`), new Uint8Array(await preview.arrayBuffer()));
  }
}

const output = await SpreadsheetFile.exportXlsx(wb);
await output.save(outputPath);
console.log(JSON.stringify({ status: "complete", output: outputPath, previews: previewDir, warnings }, null, 2));
