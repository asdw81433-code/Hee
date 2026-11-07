// ===== Math & helper utilities =====
import * as THREE from 'three';

export const V3 = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z);
export const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
export const lerp = (a, b, t) => a + (b - a) * t;
export const invLerp = (a, b, v) => clamp((v - a) / (b - a), 0, 1);
export const smooth = (t) => t * t * (3 - 2 * t);
export const easeIn = (t) => t * t;
export const easeOut = (t) => 1 - (1 - t) * (1 - t);
export const easeInOut = (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2);
export const TAU = Math.PI * 2;
export const wrapAngle = (a) => {
  while (a > Math.PI) a -= TAU;
  while (a < -Math.PI) a += TAU;
  return a;
};
export const damp = (a, b, lambda, dt) => lerp(a, b, 1 - Math.exp(-lambda * dt));

// Seeded RNG (mulberry32) so NPC fighters/faces are reproducible
export function makeRng(seed) {
  let s = seed >>> 0;
  const r = () => {
    s |= 0;
    s = (s + 0x6d2b79f5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  r.range = (a, b) => a + (b - a) * r();
  r.int = (a, b) => Math.floor(a + (b - a + 1) * r());
  r.pick = (arr) => arr[Math.floor(r() * arr.length)];
  r.chance = (p) => r() < p;
  r.gauss = () => {
    let u = 0, v = 0;
    while (u === 0) u = r();
    while (v === 0) v = r();
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(TAU * v);
  };
  return r;
}
export const rng = makeRng((Date.now() ^ 0x5eed) >>> 0);
export const hashStr = (str) => {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
};

// ---- Second-order spring-damper (PD controller) ----
// a = k*(target-x) - d*v ; with damping ratio zeta: d = 2*zeta*sqrt(k)
export class Spring {
  constructor(x = 0, k = 200, zeta = 0.8) {
    this.x = x; this.v = 0; this.t = x; this.k = k; this.z = zeta;
  }
  step(dt, kMul = 1) {
    const k = this.k * kMul;
    const d = 2 * this.z * Math.sqrt(k);
    this.v += (k * (this.t - this.x) - d * this.v) * dt;
    this.x += this.v * dt;
  }
  set(x) { this.x = x; this.t = x; this.v = 0; }
}
export class Spring3 {
  constructor(x = 0, y = 0, z = 0, k = 200, zeta = 0.8) {
    this.x = new THREE.Vector3(x, y, z);
    this.v = new THREE.Vector3();
    this.t = new THREE.Vector3(x, y, z);
    this.k = k; this.z = zeta;
  }
  step(dt, kMul = 1) {
    const k = this.k * kMul;
    const d = 2 * this.z * Math.sqrt(k);
    const x = this.x, v = this.v, t = this.t;
    v.x += (k * (t.x - x.x) - d * v.x) * dt;
    v.y += (k * (t.y - x.y) - d * v.y) * dt;
    v.z += (k * (t.z - x.z) - d * v.z) * dt;
    x.x += v.x * dt; x.y += v.y * dt; x.z += v.z * dt;
  }
  setAll(vec) { this.x.copy(vec); this.t.copy(vec); this.v.set(0, 0, 0); }
}

// Build an orthonormal basis whose Y axis is `y` and Z axis points as close as possible to `zHint`
const _bx = new THREE.Vector3(), _bz = new THREE.Vector3(), _by = new THREE.Vector3();
export function basisYZ(y, zHint, outQuat) {
  _by.copy(y).normalize();
  _bx.crossVectors(_by, zHint);
  if (_bx.lengthSq() < 1e-8) _bx.set(1, 0, 0).cross(_by).cross(_by).negate();
  _bx.normalize();
  _bz.crossVectors(_bx, _by).normalize();
  const m = _mtmp.makeBasis(_bx, _by, _bz);
  return outQuat.setFromRotationMatrix(m);
}
export function basisZY(z, yHint, outQuat) {
  _bz.copy(z).normalize();
  _bx.crossVectors(yHint, _bz);
  if (_bx.lengthSq() < 1e-8) _bx.set(1, 0, 0);
  _bx.normalize();
  _by.crossVectors(_bz, _bx).normalize();
  const m = _mtmp.makeBasis(_bx, _by, _bz);
  return outQuat.setFromRotationMatrix(m);
}
const _mtmp = new THREE.Matrix4();

// Closest distance from point p to segment ab; returns {d, t}
const _ab = new THREE.Vector3(), _ap = new THREE.Vector3();
export function pointSegDist(p, a, b) {
  _ab.subVectors(b, a);
  _ap.subVectors(p, a);
  const L2 = _ab.lengthSq();
  let t = L2 > 1e-9 ? _ap.dot(_ab) / L2 : 0;
  t = clamp(t, 0, 1);
  const cx = a.x + _ab.x * t - p.x, cy = a.y + _ab.y * t - p.y, cz = a.z + _ab.z * t - p.z;
  return { d: Math.sqrt(cx * cx + cy * cy + cz * cz), t };
}

// Two-bone analytic IK. root, target, pole in world; returns mid joint position into outMid
const _d = new THREE.Vector3(), _p = new THREE.Vector3();
export function solveIK(root, target, lenA, lenB, pole, outMid, outEnd) {
  _d.subVectors(target, root);
  let dist = _d.length();
  const maxL = (lenA + lenB) * 0.999;
  const minL = Math.abs(lenA - lenB) + 0.01;
  if (dist < 1e-6) { _d.set(0, -1, 0); dist = minL; }
  _d.divideScalar(dist);
  dist = clamp(dist, minL, maxL);
  outEnd.copy(root).addScaledVector(_d, dist);
  const cosA = clamp((lenA * lenA + dist * dist - lenB * lenB) / (2 * lenA * dist), -1, 1);
  const sinA = Math.sqrt(1 - cosA * cosA);
  _p.copy(pole).addScaledVector(_d, -pole.dot(_d));
  if (_p.lengthSq() < 1e-8) _p.set(0, 0, 1).addScaledVector(_d, -_d.z);
  _p.normalize();
  outMid.copy(root).addScaledVector(_d, lenA * cosA).addScaledVector(_p, lenA * sinA);
  return outMid;
}

// Quadratic Bezier
export function bez2(out, a, b, c, t) {
  const u = 1 - t;
  out.set(
    u * u * a.x + 2 * u * t * b.x + t * t * c.x,
    u * u * a.y + 2 * u * t * b.y + t * t * c.y,
    u * u * a.z + 2 * u * t * b.z + t * t * c.z
  );
  return out;
}

export function fmtTime(s) {
  s = Math.max(0, Math.ceil(s));
  return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
}
export function money(n) {
  return '$' + Math.round(n).toLocaleString('en-US');
}
export function el(tag, attrs = {}, ...kids) {
  const e = document.createElement(tag);
  for (const k in attrs) {
    const v = attrs[k];
    if (k === 'class') e.className = v;
    else if (k === 'style' && typeof v === 'object') Object.assign(e.style, v);
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else if (k === 'html') e.innerHTML = v;
    else if (v !== undefined && v !== null && v !== false) e.setAttribute(k, v);
  }
  for (const kid of kids.flat()) {
    if (kid === null || kid === undefined || kid === false) continue;
    e.appendChild(typeof kid === 'string' || typeof kid === 'number' ? document.createTextNode(String(kid)) : kid);
  }
  return e;
}
