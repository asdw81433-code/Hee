// ===== Low-poly 3D hairstyles and beards for the blocky head =====
// Head local frame: origin at the bottom-center of the head box, +Y up, +Z = face, +X = character's left.
// Each builder returns [geometry, which] pairs; "hang" parts attach to a pivot at the back of the head
// and swing with a spring (secondary motion), so ponytails / dreads / long hair don't move like rigid helmets.
import * as THREE from 'three';

function box(w, h, d, y0 = 0, z0 = 0, x0 = 0) {
  const g = new THREE.BoxGeometry(w, h, d);
  g.translate(x0, y0 + h / 2, z0);
  return g;
}
function rot(g, rx = 0, ry = 0, rz = 0) { g.rotateX(rx); g.rotateY(ry); g.rotateZ(rz); return g; }

export const HAIR_DEFS = [
  ['bald', 'หัวโล้น'], ['buzz', 'เกรียน'], ['short', 'สั้นรองทรง'], ['fade', 'อันเดอร์คัต'], ['slick', 'หวีเสย'], ['spiky', 'ตั้งชี้'],
  ['mohawk', 'โมฮอว์ก'], ['afro', 'แอฟโฟร'], ['bun', 'มัดจุก'], ['ponytail', 'หางม้า'], ['long', 'ยาวประบ่า'], ['dreads', 'เดรดล็อก'], ['cornrows', 'เปียข้าวโพด'],
];
export const BEARD_DEFS = [
  ['none', 'ไม่มี'], ['stubble', 'เครา 3 วัน'], ['mustache', 'หนวด'], ['goatee', 'เคราแพะ'], ['chinstrap', 'เคราแนวกราม'], ['full', 'เต็มหน้า'], ['long', 'เครายาว'],
];

// returns { fixed: [geo...], hang: [geo...], hangPivot: Vector3, coversTop: bool, coversBack: bool }
export function buildHair(style, hw, hh, hd, sc) {
  const fixed = [], hang = [];
  const top = (th, ext = 1.06, y = hh - 0.01) => fixed.push(box(hw * ext, th, hd * ext, y));
  const back = (h, th = 0.03 * sc, ext = 1.04) => fixed.push(box(hw * ext, h, th, hh - h + 0.01, -hd / 2 - th / 2 + 0.006));
  const sides = (h, th = 0.02 * sc) => { for (const sx of [1, -1]) fixed.push(box(th, h, hd * 0.75, hh - h + 0.01, -hd * 0.12, sx * (hw / 2 + th / 2 - 0.004))); };
  let pivot = new THREE.Vector3(0, hh * 0.75, -hd / 2 - 0.02);
  switch (style) {
    case 'buzz': top(0.014 * sc, 1.03, hh - 0.004); back(hh * 0.55, 0.01 * sc, 1.02); sides(hh * 0.4, 0.008 * sc); break;
    case 'short': top(0.045 * sc); back(hh * 0.55); sides(hh * 0.35); break;
    case 'fade': {
      fixed.push(box(hw * 0.78, 0.06 * sc, hd * 0.95, hh - 0.012)); // long on top
      fixed.push(rot(box(hw * 0.7, 0.035 * sc, 0.07 * sc, -0.0175 * sc, 0), -0.5, 0, 0).translate(0, hh + 0.04 * sc, hd / 2 - 0.05 * sc)); // front quiff (above, not over the face)
      top(0.01 * sc, 1.02, hh - 0.004); back(hh * 0.4, 0.008 * sc, 1.02);
      break;
    }
    case 'slick': {
      fixed.push(rot(box(hw * 1.04, 0.045 * sc, hd * 1.02, 0, 0), 0.12, 0, 0).translate(0, hh - 0.015, -0.005));
      back(hh * 0.65, 0.035 * sc); sides(hh * 0.4);
      break;
    }
    case 'spiky': {
      top(0.03 * sc, 1.04);
      for (let i = 0; i < 9; i++) {
        const cx = ((i % 3) - 1) * hw * 0.32, cz = (Math.floor(i / 3) - 1) * hd * 0.32;
        const g = new THREE.ConeGeometry(0.03 * sc, 0.07 * sc, 4);
        g.rotateZ(-cx * 4).rotateX(cz * 4 + 0.2); g.translate(cx, hh + 0.045 * sc, cz);
        fixed.push(g);
      }
      back(hh * 0.5);
      break;
    }
    case 'mohawk': fixed.push(box(0.045 * sc, 0.09 * sc, hd * 1.05, hh - 0.01)); fixed.push(box(0.045 * sc, hh * 0.65, 0.05 * sc, hh * 0.32, -hd / 2 - 0.02)); break;
    case 'afro': {
      const g = new THREE.IcosahedronGeometry(1, 0);
      g.scale(hw * 0.8, 0.13 * sc, hd * 0.6); g.translate(0, hh + 0.02 * sc, -0.04 * sc);
      fixed.push(g);
      back(hh * 0.7, 0.05 * sc, 1.12);
      sides(hh * 0.55, 0.04 * sc);
      break;
    }
    case 'bun': top(0.035 * sc); back(hh * 0.5); fixed.push(box(0.075 * sc, 0.07 * sc, 0.075 * sc, hh - 0.005, -hd * 0.18)); break;
    case 'ponytail':
      fixed.push(rot(box(hw * 1.05, 0.04 * sc, hd * 1.04, 0, 0), 0.1, 0, 0).translate(0, hh - 0.012, 0));
      back(hh * 0.6); sides(hh * 0.35);
      fixed.push(box(0.05 * sc, 0.04 * sc, 0.04 * sc, hh * 0.68, -hd / 2 - 0.03));
      hang.push(rot(box(0.045 * sc, 0.2 * sc, 0.04 * sc, -0.2 * sc, 0), 0.25, 0, 0));
      pivot = new THREE.Vector3(0, hh * 0.72, -hd / 2 - 0.035);
      break;
    case 'long':
      top(0.05 * sc, 1.08); back(hh, 0.035 * sc, 1.08); sides(hh * 0.85, 0.03 * sc);
      hang.push(box(hw * 1.0, 0.13 * sc, 0.035 * sc, -0.13 * sc, 0));
      for (const sx of [1, -1]) hang.push(box(0.03 * sc, 0.1 * sc, hd * 0.4, -0.1 * sc, hd * 0.2, sx * (hw * 0.5 + 0.018 * sc)));
      pivot = new THREE.Vector3(0, 0.01, -hd / 2 - 0.02);
      break;
    case 'dreads':
      top(0.04 * sc, 1.08); back(hh * 0.8, 0.03 * sc, 1.06);
      for (let i = 0; i < 9; i++) {
        const a = (i / 8) * Math.PI - Math.PI / 2; // around the back
        const x = Math.sin(a) * hw * 0.55, z = -Math.cos(a) * hd * 0.15 - 0.01;
        hang.push(box(0.022 * sc, (0.16 + (i % 3) * 0.03) * sc, 0.022 * sc, -(0.16 + (i % 3) * 0.03) * sc, z, x));
      }
      pivot = new THREE.Vector3(0, hh * 0.45, -hd / 2 - 0.015);
      break;
    case 'cornrows':
      for (let i = -2; i <= 2; i++) fixed.push(box(0.022 * sc, 0.025 * sc, hd * 1.04, hh - 0.012, 0, i * 0.035 * sc));
      back(hh * 0.45, 0.015 * sc);
      break;
    default: break; // bald
  }
  return { fixed, hang, pivot };
}

export function buildBeard(beard, hw, hh, hd, sc) {
  const out = [];
  const zf = hd / 2; // face plane
  const mustache = () => out.push(box(0.085 * sc, 0.016 * sc, 0.014 * sc, hh * 0.255, zf + 0.004));
  const chin = (h = 0.055) => { out.push(box(0.075 * sc, h * sc, 0.02 * sc, -0.012 * sc, zf + 0.004)); out.push(box(hw * 0.62, 0.02 * sc, hd * 0.5, -0.016 * sc, zf * 0.45)); };
  const jaw = (h, th = 0.016) => { for (const sx of [1, -1]) out.push(box(th * sc, h, hd * 0.62, -0.01 * sc, zf * 0.28, sx * hw * 0.42)); };
  switch (beard) {
    case 'mustache': mustache(); break;
    case 'goatee': mustache(); chin(0.06); break;
    case 'chinstrap': jaw(hh * 0.42, 0.012); chin(0.03); break;
    case 'full': mustache(); chin(0.07); jaw(hh * 0.5); for (const sx of [1, -1]) out.push(box(0.035 * sc, hh * 0.22, 0.016 * sc, 0, zf + 0.002, sx * hw * 0.3)); break;
    case 'long': mustache(); chin(0.07); jaw(hh * 0.5); for (const sx of [1, -1]) out.push(box(0.035 * sc, hh * 0.22, 0.016 * sc, 0, zf + 0.002, sx * hw * 0.3));
      out.push(box(0.085 * sc, 0.11 * sc, 0.035 * sc, -0.115 * sc, zf - 0.01)); break;
    default: break; // none / stubble (texture only)
  }
  return out;
}

// 2D thumbnail of a style for the creator (front view of the blocky head)
export function drawHeadThumb(ctx, size, look, hairStyle, beard) {
  const W = size, H = size;
  ctx.clearRect(0, 0, W, H);
  ctx.fillStyle = '#20222b'; ctx.fillRect(0, 0, W, H);
  const hw = W * 0.44, hh = H * 0.52, x0 = (W - hw) / 2, y0 = H * 0.3;
  const hair = look.hairColor || '#1a1410', skin = look.skin || '#c68b62';
  const fill = (c, x, y, w, h) => { ctx.fillStyle = c; ctx.fillRect(Math.round(x), Math.round(y), Math.round(w), Math.round(h)); };
  // back hair behind the head
  if (hairStyle === 'long') fill(hair, x0 - hw * 0.08, y0 - H * 0.04, hw * 1.16, hh * 1.25);
  if (hairStyle === 'dreads') for (let i = 0; i < 7; i++) fill(hair, x0 - hw * 0.08 + i * hw * 0.19, y0 + hh * 0.2, hw * 0.08, hh * (0.95 + (i % 3) * 0.1));
  if (hairStyle === 'ponytail') fill(hair, x0 + hw * 0.85, y0 + hh * 0.2, hw * 0.16, hh * 0.9);
  if (hairStyle === 'afro') { ctx.fillStyle = hair; ctx.beginPath(); ctx.ellipse(W / 2, y0 + hh * 0.1, hw * 0.85, hh * 0.55, 0, 0, Math.PI * 2); ctx.fill(); }
  // head + ears + neck
  fill(skin, W / 2 - hw * 0.25, y0 + hh, hw * 0.5, H * 0.2);
  fill(skin, x0 - hw * 0.07, y0 + hh * 0.38, hw * 0.08, hh * 0.25); fill(skin, x0 + hw * 0.99, y0 + hh * 0.38, hw * 0.08, hh * 0.25);
  ctx.fillStyle = skin; ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x0 + hw, y0); ctx.lineTo(x0 + hw * 0.93, y0 + hh); ctx.lineTo(x0 + hw * 0.07, y0 + hh); ctx.closePath(); ctx.fill();
  // face
  fill('#222', x0 + hw * 0.2, y0 + hh * 0.42, hw * 0.16, hh * 0.05); fill('#222', x0 + hw * 0.64, y0 + hh * 0.42, hw * 0.16, hh * 0.05);
  fill('rgba(0,0,0,0.25)', x0 + hw * 0.45, y0 + hh * 0.5, hw * 0.1, hh * 0.16);
  fill('#8a4a4a', x0 + hw * 0.34, y0 + hh * 0.77, hw * 0.32, hh * 0.05);
  // beard
  const bc = look.beardColor || hair;
  if (beard === 'stubble') { ctx.fillStyle = bc; ctx.globalAlpha = 0.35; ctx.fillRect(x0 + hw * 0.08, y0 + hh * 0.62, hw * 0.84, hh * 0.38); ctx.globalAlpha = 1; fill(skin, x0 + hw * 0.34, y0 + hh * 0.77, hw * 0.32, hh * 0.05); fill('#8a4a4a', x0 + hw * 0.34, y0 + hh * 0.77, hw * 0.32, hh * 0.05); }
  if (['mustache', 'goatee', 'full', 'long'].includes(beard)) fill(bc, x0 + hw * 0.3, y0 + hh * 0.7, hw * 0.4, hh * 0.06);
  if (['goatee', 'full', 'long'].includes(beard)) fill(bc, x0 + hw * 0.32, y0 + hh * 0.85, hw * 0.36, hh * 0.17);
  if (['chinstrap', 'full', 'long'].includes(beard)) { fill(bc, x0 + hw * 0.05, y0 + hh * 0.55, hw * 0.1, hh * 0.45); fill(bc, x0 + hw * 0.85, y0 + hh * 0.55, hw * 0.1, hh * 0.45); fill(bc, x0 + hw * 0.1, y0 + hh * 0.92, hw * 0.8, hh * 0.1); }
  if (beard === 'full' || beard === 'long') { fill(bc, x0 + hw * 0.12, y0 + hh * 0.72, hw * 0.18, hh * 0.25); fill(bc, x0 + hw * 0.7, y0 + hh * 0.72, hw * 0.18, hh * 0.25); }
  if (beard === 'long') fill(bc, x0 + hw * 0.3, y0 + hh, hw * 0.4, hh * 0.32);
  // hair on top
  const topH = { buzz: 0.04, short: 0.1, fade: 0.14, slick: 0.1, spiky: 0.08, bun: 0.08, ponytail: 0.09, long: 0.1, dreads: 0.09, cornrows: 0.05 }[hairStyle];
  if (topH) fill(hair, x0 - hw * 0.03, y0 - hh * topH, hw * 1.06, hh * (topH + 0.08));
  if (hairStyle === 'short' || hairStyle === 'slick') { fill(hair, x0 - hw * 0.03, y0, hw * 0.08, hh * 0.3); fill(hair, x0 + hw * 0.95, y0, hw * 0.08, hh * 0.3); }
  if (hairStyle === 'fade') { fill(skin, x0 - hw * 0.03, y0 - hh * 0.14, hw * 0.12, hh * 0.14); fill(skin, x0 + hw * 0.91, y0 - hh * 0.14, hw * 0.12, hh * 0.14); fill(hair, x0 + hw * 0.1, y0 - hh * 0.24, hw * 0.8, hh * 0.12); }
  if (hairStyle === 'spiky') for (let i = 0; i < 5; i++) { ctx.fillStyle = hair; ctx.beginPath(); const sx = x0 + hw * (0.05 + i * 0.2); ctx.moveTo(sx, y0 - hh * 0.06); ctx.lineTo(sx + hw * 0.1, y0 - hh * 0.3); ctx.lineTo(sx + hw * 0.2, y0 - hh * 0.06); ctx.fill(); }
  if (hairStyle === 'mohawk') fill(hair, W / 2 - hw * 0.1, y0 - hh * 0.22, hw * 0.2, hh * 0.3);
  if (hairStyle === 'bun') fill(hair, W / 2 - hw * 0.14, y0 - hh * 0.3, hw * 0.28, hh * 0.22);
  if (hairStyle === 'cornrows') for (let i = 0; i < 5; i++) fill('rgba(0,0,0,0.35)', x0 + hw * (0.1 + i * 0.18), y0 - hh * 0.05, hw * 0.03, hh * 0.13);
  if (hairStyle === 'long') { fill(hair, x0 - hw * 0.06, y0, hw * 0.1, hh * 0.9); fill(hair, x0 + hw * 0.96, y0, hw * 0.1, hh * 0.9); }
}
