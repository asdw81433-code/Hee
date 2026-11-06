// Headless career simulation: bundle career logic and run many weeks with random/auto decisions
import * as esbuild from 'esbuild';
import fs from 'node:fs';
await esbuild.build({ stdin: { contents: `
  import { Career } from './src/career.js';
  import { storyById } from './src/story.js';
  import { defaultProfile, computeAttrs } from './src/creator.js';
  export { Career, storyById, defaultProfile, computeAttrs };`, resolveDir: '.', loader: 'js' }, bundle: true, format: 'esm', platform: 'node', outfile: 'test/out/career_bundle.mjs', logLevel: 'error' });
globalThis.document = { createElement: () => ({ getContext: () => null }) };
const { Career, storyById, defaultProfile, computeAttrs } = await import('./out/career_bundle.mjs');
let summary = [];
for (let run = 0; run < 6; run++) {
  const p = defaultProfile(); p.attrs = computeAttrs(p); p.walkKg = 76;
  const c = Career.create(p);
  let fights = 0, stories = [], maxWeek = 900, bad = [];
  const plans = [['striking', 'cardio', 'bjj'], ['sparLight', 'wrestling', 'sc'], ['sparHard', 'diet', 'rest'], ['footwork', 'conditioning', 'cardio'], ['striking', 'wrestling', 'rest'], ['bjj', 'sc', 'diet']];
  for (let w = 0; w < maxWeek && !c.d.ended; w++) {
    // story
    let guard = 0;
    while (c.d.pendingStory.length && guard++ < 10) {
      const id = c.d.pendingStory[0]; const ev = storyById(id);
      if (!ev) { c.d.pendingStory.shift(); continue; }
      const sc = ev.scene(c);
      const ch = id === 'ending' || id === 'autoEnd' ? sc.choices[0] : sc.choices[(run + w) % Math.min(2, sc.choices.length)];
      ch.fx && ch.fx(c);
      c.d.seenStory[id] = true; c.d.pendingStory = c.d.pendingStory.filter((x) => x !== id); stories.push(id);
      if (c.d.ended) break;
    }
    if (c.d.ended) break;
    c.d.plan = plans[(w + run) % plans.length].slice();
    if (c.d.fatigue > 60) c.d.plan = ['rest', 'diet', 'film'];
    if (c.d.booked && c.d.booked.weeksOut <= 2) c.d.plan = ['rest', 'diet', 'film'];
    if (!c.d.booked && c.d.offers.length) c.acceptOffer(c.d.offers[0].id);
    const out = c.advanceWeek();
    if (out.fight) {
      c.lastWeighIn = c.weighIn();
      const res = c.simulate(); res.missedWeight = c.lastWeighIn.missed;
      c.applyResult(res); fights++;
    }
    // sanity
    for (const [k, v] of Object.entries(c.A)) if (!Number.isFinite(v)) bad.push(`attr ${k}=${v} @${w}`);
    for (const k of ['money', 'fame', 'hype', 'morale', 'fatigue', 'debt']) if (!Number.isFinite(c.d[k])) bad.push(`${k}=${c.d[k]} @${w}`);
    if (bad.length) break;
  }
  const f = c.f;
  summary.push({ run, weeks: c.d.week, age: f.age, fights, rec: `${f.record.w}-${f.record.l}-${f.record.d}`, am: `${f.am.w}-${f.am.l}`, promo: c.d.promo, rank: c.myRank(), champ: c.d.champ, titles: c.d.titles.length, money: Math.round(c.d.money), debt: c.d.debt, brain: Math.round(c.d.health.brainDamage), ovr: c.ovr(), ended: !!c.d.ended, ending: c.d.endingTitle, stories: stories.length, bad: bad.slice(0, 3) });
  if (run === 0) console.log('stories run0:', stories.join(','));
}
console.table(summary);
