// touch guard hold + sandbox ragdoll tools (limp, drag, get up)
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const pw = require(process.env.PW_PATH || 'playwright');
import path from 'node:path';
const browser = await pw.chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const errors = [];
// --- touch guard
{
  const ctx = await browser.newContext({ ...pw.devices['iPhone 13 landscape'] });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  await page.goto('file://' + path.resolve('index.html') + '?warp=2');
  await page.waitForTimeout(1500);
  await page.evaluate(() => { const u = window.__game.ui; u.qf = { me: 'random', meStyle: 'boxing', opStyle: 'boxing', opLevel: 1, rounds: 3, mode: 'play', wc: 'light' }; u.startQuick(); });
  for (let i = 0; i < 40; i++) { if (await page.evaluate(() => window.__game.scene.phase) === 'fight') break; await page.waitForTimeout(300); }
  const g = await page.locator('.teasy .tbtn.guard').boundingBox();
  await page.mouse.move(g.x + 20, g.y + 20); await page.mouse.down(); await page.waitForTimeout(700);
  const blk = await page.evaluate(() => { const p = window.__game.scene.player; return { block: p.blocking, inp: p.input.block, action: p.action && p.action.type }; });
  await page.mouse.up(); await page.waitForTimeout(300);
  const after = await page.evaluate(() => window.__game.scene.player.blocking);
  console.log('touch guard held', JSON.stringify(blk), 'released ->', after);
  await ctx.close();
}
// --- sandbox ragdoll (desktop)
{
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message + '\n' + (e.stack || '').split('\n').slice(0, 3).join('\n')));
  await page.goto('file://' + path.resolve('index.html') + '?warp=2');
  await page.waitForTimeout(1500);
  await page.locator('.tile', { hasText: 'แซนด์บ็อกซ์' }).click(); await page.waitForTimeout(300);
  await page.locator('button', { hasText: 'เข้าสู่แซนด์บ็อกซ์' }).click(); await page.waitForTimeout(2500);
  await page.locator('.sandbox-panel .iconbtn', { hasText: 'คู่เป็นหุ่น' }).click();
  await page.locator('.sandbox-panel .iconbtn', { hasText: 'ตัวอ่อน' }).click(); await page.waitForTimeout(1500);
  const limp = await page.evaluate(() => { const b = window.__game.scene.blue; return { mode: b.rig.mode, state: b.state }; });
  await page.screenshot({ path: 'test/out/rag_limp.png' });
  // drag: project blue chest to screen
  await page.locator('.sandbox-panel .iconbtn', { hasText: 'ลากร่าง' }).click(); await page.waitForTimeout(200);
  const sp = await page.evaluate(() => { const g = window.__game, b = g.scene.blue; const v = b.rig.pts[1].clone().project(g.world.camera); const r = g.view.getBoundingClientRect(); return [r.left + (v.x + 1) / 2 * r.width, r.top + (1 - v.y) / 2 * r.height]; });
  await page.mouse.move(sp[0], sp[1]); await page.mouse.down();
  await page.mouse.move(sp[0], sp[1] - 160, { steps: 10 }); await page.waitForTimeout(800);
  const held = await page.evaluate(() => { const b = window.__game.scene.blue; return { grab: !!b.rig.grab, chestY: b.rig.pts[1].y.toFixed(2) }; });
  await page.screenshot({ path: 'test/out/rag_drag.png' });
  await page.mouse.up(); await page.waitForTimeout(1500);
  const dropped = await page.evaluate(() => { const b = window.__game.scene.blue; return { grab: !!b.rig.grab, chestY: b.rig.pts[1].y.toFixed(2), mode: b.rig.mode }; });
  await page.locator('.sandbox-panel .iconbtn', { hasText: 'ลากร่าง' }).click();
  await page.locator('.sandbox-panel .iconbtn', { hasText: 'ลุกขึ้น' }).click();
  let up = null;
  for (let i = 0; i < 25; i++) { await page.waitForTimeout(400); up = await page.evaluate(() => window.__game.scene.blue.state); if (up === 'stand') break; }
  console.log('limp', JSON.stringify(limp), 'held', JSON.stringify(held), 'dropped', JSON.stringify(dropped), 'final state', up);
  await page.locator('.sandbox-panel .iconbtn', { hasText: 'ออก' }).click(); await page.waitForTimeout(800);
  console.log('panels left after exit', await page.locator('.sandbox-panel').count());
}
console.log(errors.join('\n') || 'no errors');
await browser.close();
