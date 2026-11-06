// UI flow test: title -> creator -> career -> weeks -> story -> fight sim
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PW_PATH || 'playwright');
import path from 'node:path';
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 760 } });
const errors = [];
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message + '\n' + (e.stack || '').split('\n').slice(0, 4).join('\n')));
page.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
page.on('dialog', (d) => d.accept());
await page.goto('file://' + path.resolve('index.html'));
const shot = async (n) => { await page.screenshot({ path: `test/out/ui_${n}.png` }); };
const click = async (text) => { const b = page.locator('button, .tab, .chip', { hasText: text }).first(); await b.click({ timeout: 5000 }); await page.waitForTimeout(400); };
await page.waitForTimeout(2500); await shot('01_title');
await click('เริ่มอาชีพใหม่'); await page.waitForTimeout(1500); await shot('02_creator_id');
await click('2. ร่างกาย'); await page.waitForTimeout(800); await shot('03_creator_body');
await click('3. วาดใบหน้า'); await page.waitForTimeout(800);
// draw a few strokes on the face canvas
const cv = page.locator('.face-canvas-wrap canvas').first(); const bb = await cv.boundingBox();
await page.mouse.move(bb.x + 100, bb.y + 140); await page.mouse.down(); await page.mouse.move(bb.x + 140, bb.y + 135, { steps: 5 }); await page.mouse.up();
await page.waitForTimeout(800); await shot('04_creator_face');
await click('4. สไตล์'); await page.waitForTimeout(500);
for (let i = 0; i < 5; i++) { await page.locator('.attr-row button', { hasText: '+' }).nth(0).click(); }
await shot('05_creator_style');
await click('ยืนยันนักสู้'); await page.waitForTimeout(1500); await shot('06_story_prologue');
for (let i = 0; i < 10; i++) { const n = await page.locator('button', { hasText: 'ต่อไป' }).count(); if (!n) break; await click('ต่อไป'); }
await shot('07_story_choice');
await page.locator('.choices button').first().click(); await page.waitForTimeout(1200); await shot('08_career');
// advance weeks until a fight or story
for (let w = 0; w < 12; w++) {
  const story = await page.locator('.story').count();
  if (story) { for (let i = 0; i < 10; i++) { const n = await page.locator('button', { hasText: 'ต่อไป' }).count(); if (!n) break; await click('ต่อไป'); } await page.locator('.choices button').first().click(); await page.waitForTimeout(600); continue; }
  const wi = await page.locator('h2', { hasText: 'ชั่งน้ำหนัก' }).count();
  if (wi) break;
  const nb = page.locator('button', { hasText: /สัปดาห์/ }).last(); if (await nb.count()) { await nb.click(); await page.waitForTimeout(500); }
}
await shot('09_after_weeks');
const wi = await page.locator('h2', { hasText: 'ชั่งน้ำหนัก' }).count();
if (wi) { await shot('10_weighin'); await click('จำลองผลทันที'); await page.waitForTimeout(800); await shot('11_result'); await click('กลับสู่ยิม'); await page.waitForTimeout(1200); await shot('12_back'); }
const state = await page.evaluate(() => { const c = window.__game.ui.career; return c ? { week: c.d.week, am: c.f.am, money: c.d.money, story: c.d.pendingStory, seen: Object.keys(c.d.seenStory) } : null; });
console.log(JSON.stringify(state));
console.log(errors.join('\n') || 'no errors');
await browser.close();
