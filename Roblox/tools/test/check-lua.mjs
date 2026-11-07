// Static check for Luau sources: syntax (Lua 5.1 subset via luaparse) + unknown globals + misc lint
import { createRequire } from 'module';
import fs from 'fs';
import path from 'path';
const require = createRequire(import.meta.url);
const luaparse = require('luaparse');

const GLOBALS = new Set(`game workspace script Instance Vector3 Vector2 CFrame Color3 BrickColor Enum UDim UDim2 math string table task typeof type pairs ipairs next print warn error pcall xpcall tostring tonumber select unpack require setmetatable getmetatable rawget rawset rawequal os tick time NumberSequence NumberSequenceKeypoint ColorSequence ColorSequenceKeypoint NumberRange TweenInfo Ray RaycastParams Random Rect PhysicalProperties Font Region3 utf8 coroutine bit32 debug buffer assert newproxy OverlapParams DateTime shared`.split(/\s+/));

const files = process.argv.slice(2);
let problems = 0;
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  // Luau-only syntax we promised not to use
  const lines = src.split('\n');
  lines.forEach((l, i) => {
    const code = l.replace(/--.*$/, '');
    if (/[+\-*/%^]=|\.\.=/.test(code.replace(/"[^"]*"/g, '').replace(/[<>=~]=/g, ''))) { console.log(`${f}:${i + 1}: compound assignment? ${l.trim()}`); problems++; }
    if (/\bcontinue\b/.test(code)) { console.log(`${f}:${i + 1}: continue`); problems++; }
    if (/`/.test(code)) { console.log(`${f}:${i + 1}: backtick string`); problems++; }
  });
  let ast;
  try {
    ast = luaparse.parse(src, { luaVersion: '5.1', scope: true, locations: true, comments: false });
  } catch (e) {
    console.log(`${f}: SYNTAX ${e.message}`); problems++; continue;
  }
  const seen = new Set();
  const walk = (n, parent, key) => {
    if (!n || typeof n !== 'object') return;
    if (Array.isArray(n)) { n.forEach((c) => walk(c, parent, key)); return; }
    if (n.type === 'Identifier' && n.isLocal === false) {
      // skip member keys: a.b (identifier as MemberExpression.identifier) and table keys
      const isMember = parent && parent.type === 'MemberExpression' && key === 'identifier';
      const isTableKey = parent && parent.type === 'TableKeyString' && key === 'key';
      if (!isMember && !isTableKey && !GLOBALS.has(n.name)) {
        const k = n.name + ':' + n.loc.start.line;
        if (!seen.has(k)) { seen.add(k); console.log(`${f}:${n.loc.start.line}: unknown global '${n.name}'`); problems++; }
      }
    }
    for (const [k, v] of Object.entries(n)) {
      if (k === 'loc' || k === 'range') continue;
      if (v && typeof v === 'object') walk(v, n, k);
    }
  };
  walk(ast.body, ast, 'body');
  // unused locals (rough): declared local names never referenced again
  const declared = new Map();
  const used = new Map();
  const walk2 = (n, parent, key) => {
    if (!n || typeof n !== 'object') return;
    if (Array.isArray(n)) { n.forEach((c) => walk2(c, parent, key)); return; }
    if (n.type === 'LocalStatement') n.variables.forEach((v) => declared.set(v.name + '@' + v.loc.start.line, v.name));
    if (n.type === 'Identifier' && n.isLocal) {
      const isDecl = parent && parent.type === 'LocalStatement' && key === 'variables';
      if (!isDecl) used.set(n.name, (used.get(n.name) || 0) + 1);
    }
    for (const [k, v] of Object.entries(n)) {
      if (k === 'loc' || k === 'range') continue;
      if (v && typeof v === 'object') walk2(v, n, k);
    }
  };
  walk2(ast.body, ast, 'body');
  for (const [k, name] of declared) if (!used.get(name) && name !== '_') console.log(`${path.basename(f)}: unused local '${name}' (${k})`);
}
console.log(problems ? `${problems} problem(s)` : 'OK: no syntax/global problems');
process.exit(problems ? 1 : 0);
