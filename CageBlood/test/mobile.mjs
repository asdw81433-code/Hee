// Mobile emulation: touch controls, joystick, buttons, menus at phone size
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const pw = require(process.env.PW_PATH || 'playwright');
import path from 'node:path';
const browser = await pw.chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const ctx = await browser.newContext({ ...pw.devices['iPhone 13 landscape'] });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message + '\n' + (e.stack || '').split('\n').slice(0, 3).join('\n')));
page.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
await page.goto('file://' + path.resolve('index.html') + '?warp=2');
await page.waitForTimeout(2500);
await page.screenshot({ path: 'test/out/m_title.png' });
await page.locator('.tile', { hasText: 'ไฟต์ด่วน' }).tap(); await page.waitForTimeout(400);
await page.screenshot({ path: 'test/out/m_quick.png' });
await page.locator('button', { hasText: 'เริ่มไฟต์' }).tap(); await page.waitForTimeout(1500);
for (let i = 0; i < 40; i++) { const ph = await page.evaluate(() => window.__game.scene && window.__game.scene.phase); if (ph === 'fight') break; await page.waitForTimeout(300); }
console.log('touch visible', await page.locator('.touch:not(.hidden)').count(), 'buttons', await page.locator('.touch .tbtn').count());
const st = () => page.evaluate(() => { const s = window.__game.scene, p = s.player; return { thrown: p.stats.thrown, x: p.rig.root.x.toFixed(2), z: p.rig.root.z.toFixed(2), state: p.state, block: p.blocking }; });
const before = await st();
// joystick: push forward (up)
const stick = await page.locator('.tstick').boundingBox();
await page.mouse.move(stick.x + stick.width / 2, stick.y + stick.height / 2); await page.mouse.down();
await page.mouse.move(stick.x + stick.width / 2, stick.y - 30, { steps: 4 }); await page.waitForTimeout(1500);
await page.mouse.up();
const moved = await st();
for (const lbl of ['ต่อย', 'ต่อย', 'ต่อย', 'เตะ']) { await page.locator('.teasy .tbtn', { hasText: lbl }).first().tap(); await page.waitForTimeout(450); }
await page.screenshot({ path: 'test/out/m_fight.png' });
const after = await st();
// hold guard
const g = await page.locator('.teasy .tbtn.guard').boundingBox();
await page.mouse.move(g.x + 20, g.y + 20); await page.mouse.down(); await page.waitForTimeout(400);
const guard = await st(); await page.mouse.up();
console.log('before', JSON.stringify(before), 'moved', JSON.stringify(moved), 'after', JSON.stringify(after), 'guard', guard.block);
await page.locator('.tbtn', { hasText: 'หยุด' }).tap(); await page.waitForTimeout(400);
await page.screenshot({ path: 'test/out/m_pause.png' });
console.log('pause shown', await page.locator('h2', { hasText: 'หยุดชั่วคราว' }).count());
await page.locator('.tile', { hasText: 'ออก' }).tap(); await page.waitForTimeout(300);
await page.locator('.modal button', { hasText: 'ออก' }).tap(); await page.waitForTimeout(1200);
// creator on phone
await page.locator('.tile', { hasText: 'อาชีพใหม่' }).tap(); await page.waitForTimeout(1500);
await page.locator('.tab', { hasText: 'ร่างกาย' }).tap(); await page.waitForTimeout(500);
await page.screenshot({ path: 'test/out/m_creator.png' });
await page.locator('.thumb', { hasText: 'แอฟโฟร' }).tap(); await page.waitForTimeout(300);
await page.locator('.thumb', { hasText: 'เต็มหน้า' }).tap(); await page.waitForTimeout(600);
await page.locator('button', { hasText: 'ดูตัว' }).tap(); await page.waitForTimeout(1500);
await page.screenshot({ path: 'test/out/m_peek.png' });
console.log('look', JSON.stringify(await page.evaluate(() => { const c = window.__game.ui.creator; return c && { hair: c.p.look.hairStyle, beard: c.p.look.beard }; })));
console.log(errors.join('\n') || 'no errors');
await browser.close();
