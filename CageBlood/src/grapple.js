// ===== Grappling: clinch, takedowns, sprawl, ground positions, ground & pound, submissions =====
import * as THREE from 'three';
import { P, S } from './rig.js';
import { clamp, lerp, smooth, rng } from './util.js';
import { cageClamp, cageDist } from './render.js';

const _a = new THREE.Vector3(), _b = new THREE.Vector3(), _c = new THREE.Vector3();
const UP = new THREE.Vector3(0, 1, 0);
const sig = (x) => 1 / (1 + Math.exp(-x));

export const POS_NAMES = { guard: 'การ์ดปิด (Closed Guard)', half: 'ฮาล์ฟการ์ด (Half Guard)', side: 'ไซด์คอนโทรล (Side Control)', mount: 'เมาท์ (Full Mount)', back: 'คุมหลัง (Back Control)' };
const ORDER = ['guard', 'half', 'side', 'mount', 'back'];
export const SUBS = {
  rnc: { name: 'Rear-Naked Choke', choke: true, from: 'back', who: 'top' },
  armTri: { name: 'Arm-Triangle Choke', choke: true, from: 'side', who: 'top' },
  kimura: { name: 'Kimura', choke: false, from: 'side', who: 'top' },
  armbar: { name: 'Armbar', choke: false, from: 'mount', who: 'top' },
  triangle: { name: 'Triangle Choke', choke: true, from: 'guard', who: 'bottom' },
  guardArmbar: { name: 'Armbar (จากการ์ด)', choke: false, from: 'guard', who: 'bottom' },
  halfKimura: { name: 'Kimura (จากฮาล์ฟ)', choke: false, from: 'half', who: 'bottom' },
  guillotine: { name: 'Guillotine Choke', choke: true, from: 'front', who: 'top' },
};

export class Grapple {
  constructor(game) {
    this.game = game;
    this.link = null;
    this.idleT = 0;
  }
  get active() { return !!this.link; }
  A(f, k) { return f.A(k); }
  stam(f) { return 0.55 + 0.45 * f.health.stamina / 100; }

  // ---------------- clinch ----------------
  tryClinch(f) {
    const o = f.opp;
    if (this.link || !o || !o.onFeet || o.state !== 'stand' || f.state !== 'stand') return false;
    const d = f.rig.root.distanceTo(o.rig.root);
    if (d > 1.0 * f.u) { this.game.emit('whiff', f, 'clinch'); return false; }
    const off = this.A(f, 'clinch') * 0.8 + this.A(f, 'strength') * 0.3 + (o.health.rocked > 0 ? 0.4 : 0);
    const def = this.A(o, 'clinch') * 0.5 + this.A(o, 'footwork') * 0.3 + (o.action ? -0.2 : 0);
    f.health.stamina -= 3;
    if (rng() < sig((off - def) * 3.5 + 0.6)) {
      this.link = { type: 'clinch', a: f, b: o, t: 0, ctrl: 0.3, quiet: 0 };
      f.clinch = this.link; o.clinch = this.link;
      f.action = null; o.action = null;
      this.game.emit('clinch', f, o);
      return true;
    }
    this.game.emit('clinchFail', f, o);
    return false;
  }

  // ---------------- takedown shot ----------------
  tryShoot(f) {
    const o = f.opp;
    if (!o || f.action || f.state !== 'stand') return false;
    if (this.link && this.link.type === 'clinch') return this.clinchTakedown(f);
    if (this.link) return false;
    const self = this;
    f.health.stamina -= 6;
    f.stats.tdAtt++;
    f.state = 'shoot';
    f.action = {
      type: 'scripted', name: 'shoot', t: 0, resolved: false,
      pose(fi, p, dt) {
        const a = fi.action; a.t += dt;
        const k = smooth(clamp(a.t / 0.22, 0, 1));
        const u = fi.u;
        p.pOff.y -= 0.36 * u * k; p.pOff.z += 0.12 * u * k;
        p.pRot.x += 0.55 * k; p.pRot.y = lerp(p.pRot.y, 0, k); p.chest.x += 0.35 * k; p.abd.x += 0.2 * k; p.head.x -= 0.5 * k; p.chest.y *= 1 - k; p.abd.y *= 1 - k;
        // penetration step: lead knee drops toward the mat
        p.footLocal[fi.lead].z += 0.25 * u * k;
        if (fi.opp) {
          const ot = fi.opp.rig.pts;
          p.hand[0].lerp(_a.lerpVectors(ot[P.knL], ot[P.hipL], 0.5), k); p.hand[1].lerp(_b.lerpVectors(ot[P.knR], ot[P.hipR], 0.5), k);
        }
        // drive forward
        if (a.t < 0.3) { fi.rig.F.dir(_c.set(0, 0, 1), _c); fi.vel.addScaledVector(_c, dt * 16 * (0.7 + fi.A('takedown') * 0.5)); }
        if (a.t > 0.3 && !a.resolved) { a.resolved = true; self.resolveShot(fi); }
        if (a.t > 0.75) { fi.action = null; if (fi.state === 'shoot') fi.state = 'stand'; }
      },
    };
    this.game.emit('shoot', f);
    return true;
  }

  resolveShot(f) {
    const o = f.opp;
    if (!o || this.link || o.rig.mode !== 'anim' || f.rig.mode !== 'anim' || o.state === 'grapple') return;
    const d = Math.hypot(f.rig.root.x - o.rig.root.x, f.rig.root.z - o.rig.root.z);
    if (d > 1.05 * f.u) { this.game.emit('whiff', f, 'shoot'); return; }
    if (o.state === 'down') { // pounce on a downed opponent
      f.stats.td++;
      this.startGround(f, o, rng() < 0.5 ? 'half' : 'side', false);
      this.game.emit('position', f, this.link.pos);
      return;
    }
    const timing = o.action && o.action.type === 'strike' ? 0.35 : 0; // level change under a punch
    const off = this.A(f, 'takedown') * 1.0 + this.A(f, 'strength') * 0.3 + timing + (o.health.rocked > 0 ? 0.5 : 0) + (cageDist(o.rig.root) < 0.6 ? 0.15 : 0);
    const sprawl = o.sprawlT > 0 ? 0.75 : 0;
    const def = this.A(o, 'tdDefense') * 1.0 + this.A(o, 'strength') * 0.25 + sprawl + o.health.mobility * 0.2 - 0.2;
    const p = sig((off * this.stam(f) - def * this.stam(o)) * 3.2);
    if (rng() < p) {
      const r = rng();
      const pos = r < 0.55 ? 'guard' : r < 0.85 ? 'half' : 'side';
      f.stats.td++;
      this.startGround(f, o, pos, true);
      this.game.emit('takedown', f, o);
    } else {
      // stuffed: defender sprawls on top; brief front headlock window (guillotine)
      this.game.emit('stuffed', o, f, sprawl > 0);
      o.health.stamina -= 3;
      f.vel.multiplyScalar(-0.3);
      if (sprawl > 0) { f.hitStun = 0.5; this.frontHeadlock = { att: o, def: f, t: 0 }; }
    }
  }

  clinchTakedown(f) {
    const L = this.link, o = f.opp;
    f.health.stamina -= 7; f.stats.tdAtt++;
    const off = this.A(f, 'takedown') * 0.7 + this.A(f, 'clinch') * 0.5 + this.A(f, 'strength') * 0.3 + (o.health.rocked > 0 ? 0.4 : 0) + (cageDist(o.rig.root) < 0.6 ? 0.1 : 0);
    const def = this.A(o, 'tdDefense') * 0.8 + this.A(o, 'clinch') * 0.4 + this.A(o, 'strength') * 0.3;
    if (rng() < sig((off * this.stam(f) - def * this.stam(o)) * 3.4)) {
      const pos = this.A(f, 'clinch') > 0.65 && rng() < 0.4 ? 'side' : rng() < 0.6 ? 'half' : 'guard';
      this.endClinch();
      f.stats.td++;
      this.startGround(f, o, pos, true);
      this.game.emit('takedown', f, o, 'clinch');
      return true;
    }
    this.game.emit('stuffed', o, f, false);
    L.ctrl = clamp(L.ctrl + (L.a === f ? -0.3 : 0.3), -1, 1);
    return false;
  }

  endClinch() {
    if (!this.link || this.link.type !== 'clinch') return;
    const { a, b } = this.link;
    a.clinch = null; b.clinch = null;
    this.link = null;
  }

  // ---------------- ground ----------------
  toGroundFrame(f) {
    const rig = f.rig;
    if (rig.root.y > 0.01) {
      rig.pelvisOff.x.y += rig.root.y; rig.pelvisOff.t.y += rig.root.y;
      rig.root.y = 0;
    }
    f.action = null; f.queued = null; f.slip = null; f.clinch = null;
    f.state = 'grapple';
  }
  toStandFrame(f) {
    const rig = f.rig;
    rig.root.y = f.dims.hipH;
    rig.pelvisOff.x.y -= f.dims.hipH; rig.pelvisOff.t.y -= f.dims.hipH;
    f.gpose = null; f.grapple = null; f.action = null;
  }

  startGround(top, bot, pos, fromTakedown) {
    this.toGroundFrame(top); this.toGroundFrame(bot);
    const yaw = Math.atan2(bot.rig.root.x - top.rig.root.x, bot.rig.root.z - top.rig.root.z);
    const L = {
      type: 'ground', top, bot, pos, t: 0, quiet: 0, busyT: 0, attempt: null, sub: null,
      // bottom lies with head away from the top fighter: bottom facing frame looks back toward top
      anchor: new THREE.Vector3(bot.rig.root.x, 0, bot.rig.root.z).addScaledVector(_a.set(Math.sin(yaw), 0, Math.cos(yaw)), 0.25),
      byaw: yaw + Math.PI,
    };
    cageClamp(L.anchor, 0.6);
    this.link = L;
    top.grapple = L; bot.grapple = L;
    top.gpose = (f, p, dt) => this.poseTop(f, p, dt);
    bot.gpose = (f, p, dt) => this.poseBottom(f, p, dt);
    // falling body: softer springs briefly (gravity-like drop)
    bot.rig.stiff = 0.6;
    if (fromTakedown) {
      this.game.onSlam(top, bot);
      bot.health.stamina -= 5;
      bot.health.brain += 1;
    }
    this.game.emit('position', top, pos);
  }

  release(f) {
    const L = this.link;
    if (!L) return;
    if (L.type === 'clinch') { this.endClinch(); return; }
    const other = L.top === f ? L.bot : L.top;
    this.link = null;
    for (const x of [L.top, L.bot]) { x.grapple = null; x.gpose = null; }
    if (other.rig.mode === 'anim' && other.state === 'grapple') {
      this.toStandFrame(other);
      other.state = 'stand';
      this.replantBoth(other);
    }
    if (f.state === 'grapple') f.state = 'stand';
  }

  replantBoth(f) {
    const rig = f.rig, F = rig.F;
    F.pos.copy(rig.root); F.quat.setFromAxisAngle(UP, rig.yaw);
    for (let i = 0; i < 2; i++) {
      const fo = rig.feet[i];
      F.apply(f.stanceFoot(i, _a), fo.world); fo.world.y = f.dims.ankle; fo.yaw = rig.yaw + f.footYawBase(i); fo.stepping = false;
    }
  }

  // both stand back up (top disengages, ref stand-up, or bottom gets up)
  standUp(reason) {
    const L = this.link; if (!L || L.type !== 'ground') return;
    const { top, bot } = L;
    this.link = null;
    for (const f of [top, bot]) {
      f.grapple = null; f.gpose = null;
      if (f.rig.mode !== 'anim') continue;
      if (f === bot) {
        // bottom uses a technical stand-up
        f.downFaceUp = L.pos !== 'back'; f.state = 'getup'; f.getupT = 0; f.stateT = 0; f.rig.root.y = 0;
      } else {
        this.toStandFrame(f); f.state = 'stand'; this.replantBoth(f);
        f.rig.F.dir(_a.set(0, 0, -1), _a); f.vel.copy(_a).multiplyScalar(1.2);
      }
    }
    this.game.emit('standup', top, reason);
  }

  // ---------------- update (called each physics step before fighters) ----------------
  update(dt) {
    if (this.frontHeadlock) {
      this.frontHeadlock.t += dt;
      if (this.frontHeadlock.t > 0.8) this.frontHeadlock = null;
    }
    const L = this.link; if (!L) return;
    L.t += dt;
    if (L.type === 'clinch') return this.updateClinch(L, dt);
    const { top, bot } = L;
    if (top.rig.mode !== 'anim' || bot.rig.mode !== 'anim') return;
    // control time
    top.stats.ctrl += dt;
    L.quiet += dt;
    // place roots per position (spring-smoothed)
    const byaw = L.byaw;
    const bf = _a.set(Math.sin(byaw), 0, Math.cos(byaw)); // bottom facing (toward feet / top fighter)
    const br = _b.set(Math.cos(byaw), 0, -Math.sin(byaw)); // bottom local +X (left)
    const k = 1 - Math.exp(-dt * 8);
    const anchor = L.anchor;
    bot.rig.root.lerp(_c.set(anchor.x, 0, anchor.z), k);
    bot.rig.yaw = lerpAngle(bot.rig.yaw, byaw, k);
    let tx, tz, tyaw;
    const u = bot.u;
    switch (L.pos) {
      case 'guard': tx = bf.x * 0.5 * u; tz = bf.z * 0.5 * u; tyaw = byaw + Math.PI; break;
      case 'half': tx = bf.x * 0.36 * u + br.x * 0.1; tz = bf.z * 0.36 * u + br.z * 0.1; tyaw = byaw + Math.PI - 0.25; break;
      case 'side': tx = br.x * 0.45 * u - bf.x * 0.12; tz = br.z * 0.45 * u - bf.z * 0.12; tyaw = byaw - Math.PI / 2; break;
      case 'mount': tx = -bf.x * 0.05; tz = -bf.z * 0.05; tyaw = byaw + Math.PI; break;
      case 'back': tx = bf.x * 0.06; tz = bf.z * 0.06; tyaw = byaw + Math.PI; break;
    }
    top.rig.root.lerp(_c.set(anchor.x + tx, 0, anchor.z + tz), k);
    top.rig.yaw = lerpAngle(top.rig.yaw, tyaw, k);
    top.vel.set(0, 0, 0); bot.vel.set(0, 0, 0);
    // health updates
    for (const f of [top, bot]) {
      for (const ev of f.health.update(dt, { active: true })) if (ev === 'liverCollapse') this.game.emit('liver', f);
    }
    // attempt timers (transitions)
    if (L.attempt) {
      const at = L.attempt;
      at.t += dt;
      if (at.t >= at.dur) { L.attempt = null; this.resolveAttempt(L, at); }
    }
    if (L.sub) this.updateSub(L, dt);
    // ref stand-up for inactivity
    if (L.quiet > 22 && !L.sub && !L.attempt) { this.game.emit('refStandup'); this.standUp('ref'); }
    // handle inputs
    if (!L.attempt && !L.sub) {
      this.groundInput(L, top, true);
      if (this.link === L) this.groundInput(L, bot, false);
    }
  }

  groundInput(L, f, isTop) {
    const g = f.input.g || {};
    const inp = f.input;
    // strikes from top (ground & pound) or bottom (short shots)
    if (inp.strike) {
      const id = inp.strike; inp.strike = null;
      const ok = isTop ? ['jab', 'cross', 'leadHook', 'rearHook', 'elbow', 'leadElbow', 'jabBody', 'crossBody'].includes(id) : ['jab', 'cross', 'elbow'].includes(id);
      const allowed = isTop ? L.pos !== 'back' || ['jab', 'cross', 'leadHook', 'rearHook'].includes(id) : L.pos === 'guard' || L.pos === 'half';
      if (ok && allowed && !f.action) {
        const mapped = id === 'jabBody' ? 'jab' : id === 'crossBody' ? 'cross' : id;
        f.startStrike(mapped, false);
        f.action.ground = true;
        L.quiet = 0;
      }
    }
    if (g.advance) { g.advance = false; this.begin(L, f, isTop ? 'advance' : 'sweep'); }
    else if (g.escape) { g.escape = false; this.begin(L, f, isTop ? 'standup' : 'escape'); }
    else if (g.sub) { g.sub = false; this.begin(L, f, 'sub'); }
    else if (g.getup) { g.getup = false; this.begin(L, f, isTop ? 'standup' : 'getup'); }
    if (isTop) f.blocking = false;
    else f.blocking = !!inp.block;
  }

  begin(L, f, kind) {
    if (L.attempt) return;
    const isTop = f === L.top;
    let dur = 0.8;
    if (kind === 'standup' && isTop) { this.standUp('top'); return; }
    if (kind === 'sub') {
      const sub = this.pickSub(L, isTop);
      if (!sub) { this.game.emit('noSub', f); return; }
      f.stats.subAtt++;
      this.startSub(L, f, sub);
      return;
    }
    if (kind === 'advance' && L.pos === 'back') return;
    L.attempt = { kind, f, t: 0, dur };
    L.quiet = 0;
    f.health.stamina -= 5;
    this.game.emit('attempt', f, kind);
  }

  resolveAttempt(L, at) {
    const { top, bot } = L;
    const f = at.f;
    const isTop = f === top;
    const o = isTop ? bot : top;
    const pos = L.pos;
    let off, def;
    if (at.kind === 'advance') {
      off = this.A(top, 'topControl') * 1.0 + this.A(top, 'strength') * 0.2;
      def = this.A(bot, 'bottomGame') * 0.9 + this.A(bot, 'strength') * 0.2 + (pos === 'guard' ? 0.25 : 0);
      if (rng() < sig((off * this.stam(top) - def * this.stam(bot)) * 3.2 + 0.2)) {
        const next = { guard: 'half', half: 'side', side: 'mount', mount: 'back' }[pos];
        if (next === 'back') { L.anchor.copy(bot.rig.root); L.byaw = L.byaw + Math.PI; }
        L.pos = next; this.game.emit('position', top, next);
      } else this.game.emit('attemptFail', top, 'advance');
    } else if (at.kind === 'sweep') {
      off = this.A(bot, 'bottomGame') * 1.0 + this.A(bot, 'strength') * 0.25;
      def = this.A(top, 'topControl') * 0.9 + this.A(top, 'strength') * 0.25 + (pos === 'mount' ? 0.4 : pos === 'side' ? 0.3 : 0);
      if ((pos === 'guard' || pos === 'half') && rng() < sig((off * this.stam(bot) - def * this.stam(top)) * 3.2 - 0.3)) {
        // reversal: swap roles, sweeper ends in top half guard
        this.link = null;
        const anchor = top.rig.root.clone();
        this.startGround(bot, top, rng() < 0.5 ? 'half' : 'guard', false);
        this.link.anchor.copy(anchor);
        this.game.emit('sweep', bot, top);
        return;
      }
      this.game.emit('attemptFail', bot, 'sweep');
    } else if (at.kind === 'escape') {
      off = this.A(bot, 'bottomGame') * 0.8 + this.A(bot, 'strength') * 0.3 + this.A(bot, 'cardio') * 0.1;
      def = this.A(top, 'topControl') * 0.9 + this.A(top, 'strength') * 0.25;
      if (rng() < sig((off * this.stam(bot) - def * this.stam(top)) * 3.0)) {
        const prev = { half: 'guard', side: 'half', mount: 'half', back: 'guard', guard: 'guard' }[pos];
        if (pos === 'back') { L.byaw = L.byaw + Math.PI; }
        if (pos === 'guard') { this.standUp('escape'); return; }
        L.pos = prev; this.game.emit('position', top, prev, 'escape');
      } else {
        // failed bridge from mount often gives up the back
        if (pos === 'mount' && rng() < 0.3) { L.pos = 'back'; L.byaw += Math.PI; this.game.emit('position', top, 'back'); }
        else this.game.emit('attemptFail', bot, 'escape');
      }
    } else if (at.kind === 'getup') {
      off = this.A(bot, 'tdDefense') * 0.6 + this.A(bot, 'bottomGame') * 0.4 + this.A(bot, 'strength') * 0.3 + (cageDist(bot.rig.root) < 0.9 ? 0.2 : 0);
      def = this.A(top, 'topControl') * 0.9 + this.A(top, 'strength') * 0.2 + (pos === 'mount' || pos === 'back' ? 0.6 : pos === 'side' ? 0.3 : 0);
      if (rng() < sig((off * this.stam(bot) - def * this.stam(top)) * 3.0 - 0.2)) this.standUp('bottom');
      else this.game.emit('attemptFail', bot, 'getup');
    }
  }

  pickSub(L, isTop) {
    const pos = L.pos;
    if (isTop) {
      if (pos === 'back') return 'rnc';
      if (pos === 'mount') return rng() < 0.5 ? 'armbar' : 'armTri';
      if (pos === 'side') return rng() < 0.5 ? 'kimura' : 'armTri';
      return null;
    }
    if (pos === 'guard') return rng() < 0.55 ? 'triangle' : 'guardArmbar';
    if (pos === 'half') return 'halfKimura';
    return null;
  }

  startSub(L, att, id) {
    const def = att === L.top ? L.bot : L.top;
    L.sub = { id, info: SUBS[id], att, def, t: 0, prog: 0.12, attEff: 1, defEff: 1 };
    L.quiet = 0;
    att.health.stamina -= 6;
    this.game.emit('subStart', att, def, SUBS[id].name);
  }

  // guillotine from a stuffed takedown (standing)
  tryGuillotine(f) {
    const fh = this.frontHeadlock;
    if (!fh || fh.att !== f || this.link) return false;
    const o = fh.def;
    this.frontHeadlock = null;
    // pull guard with the guillotine: attacker ends up on bottom
    this.startGround(o, f, 'guard', false);
    this.link.sub = { id: 'guillotine', info: SUBS.guillotine, att: f, def: o, t: 0, prog: 0.2, attEff: 1, defEff: 1 };
    f.stats.subAtt++;
    this.game.emit('subStart', f, o, SUBS.guillotine.name);
    return true;
  }

  updateSub(L, dt) {
    const s = L.sub;
    s.t += dt;
    const att = s.att, def = s.def;
    // player/AI effort (mashing) decays toward 1
    s.attEff = lerp(s.attEff, 1, dt * 2); s.defEff = lerp(s.defEff, 1, dt * 2);
    const ai = att.input.g || {}, di = def.input.g || {};
    if (ai.mash) { ai.mash = false; s.attEff = Math.min(2, s.attEff + 0.22); att.health.stamina -= 0.4; }
    if (di.mash) { di.mash = false; s.defEff = Math.min(2, s.defEff + 0.22); def.health.stamina -= 0.4; }
    const posBonus = { rnc: 1.35, armTri: 1.1, armbar: 1.15, kimura: 1.0, triangle: 0.95, guardArmbar: 0.9, halfKimura: 0.85, guillotine: 1.0 }[s.id] || 1;
    const ap = (0.35 + this.A(att, 'subOffense') * 0.9 + this.A(att, 'strength') * 0.15) * this.stam(att) * s.attEff * posBonus;
    const dfat = 0.35 + 0.65 * def.health.stamina / 100;
    const dp = (0.3 + this.A(def, 'subDefense') * 0.85 + this.A(def, 'strength') * 0.2) * dfat * s.defEff * (def.health.rocked > 0 ? 0.55 : 1) * (0.7 + 0.3 * def.health.consc);
    s.prog += (ap - dp * 0.95) * dt * 0.32 + (rng() - 0.5) * dt * 0.1;
    def.health.stamina = Math.max(0, def.health.stamina - dt * 3);
    att.health.stamina = Math.max(0, att.health.stamina - dt * 2.5);
    if (s.prog >= 1) {
      // tap... or refuse: chokes put you to sleep, joint locks break
      const refuse = rng() < this.A(def, 'heart') * 0.35;
      if (s.info.choke) {
        if (refuse) { def.health.consc = 0; this.game.emit('choked', def, att, s.info.name); }
        else this.game.emit('tap', def, att, s.info.name);
      } else {
        if (refuse) { def.health.submissionInjury = s.id.includes('imura') ? 'ไหล่ฉีก (Kimura)' : 'ข้อศอกหัก (Armbar)'; this.game.emit('limbBroken', def, att, s.info.name); }
        else this.game.emit('tap', def, att, s.info.name);
      }
      L.sub = null;
      this.game.onSubmission(att, def, s.info.name, refuse);
    } else if (s.prog <= 0 || s.t > 9) {
      L.sub = null;
      this.game.emit('subEscape', def, att, s.info.name);
      // failed guard subs often give up position; failed top subs lose position
      if (att === L.top && (L.pos === 'mount' || L.pos === 'side') && rng() < 0.5) { L.pos = 'guard'; this.game.emit('position', L.top, 'guard', 'lost'); }
      if (s.id === 'guillotine' && rng() < 0.5) { /* defender pops head out and passes */ L.pos = 'half'; }
    }
  }

  updateClinch(L, dt) {
    const { a, b } = L;
    if (a.rig.mode !== 'anim' || b.rig.mode !== 'anim' || a.state === 'grapple' || b.state === 'grapple') { this.endClinch(); return; }
    L.quiet += dt;
    // hold the bodies together (chest to chest)
    _a.subVectors(b.rig.root, a.rig.root); _a.y = 0;
    const d = _a.length() || 1;
    const want = 0.5 * (a.u + b.u) * 0.5;
    const corr = (d - want) * Math.min(1, dt * 12);
    _a.divideScalar(d);
    a.rig.root.addScaledVector(_a, corr * 0.5); b.rig.root.addScaledVector(_a, -corr * 0.5);
    // the stronger clinch fighter drives the pair (toward the cage)
    for (const f of [a, b]) {
      const o = f === a ? b : a;
      if (f.input.mz > 0.5) {
        const pw = (this.A(f, 'clinch') * 0.6 + this.A(f, 'strength') * 0.5) * this.stam(f) - (this.A(o, 'clinch') * 0.4 + this.A(o, 'strength') * 0.4) * this.stam(o);
        if (pw > -0.15) { f.rig.F.dir(_b.set(0, 0, 1), _b); o.vel.addScaledVector(_b, dt * 3 * (pw + 0.3)); f.vel.addScaledVector(_b, dt * 3 * (pw + 0.3)); }
      }
      // break away
      if (f.input.mz < -0.6 && f.stateT > 0.2) {
        const p = sig((this.A(f, 'clinch') * 0.8 + this.A(f, 'strength') * 0.3 - this.A(o, 'clinch') * 0.6) * 3 + 0.3);
        if (rng() < dt * 3 * p) { this.endClinch(); f.rig.F.dir(_b.set(0, 0, -1), _b); f.vel.addScaledVector(_b, 1.6); o.vel.addScaledVector(_b, -0.5); this.game.emit('clinchBreak', f); return; }
      }
    }
    if (L.quiet > 10) { this.endClinch(); this.game.emit('refBreak'); a.vel.addScaledVector(_a, -1.4); b.vel.addScaledVector(_a, 1.4); }
  }

  // clinch hand placement (called from fighter pose)
  clinchHands(f, p) {
    const L = f.clinch; if (!L) return;
    const o = f === L.a ? L.b : L.a;
    const op = o.rig.pts;
    const ctrl = f === L.a ? L.ctrl : -L.ctrl;
    if (ctrl > 0 || f.prof.style === 'muaythai') {
      // collar tie / plum: both hands behind opponent's neck
      p.hand[0].copy(op[P.neck]).add(_a.set(0, 0.05, 0)).lerp(op[P.shR], 0.15); p.hand[1].copy(op[P.neck]).add(_a.set(0, 0.05, 0)).lerp(op[P.shL], 0.15);
    } else {
      // underhooks / over-under around the body
      p.hand[0].lerpVectors(op[P.abd], op[P.shR], 0.4); p.hand[1].lerpVectors(op[P.abd], op[P.shL], 0.4);
    }
    p.pole[0].set(0.9, -0.5, 0); p.pole[1].set(-0.9, -0.5, 0);
    p.pOff.y -= 0.03 * f.u; p.chest.x += 0.2; p.head.x += 0.1;
  }

  // ---------------- poses ----------------
  poseTop(f, p, dt) {
    const L = f.grapple; if (!L) return;
    const u = f.u, ank = f.dims.ankle, rig = f.rig, F = rig.F;
    F.pos.copy(rig.root); F.quat.setFromAxisAngle(UP, rig.yaw);
    const bot = L.bot, bp = bot.rig.pts;
    const reset = () => { for (let i = 0; i < 2; i++) { p.footW[i] = 1; p.footYawAdd[i] = 0; p.footPitch[i] = 0; p.roll[i] = 0; p.handK[i] = 600; } p.lookAt = false; };
    reset();
    const pos = L.pos;
    const breath = Math.sin(f.t * 2.2) * 0.02;
    if (pos === 'guard' || pos === 'half') {
      const low = pos === 'half' ? 0.08 : 0;
      p.pOff.set(0, (0.5 - low) * u, 0); p.pRot.set(0.25 + low, 0, 0); p.abd.set(0.15, 0, 0); p.chest.set(0.25 + low * 2 + breath, 0, 0); p.neck.set(0.15, 0, 0); p.head.set(0.25, 0, 0);
      p.footLocal[0].set(0.19 * u, ank, -0.45 * u); p.footLocal[1].set(-0.19 * u, ank, -0.45 * u);
      p.footPole[0].set(0.1, -0.6, 1); p.footPole[1].set(-0.1, -0.6, 1);
      // posture: hands on opponent's chest / biceps
      bot.rig.Cf.apply(_a.set(0.1 * u, 0.15 * u, 0.12 * u), p.hand[0]); bot.rig.Cf.apply(_a.set(-0.1 * u, 0.15 * u, 0.12 * u), p.hand[1]);
      p.pole[0].set(0.5, -1, 0); p.pole[1].set(-0.5, -1, 0);
    } else if (pos === 'side') {
      p.pOff.set(0, 0.36 * u, 0); p.pRot.set(0.95, 0, 0); p.abd.set(0.2, 0, 0); p.chest.set(0.25 + breath, 0, 0); p.neck.set(0.1, 0, 0); p.head.set(0.2, 0, 0);
      p.footLocal[0].set(0.3 * u, ank, -0.5 * u); p.footLocal[1].set(-0.3 * u, ank, -0.42 * u);
      p.footPole[0].set(0.3, -0.6, 1); p.footPole[1].set(-0.3, -0.6, 1);
      p.hand[0].copy(bot.rig.headCenter).add(_a.set(0, -0.05, 0)); p.hand[1].lerpVectors(bp[P.pelvis], bp[P.hipL], 0.5); p.hand[1].y += 0.1;
      p.pole[0].set(0.6, -0.4, -0.5); p.pole[1].set(-0.6, -0.4, -0.5);
    } else if (pos === 'mount') {
      p.pOff.set(0, 0.42 * u, 0); p.pRot.set(0.12, 0, 0); p.abd.set(0.1, 0, 0); p.chest.set(0.2 + breath, 0, 0); p.neck.set(0.2, 0, 0); p.head.set(0.3, 0, 0);
      p.footLocal[0].set(0.33 * u, ank, -0.32 * u); p.footLocal[1].set(-0.33 * u, ank, -0.32 * u);
      p.footPole[0].set(0.8, -0.4, 1); p.footPole[1].set(-0.8, -0.4, 1);
      bot.rig.Cf.apply(_a.set(0.12 * u, 0.25 * u, 0.15 * u), p.hand[0]); bot.rig.Cf.apply(_a.set(-0.12 * u, 0.25 * u, 0.15 * u), p.hand[1]);
      p.pole[0].set(0.6, -1, 0); p.pole[1].set(-0.6, -1, 0);
    } else if (pos === 'back') {
      // flattened back mount: both prone, top on bottom's back, hooks in
      p.pOff.set(0, 0.32 * u, -0.05 * u); p.pRot.set(-1.3, Math.PI, 0); p.abd.set(0.05, 0, 0); p.chest.set(0.05, 0, 0); p.neck.set(-0.3, 0, 0); p.head.set(-0.3, 0, 0);
      F.toLocal(_a.lerpVectors(bp[P.knL], bp[P.hipL], 0.5), p.footLocal[0]); F.toLocal(_b.lerpVectors(bp[P.knR], bp[P.hipR], 0.5), p.footLocal[1]);
      p.footPole[0].set(0.6, 0.5, 0); p.footPole[1].set(-0.6, 0.5, 0);
      p.hand[0].copy(bp[P.neck]).add(_a.set(0, 0.06, 0)); p.hand[1].copy(bp[P.neck]).add(_b.set(0, 0.03, 0));
      p.hand[0].lerp(bp[P.shR], 0.3); p.hand[1].lerp(bp[P.shL], 0.3);
      p.pole[0].set(1, 0, -0.3); p.pole[1].set(-1, 0, -0.3);
    }
    // attempt animations
    if (L.attempt && L.attempt.f === f) {
      const k = Math.sin(clamp(L.attempt.t / L.attempt.dur, 0, 1) * Math.PI);
      p.pOff.x += 0.15 * u * k * Math.sin(f.t * 9); p.chest.z += 0.25 * k;
    }
    // submissions
    if (L.sub) this.subPose(L, f, p, true);
    // ground strikes overlay
    if (f.action && f.action.type === 'strike') this.groundStrike(f, p, dt);
    if (L.sub && L.sub.def === f) this.defendSubPose(L, f, p);
  }

  poseBottom(f, p, dt) {
    const L = f.grapple; if (!L) return;
    const u = f.u, ank = f.dims.ankle, rig = f.rig, F = rig.F;
    F.pos.copy(rig.root); F.quat.setFromAxisAngle(UP, rig.yaw);
    const top = L.top, tp = top.rig.pts;
    for (let i = 0; i < 2; i++) { p.footW[i] = 1; p.footYawAdd[i] = 0; p.footPitch[i] = 0; p.roll[i] = 0; p.handK[i] = 600; }
    p.lookAt = false;
    const pos = L.pos;
    const breath = Math.sin(f.t * 2.6) * 0.03;
    if (pos === 'guard') {
      p.pOff.set(0, 0.13 * u, 0); p.pRot.set(-1.3, 0, 0); p.abd.set(0.25, 0, 0); p.chest.set(0.3 + breath, 0, 0); p.neck.set(0.35, 0, 0); p.head.set(0.3, 0, 0);
      // legs wrapped around the top fighter's waist, ankles crossed behind
      F.toLocal(_a.lerpVectors(tp[P.pelvis], tp[P.abd], 0.4), _b);
      p.footLocal[0].set(-0.05 * u, _b.y, _b.z + 0.22 * u); p.footLocal[1].set(0.05 * u, _b.y + 0.04, _b.z + 0.24 * u);
      p.footPole[0].set(1, 0.6, 0.2); p.footPole[1].set(-1, 0.6, 0.2);
    } else if (pos === 'half') {
      p.pOff.set(0.04 * u, 0.13 * u, 0); p.pRot.set(-1.35, 0, 0.35); p.abd.set(0.2, 0, 0); p.chest.set(0.25 + breath, 0, 0.1); p.neck.set(0.35, 0, 0); p.head.set(0.25, 0, 0);
      F.toLocal(tp[P.knR], _b);
      p.footLocal[0].set(0.05 * u, ank + 0.12, _b.z + 0.05); p.footLocal[1].set(-0.18 * u, ank, 0.42 * u);
      p.footPole[0].set(1, 0.5, 0.5); p.footPole[1].set(-0.3, 1, 0.3);
    } else if (pos === 'side' || pos === 'mount') {
      p.pOff.set(0, 0.12 * u, 0); p.pRot.set(-1.52, 0, 0); p.abd.set(0.05, 0, 0); p.chest.set(0.08 + breath, 0, 0); p.neck.set(0.25, 0, 0); p.head.set(0.15, 0, 0);
      p.footLocal[0].set(0.17 * u, ank, 0.36 * u); p.footLocal[1].set(-0.17 * u, ank, 0.36 * u);
      p.footPole[0].set(0.25, 1, 0.3); p.footPole[1].set(-0.25, 1, 0.3);
    } else if (pos === 'back') {
      // flattened, face down
      p.pOff.set(0, 0.13 * u, 0); p.pRot.set(1.5, Math.PI, 0); p.abd.set(0.05, 0, 0); p.chest.set(0.05, 0, 0); p.neck.set(-0.4, 0, 0); p.head.set(-0.3, 0, 0);
      p.footLocal[0].set(0.15 * u, 0.09, 0.9 * u); p.footLocal[1].set(-0.15 * u, 0.09, 0.9 * u);
      p.footPole[0].set(0, -1, 0); p.footPole[1].set(0, -1, 0);
    }
    // hands: defend (cover face) or frame
    const hc = rig.headCenter;
    if (f.blocking || (top.action && top.action.type === 'strike')) {
      F.dir(_a.set(0.06 * u, 0, 0), _b); p.hand[0].copy(hc).add(_b); p.hand[0].y += 0.1;
      F.dir(_a.set(-0.06 * u, 0, 0), _b); p.hand[1].copy(hc).add(_b); p.hand[1].y += 0.1;
      p.pole[0].set(0.5, -0.3, 1); p.pole[1].set(-0.5, -0.3, 1);
    } else if (pos === 'back') {
      p.hand[0].copy(rig.pts[P.neck]).add(_a.set(0, -0.02, 0)); p.hand[1].copy(rig.pts[P.neck]);
      p.pole[0].set(1, 0, 0); p.pole[1].set(-1, 0, 0);
    } else {
      // framing on the top fighter (biceps / neck)
      p.hand[0].lerpVectors(tp[P.shR], tp[P.elR], 0.5); p.hand[1].lerpVectors(tp[P.shL], tp[P.elL], 0.5);
      p.pole[0].set(1, -0.5, 0); p.pole[1].set(-1, -0.5, 0);
    }
    if (L.attempt && L.attempt.f === f) {
      const k = Math.sin(clamp(L.attempt.t / L.attempt.dur, 0, 1) * Math.PI);
      p.pRot.z += 0.6 * k; p.pOff.y += 0.08 * u * k; p.chest.x += 0.3 * k;
    }
    if (L.sub) this.subPose(L, f, p, false);
    if (f.action && f.action.type === 'strike') this.groundStrike(f, p, dt);
    if (L.sub && L.sub.def === f) this.defendSubPose(L, f, p);
  }

  subPose(L, f, p, isTop) {
    const s = L.sub; if (s.att !== f) return;
    const o = s.def, op = o.rig.pts, u = f.u, F = f.rig.F;
    const squeeze = 0.5 + 0.5 * Math.sin(L.t * 6) * s.attEff * 0.3;
    switch (s.id) {
      case 'rnc': case 'guillotine':
        p.hand[0].copy(op[P.neck]).add(_a.set(0, 0.02, 0)); p.hand[1].copy(op[P.neck]).lerp(op[P.head], 0.4);
        p.chest.x -= 0.1 * squeeze; break;
      case 'armTri':
        p.hand[0].copy(op[P.neck]); p.hand[1].copy(op[P.shR]).lerp(op[P.neck], 0.5); p.chest.x += 0.25; break;
      case 'kimura': case 'halfKimura':
        p.hand[0].copy(op[P.elL]); p.hand[1].copy(op[P.haL]); p.chest.z += 0.3 * squeeze; break;
      case 'armbar': case 'guardArmbar':
        // fall back with the arm across the hips
        if (isTop) { p.pOff.y -= 0.2 * u; p.pRot.x -= 0.9; }
        else { p.pRot.x -= 0.15; }
        p.hand[0].copy(op[P.haR]); p.hand[1].copy(op[P.haR]).lerp(op[P.elR], 0.5);
        F.toLocal(op[P.head], _a); p.footLocal[0].set(_a.x + 0.1, Math.max(_a.y, 0.2), _a.z); p.footLocal[1].set(_a.x - 0.25, Math.max(_a.y - 0.1, 0.15), _a.z - 0.1);
        break;
      case 'triangle':
        F.toLocal(op[P.neck], _a);
        p.footLocal[0].set(_a.x + 0.15 * u, _a.y + 0.05, _a.z + 0.05); p.footLocal[1].set(_a.x - 0.1 * u, _a.y + 0.1, _a.z + 0.15 * u);
        p.footPole[0].set(1, 1, 0); p.footPole[1].set(-1, 1, 0);
        p.hand[0].copy(op[P.head]); p.hand[1].copy(op[P.head]); p.pRot.x -= 0.15; break;
    }
  }
  defendSubPose(L, f, p) {
    const s = L.sub, o = s.att, op = o.rig.pts;
    // hand-fighting: grab the attacker's wrists
    p.hand[0].copy(op[P.haL]); p.hand[1].copy(op[P.haR]);
    p.chest.z += Math.sin(L.t * 8) * 0.15 * s.defEff;
  }

  groundStrike(f, p, dt) {
    const a = f.action, def = a.def, u = f.u;
    a.t += dt * a.sp;
    const tw = def.wind, te = tw + def.ext, th = te + def.hold, tr = th + def.ret;
    let phase = a.t < tw ? 'wind' : a.t < te ? 'ext' : a.t < th ? 'hold' : a.t < tr ? 'ret' : 'done';
    if (a.hit && (phase === 'ext' || phase === 'hold')) { a.t = th; phase = 'ret'; }
    a.phase = phase;
    if (phase === 'done') { f.action = null; return; }
    a.active = (phase === 'ext' && (a.t - tw) / def.ext > 0.3) || phase === 'hold' || (phase === 'ret' && (a.t - th) / def.ret < 0.2);
    const hi = a.hi;
    const sExt = clamp((a.t - tw) / def.ext, 0, 1);
    const k = phase === 'wind' ? 0 : phase === 'ret' ? 1 - smooth(clamp((a.t - th) / def.ret, 0, 1)) : 1;
    // aim at opponent head (elbows: short arc)
    f.updateAim(a, false);
    if (phase === 'wind') {
      a.start.copy(f.rig.pts[hi === 0 ? P.haL : P.haR]);
      p.hand[hi].copy(f.rig.headCenter).add(_a.set(0, 0.15 * u, 0)); // cock high
      p.chest.z += (hi === 0 ? -1 : 1) * 0.2;
    } else if (phase === 'ext' || phase === 'hold') {
      if (!a.launched) { a.launched = true; a.start.copy(f.rig.pts[hi === 0 ? P.haL : P.haR]); a.through.copy(a.aim).addScaledVector(_b.subVectors(a.aim, a.start).normalize(), 0.08); }
      p.hand[hi].lerpVectors(a.start, a.through, phase === 'hold' ? 1 : Math.pow(sExt, 1.3));
      p.handK[hi] = 1500;
      p.pole[hi].set(hi === 0 ? 1 : -1, def.limb === 'elbow' ? 0.6 : -0.3, 0.2);
      if (def.limb === 'elbow') { p.hand[hi].copy(f.rig.headCenter).lerp(a.through, 0.45); }
      p.chest.z += (hi === 0 ? 1 : -1) * 0.25 * k; p.chest.x += 0.15 * k;
    }
  }

  // inactivity reset when strikes land
  noteActivity() { if (this.link) this.link.quiet = 0; }
}

function lerpAngle(a, b, t) {
  let d = b - a;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return a + d * t;
}
