// สร้างไฟล์ SoiBrawl.rbxlx จากโค้ดใน src/ (ไม่ต้องติดตั้งอะไรเพิ่ม แค่มี Node.js)
//   node tools/build-place.mjs
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
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
for (const n of TREE) xml += item(n, 1);
xml += '</roblox>\n';
const out = path.join(ROOT, 'SoiBrawl.rbxlx');
fs.writeFileSync(out, xml);
console.log('wrote', out, (xml.length / 1024).toFixed(1) + ' KB,', ref, 'instances');
