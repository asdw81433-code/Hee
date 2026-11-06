// ===== Injury & physiology model =====
// Grounded in MMA injury epidemiology: facial lacerations are the most common injury (~48% in Nevada data),
// followed by hand, nose and eye injuries; concussions ~3% of bouts. Rotational head acceleration (not linear force)
// is treated as the main knockout driver, so hooks/uppercuts to the jaw/chin rotate the head and are far more
// dangerous than straight shots to the forehead (which tend to cut instead). Liver shots cause a delayed collapse;
// accumulated calf kicks can cause peroneal-nerve "dead leg"; swelling around the eyes closes them.
import { clamp, lerp, rng } from './util.js';
import { LM } from './face.js';

let cutSeed = 1;

export class Health {
  constructor(attrs, career = {}) {
    this.a = attrs;
    const A = (k) => (attrs[k] ?? 50) / 100;
    // career-long damage (CTE-like) lowers chin permanently; scar tissue makes cuts reopen easily
    this.brainHistory = career.brainDamage || 0; // 0..100
    this.scarL = career.scarL || 0; this.scarR = career.scarR || 0;
    this.chin = clamp(A('chin') * (1 - this.brainHistory / 160), 0.08, 1);
    this.staminaMax = 100;
    this.stamina = 100;
    this.cardio = A('cardio');
    this.recovery = A('recovery');
    this.heart = A('heart');
    this.composure = A('composure');
    this.consc = 1; // consciousness (1 fine, 0 out)
    this.brain = 0; // trauma accumulated this fight (0..100)
    this.swell = { eyeL: 0, eyeR: 0, cheekL: 0, cheekR: 0, forehead: 0, lip: 0 };
    this.nose = 0; this.noseBroken = false; this.noseDeviation = 0;
    this.jaw = 0; this.jawBroken = false; this.orbitalBroken = false;
    this.cuts = [];
    this.liver = 0; this.ribsL = 0; this.ribsR = 0; this.chestDmg = 0; this.ribCracked = false;
    this.legs = [0, 0]; // thigh/calf damage per leg (index 0 = L, 1 = R)
    this.deadLeg = [false, false];
    this.arms = [0, 0];
    this.handBroken = [false, false];
    this.bloodLoss = 0; // ml
    this.bloodInEye = [0, 0]; // [R,L] screen-space: 0 = right eye, 1 = left eye
    this.adrenaline = 0.4;
    this.pain = 0;
    this.rocked = 0; // seconds remaining
    this.liverDelay = -1; // pending delayed collapse
    this.hitsTaken = 0; this.sigTaken = 0;
    this.redness = 0;
    this.submissionInjury = null;
    this.events = [];
  }

  get visionR() { return clamp(1 - Math.max(0, (this.swell.eyeR - 0.45) / 0.5) - this.bloodInEye[0] * 0.6, 0, 1); }
  get visionL() { return clamp(1 - Math.max(0, (this.swell.eyeL - 0.45) / 0.5) - this.bloodInEye[1] * 0.6, 0, 1); }
  get mobility() {
    const worst = Math.max(this.legs[0], this.legs[1]);
    return clamp(1 - worst / 140 - (this.deadLeg[0] || this.deadLeg[1] ? 0.35 : 0), 0.3, 1);
  }
  get staminaFrac() { return this.stamina / 100; }
  get output() { // general performance multiplier
    return clamp((0.45 + 0.55 * this.stamina / 100) * (0.6 + 0.4 * this.consc) * (1 - this.pain * 0.25), 0.25, 1.05);
  }
  get bleedRate() { let r = 0; for (const c of this.cuts) r += c.rate; return r + (this.noseBleed || 0); }

  // ---- hits ----
  // h: {zone, u, v, power(0..2), rot(rad/s proxy), kind('punch'|'kick'|'elbow'|'knee'), blocked, side(0=L,1=R), counter}
  takeHit(h) {
    const res = { ko: false, knockdown: false, rocked: false, cut: null, nose: false, liver: false, deadLeg: false, fencing: false, blood: 0, dmg: 0 };
    const p = h.power;
    this.hitsTaken++;
    if (h.blocked) {
      if (h.zone === 'arm' || h.zone === 'head' || h.zone === 'body') {
        const ai = h.side ?? 0;
        this.arms[ai] = clamp(this.arms[ai] + p * (h.kind === 'kick' ? 14 : 4), 0, 100);
        this.stamina = Math.max(0, this.stamina - p * 3);
        // big kicks through the guard still rattle the head a bit
        if (h.kind === 'kick' && h.zone === 'head') { this.brain += p * 2; this.consc -= p * 0.05; }
      }
      res.dmg = p * 0.2;
      return res;
    }
    if (p > 0.25) this.sigTaken++;
    this.adrenaline = clamp(this.adrenaline + p * 0.15, 0, 1);
    if (h.zone === 'head') this.headHit(h, res);
    else if (h.zone === 'body') this.bodyHit(h, res);
    else if (h.zone === 'leg') this.legHit(h, res);
    this.redness = clamp(this.redness + p * 0.04, 0, 1);
    res.dmg = p;
    return res;
  }

  headHit(h, res) {
    const p = h.power, u = h.u, v = h.v;
    const rot = h.rot; // normalized rotational intensity (0..~2)
    // --- brain trauma & consciousness ---
    const chin = this.chin * (0.75 + 0.25 * this.consc) * (1 - this.brain / 260) * (this.rocked > 0 ? 0.7 : 1) * (0.85 + this.composure * 0.15);
    const koForce = (rot * 0.75 + p * 0.25) * (h.counter ? 1.35 : 1) * (h.onGround ? 0.8 : 1);
    this.brain = clamp(this.brain + koForce * 7 + p * 2, 0, 100);
    this.consc = clamp(this.consc - koForce * 0.22 / Math.max(chin, 0.15), 0, 1);
    const thrKO = 0.95 + chin * 1.35;
    const roll = 0.85 + rng() * 0.3;
    if (koForce * roll > thrKO || this.consc <= 0.02) {
      res.ko = true; this.consc = 0;
      res.fencing = koForce > thrKO * 1.2 && rng() < 0.55;
    } else if (koForce * roll > thrKO * 0.72 || this.consc < 0.25) {
      res.knockdown = true; this.consc = Math.max(this.consc, 0.15);
      this.rocked = 4 + (1 - this.recovery) * 5;
    } else if (koForce * roll > thrKO * 0.45 || this.consc < 0.5) {
      res.rocked = true;
      this.rocked = Math.max(this.rocked, 2 + koForce * 3 * (1.2 - this.recovery));
    }
    // --- soft tissue & bone by location ---
    const sideL = u > 0.5; // char left side of face
    const cutChance = (base) => {
      const scar = sideL ? this.scarL : this.scarR;
      return base * (h.kind === 'elbow' ? 3.2 : h.kind === 'knee' ? 1.6 : 1) * (1 + scar * 0.5) * p;
    };
    if (v < 0.3) { // forehead / hairline (elbows open these)
      this.swell.forehead += p * 0.08;
      if (rng() < cutChance(0.12)) res.cut = this.addCut(u, v + 0.05, 'forehead', p);
    } else if (v < 0.52) { // brow & eye: classic cut over the eye (supraorbital ridge)
      const k = sideL ? 'eyeL' : 'eyeR';
      this.swell[k] += p * 0.11 * (h.kind === 'punch' ? 1 : 1.3);
      if (rng() < cutChance(0.2)) res.cut = this.addCut(sideL ? LM.browL[0] + (rng() - 0.3) * 0.12 : LM.browR[0] - (rng() - 0.3) * 0.12, LM.browL[1] - 0.005, sideL ? 'browL' : 'browR', p);
      if (this.swell[k] > 1.0 && p > 0.9 && rng() < 0.12) this.orbitalBroken = true;
    } else if (v < 0.7) {
      if (Math.abs(u - 0.5) < 0.13) { // nose
        this.nose += p * 0.25;
        this.noseBleed = clamp((this.noseBleed || 0) + p * 0.14, 0, 0.9);
        res.nose = true;
        if (!this.noseBroken && this.nose > 0.9 && rng() < p * 0.45) {
          this.noseBroken = true; this.noseDeviation = (rng() - 0.5) * 0.5;
          this.noseBleed = 0.9; res.noseBroken = true;
        }
      } else { // cheekbone
        const k = sideL ? 'cheekL' : 'cheekR';
        this.swell[k] += p * 0.1;
        // swelling under the eye also creeps up
        this.swell[sideL ? 'eyeL' : 'eyeR'] += p * 0.04;
        if (rng() < cutChance(0.06)) res.cut = this.addCut(u, v - 0.02, k, p);
      }
    } else if (v < 0.86) { // mouth
      this.swell.lip += p * 0.12;
      if (rng() < cutChance(0.14)) res.cut = this.addCut(0.5 + (rng() - 0.5) * 0.2, 0.79, 'lip', p * 0.8);
    } else { // chin / jaw
      this.jaw += p * 0.12;
      if (!this.jawBroken && this.jaw > 1.2 && rng() < p * 0.08) this.jawBroken = true;
    }
    for (const k in this.swell) this.swell[k] = clamp(this.swell[k], 0, 1.25);
  }

  addCut(u, v, region, p) {
    // existing cut nearby -> deepen/reopen it
    for (const c of this.cuts) {
      if (Math.hypot(c.u - u, c.v - v) < 0.07) {
        c.depth = clamp(c.depth + p * 0.25, 0, 1.2); c.len = clamp(c.len + p * 0.012, 0, 0.12);
        c.rate = clamp(c.rate + p * 0.18, 0, 1.6); c.treated = Math.max(0, c.treated - 0.5);
        return c;
      }
    }
    const c = { u, v, region, len: 0.025 + p * 0.025, depth: clamp(0.2 + p * 0.35, 0, 1), ang: (rng() - 0.5) * 0.7, rate: 0.25 + p * 0.4, seed: cutSeed++, treated: 0, acc: 0 };
    this.cuts.push(c);
    return c;
  }

  bodyHit(h, res) {
    const p = h.power;
    // liver lives on the right side of the body (u<0.5 in our front-torso coordinates = char right)
    const liverSide = h.liverSide;
    if (liverSide) {
      this.liver += p * 18;
      const thr = 55 + (this.a.bodyTough ?? 50) * 0.5;
      if ((this.liver > thr && rng() < p * 0.5) || p > 1.35 + (this.a.bodyTough ?? 50) / 140) {
        // delayed collapse (liver shot): 0.3-1.2 s later
        this.liverDelay = 0.3 + rng() * 0.9; res.liver = true;
      }
    } else if (h.ribSide === 1) this.ribsL += p * 14; else this.ribsR += p * 12;
    this.chestDmg += p * 6;
    if (!this.ribCracked && Math.max(this.ribsL, this.ribsR) > 70 && rng() < p * 0.12) { this.ribCracked = true; res.rib = true; }
    this.pain = clamp(this.pain + p * 0.18, 0, 1);
    // body shots drain the gas tank (diaphragm / solar plexus)
    this.stamina = Math.max(0, this.stamina - p * (h.solar ? 14 : 8));
    this.staminaMax = Math.max(35, this.staminaMax - p * 2.2);
  }

  legHit(h, res) {
    const p = h.power, li = h.side ?? 0;
    const calf = h.calf;
    this.legs[li] = clamp(this.legs[li] + p * (calf ? 15 : 11) * (1.3 - (this.a.legTough ?? 50) / 100), 0, 120);
    this.pain = clamp(this.pain + p * 0.08, 0, 1);
    // peroneal nerve "dead leg"
    if (!this.deadLeg[li] && calf && this.legs[li] > 70 && rng() < p * 0.3) { this.deadLeg[li] = true; res.deadLeg = true; }
    if (this.legs[li] > 95 && p > 0.6 && rng() < 0.35) res.knockdown = true; // leg gives out
  }

  // returns events like 'liverCollapse'
  update(dt, ctx = {}) {
    const ev = [];
    // stamina regeneration: cardio, breathing (broken nose hurts it), pain, adrenaline
    const breathing = this.noseBroken ? 0.75 : 1;
    const regen = (4 + this.cardio * 9) * breathing * (ctx.active ? 0.35 : 1) * (1 - this.pain * 0.3);
    this.stamina = clamp(this.stamina + regen * dt, 0, this.staminaMax);
    // consciousness recovers slowly
    if (this.consc > 0) this.consc = clamp(this.consc + dt * (0.03 + this.recovery * 0.05), 0, 1);
    if (this.rocked > 0) this.rocked = Math.max(0, this.rocked - dt * (0.6 + this.recovery * 0.8));
    this.pain = Math.max(0, this.pain - dt * 0.05);
    this.adrenaline = Math.max(0.2, this.adrenaline - dt * 0.02);
    this.redness = Math.max(this.stamina < 50 ? 0.25 : 0, this.redness - dt * 0.01);
    // bleeding
    for (const c of this.cuts) {
      const eff = c.rate * (1 - c.treated * 0.8) * (ctx.heartRate ?? 1);
      this.bloodLoss += eff * dt * 1.6;
      c.acc += eff * dt;
      // slow natural clotting of small cuts
      c.rate = Math.max(0.05 * c.depth, c.rate - dt * 0.004 * (1.2 - c.depth));
    }
    if (this.noseBleed) { this.bloodLoss += this.noseBleed * dt; this.noseBleed = Math.max(this.noseBroken ? 0.25 : 0, this.noseBleed - dt * 0.012); }
    for (let i = 0; i < 2; i++) this.bloodInEye[i] = Math.max(0, this.bloodInEye[i] - dt * 0.05);
    if (this.liverDelay > 0) {
      this.liverDelay -= dt;
      if (this.liverDelay <= 0) { this.liverDelay = -1; ev.push('liverCollapse'); }
    }
    return ev;
  }

  // Ringside physician assessment (between rounds or on ref call)
  doctorCheck() {
    let worst = 0, reason = '';
    for (const c of this.cuts) {
      const nearEye = c.region === 'browL' || c.region === 'browR';
      const sev = c.depth * (nearEye ? 1.3 : 0.9) + c.len * 5 + (c.rate * (1 - c.treated * 0.8)) * 0.5;
      if (sev > worst) { worst = sev; reason = nearEye ? 'แผลแตกเหนือตาลึกเกินไป เลือดไหลเข้าตา' : 'แผลแตกลึกเกินไป'; }
    }
    const eyeShut = Math.max(this.swell.eyeL, this.swell.eyeR);
    if (eyeShut > 1.05 && eyeShut * 1.1 > worst) { worst = eyeShut * 1.15; reason = 'ตาบวมปิดสนิท มองไม่เห็น'; }
    if (this.orbitalBroken) { worst = Math.max(worst, 1.4); reason = 'กระดูกเบ้าตาแตก'; }
    if (this.jawBroken) { worst = Math.max(worst, 1.5); reason = 'กรามหัก'; }
    return { stop: worst > 1.25 && rng() < (worst - 1.1) * 1.6, severity: worst, reason };
  }

  // corner work between rounds (cutman: pressure + adrenaline 1:1000, Vaseline, Enswell; water)
  corner(opts = {}) {
    for (const c of this.cuts) {
      if (opts.treatCuts) c.treated = clamp(c.treated + 0.6 + (opts.cutmanSkill || 0.5) * 0.3, 0, 1);
      c.rate *= 0.7;
    }
    if (opts.enswell) for (const k in this.swell) this.swell[k] = Math.max(0, this.swell[k] - 0.18);
    if (this.noseBleed) this.noseBleed *= 0.4;
    const rec = 25 + this.cardio * 25 + (opts.water ? 8 : 0);
    this.stamina = Math.min(this.staminaMax, this.stamina + rec);
    this.staminaMax = Math.min(100, this.staminaMax + 6 + this.recovery * 6);
    this.consc = Math.min(1, this.consc + 0.25);
    this.rocked = 0;
    this.pain = Math.max(0, this.pain - 0.25);
    this.bloodInEye = [0, 0];
  }

  // summary for UI
  summary() {
    const out = [];
    for (const c of this.cuts) out.push(`แผลแตก (${({ browL: 'คิ้วซ้าย', browR: 'คิ้วขวา', forehead: 'หน้าผาก', lip: 'ปาก', cheekL: 'โหนกแก้มซ้าย', cheekR: 'โหนกแก้มขวา' })[c.region] || c.region}) ลึก ${Math.round(c.depth * 100)}%`);
    if (this.noseBroken) out.push('จมูกหัก');
    if (this.orbitalBroken) out.push('กระดูกเบ้าตาแตก');
    if (this.jawBroken) out.push('กรามหัก');
    if (this.ribCracked) out.push('ซี่โครงร้าว');
    if (this.swell.eyeL > 0.6) out.push('ตาซ้ายบวม'); if (this.swell.eyeR > 0.6) out.push('ตาขวาบวม');
    if (this.deadLeg[0] || this.deadLeg[1]) out.push('เส้นประสาทขาชา (Dead leg)');
    if (this.legs[0] > 60 || this.legs[1] > 60) out.push('ขาช้ำหนัก');
    if (this.handBroken[0] || this.handBroken[1]) out.push('มือหัก');
    if (this.liver > 60) out.push('ตับช้ำ');
    if (this.brain > 45) out.push('สมองกระทบกระเทือน');
    if (this.submissionInjury) out.push(this.submissionInjury);
    return out;
  }
}
