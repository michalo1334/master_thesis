import valueParser from 'postcss-value-parser';
import stylelint from 'stylelint';
import { normalizeHex, buildTokenMap } from '../tokens.mjs';

const { createPlugin, utils } = stylelint;
const { report, ruleMessages, validateOptions } = utils;

const NAMED_COLORS = {
  aliceblue: '#f0f8ffff', antiquewhite: '#faebd7ff', aqua: '#00ffffff',
  aquamarine: '#7fffd4ff', azure: '#f0ffffff', beige: '#f5f5dcff',
  bisque: '#ffe4c4ff', black: '#000000ff', blanchedalmond: '#ffebcdff',
  blue: '#0000ffff', blueviolet: '#8a2be2ff', brown: '#a52a2aff',
  burlywood: '#deb887ff', cadetblue: '#5f9ea0ff', chartreuse: '#7fff00ff',
  chocolate: '#d2691eff', coral: '#ff7f50ff', cornflowerblue: '#6495edff',
  cornsilk: '#fff8dcff', crimson: '#dc143cff', cyan: '#00ffffff',
  darkblue: '#00008bff', darkcyan: '#008b8bff', darkgoldenrod: '#b8860bff',
  darkgray: '#a9a9a9ff', darkgreen: '#006400ff', darkgrey: '#a9a9a9ff',
  darkkhaki: '#bdb76bff', darkmagenta: '#8b008bff', darkolivegreen: '#556b2fff',
  darkorange: '#ff8c00ff', darkorchid: '#9932ccff', darkred: '#8b0000ff',
  darksalmon: '#e9967aff', darkseagreen: '#8fbc8fff', darkslateblue: '#483d8bff',
  darkslategray: '#2f4f4fff', darkslategrey: '#2f4f4fff', darkturquoise: '#00ced1ff',
  darkviolet: '#9400d3ff', deeppink: '#ff1493ff', deepskyblue: '#00bfffff',
  dimgray: '#696969ff', dimgrey: '#696969ff', dodgerblue: '#1e90ffff',
  firebrick: '#b22222ff', floralwhite: '#fffaf0ff', forestgreen: '#228b22ff',
  fuchsia: '#ff00ffff', gainsboro: '#dcdcdcff', ghostwhite: '#f8f8ffff',
  gold: '#ffd700ff', goldenrod: '#daa520ff', gray: '#808080ff',
  green: '#008000ff', greenyellow: '#adff2fff', grey: '#808080ff',
  honeydew: '#f0fff0ff', hotpink: '#ff69b4ff', indianred: '#cd5c5cff',
  indigo: '#4b0082ff', ivory: '#fffff0ff', khaki: '#f0e68cff',
  lavender: '#e6e6faff', lavenderblush: '#fff0f5ff', lawngreen: '#7cfc00ff',
  lemonchiffon: '#fffacdff', lightblue: '#add8e6ff', lightcoral: '#f08080ff',
  lightcyan: '#e0ffffff', lightgoldenrodyellow: '#fafad2ff', lightgray: '#d3d3d3ff',
  lightgreen: '#90ee90ff', lightgrey: '#d3d3d3ff', lightpink: '#ffb6c1ff',
  lightsalmon: '#ffa07aff', lightseagreen: '#20b2aaff', lightskyblue: '#87cefaff',
  lightslategray: '#778899ff', lightslategrey: '#778899ff', lightsteelblue: '#b0c4deff',
  lightyellow: '#ffffe0ff', lime: '#00ff00ff', limegreen: '#32cd32ff',
  linen: '#faf0e6ff', magenta: '#ff00ffff', maroon: '#800000ff',
  mediumaquamarine: '#66cdaaff', mediumblue: '#0000cdff', mediumorchid: '#ba55d3ff',
  mediumpurple: '#9370dbff', mediumseagreen: '#3cb371ff', mediumslateblue: '#7b68eeff',
  mediumspringgreen: '#00fa9aff', mediumturquoise: '#48d1ccff', mediumvioletred: '#c71585ff',
  midnightblue: '#191970ff', mintcream: '#f5fffaff', mistyrose: '#ffe4e1ff',
  moccasin: '#ffe4b5ff', navajowhite: '#ffdeadff', navy: '#000080ff',
  oldlace: '#fdf5e6ff', olive: '#808000ff', olivedrab: '#6b8e23ff',
  orange: '#ffa500ff', orangered: '#ff4500ff', orchid: '#da70d6ff',
  palegoldenrod: '#eee8aaff', palegreen: '#98fb98ff', paleturquoise: '#afeeeeff',
  palevioletred: '#db7093ff', papayawhip: '#ffefd5ff', peachpuff: '#ffdab9ff',
  peru: '#cd853fff', pink: '#ffc0cbff', plum: '#dda0ddff',
  powderblue: '#b0e0e6ff', purple: '#800080ff', rebeccapurple: '#663399ff',
  red: '#ff0000ff', rosybrown: '#bc8f8fff', royalblue: '#4169e1ff',
  saddlebrown: '#8b4513ff', salmon: '#fa8072ff', sandybrown: '#f4a460ff',
  seagreen: '#2e8b57ff', seashell: '#fff5eeff', sienna: '#a0522dff',
  silver: '#c0c0c0ff', skyblue: '#87ceebff', slateblue: '#6a5acdff',
  slategray: '#708090ff', slategrey: '#708090ff', snow: '#fffafaff',
  springgreen: '#00ff7fff', steelblue: '#4682b4ff', tan: '#d2b48cff',
  teal: '#008080ff', thistle: '#d8bfd8ff', tomato: '#ff6347ff',
  turquoise: '#40e0d0ff', violet: '#ee82eeff', wheat: '#f5deb3ff',
  white: '#ffffffff', whitesmoke: '#f5f5f5ff', yellow: '#ffff00ff',
  yellowgreen: '#9acd32ff',
};

const SKIP = new Set([
  'transparent', 'currentcolor', 'inherit', 'initial', 'unset', 'revert',
]);

const SYSTEM_COLORS = new Set([
  'canvas', 'canvastext', 'linktext', 'visitedtext', 'activetext',
  'buttonface', 'buttontext', 'field', 'fieldtext', 'highlight',
  'highlighttext', 'selecteditem', 'selecteditemtext',
  'mark', 'marktext', 'graytext', 'accentcolor', 'accentcolortext',
]);

function collectArgs(nodes) {
  const parts = [];
  let buf = '';
  for (const n of nodes) {
    if (n.type === 'div' && (n.value === ',' || n.value === '/')) {
      if (buf) { parts.push(buf.trim()); buf = ''; }
      continue;
    }
    if (n.type === 'space') {
      if (buf) { parts.push(buf.trim()); buf = ''; }
      continue;
    }
    if (n.type === 'word') buf += n.value;
  }
  if (buf) parts.push(buf.trim());
  return parts;
}

function toNum(s) {
  s = s.trim();
  if (s.endsWith('%')) return { val: parseFloat(s) / 100, isPct: true };
  return { val: parseFloat(s), isPct: false };
}

function rgbToHex(r, g, b, a) {
  const clamp = (v) => Math.max(0, Math.min(255, Math.round(v)));
  const alpha = a !== undefined ? Math.max(0, Math.min(255, Math.round(a * 255))) : 255;
  return '#' + [r, g, b, alpha].map(c => clamp(c).toString(16).padStart(2, '0')).join('');
}

function funcToHex(funcName, nodes) {
  const fn = funcName.toLowerCase();
  if (fn !== 'rgb' && fn !== 'rgba' && fn !== 'hsl' && fn !== 'hsla') return null;

  const args = collectArgs(nodes);
  if (args.length < 3) return null;

  try {
    if (fn === 'rgb' || fn === 'rgba') {
      const [rr, gg, bb] = args.slice(0, 3).map(toNum);
      const r = rr.isPct ? rr.val * 255 : rr.val;
      const g = gg.isPct ? gg.val * 255 : gg.val;
      const b = bb.isPct ? bb.val * 255 : bb.val;
      const a = args[3] ? toNum(args[3]).val : 1;
      return rgbToHex(r, g, b, a);
    }

    if (fn === 'hsl' || fn === 'hsla') {
      const [hh, ss, ll] = args.slice(0, 3).map(toNum);
      let h = ((hh.val % 360) + 360) % 360 / 360;
      let s = Math.max(0, Math.min(1, ss.isPct ? ss.val : ss.val / 100));
      let l = Math.max(0, Math.min(1, ll.isPct ? ll.val : ll.val / 100));
      const a = args[3] ? toNum(args[3]).val : 1;

      const hue2rgb = (p, q, t) => {
        if (t < 0) t += 1;
        if (t > 1) t -= 1;
        if (t < 1/6) return p + (q - p) * 6 * t;
        if (t < 1/2) return q;
        if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
        return p;
      };

      const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
      const p = 2 * l - q;
      return rgbToHex(
        Math.round(hue2rgb(p, q, h + 1/3) * 255),
        Math.round(hue2rgb(p, q, h) * 255),
        Math.round(hue2rgb(p, q, h - 1/3) * 255),
        a
      );
    }
  } catch {
    return null;
  }
  return null;
}

let tokenMap = null;

const ruleName = 'ds/no-hardcoded-colors';

const messages = ruleMessages(ruleName, {
  rejectedWithToken: (color, token) =>
    `Hardcoded color "${color}" → use ${token}`,
  rejectedNoToken: (color) =>
    `Hardcoded color "${color}" (no matching design token)`,
});

const ruleFunction = (primaryOption, secondaryOptions, context) => {
  return (root, result) => {
    const validOptions = validateOptions(result, ruleName, {
      actual: primaryOption,
      possible: [true, false],
    });
    if (!validOptions) return;
    if (primaryOption !== true) return;

    if (!tokenMap) {
      tokenMap = buildTokenMap();
    }

    root.walkDecls((decl) => {
      const parsed = valueParser(decl.value);

      parsed.walk((node) => {
        let display = null; // original text to show in message
        let normalized = null; // 8-digit hex for token lookup

        if (node.type === 'word') {
          const w = node.value;
          if (w.startsWith('#')) {
            display = w;
            normalized = normalizeHex(w);
          } else {
            const lower = w.toLowerCase();
            const named = NAMED_COLORS[lower];
            if (named) {
              display = w;
              normalized = named;
            }
          }
        } else if (node.type === 'function') {
          const hex = funcToHex(node.value, node.nodes);
          if (hex) {
            display = valueParser.stringify(node);
            normalized = hex;
          }
        }

        if (!display) return;
        const lower = display.toLowerCase();
        if (SKIP.has(lower)) return;
        if (SYSTEM_COLORS.has(lower)) return;

        const token = tokenMap.get(normalized);

        report({
          message: token
            ? messages.rejectedWithToken(display, token)
            : messages.rejectedNoToken(display),
          node: decl,
          word: display,
          result,
          ruleName,
        });
      });
    });
  };
};

ruleFunction.ruleName = ruleName;
ruleFunction.messages = messages;
ruleFunction.meta = { url: 'https://github.com/michalo1334/master_thesis' };

export default createPlugin(ruleName, ruleFunction);
