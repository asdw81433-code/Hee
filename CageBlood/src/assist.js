// ===== Simple controls: one button per intent; the game picks the right technique =====
// Punch / Kick / Grab / Guard / Dodge. Range, clinch, ground position and the opponent's state decide
// which real technique comes out, and an assisted step-in closes distance so strikes actually land.
import * as THREE from 'three';
import { rng } from './util.js';

const _f = new THREE.Vector3();
const PUNCH_COMBO = ['jab', 'cross', 'leadHook', 'cross', 'rearUpper', 'jab', 'leadHookBody', 'cross'];
const KICK_CYCLE = ['rearLowKick', 'rearBodyKick', 'leadLowKick', 'rearBodyKick'];

function dist(f) {
  const o = f.opp; if (!o) return 9;
  return Math.hypot(o.rig.root.x - f.rig.root.x, o.rig.root.z - f.rig.root.z) / f.u;
}
function stepIn(f, amount) {
  // short assisted lunge toward the opponent (like a real step-in jab)
  f.rig.F.quat.setFromAxisAngle(_f.set(0, 1, 0), f.rig.yaw);
  _f.set(0, 0, 1).applyQuaternion(f.rig.F.quat);
  f.vel.addScaledVector(_f, amount);
}

export function smartPunch(f, game) {
  const inp = f.input, L = game.grapple && game.grapple.link;
  if (L && L.sub && (L.sub.att === f || L.sub.def === f)) { (inp.g = inp.g || {}).mash = true; return; }
  if (f.state === 'grapple') {
    const top = L && L.top === f;
    const seq = top ? ['cross', 'jab', 'elbow', 'cross', 'rearHook'] : ['jab', 'cross'];
    f._gp = ((f._gp || 0) + 1) % seq.length;
    inp.strike = seq[f._gp];
    return;
  }
  const d = dist(f), o = f.opp;
  const now = game.time;
  if (now - (f._lastSmart || -9) > 1.3) f._combo = 0;
  f._lastSmart = now;
  let id;
  if (f.clinch || d < 0.72) id = ['rearUpper', 'leadHook', 'elbow', 'rearHook'][(f._combo++) % 4];
  else if (o && (o.health.rocked > 0 || o.state === 'down')) id = ['cross', 'leadHook', 'rearHook'][(f._combo++) % 3];
  else if (o && o.blocking && !o.blockLow && rng() < 0.6) id = ['jabBody', 'leadHookBody', 'crossBody'][(f._combo++) % 3];
  else id = PUNCH_COMBO[(f._combo++) % PUNCH_COMBO.length];
  if (d > 1.0 && d < 2.4) stepIn(f, 1.6 + (d - 1.0) * 1.2);
  inp.strike = id;
}

export function smartKick(f, game) {
  const inp = f.input, L = game.grapple && game.grapple.link;
  if (L && L.sub && (L.sub.att === f || L.sub.def === f)) { (inp.g = inp.g || {}).mash = true; return; }
  if (f.state === 'grapple') { smartPunch(f, game); return; }
  const d = dist(f), o = f.opp;
  let id;
  if (f.clinch || d < 0.8) id = 'knee';
  else if (o && o.health.rocked > 0 && rng() < 0.5) id = 'rearHeadKick';
  else if (o && o.health.legs[o.lead] > 55) id = rng() < 0.6 ? 'rearLowKick' : 'leadLowKick';
  else { f._kick = ((f._kick || 0) + 1) % KICK_CYCLE.length; id = rng() < 0.12 ? 'rearHeadKick' : KICK_CYCLE[f._kick]; }
  if (d > 1.35 && d < 2.6) stepIn(f, 1.4 + (d - 1.35) * 1.2);
  inp.strike = id;
}

export function smartGrab(f, game) {
  const inp = f.input, gr = game.grapple, g = (inp.g = inp.g || {});
  const L = gr && gr.link;
  if (L && L.sub && (L.sub.att === f || L.sub.def === f)) { g.mash = true; return; }
  if (gr && gr.frontHeadlock && gr.frontHeadlock.att === f) { gr.tryGuillotine(f); return; }
  if (f.state === 'grapple' && L && L.type === 'ground') {
    const o = L.top === f ? L.bot : L.top;
    if (L.top === f) {
      // dominant position + tired / hurt opponent -> submission, otherwise improve position
      const good = L.pos === 'mount' || L.pos === 'back' || L.pos === 'side';
      if (good && (o.health.stamina < 55 || o.health.rocked > 0 || rng() < 0.35)) g.sub = true;
      else if (L.pos !== 'back') g.advance = true;
      else g.sub = true;
    } else {
      if ((L.pos === 'guard' || L.pos === 'half') && rng() < 0.45) g.advance = true; // sweep
      else if ((L.pos === 'guard' || L.pos === 'half') && f.A('subOffense') > 0.55 && rng() < 0.35) g.sub = true;
      else if (L.pos === 'guard') g.getup = true;
      else g.escape = true;
    }
    return;
  }
  if (f.clinch) { inp.shoot = true; return; } // trip / throw from the clinch
  const d = dist(f), o = f.opp;
  if (o && o.state === 'down') { inp.shoot = true; return; }
  if (d < 0.85) inp.clinch = true;
  else if (d < 1.9) inp.shoot = true;
  else { stepIn(f, 2.2); inp.shoot = true; }
}

export function smartDodge(f, game) {
  const inp = f.input, o = f.opp;
  const L = game.grapple && game.grapple.link;
  if (L && L.sub && L.sub.def === f) { (inp.g = inp.g || {}).mash = true; return; }
  if (f.state === 'grapple') { const g = (inp.g = inp.g || {}); if (L && L.bot === f) g.escape = true; else g.getup = true; return; }
  if (o && o.state === 'shoot') { inp.sprawl = true; inp.duck = true; return; }
  // slip the side the punch is coming from (lead punches -> slip outside)
  if (o && o.action && o.action.type === 'strike' && o.action.def.kind === 'kick') { inp.mz = -1; f.vel.addScaledVector(_f.set(Math.sin(f.rig.yaw), 0, Math.cos(f.rig.yaw)), -1.8); return; }
  f._slipSide = -(f._slipSide || 1);
  inp.slip = f._slipSide;
}
