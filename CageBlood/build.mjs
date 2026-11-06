// Build: bundle src/ into one standalone index.html (works offline, file://, GitHub Pages, any static host)
import * as esbuild from 'esbuild';
import fs from 'node:fs';

const dev = process.argv.includes('--dev');
const result = await esbuild.build({
  entryPoints: ['src/main.js'],
  bundle: true,
  format: 'iife',
  minify: !dev,
  sourcemap: false,
  target: ['es2020'],
  write: false,
  legalComments: 'none',
});
const js = result.outputFiles[0].text.replace(/<\/script/gi, '<\\/script');
const tpl = fs.readFileSync('src/index.template.html', 'utf8');
const css = fs.readFileSync('src/style.css', 'utf8');
const html = tpl.replace('/*__CSS__*/', () => css).replace('/*__JS__*/', () => js);
fs.writeFileSync('index.html', html);
console.log('built index.html', (html.length / 1024).toFixed(0) + ' KB');
