import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

const LINE_RE = /^\s*(--(?:ui|ds)-color-[a-z-]+)\s*:\s*(.*?)\s*;?\s*$/;
const HEX_RE = /#([0-9a-fA-F]{3,8})\b/;

export function normalizeHex(hex) {
  let h = hex.replace(/^#/, '').toLowerCase();
  if (h.length === 3) h = h[0]+h[0]+h[1]+h[1]+h[2]+h[2];
  if (h.length === 4) h = h[0]+h[0]+h[1]+h[1]+h[2]+h[2]+h[3]+h[3];
  if (h.length === 6) h += 'ff';
  return '#' + h;
}

export function buildTokenMap() {
  const cssPath = resolve(__dirname, '../css/design-tokens.css');
  const css = readFileSync(cssPath, 'utf-8');
  const map = new Map();

  for (const line of css.split('\n')) {
    const m = line.match(LINE_RE);
    if (!m) continue;
    const hexMatch = m[2].match(HEX_RE);
    if (!hexMatch) continue;
    const tokenName = m[1];
    const normalized = normalizeHex(hexMatch[0]);
    if (!map.has(normalized)) {
      map.set(normalized, tokenName);
    }
  }

  return map;
}
