// สร้างไฟล์ AlleyBrawl.rbxlx จากโค้ดใน src/
//   cd tools && npm install && npm run place
// แมพ แสง และโมเดลผู้เล่น ถูกสร้างด้วยโค้ดเกมจริง (รันใน mock) แล้วบันทึกเป็นชิ้นงานจริงในไฟล์
import fs from 'fs';
import path from 'path';
import { createRequire } from 'module';
import { fileURLToPath } from 'url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);

// ---- รันโค้ดสร้างแมพ/ตัวละครใน Lua VM แล้วดึง XML ออกมา ----
function exportWorld() {
  const { lua, lauxlib, lualib, to_luastring } = require('fengari');
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const longString = (s) => { let eq = ''; while (s.includes(']' + eq + ']')) eq += '='; return '[' + eq + '[\n' + s + ']' + eq + ']'; };
  let sources = 'SOURCES = {}\n';
  for (const dir of ['shared', 'server', 'client']) for (const f of fs.readdirSync(path.join(ROOT, 'src', dir))) {
    sources += `SOURCES[${JSON.stringify(dir + '/' + f)}] = ${longString(fs.readFileSync(path.join(ROOT, 'src', dir, f), 'utf8'))}\n`;
  }
  const run = (code, name) => {
    if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
      throw new Error(name + ': ' + lua.lua_tojsstring(L, -1));
    }
  };
  run(sources, 'sources');
  run(fs.readFileSync(path.join(ROOT, 'tools/test/mock.lua'), 'utf8'), '@mock.lua');
  run(fs.readFileSync(path.join(ROOT, 'tools/export.lua'), 'utf8'), '@export.lua');
  const get = (n) => { lua.lua_getglobal(L, to_luastring(n)); const v = lua.lua_tojsstring(L, -1); lua.lua_pop(L, 1); return v; };
  return { map: get('XML_MAP'), template: get('XML_TEMPLATE'), lightProps: get('XML_LIGHTING_PROPS'), lightKids: get('XML_LIGHTING_KIDS'), stats: get('EXPORT_STATS') };
}
const world = exportWorld();
console.log('exported:', world.stats);
const src = (p) => fs.readFileSync(path.join(ROOT, 'src', p), 'utf8');
const MODULES = (dir, names) => names.map((n) => ({ cls: 'ModuleScript', name: n, source: src(`${dir}/${n}.lua`) }));

const TREE = [
  { cls: 'ReplicatedStorage', name: 'ReplicatedStorage', children: MODULES('shared', ['BrawlConfig', 'BrawlAnim']) },
  {
    cls: 'ServerScriptService', name: 'ServerScriptService', children: [
      { cls: 'Script', name: 'BrawlServer', source: src('server/init.server.lua'), children: MODULES('server', ['MapBuilder', 'CharacterBuilder', 'Ragdoll', 'Combat', 'Weapons', 'Bots']) },
    ],
  },
  {
    cls: 'StarterPlayer', name: 'StarterPlayer', children: [
      {
        cls: 'StarterPlayerScripts', name: 'StarterPlayerScripts', children: [
          { cls: 'LocalScript', name: 'BrawlClient', source: src('client/init.client.lua'), children: MODULES('client', ['Animator', 'Effects', 'Hud', 'Controls']) },
        ],
      },
    ],
  },
];

let ref = 0;
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const cdata = (s) => '<![CDATA[' + s.replace(/]]>/g, ']]]]><![CDATA[>') + ']]>';
function item(node, ind) {
  const pad = '\t'.repeat(ind);
  let out = `${pad}<Item class="${node.cls}" referent="RBX${(ref++).toString(16).toUpperCase().padStart(8, '0')}">\n`;
  out += `${pad}\t<Properties>\n${pad}\t\t<string name="Name">${esc(node.name)}</string>\n`;
  if (node.source !== undefined) out += `${pad}\t\t<ProtectedString name="Source">${cdata(node.source)}</ProtectedString>\n`;
  if (node.cls === 'Script' || node.cls === 'LocalScript') out += `${pad}\t\t<bool name="Disabled">false</bool>\n`;
  out += `${pad}\t</Properties>\n`;
  for (const c of node.children || []) out += item(c, ind + 1);
  out += `${pad}</Item>\n`;
  return out;
}
let xml = '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n';
xml += '\t<Meta name="ExplicitAutoJoints">true</Meta>\n';
// Workspace: แมพจริง (ชิ้นงานทุกชิ้นแก้ไขใน Studio ได้)
xml += '\t<Item class="Workspace" referent="RBXWORKSPACE">\n\t\t<Properties>\n\t\t\t<string name="Name">Workspace</string>\n\t\t\t<bool name="StreamingEnabled">false</bool>\n\t\t</Properties>\n';
xml += world.map + '\n\t</Item>\n';
// Lighting: แสงยามเย็น
xml += '\t<Item class="Lighting" referent="RBXLIGHTING">\n\t\t<Properties>\n\t\t\t<string name="Name">Lighting</string>\n' + world.lightProps + '\n\t\t</Properties>\n';
xml += world.lightKids + '\n\t</Item>\n';
// ServerStorage: โมเดลผู้เล่น Brawler (แก้หน้าตา/ขนาดใน Studio ได้ เกมจะใช้ตัวนี้)
xml += '\t<Item class="ServerStorage" referent="RBXSERVERSTORAGE">\n\t\t<Properties>\n\t\t\t<string name="Name">ServerStorage</string>\n\t\t</Properties>\n';
xml += world.template + '\n\t</Item>\n';
for (const n of TREE) xml += item(n, 1);
xml += '</roblox>\n';
const out = path.join(ROOT, 'AlleyBrawl.rbxlx');
fs.writeFileSync(out, xml);
console.log('wrote', out, (xml.length / 1024).toFixed(1) + ' KB');
