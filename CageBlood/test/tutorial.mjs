// Play through the tutorial with the simple keyboard controls
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const pw = require(process.env.PW_PATH || 'playwright');
import path from 'node:path';
const browser = await pw.chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const errors = [];
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message + '\n' + (e.stack || '').split('\n').slice(0, 3).join('\n')));
await page.goto('file://' + path.resolve('index.html') + '?warp=2');
await page.waitForTimeout(1500);
await page.locator('.tile', { hasText: 'ฝึกเล่น' }).click();
for (let i = 0; i < 40; i++) { if (await page.evaluate(() => window.__game.scene && window.__game.scene.phase) === 'fight') break; await page.waitForTimeout(300); }
const step = () => page.evaluate(() => window.__game.ui.tut ? window.__game.ui.tut.i : -1);
const t0 = Date.now(); let last = -2, shots = 0;
while (Date.now() - t0 < 240000) {
  const i = await step();
  if (i !== last) { console.log('step', i, ((Date.now() - t0) / 1000).toFixed(0) + 's'); last = i; if ([1, 3, 5, 7, 8].includes(i)) await page.screenshot({ path: `test/out/tut_${shots++}.png` }); }
  if (i === 8 || i < 0) break;
  if (i === 0) { await page.keyboard.down('KeyW'); await page.waitForTimeout(400); await page.keyboard.up('KeyW'); }
  else if (i === 1) { await page.keyboard.press('KeyJ'); await page.waitForTimeout(350); }
  else if (i === 2) { await page.keyboard.press('KeyK'); await page.waitForTimeout(700); }
  else if (i === 3) { await page.keyboard.down('Space'); await page.waitForTimeout(1500); await page.keyboard.up('Space'); }
  else if (i === 4) { await page.keyboard.press('ShiftLeft'); await page.waitForTimeout(600); }
  else if (i === 5) { await page.keyboard.press('KeyL'); await page.waitForTimeout(1200); }
  else if (i === 6) { await page.keyboard.press('KeyJ'); await page.waitForTimeout(600); }
  else if (i === 7) { await page.keyboard.press('KeyL'); await page.waitForTimeout(250); await page.keyboard.press('Space'); await page.waitForTimeout(250); }
}
console.log('final step', await step(), 'tutorialDone', await page.evaluate(() => !!window.__game.save.tutorialDone));
console.log(errors.join('\n') || 'no errors');
await browser.close();
