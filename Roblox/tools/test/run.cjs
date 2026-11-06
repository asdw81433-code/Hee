// Run a Lua test script against the Roblox mock inside fengari
const fs = require('fs');
const path = require('path');
const fengari = require('fengari');
const { lua, lauxlib, lualib, to_luastring } = fengari;
const SRC = path.resolve(__dirname, '../../src');
function longString(s) { let eq = ''; while (s.includes(']' + eq + ']')) eq += '='; return '[' + eq + '[\n' + s + ']' + eq + ']'; }
let srcTable = 'SOURCES = {}\n';
for (const dir of ['shared', 'server', 'client']) for (const f of fs.readdirSync(path.join(SRC, dir))) {
  srcTable += `SOURCES[${JSON.stringify(dir + '/' + f)}] = ${longString(fs.readFileSync(path.join(SRC, dir, f), 'utf8'))}\n`;
}
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(code, name) {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name)) !== lua.LUA_OK) { console.log('LOAD ERROR', name, lua.lua_tojsstring(L, -1)); process.exit(2); }
  lua.lua_getglobal(L, to_luastring('debug')); lua.lua_getfield(L, -1, to_luastring('traceback')); lua.lua_remove(L, -2);
  lua.lua_insert(L, -2);
  if (lua.lua_pcall(L, 0, 0, -2) !== lua.LUA_OK) { console.log('RUN ERROR', name, lua.lua_tojsstring(L, -1)); process.exit(3); }
  lua.lua_pop(L, 1);
}
const t0 = Date.now();
run(srcTable, 'sources');
run(fs.readFileSync(path.join(__dirname, 'mock.lua'), 'utf8'), '@mock.lua');
for (const extra of process.argv.slice(3)) run(extra, 'arg');
run(fs.readFileSync(path.join(__dirname, process.argv[2]), 'utf8'), '@' + process.argv[2]);
console.log('elapsed', ((Date.now() - t0) / 1000).toFixed(1) + 's');
