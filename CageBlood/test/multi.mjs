// Stability: several AI-vs-AI quick fights back to back at high clock speed; check errors, memory, fps
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PW_PATH || 'playwright');
import path from 'node:path';
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1000, height: 600 } });
const errors = [];
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message + '\n' + (e.stack || '').split('\n').slice(0, 5).join('\n')));
page.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
page.on('dialog', (d) => d.accept());
await page.goto('file://' + path.resolve('index.html') + '?warp=8');
await page.waitForTimeout(1500);
await page.evaluate(() => { const s = window.__game.save.settings; s.clockScale = 30; s.replay = false; });
const results = [];
for (let i = 0; i < 4; i++) {
  await page.evaluate(() => { const u = window.__game.ui; u.qf = { me: 'random', meStyle: ['boxing', 'wrestling', 'bjj', 'muaythai'][Math.floor(Math.random() * 4)], opStyle: ['kickboxing', 'sambo', 'brawler', 'judo'][Math.floor(Math.random() * 4)], opLevel: 2, rounds: 3, mode: 'watch', wc: 'light' }; u.startQuick(); });
  let done = false;
  for (let t = 0; t < 150 && !done; t++) {
    await page.waitForTimeout(1000);
    const st = await page.evaluate(() => { const u = window.__game.ui; if (u.screen && u.screen.name === 'corner') { u.close(); window.__game.scene.nextRound({ treatCuts: true, water: true }); } return u.screen && u.screen.name === 'result'; });
    done = st;
  }
  const r = await page.evaluate(() => { const s = window.__game.scene; const r = s.result; return r ? { m: r.method, d: r.detail, rnd: r.round, t: s.time.toFixed(0), sigR: s.red.stats.sigLanded, sigB: s.blue.stats.sigLanded, td: s.red.stats.td + s.blue.stats.td, cuts: s.red.health.cuts.length + s.blue.health.cuts.length, heap: performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1e6) : -1, geo: window.__game.world.renderer.info.memory.geometries, tex: window.__game.world.renderer.info.memory.textures } : { none: true, ph: s && s.phase, rnd: s && s.round }; });
  results.push(r);
  if (i === 1) await page.screenshot({ path: 'test/out/multi.png' });
}
console.log(JSON.stringify(results, null, 0));
console.log(errors.slice(0, 10).join('\n') || 'no errors');
await browser.close();
