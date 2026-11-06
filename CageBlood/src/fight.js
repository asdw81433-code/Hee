// ===== Fight scene: rules (Unified Rules of MMA), referee, judges, doctor, corner, commentary, KO replay =====
import * as THREE from 'three';
import { Fighter } from './fighter.js';
import { AI } from './ai.js';
import { Grapple, POS_NAMES } from './grapple.js';
import { applyPlayerInput } from './input.js';
import { P, S, SEGS } from './rig.js';
import { clamp, lerp, rng, fmtTime, makeRng } from './util.js';
import { cageDist } from './render.js';

const STEP = 1 / 240;
const _a = new THREE.Vector3(), _b = new THREE.Vector3();

const REF_PROFILE = {
  name: 'Ref. Big Mike', style: 'none', stance: 'orthodox', height: 1.85, weightKg: 95,
  look: { skin: '#c68b62', hairColor: '#141010', hairStyle: 'bald', beard: 'goatee', muscle: 0.4, fat: 0.4, seed: 7777 },
  attrs: { footwork: 60, fightIQ: 60 },
};

export class FightScene {
  constructor(app, opts) {
    this.app = app;
    this.opts = opts;
    this.world = app.world;
    this.blood = app.blood;
    this.audio = app.audio;
    this.hud = app.hud;
    this.keys = app.keys;
    this.time = 0;
    this.grapple = new Grapple(this);
    this.blood.clear();
    this.world.cleanMat();
    this.world.setBrand(opts.brand || 'APEX');
    this.red = new Fighter(this, opts.red, { corner: 'red', gloveColor: '#141414', gloveTrim: '#8b1010' });
    this.blue = new Fighter(this, opts.blue, { corner: 'blue', gloveColor: '#141414', gloveTrim: '#103a8b' });
    this.red.setOpponent(this.blue); this.blue.setOpponent(this.red);
    this.fighters = [this.red, this.blue];
    this.ref = new Fighter(this, REF_PROFILE, { ref: true });
    this.ref.state = 'idle';
    this.ref.health.update = () => [];
    this.player = opts.playerSide === 'blue' ? this.blue : opts.playerSide === 'red' ? this.red : null;
    this.ais = new Map();
    for (const f of this.fighters) if (f !== this.player || opts.playerAI) this.ais.set(f, new AI(f, f === this.red ? opts.aiLevelRed ?? opts.aiLevel ?? 0.6 : opts.aiLevel ?? 0.6));
    this.rounds = opts.rounds || 3;
    this.roundLen = opts.roundLen || 300;
    this.clockScale = opts.clockScale || 1;
    this.round = 1; this.clock = this.roundLen;
    this.phase = 'intro'; this.phaseT = 0;
    this.elapsed = 0;
    this.cards = [[], [], []]; // per judge: [redPts, bluePts] per round
    this.judges = [0, 1, 2].map(() => ({ bias: rng() * 0.6 - 0.3, noise: 0.08 + rng() * 0.12 }));
    this.roundStats = this.newRoundStats();
    this.uhits = new Map([[this.red, []], [this.blue, []]]);
    this.lastStrikeT = new Map([[this.red, -9], [this.blue, -9]]);
    this.result = null;
    this.timeScale = 1;
    this.slowmo = 0;
    this.replay = new Replay(this);
    this.hype = 0.2;
    this.feedQ = [];
    this.doctorPause = 0;
    this.koFrozen = 0;
    this.sandbox = !!opts.sandbox;
    this.background = !!opts.background;
    this._AI = AI;
    this.settings = opts.settings || {};
    this.red.placeAt(-1.7, 0, Math.PI / 2);
    this.blue.placeAt(1.7, 0, -Math.PI / 2);
    this.ref.placeAt(0, -2.4, 0);
    this.world.cam.mode = 'broadcast';
    this.world.cam.pos.set(0, 1.8, 6);
    this.hud.setupFight(this);
    this.match = this; // fighters reference game.match.elapsed
    this.hud.message(opts.title ? opts.title : `${this.red.name}  VS  ${this.blue.name}`, 2.2, 'big');
    this.audio.crowd(0.4);
  }

  newRoundStats() {
    const mk = () => ({ dmg: 0, sig: 0, kd: 0, td: 0, ctrl: 0, sub: 0, aggr: 0, cage: 0, thrown: 0 });
    return new Map([[this.red, mk()], [this.blue, mk()]]);
  }

  aiUrgency(f) {
    // late in a close/losing fight the AI pushes harder
    if (this.round < this.rounds) return 0;
    const sc = this.scoreSoFar();
    const mine = f === this.red ? sc[0] : sc[1], theirs = f === this.red ? sc[1] : sc[0];
    return mine <= theirs ? 0.25 : -0.1;
  }
  scoreSoFar() {
    let r = 0, b = 0;
    for (const j of this.cards) for (const [x, y] of j) { r += x; b += y; }
    return [r, b];
  }

  // ================= EVENTS =================
  emit(type, a, b, c, d) {
    const nm = (f) => (f ? `<b class="${f.corner}">${f.name}</b>` : '');
    const say = (t, cls) => this.hud.feed(t, cls);
    switch (type) {
      case 'swing':
        if (a.isRef) return;
        this.audio.whoosh(b.kind === 'kick' ? 'kick' : 'punch');
        if (rng() < 0.6) this.audio.exhale();
        this.lastStrikeT.set(a, this.time);
        this.roundStats.get(a).thrown++;
        break;
      case 'footstep': this.audio.step(); break;
      case 'ko':
        say(`💥 ${nm(b)} น็อก ${nm(a)} ด้วย ${c.name}! หลับคาสังเวียน!`, 'hot');
        this.hud.message('KNOCKOUT!', 3, 'ko');
        this.audio.roar(); this.hype = 1;
        this.world.cam.shake = 1.5;
        this.slowmo = 1.2;
        this.endFight(b, 'KO', c.name);
        break;
      case 'knockdown':
        say(`⚠️ ${nm(a)} ล้มลงไปกับพื้น! ${nm(b)} ปล่อย ${c.name} เข้าเต็มๆ`, 'hot');
        this.hud.message('KNOCKDOWN!', 1.6, 'warn');
        this.roundStats.get(b).kd++;
        this.audio.ooh(); this.hype = Math.min(1, this.hype + 0.5);
        this.world.cam.shake = 0.9; this.slowmo = 0.6;
        break;
      case 'rocked': if (rng() < 0.6) say(`${nm(a)} เข่าอ่อน! โดนหนักเข้าไปแล้ว`, 'warn'); this.hype = Math.min(1, this.hype + 0.25); break;
      case 'cut': say(`🩸 ${nm(a)} แผลแตก${({ browL: 'เหนือคิ้วซ้าย', browR: 'เหนือคิ้วขวา', forehead: 'ที่หน้าผาก', lip: 'ที่ปาก' })[b.region] || ''} เลือดไหลแล้ว!`, 'blood'); break;
      case 'noseBroken': say(`🩸 จมูกของ ${nm(a)} หักแล้ว! เลือดกำเดาไหลไม่หยุด`, 'blood'); break;
      case 'deadLeg': say(`${nm(a)} ขาเริ่มไม่ตอบสนอง — เส้นประสาทขาโดนเข้าไปแล้ว`, 'warn'); break;
      case 'liverHit': say(`${nm(a)} โดนเข้าที่ตับ...`, 'warn'); break;
      case 'liver': say(`💥 ${nm(a)} ทรุดลงจากหมัดเข้าตับ! เจ็บจนขยับไม่ได้`, 'hot'); this.hype = 1; this.audio.ooh(); break;
      case 'legGive': say(`${nm(a)} ลงน้ำหนักขาไม่ได้แล้ว ล้มเอง!`, 'warn'); break;
      case 'checked': say(`${nm(b)} ยกแข้งบล็อกลูกเตะ — แข้งชนแข้ง!`); this.audio.impact('leg', 1, false); break;
      case 'handBroken': say(`${nm(a)} สะบัดมือ... ดูเหมือนมือจะหัก`, 'warn'); break;
      case 'clinch': say(`${nm(a)} เข้าคลินช์`); this.lastStrikeT.set(a, this.time); break;
      case 'takedown': say(`⬇️ ${nm(a)} ${c === 'clinch' ? 'ทุ่ม' : 'ยิงเทคดาวน์'} ${nm(b)} ลงพื้นสำเร็จ!`); this.roundStats.get(a).td++; this.hud.message('TAKEDOWN', 1, 'info'); break;
      case 'stuffed': say(c ? `${nm(a)} สปรอลกันเทคดาวน์ได้สวยงาม!` : `${nm(a)} กันเทคดาวน์ไว้ได้`); break;
      case 'shoot': this.lastStrikeT.set(a, this.time); this.roundStats.get(a).thrown++; break;
      case 'position': say(`${nm(a)} ${c === 'escape' ? '(คู่ต่อสู้หนีออกมา) ' : ''}อยู่ในตำแหน่ง ${POS_NAMES[b]}`); break;
      case 'sweep': say(`🔄 ${nm(a)} สวีปพลิกกลับขึ้นมาอยู่ด้านบน!`, 'hot'); break;
      case 'subStart': say(`🔒 ${nm(a)} ล็อก ${c}!`, 'hot'); this.hud.message(c, 1.5, 'info'); this.roundStats.get(a).sub++; this.hype = Math.min(1, this.hype + 0.4); break;
      case 'subEscape': say(`${nm(a)} แก้ ${c} หลุดออกมาได้!`); break;
      case 'tap': say(`✋ ${nm(a)} ตบพื้นยอมแพ้! ${nm(b)} ชนะด้วย ${c}`, 'hot'); break;
      case 'choked': say(`😵 ${nm(a)} ไม่ยอมตบ... หลับไปใน ${c}!`, 'hot'); break;
      case 'limbBroken': say(`🦴 ${nm(a)} ไม่ยอมตบ — แขนหักจาก ${c}!`, 'blood'); break;
      case 'standup': if (b === 'ref') say('กรรมการสั่งให้ยืนขึ้นสู้ใหม่'); else say(`${nm(a)} ${b === 'top' ? 'ปล่อยลุกขึ้นยืน' : ''} กลับมายืนสู้กันอีกครั้ง`); break;
      case 'refStandup': break;
      case 'refBreak': say('กรรมการแยกคลินช์'); break;
      case 'clinchBreak': say(`${nm(a)} ดันตัวออกจากคลินช์`); break;
      case 'getup': break;
      case 'fall': this.audio.slam(); break;
      case 'whiff': break;
    }
  }

  onImpact(att, def, info) {
    const { zone, point, dir, power, blocked, u, v, res } = info;
    this.audio.impact(zone === 'arm' ? 'head' : zone, power, blocked);
    this.grapple.noteActivity();
    if (!blocked && power > 0.3) {
      const rs = this.roundStats.get(att);
      rs.sig++; rs.dmg += power * (zone === 'head' ? 1.25 : zone === 'body' ? 1 : 0.8);
      this.world.cam.shake = Math.max(this.world.cam.shake, power * 0.45);
      this.hype = Math.min(1, this.hype + power * 0.12);
      if (power > 1.0) this.audio.ooh();
      // unanswered strikes on a hurt / downed fighter -> referee
      this.uhits.get(def).push(this.time);
    }
    if (blocked) return;
    // ---- blood ----
    const b = this.blood;
    if (zone === 'head') {
      const wet = def.fx.wetness(u, v);
      const bleeding = def.health.bleedRate;
      // existing blood on the face sprays off in the direction of the strike (cast-off)
      const vol = (wet * 1.6 + bleeding * 0.25 + (res.cut ? 0.4 : 0) + (res.nose ? (def.health.noseBleed || 0) * 0.4 : 0)) * power;
      if (vol > 0.02) {
        const n = Math.round(clamp(vol * 30, 2, 40));
        b.spray(point, _a.copy(dir).add(_b.set(0, 0.25, 0)).normalize(), n, 2.5 + power * 3.5, 0.45, vol);
        def.fx.smear(u, v, dir.x * 10, -dir.y * 10);
      }
      if (res.cut) { def.fx.splat(res.cut.u, res.cut.v, 4 + power * 3, 0.95); b.spray(point, _a.copy(dir).normalize(), 8, 2 + power * 2, 0.6, 0.25 * power); }
      // sweat flies off on every clean head shot
      b.spray(point, _a.copy(dir).add(_b.set(0, 0.4, 0)).normalize(), Math.round(3 + power * 6), 1.5 + power * 2.5, 0.6, 0.15, 'sweat');
    } else if (zone === 'body') {
      if (rng() < 0.5) b.spray(point, _a.copy(dir).add(_b.set(0, 0.3, 0)).normalize(), 4, 1.5 + power, 0.6, 0.1, 'sweat');
    }
    // glove blood on the attacker if punching a bloody face
    if (zone === 'head' && def.health.bleedRate > 0.1) att.model.gloveBlood = clamp(att.model.gloveBlood + 0.08, 0, 1);
    att.model.setInjuryVisuals(att.health);
  }

  onSlam(top, bot) {
    this.audio.slam();
    this.world.cam.shake = 0.6;
    // blood shakes off a bleeding face when slammed
    if (bot.health.bleedRate > 0.2) this.blood.spray(bot.rig.headCenter, _a.set(0, 0.6, 0), 10, 1.5, 0.8, 0.3);
  }

  onSubmission(att, def, name, refused) {
    this.endFight(att, refused && name.includes('Choke') ? 'SUB (หลับ)' : 'SUB', name);
  }

  // ================= LOOP =================
  update(realDt, render = true) {
    const keys = this.keys;
    if (this.paused) return;
    let dt = Math.min(realDt, 0.05);
    // slow motion on big moments
    if (this.slowmo > 0) { this.slowmo -= realDt; dt *= 0.3; }
    if (this.sandbox && this.app.sandboxTimeScale) dt *= this.app.sandboxTimeScale;
    if (this.replay.playing) {
      if (keys.hit('Space') || keys.hit('Enter') || keys.hit('Escape')) { keys.endFrame(); this.replay.stop(); return; }
      this.replay.play(realDt);
      this.world.updateCamera(realDt, this.red.rig.root, this.blue.rig.root, { replayCam: this.replay.cam, fov: 35 });
      this.world.render(realDt);
      this.hud.tick(this, realDt);
      return;
    }
    // player input
    if (this.player && !this.opts.playerAI && this.phase === 'fight' && !this.doctorPause) applyPlayerInput(keys, this.player, this);
    this.acc = (this.acc || 0) + dt;
    let n = 0;
    while (this.acc >= STEP && n < 20) {
      this.acc -= STEP; n++;
      this.time += STEP;
      this.stepFixed(STEP);
    }
    // per-frame
    for (const f of this.fighters) f.frame(dt);
    this.ref.model.update();
    this.blood.update(dt, this.fighters);
    this.stepMatch(dt, realDt);
    const ground = this.grapple.link && this.grapple.link.type === 'ground' || this.red.state === 'down' || this.blue.state === 'down' || this.red.rig.mode === 'ragdoll' || this.blue.rig.mode === 'ragdoll';
    const pa = this.red.rig.mode === 'ragdoll' ? this.red.rig.pts[P.pelvis] : this.red.rig.root;
    const pb = this.blue.rig.mode === 'ragdoll' ? this.blue.rig.pts[P.pelvis] : this.blue.rig.root;
    this.world.updateCamera(realDt, pa, pb, { ground, playerPos: this.player ? this.player.rig.root : null, focus: _a.lerpVectors(pa, pb, 0.5).setY(1) });
    this.hype = Math.max(0.15, this.hype - realDt * 0.05);
    this.world.crowdHype = this.hype;
    this.audio.crowd(this.hype);
    if (render) this.world.render(realDt);
    this.replay.record();
    if (render) this.hud.tick(this, realDt);
    keys.endFrame();
  }

  stepFixed(h) {
    const live = this.phase === 'fight' && !this.doctorPause;
    this.aiAcc = (this.aiAcc || 0) + h;
    if (this.aiAcc >= 1 / 60) {
      for (const [f, ai] of this.ais) if (live) ai.update(this.aiAcc); else { f.input.mx = 0; f.input.mz = 0; f.input.block = false; }
      this.aiAcc = 0;
    }
    if (!live) for (const f of this.fighters) { f.input.strike = null; f.input.shoot = false; f.input.clinch = false; }
    if (live) this.grapple.update(h);
    for (const f of this.fighters) f.step(h);
    this.stepRef(h);
    this.ref.step(h);
  }

  // referee keeps a safe distance, perpendicular to the fight line, and jumps in on stoppages
  stepRef(h) {
    const r = this.ref, a = this.red.rig.root, b = this.blue.rig.root;
    const mid = _a.lerpVectors(a, b, 0.5); mid.y = 0;
    let want;
    if (this.result && this.phase !== 'corner') {
      const loser = this.result.loser;
      want = loser ? (loser.rig.mode === 'ragdoll' ? loser.rig.pts[P.pelvis].clone() : loser.rig.root.clone()) : mid.clone();
      want.y = 0;
      const w = this.result.winner;
      if (w) { const away = _b.subVectors(want, w.rig.root); away.y = 0; away.normalize(); want.addScaledVector(away, -0.6); }
    } else {
      const axis = _b.subVectors(b, a); axis.y = 0; axis.normalize();
      const perp = new THREE.Vector3(-axis.z, 0, axis.x);
      // stay on the side away from camera so he doesn't block the view
      const camSide = this.world.cam.pos.clone().sub(mid); camSide.y = 0;
      if (perp.dot(camSide) > 0) perp.negate();
      const ground = this.grapple.link && this.grapple.link.type === 'ground';
      want = mid.clone().addScaledVector(perp, ground ? 1.4 : 2.1);
    }
    if (cageDist(want) < 0.5) want.multiplyScalar(0.85);
    const d = _b.subVectors(want, r.rig.root); d.y = 0;
    const dist = d.length();
    const F = r.rig.F; F.quat.setFromAxisAngle(new THREE.Vector3(0, 1, 0), r.rig.yaw);
    const local = d.clone().applyQuaternion(F.quat.clone().invert());
    const sp = this.result ? 1 : clamp(dist * 1.2, 0, 0.9);
    r.input.mx = dist > 0.15 ? clamp(local.x / dist, -1, 1) * sp : 0;
    r.input.mz = dist > 0.15 ? clamp(local.z / dist, -1, 1) * sp : 0;
    r.idleFace = Math.atan2(mid.x - r.rig.root.x, mid.z - r.rig.root.z);
  }

  stepMatch(dt, realDt) {
    this.phaseT += realDt;
    const live = this.phase === 'fight';
    if (this.phase === 'intro') {
      if (this.phaseT > 2.5) { this.phase = 'fight'; this.phaseT = 0; this.audio.bell(1); this.hud.message(`ROUND ${this.round}`, 1.5, 'big'); this.hud.feed(`🔔 ยกที่ ${this.round} เริ่ม!`); }
      return;
    }
    if (this.doctorPause > 0) {
      this.doctorPause -= realDt;
      if (this.doctorPause <= 0) this.resolveDoctor(this.doctorFor);
      return;
    }
    if (live) {
      this.clock -= dt * this.clockScale;
      this.elapsed += dt;
      // round stats: control & aggression & cage control
      const L = this.grapple.link;
      if (L && L.type === 'ground') this.roundStats.get(L.top).ctrl += dt;
      for (const f of this.fighters) {
        const rs = this.roundStats.get(f);
        const o = f.opp;
        if (f.input.mz > 0.3) rs.aggr += dt;
        if (cageDist(o.rig.root) < 0.9 && cageDist(f.rig.root) > cageDist(o.rig.root)) rs.cage += dt;
      }
      this.checkReferee();
      // severe cut: ref calls the doctor in
      for (const f of this.fighters) {
        if (!f.docChecked && f.rig.mode === 'anim' && (f.health.bloodInEye[0] > 0.7 || f.health.bloodInEye[1] > 0.7) && f.health.cuts.some((c) => c.depth > 0.85)) {
          f.docChecked = true;
          this.callDoctor(f);
          break;
        }
      }
      if (this.clock <= 0 && !this.result) this.endRound();
    }
    if (this.phase === 'ended') {
      if (!this.resultShown && this.phaseT > (this.result.method.startsWith('KO') || this.result.method.startsWith('TKO') ? 2.2 : 1.6)) {
        this.resultShown = true;
        // instant replay of the finish
        if ((this.result.method === 'KO' || this.result.method === 'TKO') && this.settings.replay !== false) {
          this.replay.start(this.result.loser, () => this.app.onFightEnd(this));
        } else this.app.onFightEnd(this);
      }
    }
  }

  checkReferee() {
    const now = this.time;
    for (const f of this.fighters) {
      const list = this.uhits.get(f);
      while (list.length && now - list[0] > 5) list.shift();
      const L = this.grapple.link;
      const bottom = L && L.type === 'ground' && L.bot === f;
      const vulnerable = f.health.rocked > 0 || f.state === 'down' || f.state === 'ragdoll' || (bottom && !f.blocking && f.health.consc < 0.6);
      const answering = now - this.lastStrikeT.get(f) < 1.8 && f.health.consc > 0.5;
      const patience = (this.settings.refPatience ?? 0.5);
      const need = Math.round(4 + patience * 3 - (f.state === 'down' ? 2 : 0));
      if (vulnerable && !answering && list.length >= need) {
        this.endFight(f.opp, 'TKO', f.state === 'down' || bottom ? 'Ground & Pound' : 'Punches');
        this.hud.message('TKO!', 2.5, 'ko');
        this.audio.roar();
        return;
      }
      // liver collapse: fighter curled up and can't continue
      if (f.fallKind === 'liver' && (f.state === 'ragdoll' || f.state === 'down') && f.stateT > 2.6 && rng() < 0.7) {
        this.endFight(f.opp, 'TKO', 'Body Shot (ตับ)');
        this.hud.message('TKO!', 2.5, 'ko');
        return;
      }
      if (f.health.consc <= 0 && !this.result) { this.endFight(f.opp, 'KO', 'Strikes'); return; }
    }
  }

  callDoctor(f) {
    this.doctorPause = 3.5; this.doctorFor = f;
    this.hud.message('TIME! — แพทย์ตรวจแผล', 2.5, 'warn');
    this.hud.feed(`🩺 กรรมการเรียกแพทย์เข้ามาตรวจแผลของ <b class="${f.corner}">${f.name}</b>`, 'blood');
    for (const x of this.fighters) { x.input.mx = 0; x.input.mz = 0; }
  }
  resolveDoctor(f) {
    const r = f.health.doctorCheck();
    if (r.stop) {
      this.hud.feed(`🩺 แพทย์สั่งยุติการชก: ${r.reason}`, 'hot');
      this.endFight(f.opp, 'TKO (แพทย์)', r.reason);
    } else this.hud.feed('🩺 แพทย์อนุญาตให้ชกต่อ', 'info');
  }

  // ---- judging: 10-point must, effective striking/grappling first, then aggression, then cage control ----
  scoreRound() {
    const rs = this.roundStats;
    const R = rs.get(this.red), B = rs.get(this.blue);
    const eff = (s) => s.dmg * 1.0 + s.kd * 3.5 + s.td * 0.9 + s.ctrl / 40 + s.sub * 0.9 + s.sig * 0.08;
    const out = [];
    for (const j of this.judges) {
      // each judge weighs grappling a bit differently and has noise
      const er = eff(R) * (1 + (j.bias > 0 ? 0 : -j.bias * (R.td + R.ctrl / 60) * 0.05)) + rng() * j.noise * 2;
      const eb = eff(B) * (1 + (j.bias < 0 ? 0 : j.bias * (B.td + B.ctrl / 60) * 0.05)) + rng() * j.noise * 2;
      let diff = er - eb;
      const tot = er + eb + 0.5;
      if (Math.abs(diff) < tot * 0.06) diff = (R.aggr - B.aggr) * 0.05 + (R.cage - B.cage) * 0.02 + (rng() - 0.5) * 0.05;
      let r = 10, b = 10;
      const dominance = Math.abs(diff) / tot;
      if (diff > 0) b = dominance > 0.55 && Math.abs(diff) > 5 || R.kd >= 2 ? 8 : 9;
      else if (diff < 0) r = dominance > 0.55 && Math.abs(diff) > 5 || B.kd >= 2 ? 8 : 9;
      out.push([r, b]);
    }
    out.forEach((c, i) => this.cards[i].push(c));
    return out;
  }

  endRound() {
    this.audio.bell(2);
    const card = this.scoreRound();
    this.hud.feed(`🔔 จบยกที่ ${this.round}`);
    if (this.grapple.link) { if (this.grapple.link.type === 'clinch') this.grapple.endClinch(); else this.grapple.standUp('bell'); }
    if (this.round >= this.rounds) { this.decision(); return; }
    this.phase = 'corner'; this.phaseT = 0;
    for (const f of this.fighters) if (f.rig.mode === 'anim' && (f.state === 'stand' || f.state === 'strike')) { f.state = 'idle'; f.idleFace = undefined; }
    this.app.showCorner(this, card);
  }

  // called by UI when corner done
  nextRound(choices = {}) {
    for (const f of this.fighters) {
      const ai = f !== this.player;
      const treat = ai ? { treatCuts: true, enswell: true, water: true, cutmanSkill: 0.6 } : { treatCuts: choices.treatCuts, enswell: choices.enswell, water: choices.water, cutmanSkill: choices.cutmanSkill ?? 0.6 };
      f.health.corner(treat);
      if (treat.treatCuts) f.fx.wipe(0.8);
      f.fx.setDamage(f.damageView()); f.model.setInjuryVisuals(f.health);
      // doctor checks between rounds
      const doc = f.health.doctorCheck();
      if (doc.stop) {
        this.round++;
        this.hud.feed(`🩺 แพทย์ไม่อนุญาตให้ <b class="${f.corner}">${f.name}</b> ชกต่อ: ${doc.reason}`, 'hot');
        this.endFight(f.opp, 'TKO (แพทย์)', doc.reason, true);
        return;
      }
    }
    if (choices.strategy && this.ais.get(this.player)) this.ais.get(this.player).plan.aggression = choices.strategy === 'pressure' ? 0.85 : choices.strategy === 'counter' ? 0.3 : 0.5;
    this.world.wipeMat();
    this.round++;
    this.clock = this.roundLen;
    this.roundStats = this.newRoundStats();
    for (const f of this.fighters) {
      if (f.state === 'down' || f.state === 'getup') continue;
      f.state = 'stand';
    }
    // reset positions
    this.red.placeAt(-1.7, 0, Math.PI / 2); this.blue.placeAt(1.7, 0, -Math.PI / 2);
    for (const f of this.fighters) { f.state = 'stand'; f.action = null; f.health.rocked = 0; }
    this.phase = 'intro'; this.phaseT = 1.2;
    this.hud.message(`ROUND ${this.round}`, 1.5, 'big');
  }

  decision() {
    let rw = 0, bw = 0;
    const totals = this.cards.map((j) => j.reduce((s, [r, b]) => [s[0] + r, s[1] + b], [0, 0]));
    for (const [r, b] of totals) { if (r > b) rw++; else if (b > r) bw++; }
    let winner = null, method = 'DRAW';
    if (rw >= 2) { winner = this.red; method = rw === 3 ? 'UD' : bw === 1 ? 'SD' : 'MD'; }
    else if (bw >= 2) { winner = this.blue; method = bw === 3 ? 'UD' : rw === 1 ? 'SD' : 'MD'; }
    else method = rw === bw ? 'DRAW' : 'MAJ DRAW';
    const names = { UD: 'Unanimous Decision (เอกฉันท์)', SD: 'Split Decision (ไม่เอกฉันท์)', MD: 'Majority Decision (เสียงข้างมาก)' };
    this.endFight(winner, 'DEC', names[method] || 'Draw (เสมอ)', true, totals);
  }

  endFight(winner, method, detail, noRound = false, totals = null) {
    if (this.result) return;
    if (this.sandbox) {
      if (!this._sbMsg || this.time - this._sbMsg > 3) { this._sbMsg = this.time; this.hud.feed(`🧪 (แซนด์บ็อกซ์) ${method} — ${detail}. กด "รีเซ็ตตำแหน่ง" เพื่อเริ่มใหม่`, 'hot'); }
      return;
    }
    const loser = winner ? winner.opp : null;
    this.result = { winner, loser, method, detail, round: Math.min(this.round, this.rounds), time: fmtTime(this.roundLen - this.clock), totals: totals || this.cards.map((j) => j.reduce((s, [r, b]) => [s[0] + r, s[1] + b], [0, 0])), cards: this.cards };
    this.phase = 'ended'; this.phaseT = 0;
    if (method !== 'DEC') this.audio.bell(3);
    if (winner) {
      winner.state = winner.rig.mode === 'anim' && winner.state !== 'grapple' ? 'celebrate' : winner.state;
      if (this.grapple.link) this.grapple.release(loser);
      if (winner.state === 'grapple') { winner.state = 'stand'; }
    }
    for (const f of this.fighters) { f.input = Fighter.blankInput(); }
    this.hype = 1;
  }

  dispose() {
    for (const f of [...this.fighters, this.ref]) f.dispose();
    this.blood.clear();
  }
}

// ===== Instant replay: records segment transforms + blood drops, plays back in slow motion =====
class Replay {
  constructor(scene) {
    this.scene = scene;
    this.frames = [];
    this.max = 420;
    this.playing = false;
    this.cam = { pos: new THREE.Vector3(), look: new THREE.Vector3() };
  }
  record() {
    if (this.playing) return;
    const sc = this.scene;
    const fr = { f: [], blood: null };
    for (const f of [...sc.fighters, sc.ref]) {
      const arr = new Float32Array(SEGS.length * 7);
      f.rig.seg.forEach((s, i) => { arr.set([s.pos.x, s.pos.y, s.pos.z, s.quat.x, s.quat.y, s.quat.z, s.quat.w], i * 7); });
      fr.f.push(arr);
    }
    const bp = sc.blood.parts;
    const n = Math.min(bp.length, 400);
    const ba = new Float32Array(n * 4);
    for (let i = 0; i < n; i++) { const d = bp[i]; ba[i * 4] = d.p.x; ba[i * 4 + 1] = d.p.y; ba[i * 4 + 2] = d.p.z; ba[i * 4 + 3] = d.r; }
    fr.blood = ba;
    this.frames.push(fr);
    if (this.frames.length > this.max) this.frames.shift();
  }
  start(focus, done) {
    if (this.frames.length < 30) { done(); return; }
    this.playing = true; this.done = done;
    this.idx = Math.max(0, this.frames.length - 260);
    this.t = 0; this.focus = focus;
    this.scene.hud.message('INSTANT REPLAY', 99, 'replay');
    this.angle = rng() * Math.PI * 2;
  }
  play(dt) {
    const sc = this.scene;
    this.t += dt * 0.32 * 60; // slow motion
    const i = Math.min(this.frames.length - 1, this.idx + Math.floor(this.t));
    const fr = this.frames[i];
    const all = [...sc.fighters, sc.ref];
    const q = new THREE.Quaternion(), p = new THREE.Vector3(), one = new THREE.Vector3(1, 1, 1);
    all.forEach((f, k) => {
      const arr = fr.f[k];
      f.model.segs.forEach((g, si) => {
        p.set(arr[si * 7], arr[si * 7 + 1], arr[si * 7 + 2]); q.set(arr[si * 7 + 3], arr[si * 7 + 4], arr[si * 7 + 5], arr[si * 7 + 6]);
        g.matrix.compose(p, q, one); g.matrixWorldNeedsUpdate = true;
      });
    });
    // blood
    const mesh = sc.blood.mesh, m = new THREE.Matrix4(), s = new THREE.Vector3();
    const n = fr.blood.length / 4;
    for (let j = 0; j < n; j++) { p.set(fr.blood[j * 4], fr.blood[j * 4 + 1], fr.blood[j * 4 + 2]); const r = fr.blood[j * 4 + 3]; s.set(r, r * 1.6, r); m.compose(p, q.identity(), s); mesh.setMatrixAt(j, m); }
    mesh.count = n; mesh.instanceMatrix.needsUpdate = true;
    // dramatic low orbiting camera around the loser's head
    const k = this.focus ? (this.focus === sc.red ? 0 : 1) : 0;
    const arr = fr.f[k];
    const head = new THREE.Vector3(arr[S.head * 7], arr[S.head * 7 + 1], arr[S.head * 7 + 2]);
    this.angle += dt * 0.35;
    this.cam.look.lerp(head, 0.2);
    this.cam.pos.set(head.x + Math.cos(this.angle) * 2.0, Math.max(0.5, head.y * 0.7 + 0.35), head.z + Math.sin(this.angle) * 2.0);
    if (i >= this.frames.length - 1 && this.t > (this.frames.length - this.idx) + 30) this.stop();
  }
  stop() {
    this.playing = false;
    this.scene.hud.message('', 0);
    this.scene.fighters.forEach((f) => f.model.update());
    const d = this.done; this.done = null; d && d();
  }
}
