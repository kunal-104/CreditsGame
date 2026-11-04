// Merges facts/data/src/*.json into one dataset for the website and the Flutter app.
//   node facts/tools/build-data.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

const CATEGORIES = [
  ['countries', 'Countries & Cultures', '🌍', '#0ea5e9'],
  ['food', 'Food', '🍜', '#f97316'],
  ['laws', 'Laws & Norms', '⚖️', '#64748b'],
  ['languages', 'Languages', '🗣️', '#8b5cf6'],
  ['geography', 'Geography', '🗺️', '#10b981'],
  ['science', 'Science', '🔬', '#06b6d4'],
  ['space', 'Space', '🪐', '#6366f1'],
  ['body', 'Human Body', '🫀', '#ef4444'],
  ['nature', 'Animals & Nature', '🐙', '#22c55e'],
  ['mind', 'Mind & Psychology', '🧠', '#ec4899'],
  ['history', 'History', '🏛️', '#a16207'],
  ['wars', 'Wars & Battles', '⚔️', '#b91c1c'],
  ['inventions', 'Inventions & Tech', '💡', '#eab308'],
  ['money', 'Money & Economics', '💰', '#16a34a'],
  ['work', 'Professions & Work', '🧰', '#0d9488'],
  ['maths', 'Maths', '🔢', '#2563eb'],
  ['beliefs', 'Religions & Beliefs', '🕊️', '#7c3aed'],
  ['ethics', 'Ethics & Philosophy', '🤔', '#9333ea'],
  ['games', 'Games & Sports', '♟️', '#d97706'],
  ['arts', 'Art & Music', '🎨', '#db2777'],
].map(([id, name, emoji, color]) => ({ id, name, emoji, color }));

// [code, name, continent]
const COUNTRIES = `AF Afghanistan AS|AL Albania EU|DZ Algeria AF|AR Argentina SA|AU Australia OC|AT Austria EU|BD Bangladesh AS|BE Belgium EU|BT Bhutan AS|BO Bolivia SA|BR Brazil SA|BG Bulgaria EU|KH Cambodia AS|CM Cameroon AF|CA Canada NA|CL Chile SA|CN China AS|CO Colombia SA|CR Costa Rica NA|HR Croatia EU|CU Cuba NA|CZ Czechia EU|DK Denmark EU|EG Egypt AF|EE Estonia EU|ET Ethiopia AF|FI Finland EU|FR France EU|DE Germany EU|GH Ghana AF|GR Greece EU|HU Hungary EU|IS Iceland EU|IN India AS|ID Indonesia AS|IR Iran AS|IQ Iraq AS|IE Ireland EU|IL Israel AS|IT Italy EU|JM Jamaica NA|JP Japan AS|JO Jordan AS|KZ Kazakhstan AS|KE Kenya AF|KW Kuwait AS|MY Malaysia AS|MV Maldives AS|ML Mali AF|MX Mexico NA|FM Micronesia OC|MN Mongolia AS|MA Morocco AF|MM Myanmar AS|NP Nepal AS|NL Netherlands EU|NZ New Zealand OC|NG Nigeria AF|NO Norway EU|PK Pakistan AS|PS Palestine AS|PG Papua New Guinea OC|PY Paraguay SA|PE Peru SA|PH Philippines AS|PL Poland EU|PT Portugal EU|QA Qatar AS|RO Romania EU|RU Russia EU|SA Saudi Arabia AS|SN Senegal AF|RS Serbia EU|SG Singapore AS|ZA South Africa AF|KR South Korea AS|ES Spain EU|LK Sri Lanka AS|SE Sweden EU|CH Switzerland EU|TW Taiwan AS|TZ Tanzania AF|TH Thailand AS|TR Turkey AS|UG Uganda AF|UA Ukraine EU|AE United Arab Emirates AS|GB United Kingdom EU|US United States NA|UY Uruguay SA|UZ Uzbekistan AS|VA Vatican City EU|VE Venezuela SA|VN Vietnam AS|ZW Zimbabwe AF`
  .split('|').map((s) => { const p = s.trim().split(' '); return { code: p[0], name: p.slice(1, -1).join(' '), continent: p[p.length - 1] }; });
const codes = new Set(COUNTRIES.map((c) => c.code));

const facts = [];
const seen = new Set();
const srcDir = path.join(root, 'data/src');
for (const file of fs.readdirSync(srcDir).sort()) {
  const data = JSON.parse(fs.readFileSync(path.join(srcDir, file), 'utf8'));
  for (const [cat, list] of Object.entries(data)) {
    if (!CATEGORIES.find((c) => c.id === cat)) throw new Error(`unknown category ${cat} in ${file}`);
    list.forEach((f) => {
      for (const k of ['r', 's', 'a', 'e', 'w']) if (f[k] === undefined) throw new Error(`missing ${k}: ${JSON.stringify(f)}`);
      if (typeof f.a !== 'boolean') throw new Error('answer must be boolean: ' + f.s);
      for (const r of f.r) if (r !== 'world' && !codes.has(r)) throw new Error(`unknown country ${r} in: ${f.s}`);
      if (seen.has(f.s)) throw new Error('duplicate: ' + f.s);
      seen.add(f.s);
      // stable id: category + short hash of the statement
      let h = 2166136261;
      for (const ch of f.s) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
      facts.push({ id: `${cat}-${(h >>> 0).toString(36)}`, c: cat, ...f });
    });
  }
}

const out = { version: 1, categories: CATEGORIES, countries: COUNTRIES, facts };
const json = JSON.stringify(out);
for (const dest of ['web/data/facts.json', 'app/assets/facts.json']) {
  const file = path.join(root, dest);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, json);
}
const byCat = Object.fromEntries(CATEGORIES.map((c) => [c.id, facts.filter((f) => f.c === c.id).length]));
const tagged = new Set(facts.flatMap((f) => f.r).filter((r) => r !== 'world'));
console.log(`${facts.length} facts (${facts.filter((f) => f.a).length} true / ${facts.filter((f) => !f.a).length} myths), ${tagged.size} countries tagged`);
console.log(byCat);
