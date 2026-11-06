// ===== AI fighter brain =====
// Reacts with human-like delays (fast jabs are hard to read, kicks are slower and easier), manages range by style,
// throws style-specific combinations, feints, attacks the body/legs when the head is covered, shoots takedowns
// under punches, sprawls, protects itself when hurt, and hunts the finish when the opponent is rocked.
import { clamp, rng } from './util.js';
import { cageDist } from './render.js';
import { MOVES } from './moves.js';

const COMBOS = {
  boxing: [['jab'], ['jab', 'cross'], ['jab', 'cross', 'leadHook'], ['cross', 'leadHook', 'cross'], ['jab', 'jab', 'cross'], ['leadHook', 'cross'], ['jabBody', 'cross'], ['jab', 'rearHook'], ['leadUpper', 'cross'], ['jab', 'cross', 'leadHookBody'], ['crossBody', 'leadHook']],
  muaythai: [['jab', 'rearBodyKick'], ['teep'], ['rearLowKick'], ['jab', 'cross', 'rearLowKick'], ['rearBodyKick'], ['jab', 'rearHeadKick'], ['leadLowKick'], ['cross', 'leadHook', 'rearLowKick'], ['teep', 'cross'], ['elbow']],
  kickboxing: [['jab', 'cross', 'rearLowKick'], ['jab', 'leadHook', 'rearBodyKick'], ['leadLowKick', 'cross'], ['jab', 'cross', 'leadHook', 'rearLowKick'], ['rearHeadKick'], ['leadBodyKick'], ['jab', 'cross']],
  wrestling: [['jab'], ['jab', 'cross'], ['cross'], ['jab', 'jab']],
  bjj: [['jab'], ['teep'], ['jab', 'cross'], ['leadLowKick']],
  judo: [['jab'], ['jab', 'cross'], ['rearLowKick']],
  sambo: [['jab', 'cross'], ['cross', 'leadHook'], ['rearLowKick'], ['jab']],
  brawler: [['rearHook'], ['cross', 'rearHook'], ['leadHook', 'rearHook', 'leadHook'], ['rearUpper'], ['cross', 'leadHook', 'rearHook'], ['rearHook', 'rearUpper']],
};

export class AI {
  constructor(fighter, level = 0.6) {
    this.f = fighter;
    this.level = level;
    this.t = 0;
    this.decideT = 0;
    this.combo = [];
    this.circle = rng() < 0.5 ? 1 : -1;
    this.circleT = 0;
    this.reactT = -1; this.reactTo = null; this.seen = null;
    this.plan = this.makePlan();
    this.blockHold = 0;
    this.subMashT = 0;
    this.groundT = 0;
    this.memory = { headBlocks: 0, bodyHits: 0, legHits: 0, oppShoots: 0 };
  }

  makePlan() {
    const f = this.f, s = f.prof.style || 'kickboxing';
    const A = (k) => f.A(k);
    const grap = (A('takedown') + A('topControl') + A('subOffense')) / 3;
    const strike = (A('punchPower') + A('punchSpeed') + A('kickPower') + A('accuracy')) / 4;
    return {
      style: s,
      grappler: grap > strike + 0.05 || s === 'wrestling' || s === 'bjj' || s === 'judo' || s === 'sambo',
      aggression: clamp(0.35 + (s === 'brawler' ? 0.35 : 0) + (s === 'wrestling' ? 0.15 : 0) + A('heart') * 0.2 - A('fightIQ') * 0.1 + (rng() - 0.5) * 0.2, 0.15, 0.95),
      range: s === 'boxing' || s === 'brawler' ? 0.95 : s === 'muaythai' || s === 'kickboxing' ? 1.2 : 1.05,
      kicky: s === 'muaythai' || s === 'kickboxing' ? 0.45 : s === 'boxing' ? 0.03 : 0.15,
      shootRate: s === 'wrestling' ? 0.5 : s === 'sambo' || s === 'judo' ? 0.3 : s === 'bjj' ? 0.32 : grap > 0.55 ? 0.15 : 0.03,
      clinchRate: s === 'muaythai' || s === 'judo' ? 0.25 : s === 'wrestling' ? 0.12 : 0.04,
      feint: 0.08 + A('fightIQ') * 0.15,
      counter: s === 'boxing' || A('fightIQ') > 0.7 ? 0.45 : 0.2,
    };
  }

  update(dt) {
    const f = this.f, o = f.opp;
    const inp = f.input;
    inp.mx = 0; inp.mz = 0; inp.block = false; inp.blockLow = false;
    if (!o) return;
    this.t += dt;
    const h = f.health;
    if (f.rig.mode !== 'anim' || f.state === 'down' || f.state === 'getup' || f.state === 'idle' || f.state === 'corner' || f.state === 'celebrate') return;
    if (f.state === 'grapple') return this.ground(dt);
    const dx = o.rig.root.x - f.rig.root.x, dz = o.rig.root.z - f.rig.root.z;
    const dist = Math.hypot(dx, dz) / f.u;
    const lvl = this.level;
    const iq = f.A('fightIQ');
    const hurt = h.rocked > 0;
    const oppHurt = o.health.rocked > 0 || o.state === 'down';
    const tired = h.stamina < 25;

    // ---------- defence: read the opponent's attack ----------
    const oa = o.action;
    if (oa && oa.type === 'strike' && oa !== this.seen && (oa.phase === 'wind' || oa.phase === 'ext')) {
      this.seen = oa;
      // reaction delay: ~150-350 ms, worse when hurt/tired; kicks take longer so are easier to react to
      const delay = (0.32 - iq * 0.12 - lvl * 0.1) * (hurt ? 1.6 : 1) * (tired ? 1.2 : 1) * (o.isPlayer ? 1 + 0.7 * (o.assist || 0) : 1);
      this.reactT = delay; this.reactTo = oa;
    }
    if (o.state === 'shoot' && !this.sprawled) {
      this.sprawled = true;
      this.memory.oppShoots++;
      if (rng() < 0.25 + f.A('tdDefense') * 0.5 + lvl * 0.2) inp.sprawl = true;
      // knee the level change!
      else if (dist < 1.0 && !f.action && rng() < 0.15 + lvl * 0.15 + (this.plan.style === 'muaythai' ? 0.25 : 0)) inp.strike = 'knee';
    }
    if (o.state !== 'shoot') this.sprawled = false;
    if (this.reactT >= 0) {
      this.reactT -= dt;
      if (this.reactT < 0 && this.reactTo === o.action && this.reactTo) {
        const def = this.reactTo.def;
        const r = rng();
        const pBlock = (0.25 + f.A('blocking') * 0.45 + lvl * 0.15) * (o.isPlayer ? 1 - 0.4 * (o.assist || 0) : 1);
        const pSlip = def.kind === 'punch' && def.path === 'straight' ? f.A('headMove') * 0.45 : f.A('headMove') * 0.2;
        if (this.reactTo.feint && rng() < iq * 0.6) { /* read the feint */ }
        else if (def.zone === 'leg' && rng() < f.A('legTough') * 0.4 + lvl * 0.25) inp.check = true;
        else if (r < pSlip && !f.action) { inp.slip = rng() < 0.5 ? 1 : -1; if (rng() < this.plan.counter) this.combo = [rng() < 0.5 ? 'cross' : 'leadHook']; }
        else if (r < pSlip + pBlock) { this.blockHold = 0.35 + (def.kind === 'kick' ? 0.25 : 0); this.blockLowNext = def.zone === 'body'; }
        else if (rng() < f.A('footwork') * 0.4) this.backT = 0.35;
      }
    }
    if (this.blockHold > 0) { this.blockHold -= dt; inp.block = true; inp.blockLow = !!this.blockLowNext; }

    // ---------- movement / range ----------
    let want = this.plan.range * (hurt ? 1.5 : 1);
    if (oppHurt && !hurt) want = 0.85;
    if (this.plan.grappler && this.plan.shootRate > 0.25) want = 1.05;
    const aggr = clamp(this.plan.aggression + (oppHurt ? 0.4 : 0) - (hurt ? 0.5 : 0) - (tired ? 0.25 : 0) + (this.f.game.match ? this.f.game.match.aiUrgency(f) : 0), 0, 1);
    this.circleT -= dt;
    if (this.circleT <= 0) { this.circleT = 1.5 + rng() * 3; if (rng() < 0.4) this.circle *= -1; }
    // avoid getting stuck on the cage: circle toward open space
    const cd = cageDist(f.rig.root);
    let mx = this.circle * (0.55 - aggr * 0.25);
    let mz = 0;
    if (dist > want + 0.12) mz = 0.6 + aggr * 0.4;
    else if (dist < want - 0.15) mz = -0.6 - (1 - aggr) * 0.3;
    if (cd < 0.8 && dist < 1.6) { mz = Math.max(mz, -0.1); mx = this.circle * 0.9; }
    if (this.backT > 0) { this.backT -= dt; mz = -1; }
    if (hurt && rng() < dt * 0.6 && dist < 1.0) { inp.clinch = true; } // tie up to survive
    if (hurt) { inp.block = true; mz = Math.min(mz, -0.4); }
    // occasional stance stillness for realism
    inp.mx = mx * (0.5 + lvl * 0.5); inp.mz = mz;

    // follow a downed opponent to the mat (grapplers love it, strikers sometimes wave them up)
    if (o.state === 'down' && dist < 1.8 && !f.action) {
      const want = this.plan.grappler ? 0.025 : 0.008;
      inp.mz = 0.8;
      if (rng() < want) inp.shoot = true;
    }
    // ---------- offence ----------
    this.decideT -= dt;
    const canAct = !f.action || (f.action.type === 'strike' && f.action.phase === 'ret');
    if (this.combo.length && canAct && !inp.block) {
      const next = this.combo.shift();
      if (MOVES[next]) inp.strike = next;
      else if (next === 'shoot') inp.shoot = true;
      else if (next === 'clinch') inp.clinch = true;
      inp.feint = false;
    } else if (this.decideT <= 0 && !f.action && !hurt) {
      // real MMA pace: ~10-20 strike attempts per minute, with feints, resets and feeling out
      this.decideT = (0.9 + rng() * 1.6) * (1.35 - aggr * 0.6) * (tired ? 1.6 : 1) / (0.75 + lvl * 0.4) * (o.isPlayer ? 1 + 0.5 * (o.assist || 0) : 1);
      const inRange = dist < this.plan.range + 0.25;
      if (f.clinch) {
        // clinch work: knees, elbows, short punches, trips
        const r = rng();
        if (r < 0.4) this.combo = ['knee'];
        else if (r < 0.55) this.combo = ['elbow'];
        else if (r < 0.7) this.combo = ['cross', 'leadHook'];
        else if (r < 0.7 + this.plan.shootRate * 0.6) inp.shoot = true;
        else if (rng() < 0.2) inp.mz = -1;
      } else if (inRange || (oppHurt && dist < 1.6)) {
        const r = rng();
        if (r < this.plan.shootRate * (0.4 + aggr * 0.6) && dist < 1.25) {
          // set up the shot behind a strike (level change under the jab)
          this.combo = rng() < 0.6 ? ['jab', 'shoot'] : ['shoot'];
        } else if (r < this.plan.shootRate + this.plan.clinchRate * 0.5 && dist < 1.0) {
          this.combo = ['clinch'];
        } else {
          let pool = COMBOS[this.plan.style] || COMBOS.kickboxing;
          let c = pool[Math.floor(rng() * pool.length)].slice();
          // adaptive targeting: opponent covering head -> go to the body / legs
          if (o.blocking && rng() < 0.6) c = c.map((m) => (m === 'jab' ? 'jabBody' : m === 'cross' ? 'crossBody' : m === 'leadHook' ? 'leadHookBody' : m));
          if (o.health.legs[o.lead] > 50 && rng() < 0.4) c.push('rearLowKick');
          if (oppHurt) c = ['cross', 'leadHook', 'cross', 'rearHook'];
          if (dist > 1.15 && !c.some((m) => MOVES[m] && MOVES[m].kind === 'kick')) c.unshift('jab');
          this.combo = c;
          if (rng() < this.plan.feint) { inp.feint = true; inp.strike = c[0]; this.combo = c.slice(1); }
        }
      } else if (dist < 1.6 && rng() < this.plan.kicky) {
        this.combo = [rng() < 0.5 ? 'rearLowKick' : 'teep'];
      }
    }
    if (inp.shoot && this.f.game.grapple && this.f.game.grapple.frontHeadlock && this.f.game.grapple.frontHeadlock.att === f) { /* handled in fighter */ }
    // guillotine opportunity after a sprawl
    const fh = this.f.game.grapple && this.f.game.grapple.frontHeadlock;
    if (fh && fh.att === f && fh !== this.fhSeen) { this.fhSeen = fh; if (rng() < f.A('subOffense') * 0.45) this.f.game.grapple.tryGuillotine(f); }
  }

  ground(dt) {
    const f = this.f, L = f.grapple, g = (f.input.g = f.input.g || {});
    if (!L) return;
    const isTop = L.top === f;
    const o = isTop ? L.bot : L.top;
    this.groundT -= dt;
    const lvl = this.level;
    // submissions: mash
    if (L.sub) {
      this.subMashT -= dt;
      if (this.subMashT <= 0) { this.subMashT = 0.12 + (1 - lvl) * 0.2 + rng() * 0.1; g.mash = true; }
      return;
    }
    if (L.attempt) return;
    f.input.block = false;
    if (isTop) {
      if (this.groundT > 0) return;
      this.groundT = 0.35 + rng() * 0.6 / (0.6 + lvl);
      const r = rng();
      const subSkill = f.A('subOffense');
      const gnp = f.prof.style === 'wrestling' || f.prof.style === 'brawler' || f.prof.style === 'sambo' ? 0.65 : 0.45;
      if ((L.pos === 'back' || L.pos === 'mount' || L.pos === 'side') && r < 0.03 + subSkill * subSkill * 0.22 + (L.pos === 'back' ? 0.1 : 0)) g.sub = true;
      else if (r < 0.06 + f.A('topControl') * 0.12 && L.pos !== 'back') g.advance = true;
      else if (r < gnp) f.input.strike = rng() < 0.25 ? 'elbow' : rng() < 0.5 ? 'cross' : 'jab';
      else if (r < gnp + 0.03 && f.prof.style !== 'wrestling' && f.prof.style !== 'bjj' && f.A('topControl') < 0.5) g.escape = true; // strikers stand up
    } else {
      // bottom: defend when getting hit, work escapes/sweeps/subs
      if (o.action && o.action.type === 'strike') f.input.block = rng() < 0.4 + f.A('blocking') * 0.4;
      if (this.groundT > 0) return;
      this.groundT = 0.6 + rng() * 0.8 / (0.6 + lvl);
      const r = rng();
      const bjj = f.A('bottomGame'), sub = f.A('subOffense');
      if ((L.pos === 'guard' || L.pos === 'half') && r < 0.015 + sub * sub * 0.2) g.sub = true;
      else if (r < 0.25 + bjj * 0.2) g[L.pos === 'guard' || L.pos === 'half' ? 'advance' : 'escape'] = true;
      else if (r < 0.5) g.getup = true;
      else if (L.pos === 'guard' && r < 0.6) f.input.strike = 'elbow';
    }
  }
}
