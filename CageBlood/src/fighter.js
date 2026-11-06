// ===== Fighter: locomotion, footwork, strikes, defence, physical hit reactions =====
import * as THREE from 'three';
import { Rig, makeDims, P, S, angDiff } from './rig.js';
import { FighterModel } from './model.js';
import { SkinFX, FACE_W, FACE_H, mkCanvas, paintFace } from './face.js';
import { Health } from './injury.js';
import { MOVES } from './moves.js';
import { clamp, lerp, smooth, easeIn, bez2, pointSegDist, rng, hashStr } from './util.js';
import { cageClamp, cageDist, CAGE_APOTHEM } from './render.js';

const _a = new THREE.Vector3(), _b = new THREE.Vector3(), _c = new THREE.Vector3(), _d = new THREE.Vector3(), _e = new THREE.Vector3();
const _q = new THREE.Quaternion();
const UP = new THREE.Vector3(0, 1, 0);
const DOWN = new THREE.Vector3(0, -1, 0);

class Pose {
  constructor() {
    this.pOff = new THREE.Vector3(); this.pRot = new THREE.Vector3(); this.abd = new THREE.Vector3(); this.chest = new THREE.Vector3();
    this.neck = new THREE.Vector3(); this.head = new THREE.Vector3();
    this.hand = [new THREE.Vector3(), new THREE.Vector3()]; // world targets
    this.pole = [new THREE.Vector3(), new THREE.Vector3()]; // chest frame
    this.roll = [0, 0];
    this.footLocal = [new THREE.Vector3(), new THREE.Vector3()]; // facing frame
    this.footW = [0, 0];
    this.footPole = [new THREE.Vector3(0.25, 0, 1), new THREE.Vector3(-0.25, 0, 1)];
    this.footPitch = [0, 0];
    this.footYawAdd = [0, 0];
    this.handK = [600, 600];
    this.lookAt = true;
  }
}

export class Fighter {
  constructor(game, profile, opts = {}) {
    this.game = game;
    this.prof = profile;
    this.name = profile.name;
    this.attrs = profile.attrs;
    this.A = (k) => clamp((this.attrs[k] ?? 50) / 100, 0, 1.2);
    this.mir = profile.stance === 'southpaw' ? -1 : 1;
    this.lead = this.mir === 1 ? 0 : 1; this.rear = 1 - this.lead;
    const H = profile.height || 1.78;
    this.u = H / 1.8;
    this.dims = makeDims(H, profile.reachMul || 1, profile.look.muscle ?? 0.5);
    this.rig = new Rig(this.dims);
    let faceCanvas = profile.faceCanvas;
    if (!faceCanvas) {
      faceCanvas = mkCanvas(FACE_W, FACE_H);
      paintFace(faceCanvas.getContext('2d'), profile.look, profile.look.seed || hashStr(profile.name));
    }
    this.fx = new SkinFX(profile.look, faceCanvas, profile.look.tattoo);
    this.model = new FighterModel(this.rig, profile.look, this.fx, { ref: opts.ref, gloveColor: opts.gloveColor, gloveTrim: opts.gloveTrim });
    game.world.scene.add(this.model.group);
    this.health = new Health(this.attrs, profile.careerHealth || {});
    this.isRef = !!opts.ref;
    this.corner = opts.corner || 'red';
    this.pose = new Pose();
    this.state = 'stand';
    this.action = null; this.queued = null;
    this.vel = new THREE.Vector3();
    this.input = Fighter.blankInput();
    this.opp = null;
    this.t = Math.random() * 10;
    this.hitStun = 0; this.blocking = false; this.blockLow = false;
    this.slip = null; this.yawOffset = 0; this.yawVel = 0;
    this.stateT = 0;
    this.stepPhase = 0;
    this.grapple = null; this.gpose = null;
    this.downT = 0; this.getupT = 0;
    this.ko = false;
    this.lastHitT = 0;
    this.headVel = new THREE.Vector3();
    this.stats = Fighter.blankStats();
    this.bloodAcc = 0;
    this.dripAcc = 0; this.sweatAcc = 0;
    this.slowMo = 1;
    this.aiHint = {};
  }
  static blankInput() {
    return { mx: 0, mz: 0, block: false, blockLow: false, strike: null, feint: false, slip: null, duck: false, check: false, clinch: false, shoot: false, sprawl: false, g: {}, sprint: false };
  }
  static blankStats() {
    return { thrown: 0, landed: 0, sigThrown: 0, sigLanded: 0, head: 0, body: 0, leg: 0, kd: 0, tdAtt: 0, td: 0, subAtt: 0, ctrl: 0, dmgDealt: 0, dmgTaken: 0, aggression: 0, cage: 0 };
  }

  setOpponent(o) { this.opp = o; }
  get root() { return this.rig.root; }
  get pos() { return this.rig.root; }
  get standing() { return this.state === 'stand' || this.state === 'strike' || this.state === 'rocked'; }
  get onFeet() { return this.rig.mode === 'anim' && (this.state === 'stand' || this.state === 'clinch' || this.state === 'shoot'); }
  get guardUp() { return this.blocking; }

  placeAt(x, z, yaw) {
    this.rig.placeAt(x, z, yaw);
    this.rig.root.y = this.dims.hipH;
    this.vel.set(0, 0, 0);
    const d = this.dims, F = this.rig.F;
    F.pos.copy(this.rig.root); F.quat.setFromAxisAngle(UP, yaw);
    for (let i = 0; i < 2; i++) {
      const sl = this.stanceFoot(i, _a);
      F.apply(sl, this.rig.feet[i].world); this.rig.feet[i].world.y = d.ankle;
      this.rig.feet[i].yaw = yaw + this.footYawBase(i);
    }
    // settle springs at stance targets
    this.computePose(1 / 60);
    this.writeTargets(true);
    this.rig.solve();
    for (let i = 0; i < 5; i++) { this.computePose(1 / 60); this.writeTargets(true); this.rig.solve(); }
    this.rig.trackVel(1 / 60); this.rig.trackVel(1 / 60);
  }

  stanceFoot(i, out) {
    const u = this.u, lead = i === this.lead;
    const w = 0.13 * u, len = 0.3 * u;
    return out.set((i === 0 ? 1 : -1) * w, 0, lead ? len : -len);
  }
  footYawBase(i) { return i === this.lead ? -this.mir * 0.25 : -this.mir * 0.8; }

  // ================= MAIN STEP (fixed 240 Hz) =================
  step(dt) {
    this.t += dt; this.stateT += dt;
    const rig = this.rig;
    if (rig.mode === 'ragdoll') {
      this.stepRagdoll(dt);
      rig.trackVel(dt);
      return;
    }
    const h = this.health;
    // stiffness: fatigue & brain state make the body heavier and sloppier
    const out = h.output;
    rig.stiff = clamp(0.55 + 0.45 * out, 0.45, 1) * (h.rocked > 0 ? 0.65 : 1) * (this.looseT > 0 ? 0.4 : 1);
    if (this.looseT > 0) this.looseT -= dt;
    rig.legStiff = h.rocked > 0 ? 0.45 : 1;
    if (this.hitStun > 0) this.hitStun -= dt;
    if (this.slip) { this.slip.t += dt; if (this.slip.t > this.slip.dur) this.slip = null; }
    // state machine
    if (this.state === 'grapple' && this.gpose) {
      this.gpose(this, this.pose, dt);
    } else if (this.state === 'down') {
      this.stepDowned(dt);
    } else if (this.state === 'getup') {
      this.stepGetup(dt);
    } else if (this.state === 'idle' || this.state === 'celebrate' || this.state === 'corner') {
      this.stepIdle(dt);
    } else {
      this.stepStanding(dt);
    }
    if (this.state !== 'grapple' && this.state !== 'down' && this.state !== 'getup') this.computePose(dt);
    this.writeTargets(false);
    rig.stepSprings(dt);
    this.stepFeet(dt);
    rig.solve();
    rig.applyBlend(dt);
    rig.trackVel(dt);
    // hit detection
    if (this.action && this.action.type === 'strike' && this.opp) this.checkHit(this.opp);
  }

  // ---------- standing / locomotion ----------
  stepStanding(dt) {
    const h = this.health, inp = this.input, rig = this.rig, opp = this.opp;
    // liver shot delayed collapse
    for (const ev of h.update(dt, { active: !!this.action, heartRate: 1 + (1 - h.stamina / 100) * 0.4 })) {
      if (ev === 'liverCollapse') { this.game.emit('liver', this); this.fall({ kind: 'liver' }); return; }
    }
    // dead leg: putting weight on it can drop you
    for (let i = 0; i < 2; i++) if (h.deadLeg[i] && this.vel.length() > 0.8 && rng() < dt * 0.15) { this.game.emit('legGive', this); this.fall({ kind: 'leg' }); return; }
    // actions from input
    if (this.hitStun <= 0) this.handleInput(dt);
    this.blocking = !!(inp.block && (!this.action || this.action.type !== 'strike')) && this.hitStun < 0.15;
    this.blockLow = this.blocking && inp.blockLow;
    // movement
    const mob = h.mobility * (0.75 + this.A('footwork') * 0.45) * (0.65 + 0.35 * h.output);
    let mx = inp.mx, mz = inp.mz;
    const mag = Math.hypot(mx, mz); if (mag > 1) { mx /= mag; mz /= mag; }
    let spd = (mz >= 0 ? 1.55 : 1.3) * mob;
    if (this.blocking) spd *= 0.55;
    if (this.action && this.action.type === 'strike') spd *= this.action.def.kind === 'kick' ? 0.15 : 0.55;
    if (h.rocked > 0) {
      // drunk legs: drift & stumble
      spd *= 0.6;
      mx += Math.sin(this.t * 2.3) * 0.6 * Math.min(1, h.rocked / 3); mz += Math.cos(this.t * 1.7) * 0.4 * Math.min(1, h.rocked / 3);
    }
    const F = rig.F;
    F.quat.setFromAxisAngle(UP, rig.yaw);
    _a.set(mx * spd * 0.88, 0, mz * spd).applyQuaternion(F.quat);
    const acc = 7.5 * (0.7 + 0.3 * mob) * dt;
    _b.subVectors(_a, this.vel); _b.y = 0;
    const bl = _b.length(); if (bl > acc) _b.multiplyScalar(acc / bl);
    this.vel.add(_b);
    // friction on stagger velocities beyond target
    this.vel.multiplyScalar(1 - dt * 1.5);
    this.integrateRoot(dt);
    this.faceOpponent(dt, 7.5);
    this.stats.aggression += Math.max(0, mz) * dt;
  }

  integrateRoot(dt) {
    const r = this.rig.root;
    r.x += this.vel.x * dt; r.z += this.vel.z * dt;
    // body collision with opponent
    const o = this.opp;
    if (o && o.rig.mode === 'anim' && this.state !== 'grapple' && o.state !== 'grapple' && o.state !== 'down') {
      _a.subVectors(r, o.rig.root); _a.y = 0;
      const d = _a.length(), min = 0.48 * (this.u + o.u) * 0.5;
      if (d < min && d > 1e-4) {
        _a.multiplyScalar((min - d) / d * 0.5);
        r.add(_a);
        // push transfers momentum (pressure)
        const rel = this.vel.dot(_a.normalize());
        if (rel < 0) { this.vel.addScaledVector(_a, -rel * 0.5); o.vel.addScaledVector(_a, rel * 0.4); }
      }
    }
    if (cageClamp(r, 0.28 * this.u)) {
      const n = _b.set(r.x, 0, r.z).normalize();
      const out = this.vel.dot(n); if (out > 0) this.vel.addScaledVector(n, -out);
      this.stats.cage += 0; // tracked by match
    }
  }

  faceOpponent(dt, rate) {
    const rig = this.rig, o = this.opp;
    if (!o) return;
    const tx = o.rig.root.x - rig.root.x, tz = o.rig.root.z - rig.root.z;
    if (tx * tx + tz * tz < 1e-4) return;
    const want = Math.atan2(tx, tz) + this.yawOffset;
    const diff = angDiff(want, rig.yaw);
    const mx = rate * dt * (this.health.rocked > 0 ? 0.5 : 1);
    rig.yaw += clamp(diff, -mx, mx);
    this.yawOffset *= Math.exp(-dt * 2.5);
  }

  handleInput(dt) {
    const inp = this.input;
    const a = this.action;
    if (inp.strike) {
      const id = inp.strike; inp.strike = null;
      if (MOVES[id]) {
        if (!a) this.startStrike(id, inp.feint);
        else if (a.type === 'strike' && (a.phase === 'ret' || (a.phase === 'hold' && a.def.kind === 'punch'))) this.queued = { id, feint: inp.feint };
        else if (!this.queued) this.queued = { id, feint: inp.feint };
      }
    }
    if (inp.slip) {
      const dir = inp.slip; inp.slip = null;
      if (!a || (a.type === 'strike' && a.phase === 'ret')) { this.slip = { dir, t: 0, dur: 0.42, kind: 'slip' }; this.health.stamina -= 1.2; this.slipCount = (this.slipCount || 0) + 1; }
    }
    if (inp.duck) {
      inp.duck = false;
      if (!a || (a.type === 'strike' && a.phase === 'ret')) { this.slip = { dir: 0, t: 0, dur: 0.5, kind: 'duck' }; this.health.stamina -= 1.5; }
    }
    if (inp.check) {
      inp.check = false;
      if (!a) this.action = { type: 'check', t: 0, dur: 0.5 };
    }
    if (inp.clinch) { inp.clinch = false; if (!a && this.game.grapple) this.game.grapple.tryClinch(this); }
    if (inp.shoot) { inp.shoot = false; if (!a && this.game.grapple) this.game.grapple.tryShoot(this); }
    if (inp.sprawl) { inp.sprawl = false; this.sprawlT = 0.45; }
    if (this.sprawlT > 0) this.sprawlT -= dt;
  }

  startStrike(id, feint = false) {
    const def = MOVES[id];
    const h = this.health;
    const isKick = def.kind === 'kick' || def.kind === 'knee';
    const sp = (0.72 + 0.5 * this.A(isKick ? 'kickSpeed' : 'punchSpeed')) * (0.62 + 0.38 * h.output) * (h.stamina < def.stam ? 0.75 : 1);
    const cost = def.stam * (feint ? 0.35 : 1) * (1.15 - this.A('cardio') * 0.3) * (this.isPlayer ? 1 - 0.4 * (this.assist || 0) : 1);
    h.stamina = Math.max(0, h.stamina - cost);
    const hi = def.side === 'lead' ? this.lead : this.rear;
    this.action = {
      type: 'strike', id, def, t: 0, phase: 'wind', feint, hit: false, hi, sp,
      aim: new THREE.Vector3(), start: new THREE.Vector3(), through: new THREE.Vector3(), ctrl: new THREE.Vector3(),
      kStart: new THREE.Vector3(), kChamber: new THREE.Vector3(), kStrike: new THREE.Vector3(), launched: false, missed: true, active: false,
    };
    if (!feint) { this.stats.thrown++; this.stats.sigThrown += def.mass > 0.5 ? 1 : 0; }
    this.cnt = this.cnt || {}; this.cnt[def.kind] = (this.cnt[def.kind] || 0) + 1;
    this.updateAim(this.action, true);
    this.game.emit('swing', this, def);
  }

  // Aim at the opponent's target zone with accuracy error
  updateAim(a, init) {
    const o = this.opp; if (!o) return;
    const def = a.def;
    const acc = this.A('accuracy') * (0.6 + 0.4 * this.health.output);
    const vis = (this.health.visionL + this.health.visionR) * 0.5;
    const err = (1.05 - acc) * 0.07 * (2 - vis) * (this.isPlayer ? 1 - 0.6 * (this.assist || 0) : 1);
    const tgt = _a;
    if (def.zone === 'head') tgt.copy(o.rig.headCenter).add(_b.set(0, -0.03 * o.u, 0));
    else if (def.zone === 'body') {
      // liver hook targets opponent's right side
      o.rig.Af.apply(_b.set(def.path === 'hookLow' ? (def.side === 'lead' ? -this.mir : this.mir) * 0.04 : 0, 0.1 * o.u, 0.06), tgt);
    } else { // leg: opponent's lead leg (calf kick lower)
      const li = o.lead;
      const kn = o.rig.pts[li === 0 ? P.knL : P.knR], hip = o.rig.pts[li === 0 ? P.hipL : P.hipR], an = o.rig.pts[li === 0 ? P.anL : P.anR];
      if (def.calf) tgt.lerpVectors(kn, an, 0.4); else tgt.lerpVectors(hip, kn, 0.6);
    }
    if (init) a.err = new THREE.Vector3((rng() - 0.5) * 2, (rng() - 0.5) * 2, (rng() - 0.5) * 2).multiplyScalar(err);
    a.aim.copy(tgt).add(a.err);
  }

  // ---------- pose composition ----------
  computePose(dt) {
    const p = this.pose, u = this.u, mir = this.mir, rig = this.rig, h = this.health;
    const F = rig.F; F.pos.copy(rig.root); F.quat.setFromAxisAngle(UP, rig.yaw);
    const tired = clamp(1 - h.stamina / 45, 0, 1);
    const breathe = Math.sin(this.t * (1.6 + tired * 2.5)) * (0.01 + tired * 0.03);
    // rhythm: fighters stay loose, small bounce & sway
    const styleBounce = this.prof.style === 'kickboxing' || this.prof.style === 'boxing' ? 1.4 : this.prof.style === 'muaythai' ? 0.7 : 1;
    const bounce = Math.sin(this.t * 4.6) * 0.008 * styleBounce * (1 - tired * 0.6);
    const sway = Math.sin(this.t * 1.3) * 0.025;
    const crouch = (0.075 + (this.prof.style === 'wrestling' ? 0.04 : 0)) * u;
    p.pOff.set(sway * 0.6 * u, -crouch + bounce, -0.015 * u);
    p.pRot.set(0.06, -0.55 * mir, 0);
    p.abd.set(0.06 + tired * 0.08, -0.04 * mir, 0);
    p.chest.set(0.09 + breathe, -0.05 * mir, 0);
    p.neck.set(0.12, 0, 0); p.head.set(0.12 + tired * 0.05, 0, 0);
    for (let i = 0; i < 2; i++) {
      this.stanceFoot(i, p.footLocal[i]); p.footLocal[i].y = this.dims.ankle;
      p.footW[i] = 0; p.footPitch[i] = 0; p.footYawAdd[i] = 0;
      p.footPole[i].set((i === 0 ? 1 : -1) * 0.3, 0, 1);
      p.roll[i] = 0; p.handK[i] = 620;
    }
    // guard hands relative to own head (hands stay with the head when it moves)
    const hc = rig.headCenter;
    const drop = tired * 0.09 * u + (h.rocked > 0 ? 0.08 * u : 0);
    const L = this.lead, R = this.rear;
    F.dir(_a.set(mir * 0.11 * u, -0.05 * u - drop, 0.25 * u), _b); p.hand[L].copy(hc).add(_b);
    F.dir(_a.set(-mir * 0.1 * u, -0.08 * u - drop, 0.13 * u), _b); p.hand[R].copy(hc).add(_b);
    p.pole[L].set(mir * 0.4, -1, -0.15); p.pole[R].set(-mir * 0.4, -1, -0.2);
    p.roll[L] = 0.3; p.roll[R] = 0.3;
    // relaxed (creator close-up): hands down so the face, hair and beard are visible
    if (this.relaxed) {
      F.dir(_a.set(mir * 0.22 * u, -0.5 * u, 0.12 * u), _b); p.hand[L].copy(hc).add(_b);
      F.dir(_a.set(-mir * 0.22 * u, -0.5 * u, 0.08 * u), _b); p.hand[R].copy(hc).add(_b);
    }
    // breathing hand bob
    p.hand[L].y += Math.sin(this.t * 3.1) * 0.012; p.hand[R].y += Math.sin(this.t * 3.1 + 1) * 0.01;
    // block
    if (this.blocking) {
      if (this.blockLow) {
        F.dir(_a.set(mir * 0.06 * u, -0.1 * u, 0.12 * u), _b); p.hand[L].copy(hc).add(_b);
        F.dir(_a.set(-mir * 0.06 * u, -0.1 * u, 0.1 * u), _b); p.hand[R].copy(hc).add(_b);
        p.pole[L].set(mir * 0.1, -1, 0.35); p.pole[R].set(-mir * 0.1, -1, 0.35);
        p.chest.x += 0.25; p.abd.x += 0.12; p.pOff.y -= 0.05 * u;
      } else {
        F.dir(_a.set(mir * 0.075 * u, 0.03 * u, 0.13 * u), _b); p.hand[L].copy(hc).add(_b);
        F.dir(_a.set(-mir * 0.075 * u, 0.03 * u, 0.11 * u), _b); p.hand[R].copy(hc).add(_b);
        p.pole[L].set(mir * 0.15, -1, 0.25); p.pole[R].set(-mir * 0.15, -1, 0.25);
        p.chest.x += 0.12; p.head.x += 0.12;
      }
      p.roll[L] = 1.2; p.roll[R] = 1.2;
    }
    // slips & ducks: move the head off the centerline (knees and waist, not just neck)
    if (this.slip) {
      const s = this.slip, k = Math.sin(clamp(s.t / s.dur, 0, 1) * Math.PI);
      if (s.kind === 'duck') {
        p.pOff.y -= 0.2 * u * k; p.chest.x += 0.35 * k; p.abd.x += 0.25 * k;
      } else {
        const dir = s.dir; // +1 = to own left (+X)
        p.pOff.x += dir * 0.09 * u * k; p.pOff.y -= 0.05 * u * k;
        p.abd.z -= dir * 0.18 * k; p.chest.z -= dir * 0.2 * k; p.chest.x += 0.12 * k;
        p.neck.z -= dir * 0.08 * k;
      }
    }
    // being hurt: rubbery
    if (h.rocked > 0) {
      const r = Math.min(1, h.rocked / 3);
      p.pOff.y -= 0.05 * u * r;
      p.head.x += Math.sin(this.t * 3) * 0.1 * r; p.head.z += Math.sin(this.t * 2.2) * 0.15 * r;
      p.chest.z += Math.sin(this.t * 1.9) * 0.12 * r;
    }
    if (this.sprawlT > 0) {
      const k = Math.sin(clamp(1 - this.sprawlT / 0.45, 0, 1) * Math.PI);
      p.pOff.y -= 0.25 * u * k; p.pOff.z -= 0.15 * u * k; p.chest.x += 0.4 * k;
      for (let i = 0; i < 2; i++) { p.footLocal[i].z -= 0.35 * u * k; }
    }
    if (this.clinch && this.game.grapple) this.game.grapple.clinchHands(this, p);
    // action overlay
    const a = this.action;
    if (a) {
      if (a.type === 'strike') this.poseStrike(a, p, dt);
      else if (a.type === 'check') {
        a.t += dt;
        const k = Math.sin(clamp(a.t / a.dur, 0, 1) * Math.PI);
        const li = this.lead;
        p.footW[li] = k > 0.05 ? 1 : 0;
        p.footLocal[li].set(mir * 0.16 * u, this.dims.ankle + 0.32 * u * k, 0.22 * u);
        p.footPole[li].set(mir * 0.5, 0.3, 1);
        p.pOff.x -= mir * 0.05 * u * k;
        if (a.t > a.dur) { this.action = null; this.replantFoot(li); }
      } else if (a.type === 'scripted' && a.pose) a.pose(this, p, dt);
    }
    // head looks at opponent: compensate accumulated torso yaw
    if (p.lookAt) {
      const torsoYaw = p.pRot.y + p.abd.y + p.chest.y;
      p.neck.y = -torsoYaw * 0.45; p.head.y = -torsoYaw * 0.45;
    }
    if (p.lookAt && this.opp) {
      const dy = this.opp.rig.headCenter.y - rig.headCenter.y;
      const dist = Math.max(0.3, Math.hypot(this.opp.rig.root.x - rig.root.x, this.opp.rig.root.z - rig.root.z));
      p.head.x += clamp(-Math.atan2(dy, dist) * 0.5, -0.4, 0.5);
    }
  }

  poseStrike(a, p, dt) {
    const def = a.def, u = this.u, mir = this.mir, rig = this.rig, F = rig.F;
    a.t += dt * a.sp;
    const tw = def.wind, te = tw + def.ext, th = te + def.hold, tr = th + def.ret;
    let phase = a.t < tw ? 'wind' : a.t < te ? 'ext' : a.t < th ? 'hold' : a.t < tr ? 'ret' : 'done';
    if (a.feint && a.t > tw + def.ext * 0.25 && phase !== 'ret' && phase !== 'done') { a.t = th + def.ret * 0.15; phase = 'ret'; }
    if (a.hit && (phase === 'ext' || phase === 'hold')) { a.t = Math.max(a.t, th); phase = 'ret'; }
    a.phase = phase;
    if (phase === 'done') {
      // missed big strikes leave you off balance (momentum carries on)
      if (!a.hit && !a.feint && def.kind === 'kick' && def.path === 'round') {
        const sk = this.kickSideSign(a);
        this.yawOffset += -sk * 0.25 * def.mass;
      }
      if (def.limb === 'foot' || def.limb === 'knee') this.replantFoot(a.hi);
      this.action = null;
      if (this.queued) { const q = this.queued; this.queued = null; this.startStrike(q.id, q.feint); }
      return;
    }
    if (phase === 'wind') this.updateAim(a, false);
    a.active = !a.feint && ((phase === 'ext' && (a.t - tw) / def.ext > 0.35) || phase === 'hold' || (phase === 'ret' && (a.t - th) / def.ret < 0.25));
    const sWind = clamp(a.t / tw, 0, 1), sExt = clamp((a.t - tw) / def.ext, 0, 1), sRet = clamp((a.t - th) / def.ret, 0, 1);
    // body (kinetic chain): strike weight k
    const k = phase === 'wind' ? 0 : phase === 'ret' ? 1 - smooth(sRet) : 1;
    const kw = phase === 'wind' ? smooth(sWind) : 0;
    const baseYaw = -0.55;
    const windYaw = def.windYaw ?? baseYaw;
    p.pRot.y = mir * (baseYaw + (windYaw - baseYaw) * kw + (def.pelvisYaw - baseYaw) * k);
    p.chest.y += mir * (def.chestYaw || 0) * k;
    p.abd.y += mir * (def.chestYaw || 0) * 0.5 * k;
    F.dir(_a.set(mir * (def.shiftX || 0) * (def.side === 'rear' ? 1 : 0.5) * u, 0, (def.shiftZ || 0) * u), _b);
    p.pOff.x += (def.shiftX || 0) * u * mir * 0.5 * k;
    p.pOff.z += (def.shiftZ || 0) * u * k;
    p.pOff.y -= (def.crouch || 0) * u * Math.max(k, kw);
    p.chest.x += (def.chestPitch || 0) * Math.max(k, kw);
    p.chest.z += mir * (def.chestRoll || 0) * k;
    if (def.windDip) { p.pOff.y -= def.windDip * u * kw; p.pOff.y += (def.rise || 0) * u * k; p.chest.z += (def.side === 'lead' ? -1 : 1) * mir * 0.15 * kw; }
    // feet pivot (rear heel turns for power shots)
    if (def.pivot) p.footYawAdd[this.rear] = mir * def.pivot * k;
    if (def.leadPivot) p.footYawAdd[this.lead] = -mir * def.leadPivot * k;
    const hi = a.hi;
    if (def.limb === 'hand') {
      // hand trajectory in world space
      const guard = p.hand[hi];
      if (phase === 'wind') {
        a.start.copy(rig.pts[hi === 0 ? P.haL : P.haR]);
        if (def.path === 'hook' || def.path === 'hookLow') { F.dir(_a.set((hi === 0 ? 1 : -1) * 0.07 * u, 0, -0.02), _b); p.hand[hi].add(_b); }
        if (def.path === 'upper') { p.hand[hi].y -= 0.12 * u; }
      } else if (phase === 'ext' || phase === 'hold') {
        if (!a.launched) {
          a.launched = true;
          a.start.copy(rig.pts[hi === 0 ? P.haL : P.haR]);
          const dir = _c.subVectors(a.aim, a.start); const len = dir.length(); dir.divideScalar(len || 1);
          a.through.copy(a.aim).addScaledVector(dir, 0.11 * u);
          if (def.path === 'hook' || def.path === 'hookLow') {
            const side = hi === 0 ? 1 : -1;
            F.dir(_a.set(side * 0.5 * u, 0.0, 0.1 * u), _b);
            a.ctrl.lerpVectors(a.start, a.aim, 0.45).add(_b); a.ctrl.y = lerp(a.start.y, a.aim.y, 0.7);
            // hooks travel across: through point continues sideways
            F.dir(_a.set(-side * 0.15 * u, 0, -0.02), _b); a.through.copy(a.aim).add(_b);
          } else if (def.path === 'upper') {
            a.ctrl.lerpVectors(a.start, a.aim, 0.55); a.ctrl.y = Math.min(a.start.y, a.aim.y) - 0.12 * u;
            a.through.copy(a.aim); a.through.y += 0.1 * u;
          } else a.ctrl.lerpVectors(a.start, a.through, 0.5);
        }
        const s = phase === 'hold' ? 1 : Math.pow(sExt, 1.35);
        if (def.path === 'straight') p.hand[hi].lerpVectors(a.start, a.through, s);
        else bez2(p.hand[hi], a.start, a.ctrl, a.through, s);
        p.handK[hi] = 1700;
        const side = hi === 0 ? 1 : -1;
        if (def.path === 'hook' || def.path === 'hookLow') p.pole[hi].set(side * 1, def.path === 'hookLow' ? -0.6 : 0.25, -0.35);
        else if (def.path === 'upper') p.pole[hi].set(side * 0.25, -1, 0.5);
        else p.pole[hi].set(side * 0.55, -1, -0.1);
        p.roll[hi] = (def.roll || 0) * smooth(sExt);
      } else {
        p.handK[hi] = 520;
      }
      // the other hand stays home (protecting the chin)
    } else if (def.limb === 'foot') {
      this.poseKick(a, p, phase, sWind, sExt, sRet, k);
    } else if (def.limb === 'knee') {
      const fi = hi, side = fi === 0 ? 1 : -1;
      p.footW[fi] = phase === 'ret' && sRet > 0.85 ? 0 : 1;
      if (phase === 'wind') p.footLocal[fi].set(side * 0.13 * u, this.dims.ankle + 0.25 * u * sWind, -0.3 * u);
      else if (phase === 'ret') p.footLocal[fi].set(side * 0.13 * u, this.dims.ankle + 0.2 * u * (1 - sRet), lerp(0.1, -0.3, sRet) * u);
      else p.footLocal[fi].set(side * 0.1 * u, this.dims.ankle + 0.42 * u, 0.12 * u);
      p.footPole[fi].set(0, 0.35, 1);
      p.pRot.x -= 0.25 * k; p.chest.x -= 0.1 * k;
      // hands pull the head down (clinch) or frame forward
      if (this.opp) {
        const oh = this.opp.rig.pts[P.neck];
        p.hand[0].lerp(oh, 0.6 * Math.max(k, kw)); p.hand[1].lerp(oh, 0.6 * Math.max(k, kw));
      }
    } else if (def.limb === 'elbow') {
      const side = hi === 0 ? 1 : -1;
      F.dir(_a.set(side * 0.02 * u, 0.06 * u, 0.12 * u), _b); p.hand[hi].copy(rig.headCenter).add(_b);
      p.pole[hi].set(side * 1, 0.15, 0.1);
      p.handK[hi] = 1300;
    }
  }

  kickSideSign(a) { return a.hi === 0 ? 1 : -1; }

  poseKick(a, p, phase, sWind, sExt, sRet, k) {
    const def = a.def, u = this.u, mir = this.mir, rig = this.rig, F = rig.F, fi = a.hi;
    const sk = fi === 0 ? 1 : -1; // x sign of kicking leg
    const ank = this.dims.ankle;
    p.footW[fi] = phase === 'ret' && sRet > 0.9 ? 0 : 1;
    // support foot pivot & weight over it
    const sup = 1 - fi;
    if (def.supportPivot) p.footYawAdd[sup] = -sk * def.supportPivot * Math.max(k, sWind * 0.6);
    p.pOff.x -= sk * 0.07 * u * Math.max(k, sWind);
    if (def.path === 'teep') {
      p.pRot.x -= (def.lean ? -def.lean : 0) * 0; // lean back
      p.pRot.x += def.lean * Math.max(k, 0);
      if (phase === 'wind') p.footLocal[fi].set(sk * 0.1 * u, ank + 0.42 * u * smooth(sWind), 0.05 * u);
      else if (phase === 'ext' || phase === 'hold') {
        F.toLocal(a.aim, _c);
        const s = phase === 'hold' ? 1 : smooth(sExt);
        p.footLocal[fi].set(lerp(sk * 0.1 * u, _c.x, s), lerp(ank + 0.42 * u, Math.max(_c.y - 0.08, ank + 0.3 * u), s), lerp(0.05 * u, _c.z + 0.12 * u, s));
        p.footPitch[fi] = -0.6;
      } else p.footLocal[fi].set(sk * 0.12 * u, ank + 0.35 * u * (1 - sRet), lerp(0.2, 0.3 * (fi === this.lead ? 1 : -1), sRet) * u);
      p.footPole[fi].set(0, 0.4, 1);
      return;
    }
    // roundhouse family
    p.pRot.z += sk * (def.lean || 0) * Math.max(k, sWind * 0.3);
    p.chest.y -= mir * (def.pelvisYaw > 0 ? 0.35 : -0.35) * k * 0.6; // shoulders stay a bit toward the target
    const startZ = fi === this.lead ? 0.3 * u : -0.3 * u;
    const chamber = _d.set(sk * 0.28 * u, ank + def.chamberH * u * 0.6, -0.02 * u);
    if (phase === 'wind') {
      p.footLocal[fi].set(lerp(sk * 0.13 * u, chamber.x, smooth(sWind)), lerp(ank, chamber.y, smooth(sWind)), lerp(startZ, chamber.z, smooth(sWind)));
      p.footPole[fi].set(sk * 0.2, 0.6, 1);
    } else if (phase === 'ext' || phase === 'hold') {
      if (!a.launched) {
        a.launched = true;
        F.toLocal(a.aim, a.kStrike);
        // ankle goes past the target so the shin is the impact surface
        a.kStrike.x += -sk * def.sweep * u; a.kStrike.z += 0.08 * u;
        a.kStrike.y = Math.max(a.kStrike.y, ank + 0.1 * u);
        a.kChamber.copy(chamber);
        a.ctrl.set(sk * 0.55 * u, lerp(chamber.y, a.kStrike.y, 0.7), lerp(chamber.z, a.kStrike.z, 0.6));
      }
      const s = phase === 'hold' ? 1 : Math.pow(sExt, 1.2);
      bez2(p.footLocal[fi], a.kChamber, a.ctrl, a.kStrike, s);
      rig.feet[fi].local.k = 1500;
      p.footPole[fi].set(sk * 0.35, 0.75, 0.55);
      p.footPitch[fi] = 0.5;
    } else {
      rig.feet[fi].local.k = 500;
      // retract: foot comes back to stance
      const back = _e.set(sk * 0.13 * u, ank, startZ);
      p.footLocal[fi].lerpVectors(a.kStrike, back, smooth(sRet));
      p.footLocal[fi].y = lerp(a.kStrike.y, ank, smooth(sRet)) + Math.sin(sRet * Math.PI) * 0.1 * u;
      p.footPole[fi].set(sk * 0.2, 0.4, 1);
    }
    // counterbalance: kicking-side arm swings down/back, other hand guards the face
    const hk = fi; // same side hand
    F.dir(_a.set(sk * 0.32 * u, -0.05 * u, -0.25 * u), _b);
    const swing = _c.copy(rig.pts[P.pelvis]).add(_b); swing.y += 0.15 * u;
    p.hand[hk].lerp(swing, k * 0.85);
    p.pole[hk].set(sk * 0.6, -1, -0.4);
  }

  replantFoot(i) {
    const f = this.rig.feet[i];
    this.rig.footWorld(i, _a);
    const rig = this.rig;
    // current IK end becomes the new planted spot
    const an = rig.pts[i === 0 ? P.anL : P.anR];
    f.world.set(an.x, this.dims.ankle, an.z);
    f.stepping = false;
    f.yaw = rig.yaw + this.footYawBase(i);
    // start foot spring local at current
    rig.F.toLocal(an, f.local.x);
  }

  // ---------- feet: step-and-drag footwork ----------
  stepFeet(dt) {
    const rig = this.rig, p = this.pose, d = this.dims;
    if (this.state === 'grapple' || this.state === 'down' || this.state === 'getup') return;
    const F = rig.F;
    const v = this.vel;
    const fwd = v.x * Math.sin(rig.yaw) + v.z * Math.cos(rig.yaw);
    const lat = v.x * Math.cos(rig.yaw) - v.z * Math.sin(rig.yaw);
    let best = -1, bestScore = 1;
    const anyStep = rig.feet[0].stepping || rig.feet[1].stepping;
    for (let i = 0; i < 2; i++) {
      const f = rig.feet[i];
      if (f.stepping) {
        f.t += dt;
        if (f.t >= f.dur) {
          f.stepping = false; f.world.copy(f.to); f.yaw = f.toYaw;
          this.game.emit('footstep', this, i);
        }
        continue;
      }
      if (p.footW[i] > 0.5 || rig.feet[i].w.x > 0.3) continue;
      // desired position (predict ahead by velocity)
      F.apply(p.footLocal[i], _a); _a.addScaledVector(v, 0.14); _a.y = d.ankle;
      const e = Math.hypot(_a.x - f.world.x, _a.z - f.world.z);
      const ye = Math.abs(angDiff(rig.yaw + this.footYawBase(i) + p.footYawAdd[i], f.yaw));
      let score = e / (0.11 * this.u) + ye / 0.55;
      // ordering: moving forward -> lead foot first; backward -> rear first; lateral -> foot on that side first
      const isLead = i === this.lead;
      if (fwd > 0.25) score *= isLead ? 1.35 : 0.9;
      if (fwd < -0.25) score *= isLead ? 0.9 : 1.35;
      if (Math.abs(lat) > 0.25) score *= ((i === 0 ? 1 : -1) * lat > 0) ? 1.3 : 0.9;
      if (anyStep) score *= 0.5;
      if (score > bestScore) { bestScore = score; best = i; }
    }
    if (best >= 0) {
      const f = rig.feet[best];
      const mob = this.health.mobility;
      f.stepping = true; f.t = 0;
      const urgent = bestScore > 2.5;
      f.dur = clamp((0.2 - this.A('footwork') * 0.05) / (0.7 + 0.3 * mob) * (urgent ? 0.75 : 1), 0.11, 0.3);
      if (this.health.deadLeg[best]) f.dur *= 1.4;
      f.from.copy(f.world);
      F.apply(p.footLocal[best], f.to); f.to.addScaledVector(v, f.dur * 0.8 + 0.08); f.to.y = d.ankle;
      cageClamp(f.to, 0.08);
      f.fromYaw = f.yaw; f.toYaw = rig.yaw + this.footYawBase(best);
      f.lift = (0.035 + Math.min(0.04, v.length() * 0.02)) * this.u;
    }
    // planted feet still pivot in place (heel turn) without stepping
    for (let i = 0; i < 2; i++) {
      const f = rig.feet[i];
      if (!f.stepping && p.footYawAdd[i] !== 0) {
        const want = rig.yaw + this.footYawBase(i) + p.footYawAdd[i];
        f.yaw += angDiff(want, f.yaw) * Math.min(1, dt * 18);
      }
    }
  }

  writeTargets(snap) {
    const rig = this.rig, p = this.pose;
    rig.pelvisOff.t.copy(p.pOff); rig.pelvisRot.t.copy(p.pRot); rig.abdRot.t.copy(p.abd); rig.chestRot.t.copy(p.chest);
    rig.neckRot.t.copy(p.neck); rig.headRot.t.copy(p.head);
    for (let i = 0; i < 2; i++) {
      rig.Cf.toLocal(p.hand[i], rig.hands[i].t);
      rig.poles[i].t.copy(p.pole[i]);
      rig.handRoll[i].t = p.roll[i];
      rig.hands[i].k = p.handK[i];
      const f = rig.feet[i];
      f.local.t.copy(p.footLocal[i]);
      f.w.t = p.footW[i];
      f.pole.copy(p.footPole[i]);
      f.pitch.t = p.footPitch[i];
      if (p.footW[i] > 0.5 && f.w.x < 0.05) {
        // lifting a planted foot: start local spring from its current position
        rig.F.toLocal(rig.pts[i === 0 ? P.anL : P.anR], f.local.x); f.local.v.set(0, 0, 0);
      }
    }
    if (snap) {
      for (const s of [rig.pelvisOff, rig.pelvisRot, rig.abdRot, rig.chestRot, rig.neckRot, rig.headRot, ...rig.hands, ...rig.poles]) { s.x.copy(s.t); s.v.set(0, 0, 0); }
      for (const f of rig.feet) { f.local.x.copy(f.local.t); f.w.x = f.w.t; }
    }
  }

  stepIdle(dt) {
    // walking around / corner: no strikes, stand relaxed
    const inp = this.input;
    const F = this.rig.F;
    F.quat.setFromAxisAngle(UP, this.rig.yaw);
    _a.set(inp.mx * 1.1, 0, inp.mz * 1.1).applyQuaternion(F.quat);
    this.vel.lerp(_a, Math.min(1, dt * 6));
    this.integrateRoot(dt);
    if (this.idleFace !== undefined) this.rig.yaw += angDiff(this.idleFace, this.rig.yaw) * Math.min(1, dt * 4);
    else this.faceOpponent(dt, 3);
    this.health.update(dt, { active: false });
    if (this.state === 'celebrate') {
      // arms raised
    }
  }

  // ================= HITS =================
  checkHit(o) {
    const a = this.action;
    if (!a.active || a.hit || o.rig.mode !== 'anim' && o.state !== 'down') return;
    const def = a.def, rig = this.rig, u = this.u;
    // effector
    let eff, effVel, effR = 0.05 * u, seg = null;
    if (def.limb === 'hand') { eff = a.hi === 0 ? rig.handTipL : rig.handTipR; effVel = rig.ptVel[a.hi === 0 ? P.haL : P.haR]; effR = 0.055 * u; }
    else if (def.limb === 'elbow') { eff = rig.pts[a.hi === 0 ? P.elL : P.elR]; effVel = rig.ptVel[a.hi === 0 ? P.elL : P.elR]; effR = 0.06 * u; }
    else if (def.limb === 'knee') { eff = rig.pts[a.hi === 0 ? P.knL : P.knR]; effVel = rig.ptVel[a.hi === 0 ? P.knL : P.knR]; effR = 0.08 * u; }
    else { // foot: shin segment for roundhouse, foot for teep
      const kn = rig.pts[a.hi === 0 ? P.knL : P.knR], an = rig.pts[a.hi === 0 ? P.anL : P.anR], toe = rig.pts[a.hi === 0 ? P.toeL : P.toeR];
      if (def.path === 'teep') { eff = _e.lerpVectors(an, toe, 0.6); effR = 0.07 * u; }
      else { seg = [kn, an]; eff = _e.lerpVectors(kn, an, 0.6); effR = 0.065 * u; }
      effVel = rig.ptVel[a.hi === 0 ? P.anL : P.anR];
    }
    const or = o.rig, ou = o.u;
    const dist = (c) => seg ? pointSegDist(c, seg[0], seg[1]).d : eff.distanceTo(c);
    const capDist = (p0, p1) => {
      if (seg) { // sample shin points vs capsule
        let m = 1e9;
        for (let i = 0; i <= 3; i++) { _c.lerpVectors(seg[0], seg[1], i / 3); m = Math.min(m, pointSegDist(_c, p0, p1).d); }
        return m;
      }
      return pointSegDist(eff, p0, p1).d;
    };
    const blockMul = o.blocking ? 1.5 : 1;
    // 1) guard (gloves / forearms). A tight, active guard blocks; a loose passive guard only catches some shots
    const zone = def.zone;
    if (zone !== 'leg' && !a.guardPass) {
      for (let s = 0; s < 2; s++) {
        const tip = s === 0 ? or.handTipL : or.handTipR, el = or.pts[s === 0 ? P.elL : P.elR], ha = or.pts[s === 0 ? P.haL : P.haR], sh = or.pts[s === 0 ? P.shL : P.shR];
        const dG = dist(tip) - 0.055 * ou * blockMul, dF = capDist(el, ha) - 0.04 * ou * blockMul, dU = zone === 'body' ? capDist(sh, el) - 0.055 * ou * blockMul : 1;
        if (Math.min(dG, dF, dU) < effR) {
          const tgtC = zone === 'head' ? or.headCenter : or.pts[P.abd];
          const toT = _a.subVectors(tgtC, eff), toA = _b.subVectors(tip, eff);
          if (!(toA.length() < toT.length() + 0.05 * ou || o.blocking)) continue;
          let catchP = 1;
          if (!o.blocking) {
            catchP = 0.18 + o.A('blocking') * 0.32 + (def.kind === 'kick' ? 0.25 : 0) - (def.path === 'hook' ? 0.08 : 0) - (def.path === 'upper' ? 0.12 : 0);
            if (o.state === 'grapple') catchP *= 0.6;
          } else {
            // high guard is beaten by body shots / uppercuts through the middle
            if (zone === 'body' && !o.blockLow) catchP = 0.45;
            if (def.path === 'upper') catchP = 0.55;
          }
          if (rng() < catchP) { this.resolveHit(o, a, 'arm', eff, effVel, true, s); return; }
          a.guardPass = true; a.glance = o.blocking ? 0.55 : 0.8; // got through / around the guard, partially smothered
          break;
        }
      }
    }
    // 2) head
    if (zone === 'head' || def.kind === 'knee' || (zone === 'body' && def.kind === 'kick')) {
      const hr = 0.115 * ou;
      if (dist(or.headCenter) < hr + effR) { this.resolveHit(o, a, 'head', eff, effVel, false); return; }
    }
    // 3) body
    if (zone !== 'leg' || def.kind === 'knee') {
      or.Cf.apply(_d.set(0, 0.15 * ou, 0.02), _c);
      const chestC = _c.clone();
      or.Af.apply(_d.set(0, 0.08 * ou, 0.02), _c);
      if (dist(chestC) < 0.16 * ou + effR || dist(_c) < 0.15 * ou + effR) { this.resolveHit(o, a, 'body', eff, effVel, false); return; }
    }
    // 4) legs
    if (zone === 'leg' || def.kind === 'kick') {
      for (let s = 0; s < 2; s++) {
        const hip = or.pts[s === 0 ? P.hipL : P.hipR], kn = or.pts[s === 0 ? P.knL : P.knR], an = or.pts[s === 0 ? P.anL : P.anR];
        const dT = capDist(hip, kn), dS = capDist(kn, an);
        if (Math.min(dT - 0.08 * ou, dS - 0.06 * ou) < effR) {
          // checked kick: shin-on-shin hurts the kicker
          const checking = o.action && o.action.type === 'check' && s === o.lead;
          this.resolveHit(o, a, 'leg', eff, effVel, checking, s, { calf: dS < dT });
          return;
        }
      }
    }
  }

  resolveHit(o, a, zone, point, effVel, blocked, side, extra = {}) {
    a.hit = true;
    const def = a.def;
    const h = this.health;
    const dir = _a.copy(effVel); const sp = dir.length(); if (sp > 1e-3) dir.divideScalar(sp); else this.rig.F.dir(dir.set(0, 0, 1), dir);
    // relative closing speed along strike direction (counters: opponent walking into it adds speed)
    const rel = _b.copy(effVel).sub(o.vel);
    const closing = Math.max(0, rel.dot(dir));
    const nominal = a.ground ? def.nominal * 0.55 : def.nominal; // short ground-and-pound shots: body weight drops into them
    const eRatio = clamp(Math.pow(closing / nominal, 2), 0, 2.2);
    const isKick = def.kind === 'kick' || def.kind === 'knee';
    const powStat = 0.55 + 0.6 * this.A(isKick ? 'kickPower' : 'punchPower') + this.A('strength') * 0.12;
    const counter = !!(o.action && o.action.type === 'strike' && (o.action.phase === 'ext' || o.action.phase === 'wind')) || o.state === 'shoot';
    let power = eRatio * def.mass * powStat * (0.55 + 0.45 * h.output) * (counter ? 1.25 : 1) * (a.glance || 1);
    // heavier fighters hit harder
    power *= clamp((this.prof.weightKg || 75) / 75, 0.75, 1.5) ** 0.35;
    if (this.isPlayer) power *= 1 + 0.35 * (this.assist || 0); // difficulty assist
    power = clamp(power, 0.02, 2.4);
    if (window.__testLog && window.__hitLog) console.log(`LOG HIT ${def.name} ${zone}${blocked ? '(blk)' : ''} spd=${closing.toFixed(1)}/${def.nominal} pw=${power.toFixed(2)}`);
    const sig = power > 0.3 && !blocked;
    if (!blocked) { this.stats.landed++; if (sig) { this.stats.sigLanded++; this.stats[zone === 'arm' ? 'head' : zone]++; } this.stats.dmgDealt += power; }
    if (zone === 'leg' && blocked) {
      // checked kick: kicker's shin takes damage
      h.legs[a.hi] = clamp(h.legs[a.hi] + power * 9, 0, 120);
      o.health.legs[side] = clamp(o.health.legs[side] + power * 2, 0, 120);
      this.game.emit('checked', this, o);
      this.vel.addScaledVector(dir, -0.6);
      return;
    }
    o.receiveHit(this, { def, zone, point: point.clone(), dir: dir.clone(), power, blocked, side, counter, ...extra });
    // hand injury from punching hard bone (forehead/elbows) at full power
    if (def.kind === 'punch' && zone === 'head' && power > 1.1 && rng() < 0.015) { h.handBroken[a.hi] = true; this.game.emit('handBroken', this); }
    // glove picks up the opponent's blood
    if (def.limb === 'hand' && zone === 'head' && !blocked) this.model.gloveBlood = clamp(this.model.gloveBlood + o.faceWetness * 0.3, 0, 1);
  }

  get faceWetness() { return clamp(this.health.cuts.reduce((s, c) => s + c.rate, 0) * 0.4 + (this.health.noseBleed || 0) * 0.5, 0, 1); }

  receiveHit(att, hit) {
    const rig = this.rig, h = this.health, u = this.u;
    const { def, zone, point, dir, blocked } = hit;
    let power = hit.power * (this.isPlayer ? 1 - 0.35 * (this.assist || 0) : 1); // difficulty assist
    this.lastHitT = this.game.time;
    if (rig.mode === 'ragdoll') {
      // hitting a downed/ragdolled body
      if (rig.rag) {
        const idx = zone === 'head' ? P.head : P.abd;
        rig.rag.prev[idx].addScaledVector(dir, -power * 0.012);
      }
    }
    // impact info for face
    let u0 = 0.5, v0 = 0.5, rot = 0;
    if (zone === 'head') {
      const hs = rig.seg[S.head];
      _q.copy(hs.quat).invert();
      const local = _c.copy(point).sub(hs.pos).applyQuaternion(_q);
      const { hw, hh } = this.model.headDims;
      u0 = clamp(0.5 + local.x / hw, 0.02, 0.98); v0 = clamp(1 - local.y / hh, 0.02, 0.98);
      // rotational intensity: lever arm x direction
      const r = _d.subVectors(point, rig.headCenter);
      const tq = _e.crossVectors(r, dir);
      rot = (tq.length() / (0.11 * u)) * power * (v0 > 0.82 ? 1.25 : 1) * (Math.abs(u0 - 0.5) > 0.4 ? 1.15 : 1);
      // neck strength & bracing (seeing it coming) reduce head rotation
      const braced = this.blocking ? 0.75 : 1;
      rot *= braced * (1.1 - this.A('strength') * 0.2);
      if (!blocked) {
        // physical head snap: angular velocity in head-local frame
        const w = _e.copy(tq).normalize().multiplyScalar(Math.min(rot, 2) * 22).applyQuaternion(_q);
        rig.headRot.v.x += w.x; rig.headRot.v.y += w.y; rig.headRot.v.z += w.z;
        rig.neckRot.v.x += w.x * 0.6; rig.neckRot.v.y += w.y * 0.6; rig.neckRot.v.z += w.z * 0.6;
        rig.chestRot.v.x += w.x * 0.15; rig.chestRot.v.z += w.z * 0.15;
      }
    }
    const res = h.takeHit({ zone: zone === 'arm' ? 'head' : zone, u: u0, v: v0, power, rot, kind: def.kind, blocked: blocked || zone === 'arm', side: hit.side, counter: hit.counter,
      liverSide: zone === 'body' && this.localX(point, S.abdomen) < -0.02 * u, ribSide: this.localX(point, S.chest) > 0 ? 1 : 0, solar: def.path === 'teep' || def.kind === 'knee', calf: hit.calf, onGround: this.state === 'grapple' || this.state === 'down' });
    att.stats.dmgDealt += 0;
    this.stats.dmgTaken += power;
    // physical push (momentum transfer)
    const push = blocked || zone === 'arm' ? 0.55 : 0.9;
    const mRatio = clamp((att.prof.weightKg || 75) / (this.prof.weightKg || 75), 0.6, 1.6);
    if (this.rig.mode === 'anim' && this.state !== 'grapple') {
      this.vel.addScaledVector(_a.set(dir.x, 0, dir.z), power * push * mRatio * (def.push || 1) * 1.1);
      // body reaction
      if (zone === 'body') { rig.abdRot.v.x += 7 * power; rig.chestRot.v.x += 5 * power; rig.pelvisOff.v.z -= 0.5 * power; }
      if (zone === 'leg') {
        rig.pelvisOff.v.y -= 1.8 * power; rig.pelvisRot.v.z += (hit.side === 0 ? 1 : -1) * 4 * power;
        // knock the leg out of position (sweep effect)
        const f = rig.feet[hit.side];
        if (!f.stepping) { f.world.addScaledVector(_a.set(dir.x, 0, dir.z), 0.08 * power); }
      }
      if (zone === 'arm' || blocked) {
        const s = hit.side ?? 0;
        rig.hands[s].v.addScaledVector(dir, 3 * power);
        if (def.kind === 'kick' && zone !== 'leg') rig.chestRot.v.z += (s === 0 ? -1 : 1) * 3 * power;
      }
    }
    this.hitStun = Math.max(this.hitStun, blocked ? 0.06 + power * 0.06 : 0.08 + power * 0.18);
    // big shots make the body go briefly loose (partial ragdoll feel): springs weaken, momentum carries the body
    if (!blocked && power > 0.55) this.looseT = Math.max(this.looseT || 0, 0.18 + power * 0.22);
    // interrupt own strike if hit hard
    if (!blocked && power > 0.35 && this.action && this.action.type === 'strike' && this.action.phase !== 'ret') {
      if (this.action.def.limb === 'foot' || this.action.def.limb === 'knee') {
        // caught on one leg -> big balance problem
        if (power > 0.6 && rng() < 0.5) { this.replantFoot(this.action.hi); this.action = null; this.fall({ kind: 'trip', dir, power }); }
        else { this.replantFoot(this.action.hi); this.action = null; }
      } else this.action = null;
      this.queued = null;
    }
    // ---- blood ----
    this.game.onImpact(att, this, { zone, point, dir, power, blocked: blocked || zone === 'arm', u: u0, v: v0, def, res });
    // ---- outcomes ----
    if (res.ko) {
      att.stats.kd++;
      this.ko = true;
      this.fall({ kind: 'ko', dir, power, fencing: res.fencing });
      this.game.emit('ko', this, att, def);
    } else if (res.knockdown || (zone === 'leg' && res.knockdown)) {
      att.stats.kd++;
      this.fall({ kind: zone === 'leg' ? 'leg' : 'kd', dir, power });
      this.game.emit('knockdown', this, att, def);
    } else if (res.rocked) {
      this.game.emit('rocked', this, att);
    }
    if (res.cut) this.game.emit('cut', this, res.cut);
    if (res.noseBroken) this.game.emit('noseBroken', this);
    if (res.deadLeg) this.game.emit('deadLeg', this);
    if (res.liver) this.game.emit('liverHit', this);
    // balance: big pushes topple
    if (this.rig.mode === 'anim' && this.state !== 'grapple' && this.state !== 'down') {
      const sp = Math.hypot(this.vel.x, this.vel.z);
      const stab = 2.6 + this.A('strength') * 1.2 + this.health.mobility - (this.health.rocked > 0 ? 1.2 : 0) - (this.action && this.action.def && this.action.def.limb === 'foot' ? 1.4 : 0);
      if (sp > stab) this.fall({ kind: 'trip', dir, power });
    }
    this.model.setInjuryVisuals(h);
    this.fx.setDamage(this.damageView());
  }

  localX(point, si) {
    const s = this.rig.seg[si];
    _q.copy(s.quat).invert();
    return _c.copy(point).sub(s.pos).applyQuaternion(_q).x;
  }

  damageView() {
    const h = this.health;
    return { swell: h.swell, cuts: h.cuts, nose: clamp(h.nose, 0, 1), noseBroken: h.noseBroken, noseDeviation: h.noseDeviation, redness: h.redness, liver: h.liver / 100, ribsL: h.ribsL / 100, chest: h.chestDmg / 100 };
  }

  // ================= FALLING / RAGDOLL =================
  fall(opts) {
    const rig = this.rig;
    if (rig.mode === 'ragdoll') return;
    if (this.grapple && this.game.grapple) this.game.grapple.release(this);
    this.action = null; this.queued = null; this.slip = null;
    const imp = [];
    const dir = opts.dir || _a.set(0, 0, -1);
    const pw = opts.power || 0.5;
    // carry body momentum into ragdoll + extra head impulse
    const bodyV = this.vel.clone();
    for (let i = 0; i < 18; i++) imp.push([i, bodyV.clone().multiplyScalar(1)]);
    if (opts.kind === 'ko' || opts.kind === 'kd') imp.push([P.head, dir.clone().multiplyScalar(2.5 + pw * 2.5)]);
    if (opts.kind === 'liver') imp.push([P.abd, new THREE.Vector3(0, -1, 0)]);
    const limp = opts.kind === 'ko' ? 1 : 0.6;
    rig.startRagdoll({ impulse: imp, fencing: opts.fencing, limp, tone: ['ko', 'limp', 'grab'].includes(opts.kind) ? 0 : 1 });
    this.state = 'ragdoll';
    this.fallKind = opts.kind;
    this.stateT = 0;
    this.vel.set(0, 0, 0);
    if (opts.kind === 'liver') { this.health.pain = 1; }
    this.game.emit('fall', this, opts.kind);
  }

  stepRagdoll(dt) {
    const rig = this.rig;
    const others = [];
    if (this.opp && this.opp.rig.mode === 'anim') {
      const o = this.opp.rig;
      others.push({ c: o.pts[P.abd], r: 0.17 * this.opp.u }, { c: o.pts[P.pelvis], r: 0.16 * this.opp.u }, { c: o.headCenter, r: 0.12 * this.opp.u });
    }
    rig.stepRagdoll(dt, CAGE_APOTHEM - 0.05, others);
    this.health.update(dt, { active: false });
    // blood smears on the mat as the body slides
    if (rig.rag && (this.health.bleedRate > 0.1 || this.game.world)) {
      for (const idx of [P.head, P.abd, P.pelvis]) {
        const p = rig.rag.p[idx], pr = rig.rag.prev[idx];
        if (p.y < 0.16) this.game.world.smearStain(p.x, p.z, p.x - pr.x, p.z - pr.z, 0.1);
      }
    }
    rig.root.copy(rig.pts[P.pelvis]);
    // recovery (not for KO)
    if (rig.grab || this.holdRag) this.stateT = Math.min(this.stateT, 0.5);
    if (!this.ko && this.stateT > (this.fallKind === 'liver' ? 3.2 : this.fallKind === 'trip' ? 0.9 : 1.6) && rig.ragdollSpeed() < 0.5) {
      this.toDowned();
    }
  }

  // switch from ragdoll to animated "downed" pose (on the back or on knees)
  toDowned() {
    const rig = this.rig;
    const faceUp = rig.ragFaceUp();
    const pel = rig.pts[P.pelvis], head = rig.pts[P.head];
    // facing frame: head toward -Z
    const dx = pel.x - head.x, dz = pel.z - head.z;
    const yaw = Math.atan2(dx, dz);
    rig.beginBlendFromRag(0.45);
    rig.root.set(pel.x, 0, pel.z);
    rig.yaw = faceUp ? yaw : yaw + Math.PI;
    this.state = 'down'; this.stateT = 0;
    this.downFaceUp = faceUp;
    this.downT = 0;
    this.downPose(this.pose);
    this.writeTargets(true);
    rig.solve();
    rig.applyBlend(0);
    this.game.emit('downed', this);
  }

  downPose(p) {
    const u = this.u, ank = this.dims.ankle;
    if (this.downFaceUp) {
      // lying on back, propped on elbows, knees up (realistic defensive downed position)
      p.pOff.set(0, 0.13 - this.dims.hipH * 0 + 0, 0);
      p.pRot.set(-1.25, 0, 0); p.abd.set(0.25, 0, 0); p.chest.set(0.3, 0, 0); p.neck.set(0.3, 0, 0); p.head.set(0.2, 0, 0);
      p.footLocal[0].set(0.18 * u, ank + 0.02, 0.55 * u); p.footLocal[1].set(-0.18 * u, ank + 0.02, 0.45 * u);
      p.footPole[0].set(0.3, 1, 0.3); p.footPole[1].set(-0.3, 1, 0.3);
      p.footW[0] = p.footW[1] = 1;
      const F = this.rig.F; F.pos.copy(this.rig.root); F.quat.setFromAxisAngle(UP, this.rig.yaw);
      F.apply(_a.set(0.12 * u, 0.55 * u, 0.25 * u), p.hand[0]); F.apply(_a.set(-0.12 * u, 0.55 * u, 0.25 * u), p.hand[1]);
      p.pole[0].set(0.5, -0.5, -1); p.pole[1].set(-0.5, -0.5, -1);
    } else {
      // on hands and knees (turtle)
      p.pOff.set(0, 0.48 * u, 0);
      p.pRot.set(1.35, 0, 0); p.abd.set(0.1, 0, 0); p.chest.set(0.1, 0, 0); p.neck.set(-0.2, 0, 0); p.head.set(-0.5, 0, 0);
      p.footLocal[0].set(0.15 * u, ank, -0.5 * u); p.footLocal[1].set(-0.15 * u, ank, -0.5 * u);
      p.footPole[0].set(0, -0.3, 1); p.footPole[1].set(0, -0.3, 1);
      p.footW[0] = p.footW[1] = 1;
      const F = this.rig.F; F.pos.copy(this.rig.root); F.quat.setFromAxisAngle(UP, this.rig.yaw);
      F.apply(_a.set(0.15 * u, 0.05, 0.55 * u), p.hand[0]); F.apply(_a.set(-0.15 * u, 0.05, 0.55 * u), p.hand[1]);
      p.pole[0].set(0.3, 0, -1); p.pole[1].set(-0.3, 0, -1);
    }
    p.lookAt = false;
    for (let i = 0; i < 2; i++) { p.footYawAdd[i] = 0; p.roll[i] = 0; p.handK[i] = 500; p.footPitch[i] = 0; }
  }

  stepDowned(dt) {
    this.downT += dt;
    const h = this.health;
    h.update(dt, { active: false });
    this.downPose(this.pose);
    this.pose.lookAt = false;
    // protect face if opponent near
    if (this.opp && this.opp.rig.root.distanceTo(this.rig.root) < 1.6 && this.downFaceUp) {
      const hc = this.rig.headCenter;
      this.pose.hand[0].copy(hc).add(_a.set(0.05, 0.12, 0)); this.pose.hand[1].copy(hc).add(_a.set(-0.05, 0.12, 0));
    }
    const wantUp = this.downT > 1.2 + (1 - this.A('recovery')) * 1.6 + h.rocked * 0.3;
    if (wantUp && (!this.opp || this.opp.state !== 'grapple')) this.beginGetup();
  }

  beginGetup() {
    this.state = 'getup'; this.getupT = 0; this.stateT = 0;
    this.game.emit('getup', this);
  }
  // technical stand-up: sit up -> post hand -> rise -> stance
  stepGetup(dt) {
    this.getupT += dt;
    const p = this.pose, u = this.u, rig = this.rig, F = rig.F;
    this.health.update(dt, { active: false });
    const T = 1.3;
    const s = clamp(this.getupT / T, 0, 1);
    F.pos.copy(rig.root); F.quat.setFromAxisAngle(UP, rig.yaw);
    if (s < 1) {
      this.downPose(p);
      const k = smooth(s);
      // blend to stance
      const ank = this.dims.ankle;
      const standY = this.dims.hipH - 0.08 * u;
      p.pOff.y = lerp(this.downFaceUp ? 0.13 : 0.48 * u, standY, k);
      p.pRot.x = lerp(this.downFaceUp ? -1.25 : 1.35, 0.06, smooth(clamp(s * 1.3, 0, 1)));
      p.abd.x = lerp(p.abd.x, 0.06, k); p.chest.x = lerp(p.chest.x, 0.1, k); p.head.x = lerp(p.head.x, 0.1, k); p.neck.x = lerp(p.neck.x, 0.1, k);
      for (let i = 0; i < 2; i++) {
        this.stanceFoot(i, _a); _a.y = ank;
        p.footLocal[i].lerp(_a, k);
        p.footW[i] = 1;
        p.footPole[i].set((i === 0 ? 1 : -1) * 0.3, 0, 1);
      }
      F.apply(_a.set(0.2 * u, 1.3 * u, 0.25 * u), _b); p.hand[0].lerp(_b, k); F.apply(_a.set(-0.2 * u, 1.3 * u, 0.2 * u), _b); p.hand[1].lerp(_b, k);
      // root rises (root y is the pelvis reference when standing)
      rig.root.y = 0;
    } else {
      // finish: convert to standing control
      rig.root.y = this.dims.hipH;
      for (let i = 0; i < 2; i++) {
        const f = rig.feet[i];
        F.apply(this.stanceFoot(i, _a), f.world); f.world.y = this.dims.ankle; f.yaw = rig.yaw + this.footYawBase(i); f.stepping = false;
      }
      // pelvisOff was relative to y=0; convert
      rig.pelvisOff.x.y -= this.dims.hipH; rig.pelvisOff.t.y -= this.dims.hipH;
      this.state = 'stand'; this.stateT = 0;
      this.computePose(dt);
      this.game.emit('up', this);
    }
  }

  // ================= PER-FRAME (render rate): blood flow, sweat, visuals =================
  frame(dt) {
    const rig = this.rig, h = this.health, fx = this.fx;
    this.model.update(dt);
    const hs = rig.seg[S.head];
    _q.copy(hs.quat).invert();
    const gHead = _a.copy(DOWN).applyQuaternion(_q);
    const cs = rig.seg[S.chest];
    const gTorso = _b.copy(DOWN).applyQuaternion(_q.copy(cs.quat).invert());
    const self = this;
    const { hw, hh, hd } = this.model.headDims;
    const faceToWorld = (u, v, out) => out.set((u - 0.5) * hw, (1 - v) * hh, hd * 0.5 + 0.005).applyQuaternion(hs.quat).add(hs.pos);
    // spawn rivulets from bleeding cuts
    const faceDown = gHead.z > 0.65; // gravity points out of the face => face toward floor
    for (const c of h.cuts) {
      if (c.acc > 0.22) {
        const vol = Math.min(c.acc, 1.2);
        c.acc = 0;
        if (faceDown) {
          // drips straight off the wound
          faceToWorld(c.u, c.v, _c);
          this.game.blood.spawn(_c, _d.set((Math.random() - 0.5) * 0.2, -0.3, (Math.random() - 0.5) * 0.2), vol * 0.25);
        } else {
          // streams start from a few points along the wound and follow the same channels
          c.ch = c.ch || [0, 1, 2].map(() => (Math.random() - 0.5) * c.len * FACE_W * 0.8);
          fx.addRivulet(c.u * FACE_W + c.ch[Math.floor(Math.random() * 3)] + (Math.random() - 0.5) * 1.5, c.v * FACE_H + 2, vol * 2.2);
        }
      }
    }
    if (h.noseBleed > 0.02) {
      this.dripAcc += h.noseBleed * dt;
      if (this.dripAcc > 0.2) {
        const vol = this.dripAcc; this.dripAcc = 0;
        const side = Math.random() < 0.5 ? 0.46 : 0.54;
        if (faceDown) { faceToWorld(side, 0.66, _c); this.game.blood.spawn(_c, _d.set(0, -0.2, 0), vol * 0.25); }
        else fx.addRivulet(side * FACE_W + (Math.random() - 0.5) * 2, 0.67 * FACE_H, vol * 2.2);
      }
      // heavy breathing sprays blood mist from a broken nose
      if (h.noseBroken && h.stamina < 40 && Math.random() < dt * 0.6) {
        faceToWorld(0.5, 0.68, _c); rig.Hf.dir(_d.set(0, -0.2, 1), _d);
        this.game.blood.spray(_c, _d.normalize(), 6, 1.5, 0.3, 0.05);
      }
    }
    fx.flow(dt, gHead, gTorso, (u, v, vol) => {
      // upright: much of it runs down the neck onto the chest; otherwise drips off the chin / jaw
      if (v > 0.98 && gHead.y < -0.55 && Math.random() < 0.55) { fx.torsoSplat(0.25 + (u - 0.5) * 0.12, 0.01, 1.5, vol * 1.5); return; }
      faceToWorld(clamp(u, 0, 1), clamp(v, 0, 1), _c);
      const n = vol > 0.3 ? 2 : 1;
      for (let i = 0; i < n; i++) self.game.blood.spawn(_c, _d.copy(rig.ptVel[P.head]).multiplyScalar(0.5).add(_e.set((Math.random() - 0.5) * 0.1, -0.1, (Math.random() - 0.5) * 0.1)), vol * 0.35 / n);
    }, (side, amt) => { h.bloodInEye[side] = clamp(h.bloodInEye[side] + amt * 0.8, 0, 1); });
    // sweat flicks off when moving fast later in the fight
    const sweatLevel = clamp((this.game.match ? this.game.match.elapsed : 0) / 300, 0, 1) * 0.6 + (1 - h.stamina / 100) * 0.4;
    const hv = rig.ptVel[P.head].length();
    if (hv > 2.2 && Math.random() < sweatLevel * dt * 25) {
      this.game.blood.spray(rig.headCenter, _d.copy(rig.ptVel[P.head]).normalize(), 3, hv * 0.5, 0.5, 0.06, 'sweat');
    }
    fx.update();
  }

  // drops landing on this fighter get painted onto skin
  paintBlood(p, vol, kind, v) {
    if (kind !== 'blood') return false;
    const rig = this.rig;
    // head
    const hs = rig.seg[S.head];
    const { hw, hh, hd } = this.model.headDims;
    if (p.distanceTo(rig.headCenter) < 0.2 * this.u) {
      _q.copy(hs.quat).invert();
      const l = _c.copy(p).sub(hs.pos).applyQuaternion(_q);
      if (Math.abs(l.x) < hw * 0.55 && l.y > -0.02 && l.y < hh * 1.05 && Math.abs(l.z) < hd * 0.6) {
        if (l.z > hd * 0.2) this.fx.splat(0.5 + l.x / hw, 1 - l.y / hh, 1.5 + vol * 20);
        return true;
      }
    }
    // torso (chest + abdomen boxes)
    for (const [si, len, v0, v1] of [[S.chest, this.dims.chest, 0, 0.6], [S.abdomen, this.dims.abd, 0.6, 1]]) {
      const s = rig.seg[si];
      _q.copy(s.quat).invert();
      const l = _c.copy(p).sub(s.pos).applyQuaternion(_q);
      const halfW = this.dims.shW * 0.95, halfD = 0.12 * this.u;
      if (Math.abs(l.x) < halfW && l.y > 0 && l.y < len && Math.abs(l.z) < halfD) {
        const vv = v0 + (1 - l.y / len) * (v1 - v0);
        if (l.z > 0) this.fx.torsoSplat((0.5 + l.x / (halfW * 2)) * 0.5, vv, 1.2 + vol * 18, vol * 4);
        else this.fx.torsoSplat(0.5 + (0.5 - l.x / (halfW * 2)) * 0.5, vv, 1.2 + vol * 18, vol * 4);
        return true;
      }
    }
    return false;
  }

  // hit volumes for referee/others
  dispose() {
    this.game.world.scene.remove(this.model.group);
    this.model.dispose();
    this.fx.dispose();
  }
}
