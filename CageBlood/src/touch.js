// ===== On-screen touch controls (phones / tablets) =====
// Left: virtual joystick (movement / ground transitions). Right: pictogram buttons that drive the same
// virtual key codes as the keyboard, so every move in the game is reachable by touch.
import { el } from './util.js';
import { icon } from './icons.js';

export class TouchControls {
  constructor(app) {
    this.app = app;
    this.keys = app.keys;
    this.root = el('div', { class: 'touch hidden' });
    app.uiRoot.appendChild(this.root);
    // stop the browser's synthetic mouse/click events after a tap (they would "ghost click" menus that just opened)
    this.root.addEventListener('touchstart', (e) => { if (e.target !== this.root) e.preventDefault(); }, { passive: false });
    this.root.addEventListener('touchend', (e) => { if (e.target !== this.root) e.preventDefault(); }, { passive: false });
    this.toggles = { body: false, high: false };
    this.build();
    this.visible = false;
  }

  static wanted(setting) {
    if (setting === 'on') return true;
    if (setting === 'off') return false;
    return (typeof matchMedia !== 'undefined' && matchMedia('(pointer: coarse)').matches) || 'ontouchstart' in window;
  }

  show(v) {
    this.visible = v; this.root.classList.toggle('hidden', !v); if (!v) this.resetStick();
    const simple = (this.app.save.settings.controls || 'simple') !== 'pro';
    this.root.classList.toggle('simple', simple);
  }

  // a button that taps (or holds) a virtual key
  btn(name, code, label, opts = {}) {
    const b = el('div', { class: 'tbtn ' + (opts.cls || ''), role: 'button', 'aria-label': label }, icon(name, opts.size || 26), el('span', { class: 'tlbl' }, label));
    const down = (e) => {
      e.preventDefault(); e.stopPropagation();
      b.setPointerCapture && b.setPointerCapture(e.pointerId);
      b.classList.add('on');
      this.app.audio.init(); this.app.audio.resume();
      if (opts.onPress) { opts.onPress(); return; }
      if (opts.hold) this.keys.vDown(code); else this.keys.vTap(code);
    };
    const up = (e) => { b.classList.remove('on'); if (opts.hold) this.keys.vUp(code); };
    b.addEventListener('pointerdown', down);
    b.addEventListener('pointerup', up); b.addEventListener('pointercancel', up); b.addEventListener('lostpointercapture', up);
    return b;
  }
  toggle(name, key, code, label) {
    const b = el('div', { class: 'tbtn tog', role: 'button', 'aria-label': label }, icon(name, 22), el('span', { class: 'tlbl' }, label));
    b.addEventListener('pointerdown', (e) => {
      e.preventDefault(); e.stopPropagation();
      this.toggles[key] = !this.toggles[key];
      b.classList.toggle('on', this.toggles[key]);
      if (this.toggles[key]) this.keys.vDown(code); else this.keys.vUp(code);
    });
    return b;
  }

  build() {
    const r = this.root;
    // --- joystick
    this.stick = el('div', { class: 'tstick' }, el('div', { class: 'tknob' }));
    this.knob = this.stick.firstChild;
    const zone = el('div', { class: 'tzone' }, this.stick);
    let pid = null, cx = 0, cy = 0;
    const R = 52;
    zone.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      pid = e.pointerId; zone.setPointerCapture(e.pointerId);
      const rc = this.stick.getBoundingClientRect(); cx = rc.left + rc.width / 2; cy = rc.top + rc.height / 2;
      this.moveStick(e.clientX - cx, e.clientY - cy, R);
      this.app.audio.init(); this.app.audio.resume();
    });
    zone.addEventListener('pointermove', (e) => { if (e.pointerId === pid) this.moveStick(e.clientX - cx, e.clientY - cy, R); });
    const end = (e) => { if (e.pointerId === pid) { pid = null; this.resetStick(); } };
    zone.addEventListener('pointerup', end); zone.addEventListener('pointercancel', end);
    // --- action cluster
    const T = (n, c, l, o) => this.btn(n, c, l, o);
    this.pad = el('div', { class: 'tpad' },
      el('div', { class: 'trow' }, T('teep', 'KeyP', 'ถีบ', { cls: 'sm' }), T('knee', 'KeyH', 'เข่า', { cls: 'sm' }), T('elbow', 'KeyY', 'ศอก', { cls: 'sm' }), T('check', 'KeyE', 'กันเตะ', { cls: 'sm' })),
      el('div', { class: 'trow' }, T('kick', 'KeyO', 'เตะหน้า'), T('kick', 'KeyL', 'เตะหลัง', { cls: 'kickR' }), T('upper', 'KeyM', 'อัปเปอร์')),
      el('div', { class: 'trow' }, T('hookL', 'KeyU', 'ฮุคซ้าย'), T('hookR', 'KeyI', 'ฮุคขวา'), T('upper', 'KeyN', 'อัปหน้า', { cls: 'sm' })),
      el('div', { class: 'trow' }, T('jab', 'KeyJ', 'แย็บ', { cls: 'big' }), T('fist', 'KeyK', 'หมัดหลัง', { cls: 'big' }), T('shield', 'Space', 'การ์ด', { cls: 'big guard', hold: true })),
    );
    this.side = el('div', { class: 'tside' },
      this.toggle('body', 'body', 'ShiftLeft', 'ลำตัว/ขา'), this.toggle('up', 'high', 'KeyQ', 'เตะหัว'),
      T('dodge', 'KeyZ', 'หลบ', { onPress: () => { const x = this.keys.analog.x; this.keys.vTap(x > 0.2 ? 'KeyX' : x < -0.2 ? 'KeyZ' : (this._alt = !this._alt) ? 'KeyZ' : 'KeyX'); } }),
      T('duck', 'KeyC', 'ก้ม/สปรอล'),
      T('clinch', 'KeyF', 'คลินช์'), T('takedown', 'KeyG', 'ปล้ำ/ล็อก'),
      T('eye', 'KeyV', 'หลอก', { hold: true }),
    );
    this.top = el('div', { class: 'ttop' },
      T('pause', 'Escape', 'หยุด', { cls: 'sm', onPress: () => this.app.ui.togglePause() }),
      T('body', 'Tab', 'ร่างกาย', { cls: 'sm', onPress: () => this.app.hud.toggleDamage() }),
      T('camera', 'KeyT', 'กล้อง', { cls: 'sm', onPress: () => { const c = this.app.world.cam; c.mode = c.mode === 'orbit' ? 'broadcast' : 'orbit'; c.orbitDist = 4.5; } }));
    this.mash = el('div', { class: 'tmash hidden' }, T('hand', 'Space', 'รัวเพื่อแก้/บีบ!', { cls: 'huge', onPress: () => { this.keys.vTap('Space'); this.keys.vTap('KeyG'); this.keys.vTap('SmartGrab'); } }));
    // simple layout: five big buttons, the game picks the technique
    this.easy = el('div', { class: 'teasy' },
      el('div', { class: 'erow' }, T('dodge', 'SmartDodge', 'หลบ', { cls: 'emid' }), T('takedown', 'SmartGrab', 'ปล้ำ', { cls: 'emid grab' })),
      el('div', { class: 'erow' }, T('kick', 'SmartKick', 'เตะ', { cls: 'ebig kickb' }), T('shield', 'SmartGuard', 'การ์ด', { cls: 'emid guard', hold: true })),
      el('div', { class: 'erow' }, T('fist', 'SmartPunch', 'ต่อย', { cls: 'ehuge punch' })),
    );
    const rot = el('div', { class: 'rotate-hint' }, icon('rotate', 28), 'หมุนจอเป็นแนวนอนจะเล่นง่ายกว่า');
    r.append(zone, this.pad, this.side, this.easy, this.top, this.mash, rot);
  }

  moveStick(dx, dy, R) {
    const d = Math.hypot(dx, dy) || 1;
    const k = Math.min(1, R / d);
    const x = dx * k, y = dy * k;
    this.knob.style.transform = `translate(${x}px, ${y}px)`;
    const nx = x / R, ny = -y / R;
    const a = this.keys.analog;
    // edge "presses" for ground transitions (W/S/A/D taps)
    const was = a.dir;
    const dir = Math.hypot(nx, ny) < 0.7 ? '' : Math.abs(nx) > Math.abs(ny) ? (nx > 0 ? 'KeyD' : 'KeyA') : ny > 0 ? 'KeyW' : 'KeyS';
    if (dir && dir !== was) this.keys.pressed.add(dir);
    a.x = nx; a.y = ny; a.on = true; a.dir = dir;
  }
  resetStick() { this.knob.style.transform = ''; const a = this.keys.analog; a.x = 0; a.y = 0; a.on = false; a.dir = ''; }

  // contextual layout: show a big "mash" button during submissions
  update(sc) {
    if (!this.visible || !sc) return;
    const L = sc.grapple && sc.grapple.link;
    const inSub = !!(L && L.sub && sc.player && (L.sub.att === sc.player || L.sub.def === sc.player));
    this.mash.classList.toggle('hidden', !inSub);
    const ground = !!(L && L.type === 'ground');
    this.root.classList.toggle('ground', ground);
  }
}
