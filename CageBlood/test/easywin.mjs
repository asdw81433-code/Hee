// Can a button-masher beat the default (easy) AI with simple controls?
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const pw = require(process.env.PW_PATH || 'playwright');
import path from 'node:path';
const browser = await pw.chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 900, height: 560 } });
const errors = [];
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
await page.goto('file://' + path.resolve('index.html') + '?warp=4');
await page.waitForTimeout(1500);
const results = [];
for (let n = 0; n < 2; n++) {
  await page.evaluate(() => { const g = window.__game; g.save.settings.clockScale = 10; g.save.settings.replay = false; const u = g.ui; u.qf = { me: 'random', meStyle: 'boxing', opStyle: ['muaythai', 'wrestling'][Math.floor(Math.random() * 2)], opLevel: 1, rounds: 3, mode: 'play', wc: 'light' }; u.startQuick(); });
  const t0 = Date.now();
  while (Date.now() - t0 < 200000) {
    const st = await page.evaluate(() => { const s = window.__game.scene, u = window.__game.ui; if (u.screen && u.screen.name === 'corner') { u.close(); s.nextRound({ treatCuts: true, water: true, enswell: true }); } if (u.screen && u.screen.name === 'result') return { done: true }; const p = s.player; return { d: p.rig.root.distanceTo(p.opp.rig.root), ph: s.phase }; });
    if (st.done) break;
    if (st.ph !== 'fight') { await page.waitForTimeout(300); continue; }
    if (st.d > 1.6) { await page.keyboard.down('KeyW'); await page.waitForTimeout(250); await page.keyboard.up('KeyW'); }
    const r = Math.random();
    await page.keyboard.press(r < 0.65 ? 'KeyJ' : r < 0.88 ? 'KeyK' : r < 0.95 ? 'KeyL' : 'ShiftLeft');
    await page.waitForTimeout(220);
  }
  const res = await page.evaluate(() => { const s = window.__game.scene; const r = s.result; return r ? { win: r.winner === s.player, m: r.method, d: r.detail, me: s.player.stats.sigLanded + '/' + s.player.stats.thrown, opp: s.player.opp.stats.sigLanded + '/' + s.player.opp.stats.thrown, oppStyle: s.player.opp.prof.style } : null; });
  results.push(res);
  await page.evaluate(() => { window.__game.ui.exitFight(); });
  await page.waitForTimeout(800);
}
console.log(JSON.stringify(results));
console.log(errors.join('\n') || 'no errors');
await browser.close();
