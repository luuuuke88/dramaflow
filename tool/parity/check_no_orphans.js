#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const DOCS = path.join(__dirname, '..', '..', 'docs', 'parity');
const inv = JSON.parse(fs.readFileSync(path.join(DOCS, 'inventory.json'), 'utf8'));
const checklist = fs.readFileSync(path.join(DOCS, 'master-checklist.md'), 'utf8');
const na = fs.readFileSync(path.join(DOCS, 'inventory-na.md'), 'utf8');
const covered = new Set();
for (const line of checklist.split('\n')) {
  // 按未转义竖线切分：既有约定用全角｜写字面竖线，但标准 markdown 的 \| 转义
  // 也必须安全——naive split 会让含 \| 的行多出一格、覆盖库存列静默错位。
  const cells = line.split(/(?<!\\)\|/).map((c) => c.trim());
  if (cells.length < 12 || cells[1] === 'ID' || cells[1].startsWith('---')) continue;
  for (const id of cells[10].split(',').map((s) => s.trim()).filter(Boolean)) covered.add(id);
}
for (const line of na.split('\n')) {
  // 按未转义竖线切分：既有约定用全角｜写字面竖线，但标准 markdown 的 \| 转义
  // 也必须安全——naive split 会让含 \| 的行多出一格、覆盖库存列静默错位。
  const cells = line.split(/(?<!\\)\|/).map((c) => c.trim());
  if (cells.length >= 3 && cells[1] && !['库存 ID', ''].includes(cells[1]) && !cells[1].startsWith('---')) {
    if (!cells[2]) { console.error(`NA missing reason: ${cells[1]}`); process.exitCode = 1; }
    covered.add(cells[1]);
  }
}
const orphans = inv.items.map((i) => i.id).filter((id) => !covered.has(id));
const unknown = [...covered].filter((id) => !inv.items.some((i) => i.id === id));
if (unknown.length) console.error(`WARN unknown ids referenced: ${unknown.length}\n` + unknown.slice(0, 20).join('\n'));
if (orphans.length) {
  console.error(`ORPHANS ${orphans.length}/${inv.items.length}`);
  console.error(orphans.join('\n'));
  process.exit(1);
}
console.log(`OK all ${inv.items.length} inventory items covered`);
