// ===== Physics-driven character rig =====
// Hybrid model (as used in games like Euphoria/active-ragdoll setups):
//  * Torso joints are driven by PD springs (proportional-derivative) toward pose targets -> weight, lag, follow-through.
//  * Limbs are solved with analytic 2-bone IK toward spring-smoothed end-effector targets.
//  * On knockouts/knockdowns the rig switches to a Verlet particle ragdoll (Jakobsen, "Advanced Character Physics")
//    seeded with the current joint velocities, so momentum carries over (no pop).
import * as THREE from 'three';
import { Spring, Spring3, solveIK, basisYZ, basisZY, clamp, lerp } from './util.js';

export const SEGS = ['pelvis', 'abdomen', 'chest', 'neck', 'head', 'uarmL', 'farmL', 'handL', 'uarmR', 'farmR', 'handR', 'thighL', 'shinL', 'footL', 'thighR', 'shinR', 'footR'];
export const S = Object.fromEntries(SEGS.map((s, i) => [s, i]));
// Ragdoll particle / joint point indices
export const P = { pelvis: 0, abd: 1, neck: 2, head: 3, shL: 4, elL: 5, haL: 6, shR: 7, elR: 8, haR: 9, hipL: 10, knL: 11, anL: 12, hipR: 13, knR: 14, anR: 15, toeL: 16, toeR: 17 };
const NP = 18;
const PMASS = [15, 18, 4, 5, 2.5, 1.6, 0.6, 2.5, 1.6, 0.6, 3, 7, 3.5, 3, 7, 3.5, 0.6, 0.6];
const PRAD = [0.12, 0.13, 0.07, 0.12, 0.07, 0.05, 0.06, 0.07, 0.05, 0.06, 0.08, 0.06, 0.05, 0.08, 0.06, 0.05, 0.04, 0.04];

export function makeDims(heightM, reachMul = 1, bulk = 0.5) {
  const H = heightM;
  return {
    H,
    hipH: 0.53 * H,
    spineBase: 0.055 * H,
    abd: 0.1 * H,
    chest: 0.165 * H,
    neck: 0.045 * H,
    headH: 0.13 * H,
    shW: 0.1 * H + bulk * 0.025,
    shY: 0.82 * 0.165 * H,
    uarm: 0.168 * H * reachMul,
    farm: 0.148 * H * reachMul,
    hipW: 0.052 * H,
    thigh: 0.245 * H,
    shin: 0.24 * H,
    ankle: 0.04 * H,
    foot: 0.13 * H,
    bulk,
  };
}

const _q = new THREE.Quaternion(), _q2 = new THREE.Quaternion(), _e = new THREE.Euler(0, 0, 0, 'YXZ');
const _v = new THREE.Vector3(), _v2 = new THREE.Vector3(), _v3 = new THREE.Vector3();
const _m = new THREE.Matrix4();
const UP = new THREE.Vector3(0, 1, 0);

class Frame {
  constructor() { this.pos = new THREE.Vector3(); this.quat = new THREE.Quaternion(); }
  apply(local, out) { return out.copy(local).applyQuaternion(this.quat).add(this.pos); }
  dir(local, out) { return out.copy(local).applyQuaternion(this.quat); }
  toLocal(world, out) { _q2.copy(this.quat).invert(); return out.copy(world).sub(this.pos).applyQuaternion(_q2); }
  child(parent, offset, euler) {
    parent.apply(offset, this.pos);
    _e.set(euler.x, euler.y, euler.z, 'YXZ');
    this.quat.copy(parent.quat).multiply(_q.setFromEuler(_e));
    return this;
  }
}

export class Rig {
  constructor(dims) {
    this.d = dims;
    this.root = new THREE.Vector3();
    this.yaw = 0;
    // pose springs (relative to facing frame)
    this.pelvisOff = new Spring3(0, 0, 0, 260, 0.85); // pelvis offset from root (facing frame) - weight shift/crouch
    this.pelvisRot = new Spring3(0, 0, 0, 240, 0.8);
    this.abdRot = new Spring3(0, 0, 0, 260, 0.75);
    this.chestRot = new Spring3(0, 0, 0, 300, 0.72);
    this.neckRot = new Spring3(0, 0, 0, 260, 0.7);
    this.headRot = new Spring3(0, 0, 0, 320, 0.65);
    this.hands = [new Spring3(0, 0, 0, 600, 0.78), new Spring3(0, 0, 0, 600, 0.78)]; // chest frame; 0=L 1=R
    this.poles = [new Spring3(0.4, -1, 0, 300, 0.9), new Spring3(-0.4, -1, 0, 300, 0.9)];
    this.handRoll = [new Spring(0, 400, 0.8), new Spring(0, 400, 0.8)];
    this.feet = [0, 1].map((i) => ({
      world: new THREE.Vector3(), yaw: 0, stepping: false,
      from: new THREE.Vector3(), to: new THREE.Vector3(), t: 0, dur: 0.2, lift: 0.07, fromYaw: 0, toYaw: 0,
      local: new Spring3(0, 0, 0, 500, 0.8), w: new Spring(0, 300, 1), pole: new THREE.Vector3(i === 0 ? 0.25 : -0.25, 0, 1),
      pitch: new Spring(0, 300, 0.8), planted: true, liftLock: 0,
    }));
    this.stiff = 1; // global stiffness multiplier (fatigue/hurt -> lower = sloppier, heavier)
    this.legStiff = 1;
    // frames
    this.F = new Frame(); this.Pf = new Frame(); this.Af = new Frame(); this.Cf = new Frame(); this.Nf = new Frame(); this.Hf = new Frame();
    this.pts = Array.from({ length: NP }, () => new THREE.Vector3());
    this.prevPts = Array.from({ length: NP }, () => new THREE.Vector3());
    this.ptVel = Array.from({ length: NP }, () => new THREE.Vector3());
    this.seg = SEGS.map(() => ({ pos: new THREE.Vector3(), quat: new THREE.Quaternion() }));
    this.mode = 'anim';
    this.rag = null;
    this.blend = 0; this.blendSnap = null;
    this.handTipL = new THREE.Vector3(); this.handTipR = new THREE.Vector3();
    this.headCenter = new THREE.Vector3(); this.headFwd = new THREE.Vector3(0, 0, 1);
  }

  get facing() { return _v3.set(Math.sin(this.yaw), 0, Math.cos(this.yaw)); }

  placeAt(x, z, yaw) {
    this.root.set(x, this.d.hipH * 0.93, z);
    this.yaw = yaw;
    this.F.pos.copy(this.root); this.F.quat.setFromAxisAngle(UP, yaw);
    const sx = [1, -1];
    for (let i = 0; i < 2; i++) {
      const f = this.feet[i];
      this.F.apply(_v.set(sx[i] * this.d.hipW * 1.2, 0, 0), f.world);
      f.world.y = this.d.ankle; f.yaw = yaw; f.stepping = false;
    }
    this.mode = 'anim'; this.rag = null; this.blend = 0;
  }

  // --- spring stepping ---
  stepSprings(dt) {
    const k = this.stiff;
    this.pelvisOff.step(dt, k); this.pelvisRot.step(dt, k); this.abdRot.step(dt, k); this.chestRot.step(dt, k);
    this.neckRot.step(dt, k); this.headRot.step(dt, k);
    for (let i = 0; i < 2; i++) {
      this.hands[i].step(dt, k); this.poles[i].step(dt, k); this.handRoll[i].step(dt, k);
      const f = this.feet[i]; f.local.step(dt, k * this.legStiff); f.w.step(dt); f.pitch.step(dt, k);
      f.w.x = clamp(f.w.x, 0, 1);
    }
  }

  // world position of foot including step arc
  footWorld(i, out) {
    const f = this.feet[i];
    if (f.stepping) {
      const t = clamp(f.t / f.dur, 0, 1);
      const s = t * t * (3 - 2 * t);
      out.lerpVectors(f.from, f.to, s);
      out.y = this.d.ankle + Math.sin(Math.PI * t) * f.lift;
    } else out.copy(f.world);
    return out;
  }
  footYaw(i) {
    const f = this.feet[i];
    if (f.stepping) { const t = clamp(f.t / f.dur, 0, 1); return f.fromYaw + angDiff(f.toYaw, f.fromYaw) * t; }
    return f.yaw;
  }

  // Forward kinematics + IK: compute joint points and segment transforms
  solve() {
    const d = this.d, F = this.F;
    F.pos.copy(this.root);
    F.quat.setFromAxisAngle(UP, this.yaw);
    // pelvis
    this.Pf.child(F, this.pelvisOff.x, this.pelvisRot.x);
    this.Af.child(this.Pf, _v.set(0, d.spineBase, 0), this.abdRot.x);
    this.Cf.child(this.Af, _v.set(0, d.abd, 0), this.chestRot.x);
    this.Nf.child(this.Cf, _v.set(0, d.chest, 0), this.neckRot.x);
    this.Hf.child(this.Nf, _v.set(0, d.neck, 0), this.headRot.x);
    const pts = this.pts;
    pts[P.pelvis].copy(this.Pf.pos);
    pts[P.abd].copy(this.Cf.pos);
    pts[P.neck].copy(this.Nf.pos);
    this.Hf.apply(_v.set(0, d.headH * 0.5, 0.01), pts[P.head]);
    this.headCenter.copy(pts[P.head]);
    this.Hf.dir(_v.set(0, 0, 1), this.headFwd);
    // arms
    for (let i = 0; i < 2; i++) {
      const sx = i === 0 ? 1 : -1;
      const sh = pts[i === 0 ? P.shL : P.shR], el = pts[i === 0 ? P.elL : P.elR], ha = pts[i === 0 ? P.haL : P.haR];
      this.Cf.apply(_v.set(sx * d.shW, d.shY, 0), sh);
      this.Cf.apply(this.hands[i].x, _v2);
      this.Cf.dir(this.poles[i].x, _v);
      solveIK(sh, _v2, d.uarm, d.farm, _v, el, ha);
    }
    // legs
    for (let i = 0; i < 2; i++) {
      const sx = i === 0 ? 1 : -1;
      const hip = pts[i === 0 ? P.hipL : P.hipR], kn = pts[i === 0 ? P.knL : P.knR], an = pts[i === 0 ? P.anL : P.anR], toe = pts[i === 0 ? P.toeL : P.toeR];
      this.Pf.apply(_v.set(sx * d.hipW, -0.02, 0), hip);
      const f = this.feet[i];
      this.footWorld(i, _v2);
      F.apply(f.local.x, _v3);
      const w = f.w.x;
      _v2.lerp(_v3, w);
      // floor clamp for target
      if (_v2.y < d.ankle * 0.8) _v2.y = d.ankle * 0.8;
      F.dir(f.pole, _v);
      // keep knee pole roughly forward of pelvis when planted
      solveIK(hip, _v2, d.thigh, d.shin, _v, kn, an);
      // toe: planted -> along foot yaw on floor; kicking -> along shin with pitch
      const yaw = this.footYaw(i);
      const fx = Math.sin(yaw), fz = Math.cos(yaw);
      _v.set(fx, 0, fz);
      if (w > 0.01) {
        // kicking foot: point toes along a blend of facing forward and shin-perpendicular
        _v2.subVectors(an, kn).normalize();
        const p = f.pitch.x;
        _v3.copy(F.dir(_v3.set(0, 0, 1), _v3));
        _v3.addScaledVector(_v2, p).normalize();
        _v.lerp(_v3, w).normalize();
      }
      toe.copy(an).addScaledVector(_v, d.foot);
      if (toe.y < 0.02) toe.y = 0.02;
    }
    this.computeSegmentsAnim();
  }

  computeSegmentsAnim() {
    const pts = this.pts, seg = this.seg, d = this.d;
    seg[S.pelvis].pos.copy(this.Pf.pos); seg[S.pelvis].quat.copy(this.Pf.quat);
    seg[S.abdomen].pos.copy(this.Af.pos); seg[S.abdomen].quat.copy(this.Af.quat);
    seg[S.chest].pos.copy(this.Cf.pos); seg[S.chest].quat.copy(this.Cf.quat);
    seg[S.neck].pos.copy(this.Nf.pos); seg[S.neck].quat.copy(this.Nf.quat);
    seg[S.head].pos.copy(this.Hf.pos); seg[S.head].quat.copy(this.Hf.quat);
    this.Cf.dir(_v3.set(0, 0, 1), _v3);
    this.limbSegs(_v3);
  }

  limbSegs(torsoFwd) {
    const pts = this.pts, seg = this.seg;
    const L = [[S.uarmL, P.shL, P.elL], [S.farmL, P.elL, P.haL], [S.uarmR, P.shR, P.elR], [S.farmR, P.elR, P.haR],
      [S.thighL, P.hipL, P.knL], [S.shinL, P.knL, P.anL], [S.thighR, P.hipR, P.knR], [S.shinR, P.knR, P.anR]];
    for (const [si, a, b] of L) {
      _v.subVectors(pts[b], pts[a]);
      seg[si].pos.copy(pts[a]);
      // z hint: for arms use torso forward; for legs use forward too
      basisYZ(_v, torsoFwd, seg[si].quat);
    }
    // gloves continue forearm with roll
    for (let i = 0; i < 2; i++) {
      const si = i === 0 ? S.handL : S.handR, el = pts[i === 0 ? P.elL : P.elR], ha = pts[i === 0 ? P.haL : P.haR];
      _v.subVectors(ha, el);
      seg[si].pos.copy(ha);
      _v2.copy(torsoFwd);
      if (this.mode === 'anim') {
        const r = this.handRoll[i].x;
        _v2.applyAxisAngle(_v.clone().normalize(), r * (i === 0 ? 1 : -1));
      }
      basisYZ(_v, _v2, seg[si].quat);
      const tip = i === 0 ? this.handTipL : this.handTipR;
      tip.copy(ha).addScaledVector(_v.normalize(), this.d.H * 0.045);
    }
    // feet: Z along toe direction
    for (let i = 0; i < 2; i++) {
      const si = i === 0 ? S.footL : S.footR, an = pts[i === 0 ? P.anL : P.anR], toe = pts[i === 0 ? P.toeL : P.toeR], kn = pts[i === 0 ? P.knL : P.knR];
      _v.subVectors(toe, an);
      _v2.subVectors(kn, an);
      seg[si].pos.copy(an);
      basisZY(_v, _v2.lengthSq() > 1e-6 ? _v2 : UP, seg[si].quat);
    }
  }

  // track joint velocities (for ragdoll handoff & hit physics)
  trackVel(dt) {
    for (let i = 0; i < NP; i++) {
      this.ptVel[i].subVectors(this.pts[i], this.prevPts[i]).divideScalar(Math.max(dt, 1e-4));
      this.prevPts[i].copy(this.pts[i]);
    }
  }

  // ======== RAGDOLL ========
  startRagdoll(opts = {}) {
    const n = NP;
    const p = this.pts.map((v) => v.clone());
    const prev = p.map((v, i) => v.clone().addScaledVector(this.ptVel[i], -1 / 240));
    const cons = [];
    const add = (a, b, minF = 1, maxF = 1, stiff = 1) => {
      const L = p[a].distanceTo(p[b]);
      cons.push([a, b, L * minF, L * maxF, stiff]);
    };
    const rigid = (arr, s = 1) => { for (let i = 0; i < arr.length; i++) for (let j = i + 1; j < arr.length; j++) add(arr[i], arr[j], 1, 1, s); };
    rigid([P.pelvis, P.hipL, P.hipR, P.abd]);
    rigid([P.abd, P.neck, P.shL, P.shR]);
    add(P.pelvis, P.neck, 0.86, 1.02, 0.6); // spine bend
    add(P.hipL, P.shL, 0.85, 1.08, 0.5); add(P.hipR, P.shR, 0.85, 1.08, 0.5); // spine twist
    add(P.neck, P.head, 1, 1);
    add(P.head, P.shL, 0.75, 1.15, 0.6); add(P.head, P.shR, 0.75, 1.15, 0.6); add(P.head, P.abd, 0.85, 1.1, 0.5);
    // limbs (use anatomical lengths, not current, so they never stretch)
    const d = this.d;
    const lim = (a, b, L) => cons.push([a, b, L, L, 1]);
    lim(P.shL, P.elL, d.uarm); lim(P.elL, P.haL, d.farm); lim(P.shR, P.elR, d.uarm); lim(P.elR, P.haR, d.farm);
    lim(P.hipL, P.knL, d.thigh); lim(P.knL, P.anL, d.shin); lim(P.hipR, P.knR, d.thigh); lim(P.knR, P.anR, d.shin);
    lim(P.anL, P.toeL, d.foot); lim(P.anR, P.toeR, d.foot);
    // joint flex limits
    cons.push([P.shL, P.haL, d.uarm * 0.35, d.uarm + d.farm, 1], [P.shR, P.haR, d.uarm * 0.35, d.uarm + d.farm, 1]);
    cons.push([P.hipL, P.anL, d.thigh * 0.3, d.thigh + d.shin, 1], [P.hipR, P.anR, d.thigh * 0.3, d.thigh + d.shin, 1]);
    cons.push([P.knL, P.toeL, d.shin * 0.75, d.shin + d.foot * 0.75, 0.6], [P.knR, P.toeR, d.shin * 0.75, d.shin + d.foot * 0.75, 0.6]);
    cons.push([P.hipL, P.hipR, d.hipW * 2, d.hipW * 2, 1]);
    cons.push([P.knL, P.knR, 0.08, 1.2, 0.5], [P.anL, P.anR, 0.08, 2, 0.5]);
    // apply impulse
    if (opts.impulse) {
      for (const [idx, vec] of opts.impulse) prev[idx].addScaledVector(vec, -1 / 240);
    }
    this.rag = { p, prev, cons, t: 0, limp: opts.limp ?? 1, fencing: opts.fencing ? 2.4 : 0, fenceSide: Math.random() < 0.5 ? 0 : 1, tone: opts.tone ?? 0 };
    this.mode = 'ragdoll';
  }

  stepRagdoll(dt, cageR, others) {
    const r = this.rag; if (!r) return;
    r.t += dt;
    const p = r.p, prev = r.prev;
    const g = -9.81 * dt * dt;
    for (let i = 0; i < NP; i++) {
      const pi = p[i], pr = prev[i];
      const vx = (pi.x - pr.x) * 0.996, vy = (pi.y - pr.y) * 0.996, vz = (pi.z - pr.z) * 0.996;
      pr.copy(pi);
      pi.x += vx; pi.y += vy + g; pi.z += vz;
    }
    // muscle tone: knockdown (not KO) keeps some posture; fencing response raises arms rigidly
    if (r.fencing > 0) {
      r.fencing -= dt;
      const side = r.fenceSide;
      const sh = p[side === 0 ? P.shL : P.shR], ha = p[side === 0 ? P.haL : P.haR], el = p[side === 0 ? P.elL : P.elR];
      // torso up axis
      _v.subVectors(p[P.neck], p[P.pelvis]).normalize();
      _v2.subVectors(p[P.shL], p[P.shR]).normalize();
      _v3.crossVectors(_v2, _v).normalize(); // forward (chest normal)
      const tgt = _v2.clone().multiplyScalar(0).addScaledVector(_v, 0.35).addScaledVector(_v3, 0.4).add(sh);
      ha.lerp(tgt, 0.12);
      const tgtEl = sh.clone().addScaledVector(_v3, 0.2).addScaledVector(_v, 0.15);
      el.lerp(tgtEl, 0.06);
    }
    if (r.tone > 0) {
      // keep chin tucked & hands toward head (instinctive cover)
      const h = p[P.head];
      for (const hi of [P.haL, P.haR]) p[hi].lerp(h, 0.015 * r.tone);
    }
    // constraints
    const cons = r.cons;
    for (let it = 0; it < 10; it++) {
      for (let c = 0; c < cons.length; c++) {
        const [a, b, mn, mx, st] = cons[c];
        const pa = p[a], pb = p[b];
        let dx = pb.x - pa.x, dy = pb.y - pa.y, dz = pb.z - pa.z;
        const dist = Math.sqrt(dx * dx + dy * dy + dz * dz) || 1e-6;
        let target = dist < mn ? mn : dist > mx ? mx : dist;
        if (target === dist) continue;
        const diff = ((dist - target) / dist) * st;
        const wa = 1 / PMASS[a], wb = 1 / PMASS[b], ws = wa + wb;
        const ka = (diff * wa) / ws, kb = (diff * wb) / ws;
        pa.x += dx * ka; pa.y += dy * ka; pa.z += dz * ka;
        pb.x -= dx * kb; pb.y -= dy * kb; pb.z -= dz * kb;
      }
      // collisions
      for (let i = 0; i < NP; i++) {
        const pi = p[i], rad = PRAD[i];
        if (pi.y < rad) {
          pi.y = rad;
          // friction (mat is grippy)
          const pr = prev[i];
          pr.x = lerp(pr.x, pi.x, 0.35); pr.z = lerp(pr.z, pi.z, 0.35);
          if (pr.y < pi.y - 0.0) pr.y = lerp(pr.y, pi.y, 0.5);
        }
        const rr = Math.hypot(pi.x, pi.z);
        const lim = cageR - rad;
        if (rr > lim) { pi.x *= lim / rr; pi.z *= lim / rr; const pr = prev[i]; pr.x = lerp(pr.x, pi.x, 0.5); pr.z = lerp(pr.z, pi.z, 0.5); }
        if (others) {
          for (const o of others) {
            _v.subVectors(pi, o.c);
            const dd = _v.length(), md = rad + o.r;
            if (dd < md && dd > 1e-5) pi.addScaledVector(_v, (md - dd) / dd * 0.5);
          }
        }
      }
    }
    for (let i = 0; i < NP; i++) this.pts[i].copy(p[i]);
    this.computeSegmentsRag();
  }

  ragdollSpeed() {
    if (!this.rag) return 0;
    let s = 0;
    for (let i = 0; i < NP; i++) s += this.rag.p[i].distanceTo(this.rag.prev[i]);
    return (s / NP) * 240;
  }

  computeSegmentsRag() {
    const pts = this.pts, seg = this.seg, d = this.d;
    const pel = pts[P.pelvis], abd = pts[P.abd], nk = pts[P.neck], hd = pts[P.head];
    // pelvis
    _v.subVectors(abd, pel).normalize();
    _v2.subVectors(pts[P.hipL], pts[P.hipR]);
    _v3.crossVectors(_v2, _v);
    seg[S.pelvis].pos.copy(pel); basisYZ(_v, _v3, seg[S.pelvis].quat);
    seg[S.abdomen].pos.copy(pel).addScaledVector(_v, d.spineBase); basisYZ(_v, _v3, seg[S.abdomen].quat);
    const torsoFwd = _v3.clone().normalize();
    // chest
    _v.subVectors(nk, abd).normalize();
    _v2.subVectors(pts[P.shL], pts[P.shR]);
    _v3.crossVectors(_v2, _v);
    seg[S.chest].pos.copy(abd); basisYZ(_v, _v3, seg[S.chest].quat);
    const chestFwd = _v3.clone().normalize();
    // neck & head
    _v.subVectors(hd, nk).normalize();
    seg[S.neck].pos.copy(nk); basisYZ(_v, chestFwd, seg[S.neck].quat);
    seg[S.head].pos.copy(nk).addScaledVector(_v, d.neck * 0.8); basisYZ(_v, chestFwd, seg[S.head].quat);
    this.headCenter.copy(hd);
    this.headFwd.copy(chestFwd);
    this.limbSegs(torsoFwd);
  }

  // Blend from ragdoll snapshot back to animated pose (for get-ups)
  beginBlendFromRag(dur = 0.5) {
    this.blendSnap = this.seg.map((s) => ({ pos: s.pos.clone(), quat: s.quat.clone() }));
    this.blend = 1; this.blendDur = dur;
    this.mode = 'anim'; this.rag = null;
  }
  applyBlend(dt) {
    if (this.blend <= 0 || !this.blendSnap) return;
    this.blend = Math.max(0, this.blend - dt / this.blendDur);
    const b = this.blend * this.blend * (3 - 2 * this.blend);
    for (let i = 0; i < this.seg.length; i++) {
      this.seg[i].pos.lerp(this.blendSnap[i].pos, b);
      this.seg[i].quat.slerp(this.blendSnap[i].quat, b);
    }
  }

  // Pelvis orientation info of ragdoll: face up?
  ragFaceUp() {
    const pts = this.pts;
    _v.subVectors(pts[P.neck], pts[P.pelvis]).normalize();
    _v2.subVectors(pts[P.shL], pts[P.shR]);
    _v3.crossVectors(_v2, _v).normalize();
    return _v3.y > 0;
  }

  // impulse helpers in anim mode: add angular velocity to a torso spring (Euler rates)
  kick(spring, x, y, z) { spring.v.x += x; spring.v.y += y; spring.v.z += z; }
}

export function angDiff(a, b) {
  let d = a - b;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return d;
}
