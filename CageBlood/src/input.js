// ===== Keyboard input -> fighter commands =====
import { resolveStrike } from './moves.js';
import { smartPunch, smartKick, smartGrab, smartDodge } from './assist.js';

export class Keys {
  constructor() {
    this.down = new Set();
    this.vdown = new Set();
    this.pressed = new Set();
    this.analog = { x: 0, y: 0, on: false, dir: '' };
    this.enabled = true;
    window.addEventListener('keydown', (e) => {
      if (!this.enabled) return;
      if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT')) return;
      const k = e.code;
      if (['Space', 'Tab', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'F1'].includes(k)) e.preventDefault();
      if (!this.down.has(k)) this.pressed.add(k);
      this.down.add(k);
    });
    window.addEventListener('keyup', (e) => { this.down.delete(e.code); });
    window.addEventListener('blur', () => { this.down.clear(); });
  }
  // virtual keys (touch controls)
  vDown(k) { if (!this.vdown.has(k)) this.pressed.add(k); this.vdown.add(k); }
  vUp(k) { this.vdown.delete(k); }
  vTap(k) { this.pressed.add(k); }
  is(k) { return this.down.has(k) || this.vdown.has(k); }
  hit(k) { return this.pressed.has(k); }
  endFrame() { this.pressed.clear(); }
}

const STRIKE_KEYS = {
  KeyJ: 'jab', KeyK: 'cross', KeyU: 'leadHook', KeyI: 'rearHook', KeyN: 'leadUpper', KeyM: 'rearUpper',
  KeyO: 'leadKick', KeyL: 'rearKick', KeyP: 'teep', KeyH: 'knee', KeyY: 'elbow',
};

export function applyPlayerInput(keys, f, game) {
  const inp = f.input;
  const g = (inp.g = inp.g || {});
  let mx = 0, mz = 0;
  if (keys.is('KeyW') || keys.is('ArrowUp')) mz += 1;
  if (keys.is('KeyS') || keys.is('ArrowDown')) mz -= 1;
  if (keys.is('KeyA') || keys.is('ArrowLeft')) mx += 1;
  if (keys.is('KeyD') || keys.is('ArrowRight')) mx -= 1;
  if (keys.analog && keys.analog.on && Math.hypot(keys.analog.x, keys.analog.y) > 0.18) { mx = -keys.analog.x; mz = keys.analog.y; }
  inp.mx = mx; inp.mz = mz;
  if (!game.settings || game.settings.controls !== 'pro') { applySimple(keys, f, game); return; }
  const body = keys.is('ShiftLeft') || keys.is('ShiftRight');
  const high = keys.is('KeyQ');
  inp.block = keys.is('Space');
  inp.blockLow = body;
  inp.feint = keys.is('KeyV');
  for (const code in STRIKE_KEYS) {
    if (keys.hit(code)) {
      let id = resolveStrike(STRIKE_KEYS[code], body, high);
      if (f.clinch && (id.includes('Kick') || id === 'teep')) id = 'knee';
      inp.strike = id;
    }
  }
  if (keys.hit('KeyZ')) inp.slip = 1;
  if (keys.hit('KeyX')) inp.slip = -1;
  if (keys.hit('KeyC')) { inp.duck = true; inp.sprawl = true; }
  if (keys.hit('KeyE')) inp.check = true;
  if (keys.hit('KeyF')) { if (f.clinch) inp.mz = -1; else inp.clinch = true; }
  if (keys.hit('KeyG')) {
    const gr = game.grapple;
    if (gr && gr.frontHeadlock && gr.frontHeadlock.att === f) gr.tryGuillotine(f);
    else if (f.state === 'grapple') { if (gr.link && gr.link.sub && gr.link.sub.att === f) g.mash = true; else g.sub = true; }
    else inp.shoot = true;
  }
  // ground controls
  if (f.state === 'grapple' && game.grapple && game.grapple.link) {
    const L = game.grapple.link;
    const top = L.top === f;
    inp.mx = 0; inp.mz = 0;
    if (L.sub) {
      if (L.sub.def === f && (keys.hit('Space') || keys.hit('KeyA') || keys.hit('KeyD'))) g.mash = true;
      if (L.sub.att === f && keys.hit('Space')) g.mash = true;
    } else {
      if (keys.hit('KeyW')) g.advance = true;
      if (keys.hit('KeyS')) g.getup = true;
      if (!top && (keys.hit('KeyA') || keys.hit('KeyD'))) g.escape = true;
      if (top && keys.hit('KeyS')) g.getup = true;
    }
  }
}

// ---- Simple controls: J punch · K kick · L grab · Space guard · Shift/C dodge (touch uses the same virtual codes)
function applySimple(keys, f, game) {
  const inp = f.input;
  const g = (inp.g = inp.g || {});
  inp.block = keys.is('Space') || keys.is('SmartGuard');
  inp.blockLow = false;
  inp.feint = false;
  const L = game.grapple && game.grapple.link;
  const inSub = !!(L && L.sub && (L.sub.att === f || L.sub.def === f));
  if (inSub) {
    // any button mashes during a submission
    for (const k of ['KeyJ', 'KeyK', 'KeyL', 'Space', 'ShiftLeft', 'KeyC', 'SmartPunch', 'SmartKick', 'SmartGrab', 'SmartDodge', 'SmartGuard', 'Enter']) if (keys.hit(k)) g.mash = true;
    inp.mx = 0; inp.mz = 0;
    return;
  }
  if (keys.hit('KeyJ') || keys.hit('SmartPunch')) smartPunch(f, game);
  if (keys.hit('KeyK') || keys.hit('SmartKick')) smartKick(f, game);
  if (keys.hit('KeyL') || keys.hit('SmartGrab')) smartGrab(f, game);
  if (keys.hit('ShiftLeft') || keys.hit('ShiftRight') || keys.hit('KeyC') || keys.hit('SmartDodge')) smartDodge(f, game);
  if (f.state === 'grapple' && L) {
    inp.mx = 0; inp.mz = 0;
    const top = L.top === f;
    if (keys.hit('KeyW')) g.advance = true;
    if (keys.hit('KeyS')) g.getup = true;
    if (!top && (keys.hit('KeyA') || keys.hit('KeyD'))) g.escape = true;
  }
}
