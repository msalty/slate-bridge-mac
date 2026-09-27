// Test vectors for the filename port, produced by Slate's own TypeScript.
//
//   node scripts/name-vectors.mjs ../slate > Tests/Fixtures/name-vectors.json
//
// Runs `safeSegment`, `fitSegment`, `numberedSegment` (src/core/util.ts) and
// `importedNoteName` (src/core/eventname.ts) from a Slate checkout over inputs
// chosen to find where Swift and JavaScript disagree: UTF-16 lengths,
// surrogate pairs at the cut, JavaScript's idea of whitespace, reserved names.
// Needs a Node that strips TypeScript types (22.18+).

import { cpSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

const slate = process.argv[2] ?? '../slate'
const dir = mkdtempSync(join(tmpdir(), 'name-vectors-'))
for (const f of ['util.ts', 'eventname.ts']) {
  const src = readFileSync(join(slate, 'src/core', f), 'utf8').replace(/from '\.\/util'/g, "from './util.ts'")
  writeFileSync(join(dir, f), src)
}
writeFileSync(join(dir, 'package.json'), '{"type":"module"}')
const util = await import(pathToFileURL(join(dir, 'util.ts')).href)
const names = await import(pathToFileURL(join(dir, 'eventname.ts')).href)

const emoji = '🎉'
const inputs = [
  'Design review', 'Q3: planning / review?', 'a<b>c:d"e/f\\g|h?i*j', 'tab\there', 'line\nbreak\r\nand more',
  '  padded  ', '   ', '', '...', 'trailing.', 'trailing. . .', 'dots... and spaces . ', 'CON', 'con',
  'Com1', 'LPT9', 'COM0', 'con.txt', 'nul ', 'aux.', '\u0000\u001f control', 'nbsp here',
  'ls ps ', 'bom﻿x', 'zwsp​x', 'mongolian᠎x', 'nel\u0085x', 'ideo　space',
  'thin  spaces', 'Café crème', 'é combining', '日本語の会議', 'Ǆemo',
  'x'.repeat(200), 'M'.repeat(120), 'M'.repeat(121), 'a'.repeat(119) + emoji, 'a'.repeat(118) + emoji,
  'a' + emoji.repeat(70), emoji.repeat(61), 'a'.repeat(115) + ' . . . . . . b', 'a'.repeat(113) + '.     x',
  'Lunch with Joe - 2026-09-22', 'Standup (a41b)', '👩‍👩‍👧‍👦 family', 'ab\ud83d', // a lone surrogate on the end
]

const out = { safeSegment: [], fitSegment: [], numberedSegment: [], importedNoteName: [] }
for (const s of inputs) {
  // A lone surrogate cannot be a Swift String; it is here only to show the
  // TypeScript's behaviour and is left out of the vectors.
  if (/[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/.test(s)) continue
  const safe = util.safeSegment(s)
  out.safeSegment.push([s, safe])
  for (const room of [0, 1, 4, 50, 100, 112, 113, 114, 119, 120]) out.fitSegment.push([safe, room, util.fitSegment(safe, room)])
  for (const n of [1, 2, 13, 100]) out.numberedSegment.push([safe, n, util.numberedSegment(safe, n)])
  for (const tag of ['a41b', 'c0ffee', 'b36177ac']) out.importedNoteName.push([s, tag, names.importedNoteName(s, tag)])
}
process.stdout.write(JSON.stringify(out, null, 1) + '\n')
