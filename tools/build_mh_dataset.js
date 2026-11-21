// Usage: node tools/build_mh_dataset.js <path-to-master_icd_x.json>
const assert = require('node:assert/strict');
const { mkdirSync, readFileSync, writeFileSync } = require('node:fs');
const { dirname, resolve } = require('node:path');

function classify(code) {
  if (/^F\d{2}(?:\.\d+)?$/.test(code)) return 'disorder';
  if (/^Z(?:5[5-9]|6[0-5]|71)(?:\.\d+)?$/.test(code)) return 'psychosocial';
  if (code === 'R45.8' || /^X(?:[67]\d|8[0-4])(?:\.\d+)?$/.test(code)) {
    return 'risk_indicator';
  }
  return null;
}

function aliasesFor(code) {
  if (code === 'F41.1') return ['GAD', 'gangguan cemas menyeluruh'];
  if (code === 'F43.1') return ['PTSD', 'gangguan stres pascatrauma'];
  if (code === 'F60.3') return ['BPD', 'gangguan kepribadian ambang'];
  if (code === 'F90.0') {
    return ['ADHD', 'GPPH', 'gangguan pemusatan perhatian dan hiperaktivitas'];
  }
  if (/^F42(?:\.|$)/.test(code)) return ['OCD', 'gangguan obsesif kompulsif'];
  if (/^F(?:32\.[0-3]|33\.[0-4])$/.test(code)) return ['MDD', 'depresi mayor'];
  return [];
}

const [inputPath] = process.argv.slice(2);
if (!inputPath) {
  console.error('Usage: node tools/build_mh_dataset.js <path-to-master_icd_x.json>');
  process.exit(1);
}

const rows = JSON.parse(readFileSync(inputPath, 'utf8').replace(/^\uFEFF/, ''));
assert(Array.isArray(rows), 'Expected an array of ICD-10 rows');
const entries = new Map();
for (const row of rows) {
  assert(typeof row?.kode_icd === 'string', 'Missing kode_icd');
  const match = /^([A-Z]\d{2})(?:\.?(\d+))?$/.exec(row.kode_icd.trim().toUpperCase());
  if (!match) continue;
  const [, category, subcategory] = match;
  const code = subcategory ? `${category}.${subcategory}` : category;
  const type = classify(code);
  if (type === null) continue;

  assert(!entries.has(code), `Duplicate code: ${code}`);
  assert(typeof row.nama_icd === 'string' && row.nama_icd.trim(), `Missing title: ${code}`);
  const indonesian = row.nama_icd_indo?.trim();
  entries.set(code, {
    code,
    code_clean: code.replace('.', ''),
    title: row.nama_icd.trim(),
    keywords: [...new Set([indonesian, ...aliasesFor(code)].filter(Boolean))],
    type,
  });
}

const dataset = [...entries.keys()].sort().map((code) => entries.get(code));
assert(dataset.length > 0, 'No matching mental-health codes in input');
const output = resolve(__dirname, '../assets/data/mh_icd10_id_en.json');
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${JSON.stringify(dataset, null, 2)}\n`);
console.log(`Wrote ${dataset.length} ICD-10 entries from ${rows.length} input rows.`);
