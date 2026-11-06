// ===== Face & skin canvases =====
// Each fighter has a painted face (player-drawn or procedurally painted) on the front of a blocky head.
// Damage is composited on top: bruises, swelling, cuts, and a live blood layer where blood flows
// along gravity projected on the face plane, pools, runs into eyes, and slowly oxidizes red -> brown.
import * as THREE from 'three';
import { makeRng, clamp, lerp } from './util.js';

export const FACE_W = 320, FACE_H = 400;
export const TORSO_W = 256, TORSO_H = 256;

// Normalized landmark positions on the face canvas (u right = character's LEFT side)
export const LM = {
  browR: [0.3, 0.37], browL: [0.7, 0.37],
  eyeR: [0.31, 0.45], eyeL: [0.69, 0.45],
  cheekR: [0.24, 0.6], cheekL: [0.76, 0.6],
  nose: [0.5, 0.61], mouth: [0.5, 0.775], chin: [0.5, 0.92], forehead: [0.5, 0.22],
};

function hexToRgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
export function shade(hex, f, a = 1) {
  const [r, g, b] = hexToRgb(hex);
  const m = (c) => clamp(Math.round(f >= 0 ? c + (255 - c) * f : c * (1 + f)), 0, 255);
  return `rgba(${m(r)},${m(g)},${m(b)},${a})`;
}
function tint(hex, rgb, t, a = 1) {
  const [r, g, b] = hexToRgb(hex);
  return `rgba(${Math.round(lerp(r, rgb[0], t))},${Math.round(lerp(g, rgb[1], t))},${Math.round(lerp(b, rgb[2], t))},${a})`;
}

export function mkCanvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  return c;
}

// ---------- Procedural realistic face painter ----------
export function paintFace(ctx, look, seed = 1) {
  const r = makeRng(seed);
  const W = FACE_W, H = FACE_H;
  const skin = look.skin;
  const eyeColor = look.eyeColor || r.pick(['#3b2414', '#4a3018', '#2e1e10', '#4f6b3a', '#3a5a7a', '#1d1410']);
  const browCol = look.hairColor === '#8c8c8c' ? '#5a5050' : shade(look.hairColor || '#1a1410', -0.1);
  const noseW = look.noseW ?? r.range(0.85, 1.25);
  const lipFull = look.lipFull ?? r.range(0.8, 1.3);
  const browThick = look.browThick ?? r.range(0.8, 1.4);
  const eyeSize = look.eyeSize ?? r.range(0.85, 1.1);
  const jaw = look.jaw ?? r.range(0.9, 1.15);
  ctx.save();
  ctx.clearRect(0, 0, W, H);
  // base skin
  ctx.fillStyle = skin; ctx.fillRect(0, 0, W, H);
  // global light: top-front key light, darker sides & under jaw
  let g = ctx.createRadialGradient(W * 0.5, H * 0.38, W * 0.1, W * 0.5, H * 0.45, W * 0.75);
  g.addColorStop(0, shade(skin, 0.1, 0.55)); g.addColorStop(0.55, shade(skin, 0, 0)); g.addColorStop(1, shade(skin, -0.35, 0.75));
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  // jaw shading (face shape illusion on box head)
  ctx.fillStyle = shade(skin, -0.32, 0.5);
  ctx.beginPath();
  ctx.moveTo(0, H * 0.55); ctx.quadraticCurveTo(W * 0.1 / jaw, H * 0.93, W * 0.5, H * 1.0);
  ctx.quadraticCurveTo(W * (1 - 0.1 / jaw), H * 0.93, W, H * 0.55); ctx.lineTo(W, H); ctx.lineTo(0, H); ctx.closePath(); ctx.fill();
  // cheekbone highlight
  for (const [u, v] of [LM.cheekR, LM.cheekL]) {
    g = ctx.createRadialGradient(u * W, (v - 0.04) * H, 2, u * W, (v - 0.04) * H, W * 0.15);
    g.addColorStop(0, shade(skin, 0.12, 0.45)); g.addColorStop(1, shade(skin, 0.12, 0));
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
    g = ctx.createRadialGradient(u * W, (v + 0.08) * H, 2, u * W, (v + 0.08) * H, W * 0.14);
    g.addColorStop(0, shade(skin, -0.2, 0.35)); g.addColorStop(1, shade(skin, -0.2, 0));
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  }
  // eye sockets (shadow under brow ridge)
  for (const [u, v] of [LM.eyeR, LM.eyeL]) {
    g = ctx.createRadialGradient(u * W, (v - 0.01) * H, 3, u * W, (v - 0.01) * H, W * 0.13);
    g.addColorStop(0, shade(skin, -0.28, 0.55)); g.addColorStop(1, shade(skin, -0.28, 0));
    ctx.fillStyle = g; ctx.beginPath(); ctx.ellipse(u * W, v * H, W * 0.14, H * 0.08, 0, 0, Math.PI * 2); ctx.fill();
  }
  // brow ridge highlight
  ctx.fillStyle = shade(skin, 0.1, 0.35);
  ctx.beginPath(); ctx.ellipse(W * 0.5, H * 0.33, W * 0.36, H * 0.035, 0, 0, Math.PI * 2); ctx.fill();
  // eyes
  for (const [side, [u, v]] of [[-1, LM.eyeR], [1, LM.eyeL]]) {
    const cx = u * W, cy = v * H, ew = W * 0.075 * eyeSize, eh = H * 0.022 * eyeSize;
    // sclera (almond)
    ctx.fillStyle = '#e9e2d6';
    ctx.beginPath();
    ctx.moveTo(cx - ew, cy);
    ctx.quadraticCurveTo(cx, cy - eh * 2.0, cx + ew, cy);
    ctx.quadraticCurveTo(cx, cy + eh * 1.5, cx - ew, cy);
    ctx.fill();
    ctx.save(); ctx.clip();
    // iris
    const ir = eh * 1.25;
    g = ctx.createRadialGradient(cx, cy - eh * 0.1, ir * 0.2, cx, cy - eh * 0.1, ir);
    g.addColorStop(0, shade(eyeColor, 0.25)); g.addColorStop(0.8, eyeColor); g.addColorStop(1, shade(eyeColor, -0.5));
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(cx, cy - eh * 0.1, ir, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#080605'; ctx.beginPath(); ctx.arc(cx, cy - eh * 0.1, ir * 0.42, 0, Math.PI * 2); ctx.fill();
    // upper lid shadow on eyeball
    ctx.fillStyle = 'rgba(40,20,10,0.35)'; ctx.fillRect(cx - ew, cy - eh * 2, ew * 2, eh * 1.1);
    ctx.restore();
    // catchlight
    ctx.fillStyle = 'rgba(255,255,255,0.9)'; ctx.beginPath(); ctx.arc(cx + side * ir * 0.3, cy - eh * 0.5, ir * 0.18, 0, Math.PI * 2); ctx.fill();
    // upper eyelid line + lashes
    ctx.strokeStyle = shade(skin, -0.75, 0.95); ctx.lineWidth = 2.6;
    ctx.beginPath(); ctx.moveTo(cx - ew * 1.05, cy + 1); ctx.quadraticCurveTo(cx, cy - eh * 2.1, cx + ew * 1.05, cy - 1); ctx.stroke();
    // lid crease
    ctx.strokeStyle = shade(skin, -0.4, 0.5); ctx.lineWidth = 1.4;
    ctx.beginPath(); ctx.moveTo(cx - ew * 0.9, cy - eh * 1.1); ctx.quadraticCurveTo(cx, cy - eh * 3.0, cx + ew * 0.95, cy - eh * 1.2); ctx.stroke();
    // lower lid
    ctx.strokeStyle = shade(skin, -0.35, 0.5); ctx.lineWidth = 1.2;
    ctx.beginPath(); ctx.moveTo(cx - ew * 0.9, cy + eh * 0.3); ctx.quadraticCurveTo(cx, cy + eh * 1.7, cx + ew, cy); ctx.stroke();
    // under-eye bag
    ctx.strokeStyle = shade(skin, -0.25, 0.3); ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(cx - ew * 0.7, cy + eh * 2.2); ctx.quadraticCurveTo(cx, cy + eh * 3.2, cx + ew * 0.8, cy + eh * 2.0); ctx.stroke();
  }
  // eyebrows: many hair strokes
  for (const [side, [u, v]] of [[-1, LM.browR], [1, LM.browL]]) {
    const cx = u * W, cy = v * H, bw = W * 0.11;
    ctx.strokeStyle = browCol; ctx.lineCap = 'round';
    const n = Math.floor(70 * browThick);
    for (let i = 0; i < n; i++) {
      const t = r();
      // inner end (near nose) is thicker/lower; arch peaks ~65%
      const x = cx + side * (t - 0.45) * bw * 2;
      const arch = Math.sin(t * Math.PI * 0.95) * H * 0.018;
      const thick = (1 - t * 0.6) * H * 0.016 * browThick;
      const y = cy - arch + (r() - 0.5) * thick;
      const ang = side * (0.35 + t * 0.5) - Math.PI / 2 * 0;
      const len = 5 + r() * 5;
      ctx.globalAlpha = 0.25 + r() * 0.45; ctx.lineWidth = 1 + r() * 0.9;
      ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + Math.cos(ang) * len * side, y - Math.sin(Math.abs(ang)) * len * 0.35); ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }
  // nose
  const nx = LM.nose[0] * W, ny = LM.nose[1] * H, nw = W * 0.07 * noseW;
  // bridge highlight
  g = ctx.createLinearGradient(nx - nw, 0, nx + nw, 0);
  g.addColorStop(0, shade(skin, -0.25, 0.0)); g.addColorStop(0.35, shade(skin, -0.25, 0.4)); g.addColorStop(0.5, shade(skin, 0.18, 0.5)); g.addColorStop(0.65, shade(skin, -0.25, 0.4)); g.addColorStop(1, shade(skin, -0.25, 0));
  ctx.fillStyle = g; ctx.fillRect(nx - nw, H * 0.42, nw * 2, ny - H * 0.42 + 8);
  // tip highlight & ball
  g = ctx.createRadialGradient(nx, ny - 4, 1, nx, ny - 2, nw * 0.9);
  g.addColorStop(0, shade(skin, 0.2, 0.55)); g.addColorStop(1, shade(skin, 0.0, 0));
  ctx.fillStyle = g; ctx.beginPath(); ctx.arc(nx, ny - 2, nw * 0.9, 0, Math.PI * 2); ctx.fill();
  // alae shadows
  ctx.fillStyle = shade(skin, -0.35, 0.55);
  ctx.beginPath(); ctx.ellipse(nx - nw * 0.95, ny + 2, nw * 0.35, nw * 0.45, 0.3, 0, Math.PI * 2); ctx.fill();
  ctx.beginPath(); ctx.ellipse(nx + nw * 0.95, ny + 2, nw * 0.35, nw * 0.45, -0.3, 0, Math.PI * 2); ctx.fill();
  // nostrils
  ctx.fillStyle = shade(skin, -0.75, 0.85);
  ctx.beginPath(); ctx.ellipse(nx - nw * 0.42, ny + nw * 0.42, nw * 0.26, nw * 0.13, 0.25, 0, Math.PI * 2); ctx.fill();
  ctx.beginPath(); ctx.ellipse(nx + nw * 0.42, ny + nw * 0.42, nw * 0.26, nw * 0.13, -0.25, 0, Math.PI * 2); ctx.fill();
  // nose base shadow
  g = ctx.createLinearGradient(0, ny + nw * 0.4, 0, ny + nw * 1.3);
  g.addColorStop(0, shade(skin, -0.3, 0.45)); g.addColorStop(1, shade(skin, -0.3, 0));
  ctx.fillStyle = g; ctx.fillRect(nx - nw * 1.2, ny + nw * 0.4, nw * 2.4, nw);
  // philtrum
  ctx.fillStyle = shade(skin, -0.15, 0.35); ctx.fillRect(nx - 3, ny + nw * 0.7, 6, H * 0.05);
  // mouth
  const mx = LM.mouth[0] * W, my = LM.mouth[1] * H, mw = W * 0.13, lu = H * 0.017 * lipFull, ll = H * 0.024 * lipFull;
  const lipCol = look.lipColor || tint(skin, [150, 70, 70], 0.38);
  ctx.fillStyle = shade(lipCol.startsWith('#') ? lipCol : '#a05a5a', -0.12);
  ctx.fillStyle = lipCol;
  ctx.beginPath(); // upper lip with cupid's bow
  ctx.moveTo(mx - mw, my); ctx.quadraticCurveTo(mx - mw * 0.5, my - lu * 1.3, mx - mw * 0.12, my - lu * 1.1);
  ctx.lineTo(mx, my - lu * 0.75); ctx.lineTo(mx + mw * 0.12, my - lu * 1.1);
  ctx.quadraticCurveTo(mx + mw * 0.5, my - lu * 1.3, mx + mw, my); ctx.closePath(); ctx.fill();
  ctx.fillStyle = 'rgba(0,0,0,0.18)'; ctx.fill();
  ctx.fillStyle = lipCol;
  ctx.beginPath(); // lower lip
  ctx.moveTo(mx - mw * 0.95, my); ctx.quadraticCurveTo(mx, my + ll * 2.0, mx + mw * 0.95, my); ctx.closePath(); ctx.fill();
  g = ctx.createRadialGradient(mx, my + ll * 0.6, 1, mx, my + ll * 0.6, mw * 0.5);
  g.addColorStop(0, 'rgba(255,255,255,0.22)'); g.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = g; ctx.fill();
  ctx.strokeStyle = 'rgba(40,10,10,0.85)'; ctx.lineWidth = 1.8;
  ctx.beginPath(); ctx.moveTo(mx - mw, my); ctx.quadraticCurveTo(mx, my + 2, mx + mw, my); ctx.stroke();
  // under-lip shadow & chin
  g = ctx.createRadialGradient(mx, my + ll * 2.6, 1, mx, my + ll * 2.6, mw * 0.7);
  g.addColorStop(0, shade(skin, -0.25, 0.35)); g.addColorStop(1, shade(skin, 0, 0));
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  // nasolabial folds
  ctx.strokeStyle = shade(skin, -0.3, 0.35); ctx.lineWidth = 1.6;
  ctx.beginPath(); ctx.moveTo(nx - nw * 1.3, ny + 4); ctx.quadraticCurveTo(mx - mw * 1.25, my - 10, mx - mw * 1.2, my + 8); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(nx + nw * 1.3, ny + 4); ctx.quadraticCurveTo(mx + mw * 1.25, my - 10, mx + mw * 1.2, my + 8); ctx.stroke();
  // beard / stubble
  const beard = look.beard || 'none';
  if (beard !== 'none') {
    const hc = look.hairColor || '#1a1410';
    const dens = beard === 'stubble' ? 900 : beard === 'goatee' ? 500 : 2200;
    for (let i = 0; i < dens; i++) {
      let x = r() * W, y = H * 0.6 + r() * H * 0.4;
      // shape masks
      const dx = (x - W / 2) / W, dy = (y - H * 0.78) / H;
      if (beard === 'goatee' && Math.abs(dx) > 0.16) continue;
      if (Math.abs(x - mx) < mw * 0.95 && Math.abs(y - my) < ll * 1.6) continue; // lips
      if (y < ny + nw * 0.6 && Math.abs(dx) < 0.12) continue;
      if (beard !== 'goatee' && y < H * 0.62 + Math.abs(dx) * -0.2 * H && Math.abs(dx) < 0.3) continue;
      ctx.fillStyle = shade(hc, r() * 0.2, beard === 'stubble' ? 0.25 + r() * 0.25 : 0.4 + r() * 0.4);
      const s = beard === 'stubble' ? 1.2 : 1.8;
      ctx.fillRect(x, y, s, s * (1 + r()));
    }
  }
  // skin texture (pores / mottling)
  for (let i = 0; i < 1600; i++) {
    ctx.fillStyle = r() < 0.5 ? shade(skin, -0.2, 0.06 + r() * 0.06) : shade(skin, 0.15, 0.05 + r() * 0.05);
    const s = 1 + r() * 2;
    ctx.fillRect(r() * W, r() * H, s, s);
  }
  // scars
  if (look.scar) {
    ctx.strokeStyle = shade(skin, 0.25, 0.7); ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(W * 0.62, H * 0.33); ctx.lineTo(W * 0.74, H * 0.31); ctx.stroke();
  }
  // hairline
  const hs = look.hairStyle || 'short';
  if (hs !== 'bald') {
    const hc = look.hairColor || '#1a1410';
    const depth = hs === 'buzz' ? 0.09 : hs === 'mohawk' ? 0.06 : 0.12;
    ctx.fillStyle = hc;
    ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(W, 0); ctx.lineTo(W, H * (depth + 0.08));
    for (let x = W; x >= 0; x -= 6) {
      const u = x / W;
      const y = H * (depth + 0.04 * Math.pow(Math.abs(u - 0.5) * 2, 2) * 2) + (r() - 0.5) * 4 - (hs === 'mohawk' && Math.abs(u - 0.5) > 0.15 ? H * 0.2 : 0);
      ctx.lineTo(x, Math.max(0, y));
    }
    ctx.closePath();
    ctx.globalAlpha = hs === 'buzz' ? 0.6 : 0.95; ctx.fill(); ctx.globalAlpha = 1;
  }
  // temple shading at canvas edges (box head sides)
  g = ctx.createLinearGradient(0, 0, W, 0);
  g.addColorStop(0, 'rgba(0,0,0,0.22)'); g.addColorStop(0.12, 'rgba(0,0,0,0)'); g.addColorStop(0.88, 'rgba(0,0,0,0)'); g.addColorStop(1, 'rgba(0,0,0,0.22)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  ctx.restore();
}

// Face guide overlay for drawing
export function drawFaceGuides(ctx) {
  const W = FACE_W, H = FACE_H;
  ctx.save();
  ctx.strokeStyle = 'rgba(0,200,255,0.5)'; ctx.setLineDash([4, 4]); ctx.lineWidth = 1;
  for (const k of ['eyeR', 'eyeL']) { const [u, v] = LM[k]; ctx.beginPath(); ctx.ellipse(u * W, v * H, W * 0.08, H * 0.03, 0, 0, Math.PI * 2); ctx.stroke(); }
  ctx.beginPath(); ctx.moveTo(W / 2, 0); ctx.lineTo(W / 2, H); ctx.stroke();
  for (const v of [LM.eyeR[1], LM.nose[1], LM.mouth[1], LM.browR[1]]) { ctx.beginPath(); ctx.moveTo(0, v * H); ctx.lineTo(W, v * H); ctx.stroke(); }
  ctx.fillStyle = 'rgba(0,200,255,0.8)'; ctx.font = '11px sans-serif';
  ctx.fillText('คิ้ว', 4, LM.browR[1] * H - 3); ctx.fillText('ตา', 4, LM.eyeR[1] * H - 3); ctx.fillText('จมูก', 4, LM.nose[1] * H - 3); ctx.fillText('ปาก', 4, LM.mouth[1] * H - 3);
  ctx.restore();
}

// ---------- Live skin with damage + blood ----------
export class SkinFX {
  constructor(look, baseFaceCanvas, tattoo) {
    this.look = look;
    this.base = baseFaceCanvas; // painted face
    this.face = mkCanvas(FACE_W, FACE_H);
    this.fctx = this.face.getContext('2d');
    this.blood = mkCanvas(FACE_W, FACE_H);
    this.bctx = this.blood.getContext('2d', { willReadFrequently: true });
    this.faceTex = new THREE.CanvasTexture(this.face);
    this.faceTex.colorSpace = THREE.SRGBColorSpace;
    this.faceTex.anisotropy = 2;
    // torso
    this.torsoBase = mkCanvas(TORSO_W, TORSO_H);
    this.torso = mkCanvas(TORSO_W, TORSO_H);
    this.tctx = this.torso.getContext('2d');
    this.tblood = mkCanvas(TORSO_W, TORSO_H);
    this.tbctx = this.tblood.getContext('2d');
    this.torsoTex = new THREE.CanvasTexture(this.torso);
    this.torsoTex.colorSpace = THREE.SRGBColorSpace;
    paintTorso(this.torsoBase.getContext('2d'), look, tattoo);
    this.rivers = []; // face rivulets
    this.trivers = []; // torso rivulets
    this.dirty = true; this.tdirty = true;
    this.ageT = 0;
    this.damage = null;
    this.compose();
    this.composeTorso();
  }

  // gravity direction in face texture space (gx right, gy down), and how much it points into the face
  addRivulet(x, y, vol, list = this.rivers) {
    if (list.length > 180) list.shift();
    list.push({ x, y, px: x, py: y, vol, w: clamp(1.4 + vol * 1.6, 1.4, 5.5), wob: 0, seed: Math.random() * 6.28, age: 0 });
  }

  // step blood flow. g = {x,y,z} gravity in head-local coords (x right(char left), y up, z out of face)
  flow(dt, gLocal, gTorso, onDrip, onEye) {
    const ctx = this.bctx;
    // planar gravity on face texture: texture x = +local x, texture y = -local y
    let gx = gLocal.x, gy = -gLocal.y;
    const planar = Math.hypot(gx, gy);
    if (planar > 1e-3) { gx /= planar; gy /= planar; }
    ctx.lineCap = 'round';
    for (let i = this.rivers.length - 1; i >= 0; i--) {
      const rv = this.rivers[i];
      rv.age += dt;
      rv.wob += dt * 3.2;
      const speed = (30 + rv.vol * 50) * planar; // px/s
      // blood follows existing wet channels: only a small meander
      const wx = Math.sin(rv.wob + rv.seed) * 0.14;
      rv.px = rv.x; rv.py = rv.y;
      rv.x += (gx + -gy * wx) * speed * dt;
      rv.y += (gy + gx * wx) * speed * dt;
      const deposit = speed * dt * 0.0006 + dt * 0.01;
      rv.vol -= deposit;
      const fresh = clamp(rv.vol, 0, 1);
      const lw = rv.w * clamp(0.65 + rv.vol * 0.8, 0.65, 1.5);
      // dark edge then glossy core (fresh blood is bright, thin films look darker)
      ctx.strokeStyle = 'rgba(70,0,4,0.55)'; ctx.lineWidth = lw + 1.6;
      ctx.beginPath(); ctx.moveTo(rv.px, rv.py); ctx.lineTo(rv.x, rv.y); ctx.stroke();
      ctx.strokeStyle = `rgba(${120 + fresh * 45},${3 + fresh * 8},${8},0.9)`; ctx.lineWidth = lw;
      ctx.beginPath(); ctx.moveTo(rv.px, rv.py); ctx.lineTo(rv.x, rv.y); ctx.stroke();
      if (planar < 0.35) { // pooling when face points up/down
        ctx.fillStyle = 'rgba(120,6,8,0.12)'; ctx.beginPath(); ctx.arc(rv.x, rv.y, rv.w * 2.5, 0, 6.28); ctx.fill();
      }
      if (rv.vol <= 0.015) { // a bead forms where the stream stops
        ctx.fillStyle = 'rgba(105,2,6,0.95)'; ctx.beginPath(); ctx.ellipse(rv.x, rv.y + 1, lw * 0.9, lw * 1.2, 0, 0, 6.28); ctx.fill();
      }
      // blood running into an eye
      for (const [k, side] of [['eyeR', 0], ['eyeL', 1]]) {
        const [u, v] = LM[k];
        if (Math.abs(rv.x - u * FACE_W) < FACE_W * 0.08 && Math.abs(rv.y - v * FACE_H) < FACE_H * 0.03) onEye && onEye(side, dt * rv.vol);
      }
      const out = rv.x < 0 || rv.x > FACE_W || rv.y < 0 || rv.y > FACE_H;
      if (out || rv.vol <= 0) {
        if (out && rv.vol > 0.02) onDrip && onDrip(rv.x / FACE_W, rv.y / FACE_H, rv.vol);
        this.rivers.splice(i, 1);
      }
      this.dirty = true;
    }
    // torso rivulets (gravity on torso front plane)
    if (this.trivers.length) {
      let tx = gTorso.x, ty = -gTorso.y; const tp = Math.hypot(tx, ty); if (tp > 1e-3) { tx /= tp; ty /= tp; }
      const tc = this.tbctx; tc.lineCap = 'round';
      for (let i = this.trivers.length - 1; i >= 0; i--) {
        const rv = this.trivers[i];
        rv.wob += dt * 5;
        const sp = (14 + rv.vol * 30) * tp;
        rv.px = rv.x; rv.py = rv.y;
        const wx = Math.cos(rv.wob) * 0.2;
        rv.x += (tx - ty * wx) * sp * dt; rv.y += (ty + tx * wx) * sp * dt;
        rv.vol -= dt * 0.25 + sp * dt * 0.004;
        tc.strokeStyle = 'rgba(128,8,10,0.7)'; tc.lineWidth = rv.w;
        tc.beginPath(); tc.moveTo(rv.px, rv.py); tc.lineTo(rv.x, rv.y); tc.stroke();
        if (rv.vol <= 0 || rv.y > TORSO_H || rv.y < 0) this.trivers.splice(i, 1);
        this.tdirty = true;
      }
    }
    // oxidation: fresh blood darkens toward brown over ~1-2 minutes
    this.ageT += dt;
    if (this.ageT > 1.5) {
      this.ageT = 0;
      for (const c of [ctx, this.tbctx]) {
        c.save(); c.globalCompositeOperation = 'source-atop';
        c.fillStyle = 'rgba(55,18,8,0.035)'; c.fillRect(0, 0, c.canvas.width, c.canvas.height);
        c.restore();
      }
      this.dirty = true; this.tdirty = true;
    }
  }

  splat(u, v, size, alpha = 0.8) {
    const c = this.bctx, x = u * FACE_W, y = v * FACE_H;
    c.fillStyle = `rgba(135,8,10,${alpha})`;
    c.beginPath(); c.ellipse(x, y, size, size * (0.7 + Math.random() * 0.5), Math.random() * 3, 0, 6.28); c.fill();
    this.dirty = true;
  }
  torsoSplat(u, v, size, runVol = 0) {
    const c = this.tbctx, x = u * TORSO_W, y = v * TORSO_H;
    c.fillStyle = 'rgba(130,8,10,0.85)';
    c.beginPath(); c.ellipse(x, y, size, size * (0.8 + Math.random() * 0.4), Math.random() * 3, 0, 6.28); c.fill();
    if (runVol > 0.05) { if (this.trivers.length > 40) this.trivers.shift(); this.trivers.push({ x, y, px: x, py: y, vol: runVol, w: 1.5 + runVol * 2, wob: Math.random() * 6 }); }
    this.tdirty = true;
  }
  // smear blood on impact (punch drags it across)
  smear(u, v, dx, dy) {
    const c = this.bctx, x = u * FACE_W, y = v * FACE_H, R = 40;
    c.save(); c.globalAlpha = 0.5;
    c.beginPath(); c.arc(x, y, R, 0, 6.28); c.clip();
    c.drawImage(this.blood, x - R, y - R, R * 2, R * 2, x - R + dx, y - R + dy, R * 2, R * 2);
    c.restore();
    this.dirty = true;
  }
  wetness(u, v) {
    // how much blood near a point (sample a few pixels)
    const x = clamp(Math.round(u * FACE_W), 0, FACE_W - 1), y = clamp(Math.round(v * FACE_H), 0, FACE_H - 1);
    const d = this.bctx.getImageData(Math.max(0, x - 6), Math.max(0, y - 6), 12, 12).data;
    let s = 0; for (let i = 3; i < d.length; i += 16) s += d[i];
    return s / (36 * 255);
  }
  wipe(amount = 0.85) {
    for (const c of [this.bctx, this.tbctx]) {
      c.save(); c.globalCompositeOperation = 'destination-out'; c.fillStyle = `rgba(0,0,0,${amount})`;
      c.fillRect(0, 0, c.canvas.width, c.canvas.height); c.restore();
    }
    this.rivers.length = 0; this.trivers.length = 0;
    this.dirty = true; this.tdirty = true;
  }
  clearAll() {
    this.bctx.clearRect(0, 0, FACE_W, FACE_H); this.tbctx.clearRect(0, 0, TORSO_W, TORSO_H);
    this.rivers.length = 0; this.trivers.length = 0; this.dirty = this.tdirty = true;
  }

  setDamage(dmg) { this.damage = dmg; this.dirty = true; }

  compose() {
    const c = this.fctx, W = FACE_W, H = FACE_H;
    c.clearRect(0, 0, W, H);
    c.drawImage(this.base, 0, 0, W, H);
    const d = this.damage;
    if (d) {
      const sk = this.look.skin;
      // general redness / flush with fatigue & damage
      if (d.redness > 0.02) { c.fillStyle = `rgba(200,40,40,${clamp(d.redness, 0, 1) * 0.18})`; c.fillRect(0, 0, W, H); }
      // bruises & swelling
      const bruise = (u, v, rx, ry, amt) => {
        if (amt < 0.03) return;
        const a = clamp(amt, 0, 1);
        const g = c.createRadialGradient(u * W, v * H, 2, u * W, v * H, Math.max(rx, ry) * W);
        g.addColorStop(0, `rgba(${110 - a * 40},${30},${60 + a * 40},${0.55 * a + 0.1})`);
        g.addColorStop(0.5, `rgba(150,40,50,${0.35 * a})`);
        g.addColorStop(1, 'rgba(150,40,50,0)');
        c.fillStyle = g; c.beginPath(); c.ellipse(u * W, v * H, rx * W, ry * H, 0, 0, 6.28); c.fill();
      };
      bruise(LM.eyeR[0], LM.eyeR[1] + 0.01, 0.14, 0.08, d.swell.eyeR);
      bruise(LM.eyeL[0], LM.eyeL[1] + 0.01, 0.14, 0.08, d.swell.eyeL);
      bruise(LM.cheekR[0], LM.cheekR[1], 0.12, 0.09, d.swell.cheekR);
      bruise(LM.cheekL[0], LM.cheekL[1], 0.12, 0.09, d.swell.cheekL);
      bruise(LM.forehead[0], LM.forehead[1], 0.22, 0.1, d.swell.forehead);
      bruise(LM.mouth[0], LM.mouth[1], 0.12, 0.05, d.swell.lip);
      bruise(LM.nose[0], LM.nose[1] - 0.05, 0.06, 0.1, d.nose * 0.9);
      // swollen eye closing
      for (const [k, s] of [['eyeR', d.swell.eyeR], ['eyeL', d.swell.eyeL]]) {
        if (s > 0.45) {
          const [u, v] = LM[k];
          const close = clamp((s - 0.45) / 0.45, 0, 1);
          c.fillStyle = tint(sk, [120, 50, 90], 0.45, 1);
          c.beginPath(); c.ellipse(u * W, (v - 0.012) * H, W * 0.085, H * 0.03 * close + 2, 0, Math.PI, 0); c.fill();
          c.beginPath(); c.ellipse(u * W, (v + 0.004) * H, W * 0.085, H * 0.022 * close + 1, 0, 0, Math.PI); c.fill();
          c.strokeStyle = 'rgba(40,10,20,0.9)'; c.lineWidth = 1.5;
          c.beginPath(); c.moveTo(u * W - W * 0.07, v * H); c.lineTo(u * W + W * 0.07, v * H); c.stroke();
        }
      }
      // cuts: open wounds
      for (const cut of d.cuts) {
        const x = cut.u * W, y = cut.v * H, L = cut.len * W;
        c.save(); c.translate(x, y); c.rotate(cut.ang);
        c.strokeStyle = 'rgba(70,0,5,0.95)'; c.lineWidth = 2 + cut.depth * 3;
        c.beginPath(); c.moveTo(-L / 2, 0);
        for (let i = 1; i <= 6; i++) c.lineTo(-L / 2 + (L * i) / 6, ((i * 7919 + cut.seed) % 5 - 2) * 0.8);
        c.stroke();
        c.strokeStyle = `rgba(200,30,40,${0.8})`; c.lineWidth = 1 + cut.depth;
        c.stroke();
        c.restore();
      }
    }
    c.drawImage(this.blood, 0, 0);
    this.faceTex.needsUpdate = true;
    this.dirty = false;
  }
  composeTorso() {
    const c = this.tctx;
    c.clearRect(0, 0, TORSO_W, TORSO_H);
    c.drawImage(this.torsoBase, 0, 0);
    const d = this.damage;
    if (d) {
      // body bruising (liver/ribs)
      const br = (u, v, r, a) => {
        if (a < 0.05) return;
        const g = c.createRadialGradient(u * TORSO_W, v * TORSO_H, 2, u * TORSO_W, v * TORSO_H, r);
        g.addColorStop(0, `rgba(140,30,50,${clamp(a, 0, 1) * 0.6})`); g.addColorStop(1, 'rgba(140,30,50,0)');
        c.fillStyle = g; c.fillRect(0, 0, TORSO_W, TORSO_H);
      };
      // front half: x in [0,0.5]; char right side = u<0.25
      br(0.1, 0.72, 34, d.liver); br(0.4, 0.72, 34, d.ribsL); br(0.25, 0.4, 40, d.chest);
    }
    c.drawImage(this.tblood, 0, 0);
    this.torsoTex.needsUpdate = true;
    this.tdirty = false;
  }
  update() {
    if (this.dirty) this.compose();
    if (this.tdirty) this.composeTorso();
  }
  dispose() { this.faceTex.dispose(); this.torsoTex.dispose(); }
}

export function paintTorso(ctx, look, tattoo) {
  const W = TORSO_W, H = TORSO_H, skin = look.skin;
  ctx.fillStyle = skin; ctx.fillRect(0, 0, W, H);
  const r = makeRng(look.seed || 7);
  // front half (0..W/2): pecs and abs shading
  const fw = W / 2;
  const mus = look.muscle ?? 0.5, fat = look.fat ?? 0.2;
  let g;
  // pecs
  for (const sx of [0.27, 0.73]) {
    g = ctx.createRadialGradient(fw * sx, H * 0.3, 4, fw * sx, H * 0.3, fw * 0.32);
    g.addColorStop(0, shade(skin, 0.08, 0.5)); g.addColorStop(0.7, shade(skin, 0, 0)); g.addColorStop(0.88, shade(skin, -0.35, 0.3 * mus)); g.addColorStop(1, shade(skin, -0.35, 0));
    ctx.fillStyle = g; ctx.fillRect(0, 0, fw, H * 0.6);
  }
  ctx.strokeStyle = shade(skin, -0.35, 0.3 + mus * 0.4); ctx.lineWidth = 2;
  ctx.beginPath(); ctx.moveTo(fw * 0.08, H * 0.48); ctx.quadraticCurveTo(fw * 0.25, H * 0.55, fw * 0.48, H * 0.47); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(fw * 0.92, H * 0.48); ctx.quadraticCurveTo(fw * 0.75, H * 0.55, fw * 0.52, H * 0.47); ctx.stroke();
  // nipples
  ctx.fillStyle = shade(skin, -0.35, 0.8);
  ctx.beginPath(); ctx.arc(fw * 0.25, H * 0.43, 3, 0, 6.28); ctx.fill();
  ctx.beginPath(); ctx.arc(fw * 0.75, H * 0.43, 3, 0, 6.28); ctx.fill();
  // abs (more visible with muscle, less with fat)
  const absA = clamp(mus * 0.7 - fat * 0.6, 0.05, 0.6);
  ctx.strokeStyle = shade(skin, -0.35, absA); ctx.lineWidth = 2;
  ctx.beginPath(); ctx.moveTo(fw / 2, H * 0.52); ctx.lineTo(fw / 2, H * 0.97); ctx.stroke();
  for (const y of [0.64, 0.76, 0.88]) { ctx.beginPath(); ctx.moveTo(fw * 0.3, H * y); ctx.quadraticCurveTo(fw * 0.5, H * (y + 0.015), fw * 0.7, H * y); ctx.stroke(); }
  ctx.fillStyle = shade(skin, -0.5, 0.7); ctx.beginPath(); ctx.ellipse(fw / 2, H * 0.86, 2.5, 3.5, 0, 0, 6.28); ctx.fill();
  // back half: shoulder blades & spine
  ctx.strokeStyle = shade(skin, -0.3, 0.35); ctx.lineWidth = 2;
  ctx.beginPath(); ctx.moveTo(fw * 1.5, H * 0.08); ctx.lineTo(fw * 1.5, H * 0.98); ctx.stroke();
  for (const sx of [1.25, 1.75]) { ctx.beginPath(); ctx.ellipse(fw * sx, H * 0.3, fw * 0.14, H * 0.12, 0, 0, 6.28); ctx.stroke(); }
  // chest hair
  if (look.chestHair) {
    for (let i = 0; i < 500; i++) {
      const x = fw * (0.2 + r() * 0.6), y = H * (0.2 + r() * 0.75);
      if (Math.abs(x - fw / 2) > fw * (0.35 - (y / H) * 0.25)) continue;
      ctx.fillStyle = shade(look.hairColor || '#1a1410', 0, 0.35); ctx.fillRect(x, y, 1.2, 2.5);
    }
  }
  // tattoos (simple tribal / script)
  if (tattoo && tattoo !== 'none') {
    ctx.strokeStyle = 'rgba(25,30,45,0.8)'; ctx.fillStyle = 'rgba(25,30,45,0.75)'; ctx.lineWidth = 3;
    if (tattoo === 'tribal') {
      for (let k = 0; k < 2; k++) {
        const ox = k === 0 ? fw * 0.12 : fw * 1.1;
        ctx.beginPath();
        for (let i = 0; i < 6; i++) { ctx.moveTo(ox + i * 9, H * 0.1); ctx.quadraticCurveTo(ox + i * 12 + 20, H * 0.25, ox + i * 6, H * 0.4); }
        ctx.stroke();
      }
    } else if (tattoo === 'script') {
      ctx.font = 'italic bold 22px serif'; ctx.fillText('Loyalty', fw * 0.18, H * 0.66);
      ctx.font = 'bold 20px serif'; ctx.fillText('FAMILY', fw * 1.18, H * 0.2);
    } else if (tattoo === 'sakyant') {
      // geometric yant on back
      ctx.lineWidth = 2;
      const cx = fw * 1.5, cy = H * 0.28;
      for (let i = 0; i < 5; i++) { ctx.beginPath(); ctx.arc(cx, cy, 12 + i * 8, Math.PI, 0); ctx.stroke(); }
      ctx.beginPath(); ctx.moveTo(cx - 45, cy); ctx.lineTo(cx + 45, cy); ctx.lineTo(cx, cy + 50); ctx.closePath(); ctx.stroke();
      for (let i = 0; i < 9; i++) { ctx.beginPath(); ctx.moveTo(cx - 40 + i * 10, cy + 60); ctx.lineTo(cx - 40 + i * 10, cy + 75); ctx.stroke(); }
    }
  }
}
