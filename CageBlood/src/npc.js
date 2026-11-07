// ===== Procedural fighter generation =====
import { makeRng, clamp } from './util.js';
import { STYLES, ALL_ATTRS, FIRST_NAMES, LAST_NAMES, NICKNAMES, SKIN_TONES, HAIR_COLORS, HAIR_STYLES, BEARDS, SHORTS_COLORS, COUNTRIES, wcById } from './data.js';

const SKIN_BY_COUNTRY = {
  TH: [2, 3, 4], US: [0, 1, 2, 4, 5, 6], BR: [1, 2, 3, 4, 5], RU: [0, 1], JP: [1, 2], KR: [1, 2], MX: [2, 3, 4], IE: [0], GB: [0, 1, 6],
  NG: [5, 6, 7], PH: [3, 4], CN: [1, 2], NL: [0, 1], PL: [0, 1], AU: [0, 1, 2], GE: [1, 2], DA: [1, 2, 3], FR: [0, 1, 4, 5],
};
const STYLE_BY_COUNTRY = {
  TH: ['muaythai', 'muaythai', 'kickboxing', 'boxing'], US: ['wrestling', 'wrestling', 'boxing', 'bjj', 'brawler', 'kickboxing'], BR: ['bjj', 'bjj', 'muaythai', 'kickboxing'],
  RU: ['sambo', 'wrestling', 'boxing', 'kickboxing'], JP: ['judo', 'kickboxing', 'bjj'], KR: ['kickboxing', 'judo', 'boxing'], MX: ['boxing', 'brawler', 'kickboxing'],
  IE: ['boxing', 'kickboxing', 'bjj'], GB: ['boxing', 'kickboxing', 'brawler'], NG: ['wrestling', 'boxing', 'kickboxing'], PH: ['boxing', 'kickboxing'], CN: ['kickboxing', 'wrestling', 'judo'],
  NL: ['kickboxing', 'kickboxing', 'muaythai'], PL: ['wrestling', 'boxing', 'brawler'], AU: ['kickboxing', 'brawler', 'bjj'], GE: ['wrestling', 'judo', 'sambo'], DA: ['wrestling', 'sambo', 'sambo'], FR: ['kickboxing', 'boxing', 'judo'],
};

export function baseAttrs(style, level, rnd) {
  const a = {};
  const mod = (STYLES[style] || STYLES.kickboxing).mod;
  for (const k of ALL_ATTRS) a[k] = clamp(Math.round(level + (mod[k] || 0) * 0.8 + (rnd ? rnd.gauss() * 5 : 0)), 15, 99);
  return a;
}

export function makeNPC(seed, opts = {}) {
  const r = makeRng(seed);
  const country = opts.country || r.pick(COUNTRIES)[0];
  const style = opts.style || r.pick(STYLE_BY_COUNTRY[country] || ['kickboxing']);
  const wc = wcById(opts.wc || 'light');
  const tier = opts.tier ?? 1;
  const levelBase = [42, 52, 60, 68][tier] + (opts.levelAdd || 0);
  const level = levelBase + r.gauss() * 4;
  const attrs = baseAttrs(style, level, r);
  const fn = r.pick(FIRST_NAMES[country] || FIRST_NAMES.US), ln = r.pick(LAST_NAMES[country] || LAST_NAMES.US);
  const skinI = r.pick(SKIN_BY_COUNTRY[country] || [1, 2, 3]);
  const age = Math.round(clamp(22 + tier * 2.5 + r.gauss() * 3.5, 19, 39));
  const grappler = ['wrestling', 'bjj', 'judo', 'sambo'].includes(style);
  const look = {
    skin: SKIN_TONES[skinI],
    hairColor: skinI > 4 ? r.pick([HAIR_COLORS[0], HAIR_COLORS[1]]) : r.pick(HAIR_COLORS.slice(0, 7)),
    hairStyle: r.pick(HAIR_STYLES)[0],
    beard: r.pick(BEARDS)[0],
    muscle: clamp(0.4 + r.gauss() * 0.15 + (style === 'wrestling' ? 0.15 : 0), 0.1, 0.95),
    fat: clamp(0.12 + r() * 0.2 + (wc.id === 'heavy' ? 0.25 : 0), 0, 0.7),
    shorts: r.pick(SHORTS_COLORS), tattoo: r.pick(['none', 'none', 'tribal', 'script', country === 'TH' ? 'sakyant' : 'none']),
    cauliflower: grappler && r() < 0.6, chestHair: r() < 0.25, scar: r() < 0.3,
    seed: Math.floor(r() * 1e9),
  };
  if (age > 33 && r() < 0.4) look.hairColor = HAIR_COLORS[7];
  const wins = tier === 0 ? r.int(0, 4) : tier === 1 ? r.int(2, 9) : tier === 2 ? r.int(5, 12) : r.int(9, 24);
  const losses = r.int(0, Math.max(1, Math.floor(wins / 3)));
  return {
    id: 'npc' + seed,
    name: `${fn} ${ln}`,
    nick: r() < 0.6 ? r.pick(NICKNAMES) : '',
    country, style, wc: wc.id,
    stance: r() < 0.78 ? 'orthodox' : 'southpaw',
    height: clamp(wc.h + r.gauss() * 0.045, 1.55, 2.05),
    weightKg: wc.kg * (1.04 + r() * 0.06),
    reachMul: clamp(1 + r.gauss() * 0.035, 0.92, 1.1),
    age, look, attrs,
    record: { w: wins, l: losses, d: r() < 0.1 ? 1 : 0 },
    tier,
  };
}
