// usage: node test/shot.mjs "<query>" waitMs outName [evalJS]
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PW_PATH || 'playwright');
import path from 'node:path';
const [,, query = 'test=1', wait = '3000', out = 'shot', js = ''] = process.argv;
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const errors = [];
page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') errors.push(m.type() + ': ' + m.text()); else if (m.text().startsWith('END') || m.text().startsWith('LOG')) console.log(m.text()); });
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message + '\n' + e.stack));
const url = 'file://' + path.resolve('index.html') + '?' + query;
await page.goto(url);
const steps = wait.split(',').map(Number);
let i = 0;
for (const w of steps) {
  await page.waitForTimeout(w);
  if (js) { try { const r = await page.evaluate(js); if (r !== undefined) console.log('eval:', JSON.stringify(r)); } catch (e) { errors.push('eval: ' + e.message); } }
  await page.screenshot({ path: `test/out/${out}${steps.length > 1 ? '_' + i : ''}.png` });
  i++;
}
console.log(errors.slice(0, 15).join('\n') || 'no errors');
await browser.close();
