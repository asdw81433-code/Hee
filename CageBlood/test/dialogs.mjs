// in-page dialogs: new career over existing save, retire, forfeit
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PW_PATH || 'playwright');
import path from 'node:path';
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 760 } });
const errors = [];
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
page.on('dialog', (d) => { errors.push('native dialog used: ' + d.message()); d.dismiss(); });
await page.goto('file://' + path.resolve('index.html'));
await page.waitForTimeout(1500);
// make a career quickly via API
await page.evaluate(() => { const u = window.__game.ui; u.newCareer(); });
await page.waitForTimeout(800);
await page.locator('.tab', { hasText: '4.' }).click(); await page.locator('button', { hasText: 'ยืนยันนักสู้' }).click(); await page.waitForTimeout(800);
await page.evaluate(() => { const u = window.__game.ui; u.career.d.pendingStory = []; u.go('title'); });
await page.waitForTimeout(300);
await page.locator('button', { hasText: 'เริ่มอาชีพใหม่' }).click(); await page.waitForTimeout(300);
const modal = await page.locator('.modal').count();
await page.screenshot({ path: 'test/out/dialog_modal.png' });
await page.locator('.modal button', { hasText: 'ยกเลิก' }).click(); await page.waitForTimeout(300);
console.log('modal shown', modal, 'after cancel', await page.locator('.modal').count());
await page.locator('button', { hasText: 'ตั้งค่า' }).click(); await page.waitForTimeout(300);
await page.locator('button', { hasText: 'นำเข้าเซฟ' }).click(); await page.waitForTimeout(300);
console.log('import box', await page.locator('.modal textarea').count());
console.log(errors.join('\n') || 'no errors');
await browser.close();
