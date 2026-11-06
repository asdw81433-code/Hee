// Human-play test: quick fight, press keys, check strikes; corner screen; pause; sandbox
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PW_PATH || 'playwright');
import path from 'node:path';
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const errors = [];
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message + '\n' + (e.stack || '').split('\n').slice(0, 4).join('\n')));
page.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
page.on('dialog', (d) => d.accept());
await page.goto('file://' + path.resolve('index.html') + '?warp=3');
await page.waitForTimeout(1500);
await page.locator('button', { hasText: 'ไฟต์ด่วน' }).first().click(); await page.waitForTimeout(400);
await page.locator('button', { hasText: 'เริ่มไฟต์' }).click(); await page.waitForTimeout(3500);
const st = () => page.evaluate(() => { const s = window.__game.scene; const p = s.player; return { phase: s.phase, t: s.time.toFixed(1), thrown: p.stats.thrown, landed: p.stats.landed, state: p.state, opp: p.opp.stats.landed, stam: Math.round(p.health.stamina), dist: p.rig.root.distanceTo(p.opp.rig.root).toFixed(2) }; });
console.log('start', JSON.stringify(await st()));
for (let i = 0; i < 40; i++) { const ph = await page.evaluate(() => window.__game.scene.phase); if (ph === 'fight') break; await page.waitForTimeout(300); }
// walk forward and throw combos
await page.keyboard.down('KeyW'); await page.waitForTimeout(700); await page.keyboard.up('KeyW');
for (const k of ['KeyJ', 'KeyK', 'KeyU', 'KeyJ', 'KeyK', 'KeyL', 'KeyI', 'KeyO']) { await page.keyboard.press(k); await page.waitForTimeout(250); }
await page.keyboard.down('ShiftLeft'); await page.keyboard.press('KeyU'); await page.keyboard.press('KeyL'); await page.keyboard.up('ShiftLeft');
await page.keyboard.down('KeyQ'); await page.keyboard.press('KeyL'); await page.keyboard.up('KeyQ');
await page.waitForTimeout(600);
console.log('after strikes', JSON.stringify(await st()));
await page.screenshot({ path: 'test/out/play_1.png' });
await page.keyboard.press('KeyZ'); await page.keyboard.press('KeyC'); await page.keyboard.down('Space'); await page.waitForTimeout(500); await page.keyboard.up('Space');
await page.keyboard.press('KeyG'); await page.waitForTimeout(1500);
console.log('after shoot', JSON.stringify(await st()));
await page.keyboard.press('Tab'); await page.waitForTimeout(300); await page.screenshot({ path: 'test/out/play_2_dmg.png' }); await page.keyboard.press('Tab');
// pause
await page.keyboard.press('Escape'); await page.waitForTimeout(300); await page.screenshot({ path: 'test/out/play_3_pause.png' });
await page.locator('button', { hasText: 'เล่นต่อ' }).click(); await page.waitForTimeout(300);
// force end of round -> corner
await page.evaluate(() => { window.__game.scene.clock = 0.01; });
await page.waitForTimeout(2000); await page.screenshot({ path: 'test/out/play_4_corner.png' });
const corner = await page.locator('h2', { hasText: 'พักยก' }).count();
console.log('corner shown', corner);
if (corner) { await page.locator('button', { hasText: 'ยกที่ 2' }).click(); await page.waitForTimeout(2500); console.log('round2', JSON.stringify(await page.evaluate(() => ({ r: window.__game.scene.round, ph: window.__game.scene.phase })))); }
// force decision
await page.evaluate(() => { const s = window.__game.scene; s.round = s.rounds; s.clock = 0.01; });
for (let i = 0; i < 40; i++) { if (await page.locator('.result-big').count()) break; await page.waitForTimeout(400); }
await page.screenshot({ path: 'test/out/play_5_result.png' });
console.log('result', await page.locator('.result-big').count());
// sandbox
await page.locator('button', { hasText: 'เมนูหลัก' }).click(); await page.waitForTimeout(1000);
await page.locator('button', { hasText: 'แซนด์บ็อกซ์' }).first().click(); await page.waitForTimeout(400);
await page.locator('button', { hasText: 'เข้าสู่แซนด์บ็อกซ์' }).click(); await page.waitForTimeout(2500);
for (const t of ['คิ้วซ้ายแตก', 'จมูกหัก', 'ตาบวมปิด']) { await page.locator('.sandbox-panel button', { hasText: t }).click(); await page.waitForTimeout(200); }
await page.locator('.sandbox-panel select').first().selectOption('aiai'); await page.waitForTimeout(4000);
await page.screenshot({ path: 'test/out/play_6_sandbox.png' });
await page.locator('.sandbox-panel button', { hasText: 'น็อกเลย' }).click(); await page.waitForTimeout(2500);
await page.screenshot({ path: 'test/out/play_7_sandbox_ko.png' });
await page.locator('.sandbox-panel button', { hasText: 'รีเซ็ตตำแหน่ง' }).click(); await page.waitForTimeout(1500);
console.log('sandbox', JSON.stringify(await page.evaluate(() => { const s = window.__game.scene; return { ph: s.phase, red: s.red.state, blue: s.blue.state, mode: s.blue.rig.mode }; })));
console.log(errors.join('\n') || 'no errors');
await browser.close();
