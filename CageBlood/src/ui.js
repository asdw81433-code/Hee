// ===== Menus, career hub, story, corner, results, sandbox =====
import * as THREE from 'three';
import { el, money, clamp, rng, fmtTime } from './util.js';
import { makeNPC } from './npc.js';
import { Creator, computeAttrs, loadFaceCanvas, profileForFight, defaultProfile } from './creator.js';
import { Career, ACTIVITIES, GYMS, overall } from './career.js';
import { storyById } from './story.js';
import { writeSave, DEFAULT_SETTINGS, exportSave, importSave, PRESETS } from './save.js';
import { STYLES, PROMOTIONS, ATTRS, ATTR_LABEL, wcById, WEIGHT_CLASSES } from './data.js';
import { Fighter } from './fighter.js';
import { P } from './rig.js';
import { icon } from './icons.js';
import { drawHeadThumb } from './hair.js';
import { TouchControls } from './touch.js';

const STYLE_KEYS = Object.keys(STYLES);

export class UI {
  constructor(app) {
    this.app = app;
    this.layer = el('div', { class: 'menu-layer' });
    app.uiRoot.appendChild(this.layer);
    this.screen = null;
    this.career = app.save.career ? new Career(app.save.career) : null;
    this.bindKeys();
    this.bindOrbit();
  }

  // ---------- plumbing ----------
  save() {
    if (this.career) this.app.save.career = this.career.d;
    writeSave(this.app.save);
  }
  go(name, data = {}) { this.screen = { name, data }; this.refresh(); }
  refresh() {
    const s = this.screen;
    this.app.uiRoot.classList.toggle('menu-open', !!s);
    if (s && this.app.touch) { this.app.keys.vdown.clear(); this.app.touch.resetStick(); }
    if (!s) { this.layer.innerHTML = ''; return; }
    const fn = this['scr_' + s.name];
    this.layer.innerHTML = '';
    if (fn) { const node = fn.call(this, s.data); if (node) this.layer.appendChild(node); }
  }
  close() { this.screen = null; this.layer.innerHTML = ''; this.app.uiRoot.classList.remove('menu-open'); }
  // in-page dialogs (browser alert/confirm/prompt are blocked in some embeds)
  ask(text, onYes, yesLabel = 'ยืนยัน') {
    const ov = el('div', { class: 'screen dim modal' }, el('div', { class: 'panel', style: { width: 'min(440px, 100%)' } },
      el('p', { style: { fontSize: '16px' } }, text),
      el('div', { class: 'row' },
        el('button', { class: 'btn primary', onclick: () => { ov.remove(); onYes(); } }, yesLabel),
        el('button', { class: 'btn', onclick: () => ov.remove() }, 'ยกเลิก'))));
    this.app.uiRoot.appendChild(ov);
  }
  textBox(title, value, onOk, okLabel) {
    const ta = el('textarea', { id: 'savecode', rows: 6, style: { width: '100%', background: '#121217', color: '#e9e6e1', border: '1px solid #34343e', borderRadius: '4px', padding: '8px', fontFamily: 'monospace', fontSize: '12px' } });
    ta.value = value || '';
    const ov = el('div', { class: 'screen dim modal' }, el('div', { class: 'panel', style: { width: 'min(560px, 100%)' } },
      el('h3', {}, title), ta,
      el('div', { class: 'row', style: { marginTop: '10px' } },
        onOk ? el('button', { class: 'btn primary', onclick: () => { ov.remove(); onOk(ta.value); } }, okLabel || 'ตกลง') : null,
        el('button', { class: 'btn', onclick: () => ov.remove() }, onOk ? 'ยกเลิก' : 'ปิด'))));
    this.app.uiRoot.appendChild(ov);
    setTimeout(() => { ta.focus(); if (value) ta.select(); }, 30);
  }
  toast(t, ms = 2500) { const e = el('div', { class: 'toast' }, t); this.app.uiRoot.appendChild(e); setTimeout(() => e.remove(), ms); }
  frame(dt) { if (this.tut) this.tutFrame(dt); }

  // ================= TUTORIAL =================
  startTutorial() {
    this.stopBackground(); this.close();
    if (this.sbPanel) { this.sbPanel.remove(); this.sbPanel = null; }
    const me = makeNPC(Math.floor(rng() * 1e9), { tier: 2, wc: 'light', style: 'boxing' });
    me.name = 'คุณ'; me.nick = '';
    const dummy = makeNPC(Math.floor(rng() * 1e9), { tier: 0, wc: 'light', style: 'kickboxing' });
    dummy.name = 'คู่ซ้อม'; dummy.nick = 'Sparring';
    for (const k of ['tdDefense', 'clinch', 'subDefense', 'bottomGame', 'strength', 'headMove', 'blocking']) dummy.attrs[k] = 8;
    const sc = this.app.startFight({ red: me, blue: dummy, playerSide: 'red', rounds: 1, roundLen: 9999, sandbox: true, aiLevel: 0.2, brand: 'IRON GATE', title: 'ฝึกเล่น' });
    sc.tutorial = true;
    sc.ais.clear();
    const orig = sc.stepFixed.bind(sc);
    sc.stepFixed = (h) => { for (const f of sc.fighters) { f.health.consc = Math.max(f.health.consc, 0.7); f.health.rocked = 0; f.health.stamina = Math.max(f.health.stamina, 40); f.ko = false; } orig(h); };
    const touch = TouchControls.wanted(this.app.save.settings.touch);
    const k = (key, btn) => (touch ? btn : key);
    const P = () => sc.player;
    const dist = () => P().rig.root.distanceTo(P().opp.rig.root);
    const STEPS = [
      { pic: '🕹️', t: 'เดินเข้าหาคู่ซ้อม', s: touch ? 'ดันจอยซ้ายขึ้น' : 'กด W ค้างไว้', done: () => dist() < 1.5 },
      { pic: '👊', t: 'ต่อย 4 ครั้ง', s: `กด ${k('J', 'ปุ่ม ต่อย')} ติดกัน = คอมโบ (เกมเลือกหมัดให้เอง)`, base: () => P().cnt?.punch || 0, done: (b) => (P().cnt?.punch || 0) - b >= 4 },
      { pic: '🦵', t: 'เตะ 2 ครั้ง', s: `กด ${k('K', 'ปุ่ม เตะ')} — ใกล้มาก ๆ จะเป็นเข่า`, base: () => (P().cnt?.kick || 0) + (P().cnt?.knee || 0), done: (b) => (P().cnt?.kick || 0) + (P().cnt?.knee || 0) - b >= 2 },
      { pic: '🛡️', t: 'ยกการ์ดกันหมัด 2 ครั้ง', s: `กด ${k('Space', 'ปุ่ม การ์ด')} ค้างไว้ — คู่ซ้อมจะเริ่มต่อยแล้ว`, start: () => { const ai = new sc._AI(sc.blue, 0.25); ai.plan.aggression = 0.9; ai.plan.shootRate = 0; ai.plan.clinchRate = 0; ai.plan.kicky = 0; sc.ais.set(sc.blue, ai); }, base: () => P().blockCount || 0, done: (b) => (P().blockCount || 0) - b >= 2 },
      { pic: '↔️', t: 'หลบ 2 ครั้ง', s: `กด ${k('Shift', 'ปุ่ม หลบ')} — หัวจะเบี่ยงหลบหมัด`, base: () => P().slipCount || 0, done: (b) => (P().slipCount || 0) - b >= 2 },
      { pic: '🤼', t: 'ทุ่มคู่ซ้อมลงพื้น', s: `กด ${k('L', 'ปุ่ม ปล้ำ')} (ถ้าชิดกันกดอีกครั้งเพื่อทุ่ม)`, start: () => { sc.ais.clear(); sc.blue.input = Fighter.blankInput(); }, done: () => { const L = sc.grapple.link; return L && L.type === 'ground' && L.top === P(); } },
      { pic: '👊', t: 'ทุบจากด้านบน 3 ครั้ง', s: `อยู่ด้านบนแล้ว! กด ${k('J', 'ปุ่ม ต่อย')}`, base: () => P().stats.thrown, done: (b) => P().stats.thrown - b >= 3, fail: () => !sc.grapple.link },
      { pic: '🔒', t: 'จับล็อกให้ตบ', s: `กด ${k('L', 'ปุ่ม ปล้ำ')} ไล่ตำแหน่งจนล็อกได้ แล้วรัวปุ่มเร็ว ๆ`, done: () => { const L = sc.grapple.link; if (L && L.sub && L.sub.att === P()) this.tut.subSeen = true; return this.tut.subSeen && !(L && L.sub); }, fail: () => !sc.grapple.link },
      { pic: '🎉', t: 'เก่งมาก! พร้อมขึ้นชกจริงแล้ว', s: 'ลองไฟต์ด่วน หรือเริ่มโหมดอาชีพได้เลย', final: true },
    ];
    this.tut = { sc, steps: STEPS, i: -1, base: 0, t: 0, subSeen: false };
    this.tutBox = el('div', { class: 'tut' });
    this.app.uiRoot.appendChild(this.tutBox);
    this.tutNext();
  }
  tutNext() {
    const T = this.tut; T.i++; T.t = 0; T.subSeen = false;
    const st = T.steps[T.i];
    if (st.start) st.start();
    T.base = st.base ? st.base() : 0;
    const prog = el('div', { class: 'tp' }, ...T.steps.map((_, j) => el('i', { class: j <= T.i ? 'on' : '' })));
    const btns = st.final
      ? el('div', { class: 'tbtns' }, el('button', { class: 'btn small primary', onclick: () => { this.endTutorial(); this.qf = null; this.startQuick(); } }, '⚡ ไฟต์ด่วน'), el('button', { class: 'btn small', onclick: () => { this.endTutorial(); this.app.endScene(); this.newCareer(); } }, '🏆 อาชีพ'), el('button', { class: 'btn small', onclick: () => { this.endTutorial(); this.exitFight(); } }, '🏠 เมนู'))
      : el('div', { class: 'tbtns' }, el('button', { class: 'btn small ghost', onclick: () => { this.endTutorial(); this.exitFight(); } }, 'ข้ามการฝึก'));
    this.tutBox.innerHTML = '';
    this.tutBox.append(el('span', { class: 'pic' }, st.pic), el('div', {}, el('div', { class: 'tt' }, `${T.i + 1}. ${st.t}`), el('div', { class: 'ts' }, st.s), prog, btns));
    if (st.final) { this.app.save.tutorialDone = true; writeSave(this.app.save); this.app.audio.roar && this.app.audio.roar(); }
  }
  tutFrame(dt) {
    const T = this.tut; if (!T || this.app.scene !== T.sc) { this.endTutorial(); return; }
    const st = T.steps[T.i]; if (!st || st.final) return;
    T.t += dt;
    if (st.fail && st.fail() && T.t > 1) { T.i -= 2; this.tutNext(); return; } // fell out of the ground position: redo the takedown
    if (st.done(T.base)) { this.app.audio.ui && this.app.audio.ui(); this.app.hud.message('✔', 0.6, 'info'); this.tutNext(); }
  }
  endTutorial() { if (this.tutBox) this.tutBox.remove(); this.tutBox = null; this.tut = null; }
  error(e) { if (!this._errShown) { this._errShown = true; this.toast('เกิดข้อผิดพลาด: ' + e.message, 6000); } }

  bindKeys() {
    window.addEventListener('keydown', (e) => {
      const sc = this.app.scene;
      if (!sc || sc.background) return;
      if (sc.replay.playing && ['Space', 'Enter', 'Escape'].includes(e.code)) { sc.replay.stop(); return; }
      if (e.code === 'Escape') this.togglePause();
      if (e.code === 'Tab') this.app.hud.toggleDamage();
    });
    // tap to skip the replay on touch screens
    this.app.view.addEventListener('pointerdown', () => { const sc = this.app.scene; if (sc && !sc.background && sc.replay.playing) sc.replay.stop(); });
  }
  togglePause() {
    const sc = this.app.scene;
    if (!sc || sc.background) return;
    if (this.screen && this.screen.name === 'pause') { this.close(); sc.paused = false; }
    else if (!this.screen && sc.phase !== 'ended') { sc.paused = true; this.go('pause'); }
  }
  bindOrbit() {
    const v = this.app.view; let drag = null;
    v.addEventListener('pointerdown', (e) => { if (this.pickBody(e)) return; if (this.app.world.cam.mode === 'orbit') drag = [e.clientX, e.clientY]; });
    window.addEventListener('pointerup', () => { drag = null; this.endDrag(); });
    window.addEventListener('pointercancel', () => { drag = null; this.endDrag(); });
    window.addEventListener('pointermove', (e) => {
      if (this.drag) { this.moveDrag(e); return; }
      if (!drag) return;
      const c = this.app.world.cam;
      c.orbitYaw -= (e.clientX - drag[0]) * 0.006; c.orbitPitch = clamp(c.orbitPitch + (e.clientY - drag[1]) * 0.004, 0.05, 1.3);
      drag = [e.clientX, e.clientY];
    });
    v.addEventListener('wheel', (e) => { const c = this.app.world.cam; if (c.mode === 'orbit') c.orbitDist = clamp(c.orbitDist + e.deltaY * 0.004, 1.2, 12); }, { passive: true });
  }

  boot() {
    const q = new URLSearchParams(location.search);
    if (q.get('test')) {
      window.__testLog = true;
      const a = makeNPC(Number(q.get('a') || 11), { tier: 3, wc: 'light', style: q.get('sa') || 'boxing' });
      const b = makeNPC(Number(q.get('b') || 22), { tier: 3, wc: 'light', style: q.get('sb') || 'muaythai' });
      this.app.startFight({ red: a, blue: b, playerSide: null, rounds: 3, roundLen: 300, aiLevel: 0.7, sandbox: q.get('sandbox') === '1' });
      if (q.get('sandbox') === '1') this.sandboxPanel();
      return;
    }
    this.go('title');
    this.backgroundFight();
  }

  backgroundFight() {
    if (this.app.scene && this.app.scene.background) return;
    const s = Math.floor(rng() * 1e6);
    const st = STYLE_KEYS;
    const a = makeNPC(s, { tier: 3, wc: 'welter', style: st[s % st.length] }), b = makeNPC(s + 1, { tier: 3, wc: 'welter', style: st[(s + 3) % st.length] });
    const sc = this.app.startFight({ red: a, blue: b, playerSide: null, rounds: 99, roundLen: 9999, aiLevel: 0.7, background: true, settings: { ...this.app.save.settings, replay: false } });
    sc.background = true;
    this.app.hud.show(false);
    this.app.world.cam.mode = 'orbit'; this.app.world.cam.orbitDist = 5.5; this.app.world.cam.orbitPitch = 0.28;
  }
  stopBackground() { if (this.app.scene && this.app.scene.background) this.app.endScene(); }

  // ================= SCREENS =================
  scr_title() {
    const has = !!this.career && !this.career.d.ended;
    const tile = (pic, label, sub, fn, cls = '') => el('button', { class: 'tile ' + cls, onclick: fn }, el('span', { class: 'pic' }, pic), el('span', {}, label), sub ? el('span', { class: 'sub' }, sub) : null);
    const fs = el('button', { class: 'iconbtn fs-btn', title: 'เต็มจอ', onclick: () => { try { const d = document.documentElement; (d.requestFullscreen ? d.requestFullscreen() : Promise.reject()).then(() => { try { screen.orientation.lock('landscape').catch(() => {}); } catch (e) {} }).catch(() => this.toast('อุปกรณ์นี้ไม่รองรับโหมดเต็มจอ')); } catch (e) { this.toast('อุปกรณ์นี้ไม่รองรับโหมดเต็มจอ'); } } }, icon('expand', 22), 'เต็มจอ');
    return el('div', { class: 'screen dim' }, fs, el('div', { style: { width: 'min(760px, 100%)' } },
      el('div', { class: 'title-logo' }, 'สังเวียนเลือด', el('span', { class: 'en' }, 'CAGE BLOOD')),
      el('div', { class: 'title-sub' }, 'MMA แซนด์บ็อกซ์ · ฟิสิกส์ร่างกาย · เลือดสมจริง'),
      el('div', { class: 'tiles' },
        has ? tile('▶️', 'เล่นต่อ', `${this.career.f.name} · ${this.career.dateStr}`, () => this.openCareer(), 'primary') : null,
        tile('🎓', 'ฝึกเล่น', this.app.save.tutorialDone ? 'ทบทวนปุ่ม 2 นาที' : 'เริ่มที่นี่! สอนทีละขั้น 2 นาที', () => this.startTutorial(), this.app.save.tutorialDone ? '' : 'glow'),
        tile('🏆', 'อาชีพใหม่', 'สร้างนักสู้ วาดหน้า ไต่สู่แชมป์โลก', () => this.newCareer(), has ? '' : 'primary'),
        tile('⚡', 'ไฟต์ด่วน', 'ชกทันที', () => this.go('quick')),
        tile('🧪', 'แซนด์บ็อกซ์', 'ragdoll สโลว์โม ทำแผล', () => this.go('sandboxSetup')),
        tile('🧑‍🎨', 'นักสู้ของฉัน', 'สร้าง / แก้ไขนักสู้', () => this.go('fighters')),
        tile('🎮', 'วิธีเล่น', 'ปุ่มคีย์บอร์ดและจอสัมผัส', () => this.go('help')),
        tile('⚙️', 'ตั้งค่า', 'ความสว่าง กราฟิก เลือด', () => this.go('settings')),
        tile('📚', 'ข้อมูลอ้างอิง', 'งานวิจัยที่ใช้', () => this.go('research')),
      )));
  }

  scr_help() {
    const k = (x) => el('kbd', {}, x);
    const row = (keys, ic, text) => el('div', { class: 'help-row' }, icon(ic, 22), el('span', { class: 'keys' }, ...[].concat(keys).map((x) => [k(x), ' '])), el('span', {}, text));
    const sec = (pic, t, rows) => el('div', { class: 'card' }, el('h3', {}, pic + ' ' + t), ...rows.map((r) => row(...r)));
    return el('div', { class: 'screen dim' }, el('div', { class: 'panel', style: { width: 'min(1000px, 100%)', maxHeight: '92vh', overflow: 'auto' } },
      el('h2', {}, '🎮 วิธีเล่น'),
      el('div', { class: 'help-grid' },
        sec('🦶', 'เคลื่อนที่', [[['W', 'S'], 'up', 'เข้า / ถอย'], [['A', 'D'], 'dodge', 'วนซ้าย / ขวา'], [['Z', 'X'], 'dodge', 'หลบหัว'], ['C', 'duck', 'ก้ม / สปรอล']]),
        sec('👊', 'หมัด (Shift = ลำตัว)', [['J', 'jab', 'แย็บ'], ['K', 'fist', 'หมัดหลัง'], ['U', 'hookL', 'ฮุคหน้า'], ['I', 'hookR', 'ฮุคหลัง'], [['N', 'M'], 'upper', 'อัปเปอร์คัต'], ['Y', 'elbow', 'ศอก']]),
        sec('🦵', 'เตะ (Shift = ขา · Q = หัว)', [['O', 'kick', 'เตะเท้าหน้า'], ['L', 'kick', 'เตะเท้าหลัง'], ['P', 'teep', 'ถีบ'], ['H', 'knee', 'เข่า'], ['E', 'check', 'ยกแข้งกันเตะ']]),
        sec('🛡️', 'ป้องกัน', [['Space', 'shield', 'การ์ดสูง (ค้าง)'], [['Space', 'Shift'], 'shieldLow', 'การ์ดลำตัว'], ['V', 'eye', 'ค้าง + หมัด = หลอก']]),
        sec('🤼', 'ปล้ำ', [['F', 'clinch', 'คลินช์'], ['G', 'takedown', 'เทคดาวน์ / ทุ่ม / ล็อก']]),
        sec('⬇️', 'บนพื้น', [['W', 'up', 'ไล่ตำแหน่ง / สวีป'], [['A', 'D'], 'dodge', 'หนีตำแหน่ง'], ['S', 'duck', 'ลุกขึ้น'], ['G', 'lock', 'จับล็อก'], ['Space', 'hand', 'ปิดหน้า / รัวแก้ล็อก']]),
        sec('📱', 'จอสัมผัส', [[[], 'target', 'จอยซ้าย = เดิน · ปุ่มขวา = หมัด เตะ การ์ด'], [[], 'body', 'ปุ่ม ลำตัว/ขา และ เตะหัว เป็นสวิตช์เปิด-ปิด'], [[], 'up', 'บนพื้น: ดันจอย ขึ้น/ลง/ซ้าย/ขวา'], [[], 'hand', 'ตอนโดนล็อก: รัวปุ่มมือตรงกลาง']]),
        sec('⏸️', 'อื่นๆ', [['Esc', 'pause', 'หยุดเกม'], ['Tab', 'body', 'ดูอาการบาดเจ็บ'], [['Space'], 'play', 'ข้ามรีเพลย์ (มือถือ: แตะจอ)']]),
      ),
      el('div', { class: 'card', style: { marginTop: '12px' } }, el('h3', {}, '💡 เคล็ดลับ'),
        el('ul', {},
          el('li', {}, 'ฮุค/อัปเปอร์คัตเข้าคาง = น็อกง่าย · หมัดเข้าหน้าผาก = คิ้วแตก'),
          el('li', {}, 'หมัดสวนตอนคู่ชกพุ่งเข้ามาแรงกว่า'),
          el('li', {}, 'ฮุคซ้ายเข้าลำตัวฝั่งขวาคู่ชก = หมัดตับ ทรุดตามหลัง'),
          el('li', {}, 'เตะน่องสะสม = ขาตาย · เลือดเข้าตา/ตาบวม = มองไม่เห็น'))),
      el('button', { class: 'btn', style: { marginTop: '12px' }, onclick: () => this.back() }, icon('back', 18), ' กลับ')));
  }
  back() {
    const sc = this.app.scene;
    if (sc && !sc.background && sc.paused) { this.go('pause'); return; }
    this.go('title');
  }

  scr_settings() {
    const s = this.app.save.settings;
    const row = (label, input) => el('div', { class: 'field' }, el('label', {}, label), input);
    const rng_ = (k, min, max, step, fmt) => { const out = el('b', {}, ' ' + fmt(s[k])); return [out, el('input', { type: 'range', min, max, step, value: s[k], oninput: (e) => { s[k] = Number(e.target.value); out.textContent = ' ' + fmt(s[k]); this.app.applySettings(); writeSave(this.app.save); } })]; };
    const [o1, i1] = rng_('potato', 0.3, 1, 0.05, (v) => v <= 0.45 ? 'มันฝรั่งสุดๆ' : v <= 0.7 ? 'มันฝรั่ง' : v < 1 ? 'มันฝรั่งทอด' : 'คมชัด');
    const [o2, i2] = rng_('gore', 0, 2, 0.25, (v) => v === 0 ? 'ปิดเลือด' : v < 1 ? 'น้อย' : v === 1 ? 'สมจริง' : 'มากกว่าจริง');
    const [o3, i3] = rng_('volume', 0, 1, 0.05, (v) => Math.round(v * 100) + '%');
    const [o4, i4] = rng_('clockScale', 1, 4, 0.5, (v) => v === 1 ? 'เวลาจริง (ยกละ 5 นาที)' : `เร็วขึ้น ${v}x (ยกละ ~${(5 / v).toFixed(1)} นาที)`);
    const [o5, i5] = rng_('difficulty', 0.2, 1, 0.05, (v) => v < 0.4 ? 'ง่าย' : v < 0.65 ? 'ปกติ' : v < 0.85 ? 'ยาก' : 'โปร');
    const [o6, i6] = rng_('refPatience', 0, 1, 0.1, (v) => v < 0.3 ? 'หยุดเร็ว' : v < 0.7 ? 'ปกติ' : 'ปล่อยนาน');
    const [o7, i7] = rng_('brightness', 0.8, 2.2, 0.05, (v) => v < 1.1 ? 'มืด' : v < 1.6 ? 'ปกติ' : v < 1.9 ? 'สว่าง' : 'สว่างมาก');
    const presetSel = el('div', { class: 'iconbar' }, ...[['easy', '😊', 'ง่าย'], ['normal', '🙂', 'ปกติ'], ['hard', '😤', 'ยาก'], ['pro', '💀', 'โปร']].map(([v, pic, t]) => el('button', { class: 'iconbtn' + (s.preset === v ? ' sel' : ''), onclick: () => { s.preset = v; Object.assign(s, PRESETS[v]); writeSave(this.app.save); this.refresh(); } }, el('span', { class: 'pic' }, pic), t)));
    const ctrlSel = el('div', { class: 'iconbar' }, ...[['simple', '🎮', 'ง่าย (5 ปุ่ม)'], ['pro', '🧠', 'โปร (ทุกท่า)']].map(([v, pic, t]) => el('button', { class: 'iconbtn' + ((s.controls || 'simple') === v ? ' sel' : ''), onclick: () => { s.controls = v; writeSave(this.app.save); this.refresh(); } }, el('span', { class: 'pic' }, pic), t)));
    const ragSel = el('div', { class: 'iconbar' }, ...[['off', '🤖', 'ปิด'], ['low', '🧍', 'น้อย'], ['mid', '🤸', 'กลาง'], ['full', '🪆', 'เต็มที่']].map(([v, pic, t]) => el('button', { class: 'iconbtn' + ((s.ragdoll || 'full') === v ? ' sel' : ''), onclick: () => { s.ragdoll = v; writeSave(this.app.save); this.refresh(); } }, el('span', { class: 'pic' }, pic), t)));
    const touchSel = el('div', { class: 'iconbar' }, ...[['auto', '🤖', 'อัตโนมัติ'], ['on', '📱', 'เปิด'], ['off', '⌨️', 'ปิด']].map(([v, pic, t]) => el('button', { class: 'iconbtn' + (s.touch === v ? ' sel' : ''), onclick: () => { s.touch = v; writeSave(this.app.save); this.refresh(); } }, el('span', { class: 'pic' }, pic), t)));
    return el('div', { class: 'screen dim' }, el('div', { class: 'panel', style: { width: 'min(560px, 100%)' } },
      el('h2', {}, '⚙️ ตั้งค่า'),
      row(el('span', {}, '☀️ ความสว่าง', o7), i7), row(el('span', {}, '🥔 ความละเอียดกราฟิก', o1), i1), row(el('span', {}, '🩸 ระดับเลือด', o2), i2), row(el('span', {}, '🔊 เสียง', o3), i3),
      row(el('span', {}, '🎚️ ความยาก'), presetSel), row(el('span', {}, '🪆 ร่างกาย Ragdoll (ทั้งตัวเป็นฟิสิกส์)'), ragSel), row(el('span', {}, '🕹️ ปุ่มควบคุม'), ctrlSel),
      row(el('span', {}, '⏱️ นาฬิกาในไฟต์', o4), i4), row(el('span', {}, '🧑‍⚖️ กรรมการหยุดไฟต์', o6), i6),
      row(el('span', {}, '📱 ปุ่มบนจอสัมผัส'), touchSel),
      el('label', {}, el('input', { type: 'checkbox', checked: s.replay ? 'checked' : null, onchange: (e) => { s.replay = e.target.checked; writeSave(this.app.save); } }), ' แสดงรีเพลย์ตอนน็อก'),
      el('h3', {}, 'สำรองเซฟ'),
      el('div', { class: 'row' },
        el('button', { class: 'btn small', onclick: () => {
          const code = exportSave(this.app.save);
          const show = () => this.textBox('รหัสเซฟ (เลือกทั้งหมดแล้วคัดลอกเก็บไว้)', code);
          try { navigator.clipboard.writeText(code).then(() => this.toast('คัดลอกรหัสเซฟแล้ว'), show); } catch (e) { show(); }
        } }, 'คัดลอกรหัสเซฟ'),
        el('button', { class: 'btn small', onclick: () => this.textBox('วางรหัสเซฟที่นี่', '', (t) => { if (!t.trim()) return; try { const d = importSave(t); Object.assign(this.app.save, d); writeSave(this.app.save); this.career = this.app.save.career ? new Career(this.app.save.career) : null; this.toast('นำเข้าเซฟแล้ว'); } catch (e) { this.toast('รหัสเซฟไม่ถูกต้อง ลองคัดลอกใหม่ทั้งหมด'); } }, 'นำเข้า') }, 'นำเข้าเซฟ'),
        el('button', { class: 'btn small', onclick: () => { Object.assign(s, DEFAULT_SETTINGS); this.app.applySettings(); writeSave(this.app.save); this.refresh(); } }, 'ค่าเริ่มต้น')),
      el('button', { class: 'btn', style: { marginTop: '14px' }, onclick: () => this.back() }, '← กลับ')));
  }

  scr_research() {
    const refs = [
      ['ไบโอเมคานิกส์ของหมัด', 'Kinetic chain: เท้า → สะโพก → ลำตัว → แขน, ขาส่งแรงผ่านการถ่ายโมเมนตัม (Annals of Applied Sport Science 2014; MDPI Bioengineering 2025)'],
      ['เวลาออกหมัด', 'Motion capture นักมวย: แย็บเร็วที่สุด ~0.3-0.4 วินาที, ฮุคหน้ามีความเร็วกำปั้นสูงสุด (Stanley et al., 2018)'],
      ['การน็อกเอาต์', 'การหมุนของศีรษะ (rotational acceleration) เป็นสาเหตุหลักของการบาดเจ็บทางสมอง มากกว่าแรงตรง (Sports Biomechanics review; Frontiers in Neurology 2020)'],
      ['Fencing response', 'แขนเกร็งชูขึ้นหลังโดนน็อก เป็นสัญญาณการบาดเจ็บก้านสมองระดับปานกลาง (University of Kentucky, 2,000 คลิปน็อกเอาต์)'],
      ['ระบาดวิทยาการบาดเจ็บ MMA', 'แผลฉีกขาดที่ใบหน้าพบบ่อยที่สุด (~48% ในข้อมูลเนวาดา) ตามด้วยมือ จมูก ตา; ศีรษะบาดเจ็บ 67-78% (PubMed 26535267; JSSM)'],
      ['คัทแมน', 'การกดแผล + อะดรีนาลีน 1:1000 + วาสลีน + Enswell ประคบเย็นลดบวม; แผลใกล้ตาเป็นสาเหตุหยุดไฟต์ทางการแพทย์'],
      ['เลือด', 'หยดเลือดตกตามวิถีโปรเจกไทล์ (ความหนาแน่น ~1.06 g/cm³), รูปทรงคราบยืดตาม sin(มุมตกกระทบ), สีเปลี่ยนแดง→น้ำตาลจากออกซิเดชัน (bloodstain pattern analysis)'],
      ['แอนิเมชันฟิสิกส์', 'PD controller ขับข้อต่อ, SIMBICON foot placement เพื่อการทรงตัว, Verlet ragdoll (Jakobsen, Advanced Character Physics — Hitman)'],
      ['เตะน่อง', 'การกระแทกเส้นประสาท peroneal ทำให้เท้าตก ลงน้ำหนักไม่ได้ (กรณีศึกษาในไฟต์ระดับโลก)'],
      ['กติกา', 'Unified Rules of MMA: 10-point must, เกณฑ์หลักคือ effective striking/grappling แล้วจึงดู aggression และ cage control; น็อกดาวน์ไม่ได้ทำให้เป็น 10-8 อัตโนมัติ'],
      ['เส้นทางอาชีพ', 'สมัครเล่น → โปรภูมิภาค → contender series → ลีกใหญ่, ค่าตัว show/win, การตัดน้ำหนักและรีไฮเดรต 24-36 ชม., Medical suspension'],
    ];
    return el('div', { class: 'screen dim' }, el('div', { class: 'panel', style: { width: 'min(860px, 100%)', maxHeight: '92vh', overflow: 'auto' } },
      el('h2', {}, 'ข้อมูลอ้างอิงที่ใช้ออกแบบเกม'),
      el('p', { class: 'muted' }, 'ก่อนสร้างเกม ได้ค้นคว้าข้อมูลจริงเพื่อใช้กำหนดระบบต่างๆ (เป็นการจำลองเพื่อความบันเทิง ไม่ใช่ข้อมูลทางการแพทย์):'),
      ...refs.map(([t, d]) => el('div', { class: 'card', style: { marginBottom: '8px' } }, el('b', {}, t), el('div', { class: 'muted small' }, d))),
      el('p', { class: 'muted small' }, 'ชื่อโปรโมชัน ตัวละคร และนักสู้ทั้งหมดในเกมเป็นเรื่องสมมติ'),
      el('button', { class: 'btn', onclick: () => this.go('title') }, '← กลับ')));
  }

  // ---------- fighters ----------
  scr_fighters() {
    const list = this.app.save.fighters;
    return el('div', { class: 'screen dim' }, el('div', { class: 'panel', style: { width: 'min(640px, 100%)' } },
      el('h2', {}, 'นักสู้ของฉัน'),
      list.length ? null : el('p', { class: 'muted' }, 'ยังไม่มีนักสู้ — สร้างใหม่ได้เลย'),
      ...list.map((p, i) => el('div', { class: 'card row', style: { marginBottom: '6px' } },
        el('div', { class: 'grow' }, el('b', {}, p.name), p.nick ? el('span', { class: 'muted' }, ` "${p.nick}"`) : null, el('div', { class: 'muted small' }, `${wcById(p.wc).name} · ${STYLES[p.style].name} · OVR ${Math.round(overall(p.attrs || computeAttrs(p)))}`)),
        el('button', { class: 'btn small', onclick: () => this.openCreator((np) => { list[i] = np; writeSave(this.app.save); this.go('fighters'); }, () => this.go('fighters'), { profile: p, title: 'แก้ไขนักสู้' }) }, 'แก้ไข'),
        el('button', { class: 'btn small', onclick: () => this.ask(`ลบนักสู้ ${p.name}?`, () => { list.splice(i, 1); writeSave(this.app.save); this.refresh(); }, 'ลบ') }, 'ลบ'))),
      el('div', { class: 'row', style: { marginTop: '10px' } },
        el('button', { class: 'btn primary', onclick: () => this.openCreator((p) => { list.push(p); writeSave(this.app.save); this.go('fighters'); }, () => this.go('fighters')) }, '+ สร้างนักสู้ใหม่'),
        el('button', { class: 'btn', onclick: () => this.go('title') }, '← กลับ'))));
  }

  openCreator(done, cancel, opts) {
    this.stopBackground();
    this.app.preview.zoom = 1; this.app.preview.offset = 0.55;
    const cr = new Creator(this, (p) => { this.app.preview.clear(); this.creator = null; this.backgroundFight(); done(p); }, () => { this.app.preview.clear(); this.creator = null; this.backgroundFight(); cancel(); }, opts);
    this.creator = cr;
    cr.refreshPreview();
    this.go('creator');
  }
  scr_creator() { return this.creator ? this.creator.render() : null; }

  // ---------- career ----------
  newCareer(force) {
    if (!force && this.career && !this.career.d.ended) { this.ask('มีเซฟอาชีพอยู่แล้ว ถ้าเริ่มใหม่ เซฟเดิมจะถูกเขียนทับ', () => this.newCareer(true), 'เริ่มอาชีพใหม่'); return; }
    this.openCreator((p) => {
      this.career = Career.create(p);
      if (!this.app.save.fighters.find((x) => x.id === p.id)) this.app.save.fighters.push(p);
      this.save();
      this.openCareer();
    }, () => this.go('title'), { title: 'สร้างนักสู้สำหรับโหมดอาชีพ' });
  }
  openCareer() {
    this.stopBackground();
    this.app.endScene();
    this.careerTab = this.careerTab || 'week';
    this.go('career');
    this.checkStory();
    // ambient: show my fighter in the empty octagon
    loadFaceCanvas(this.career.f.faceData).then((c) => { if (this.screen && this.screen.name === 'career') { this.app.preview.offset = 0; this.app.preview.zoom = 1.7; this.app.preview.show(this.career.myFightProfile(null), c); } });
  }
  leaveCareer() { this.app.preview.clear(); this.app.preview.offset = 0.55; this.app.preview.zoom = 1; this.save(); this.go('title'); this.backgroundFight(); }

  checkStory() {
    const c = this.career;
    if (c && c.d.pendingStory.length) { const id = c.d.pendingStory[0]; this.go('story', { id }); return true; }
    return false;
  }

  scr_story({ id }) {
    const c = this.career, ev = storyById(id);
    if (!ev) { c.d.pendingStory.shift(); return this.scr_career(); }
    const sc = this._storyCache && this._storyCache.id === id ? this._storyCache.sc : ev.scene(c);
    this._storyCache = { id, sc };
    const idx = this.storyIdx || 0;
    const line = sc.lines[Math.min(idx, sc.lines.length - 1)];
    const last = idx >= sc.lines.length - 1;
    const glitch = c.d.health.brainDamage > 55 && rng() < 0.3;
    const text = glitch ? line.text.replace(/[ก-ฮ]/g, (ch) => (rng() < 0.06 ? '▒' : ch)) : line.text;
    return el('div', { class: 'screen solid' }, el('div', { class: 'panel story' },
      el('div', { class: 'scene-img' }, ev.bg || '🥊'),
      sc.title ? el('h2', {}, `ฉากจบ: "${sc.title}"`) : null,
      line.who ? el('div', { class: 'speaker' }, line.who) : null,
      el('div', { class: 'text' }, text),
      el('div', { class: 'muted small', style: { marginTop: '8px' } }, `${idx + 1}/${sc.lines.length}`),
      last ? el('div', { class: 'choices' }, ...sc.choices.map((ch) => el('button', { class: 'btn', onclick: () => {
        ch.fx && ch.fx(c);
        c.d.seenStory[id] = true;
        c.d.pendingStory = c.d.pendingStory.filter((x) => x !== id);
        this.storyIdx = 0; this._storyCache = null;
        for (const k of ['coach', 'family', 'rival', 'journalist', 'viktor', 'may']) c.d.rel[k] = clamp(c.d.rel[k], -100, 100);
        c.d.morale = clamp(c.d.morale, 0, 100); c.d.hype = clamp(c.d.hype, 0, 100);
        this.save();
        if (c.d.ended) { this.go('careerEnd'); return; }
        if (!this.checkStory()) this.go('career');
      } }, ch.text)))
        : el('div', { class: 'choices' }, el('button', { class: 'btn primary', onclick: () => { this.storyIdx = idx + 1; this.refresh(); } }, 'ต่อไป ▶')),
    ));
  }

  scr_careerEnd() {
    const c = this.career;
    return el('div', { class: 'screen solid' }, el('div', { class: 'panel story' },
      el('div', { class: 'scene-img' }, '🌅'),
      el('h2', {}, `จบอาชีพ: "${c.d.endingTitle || ''}"`),
      el('p', {}, `${c.f.name} · สถิติ ${c.f.record.w}-${c.f.record.l}-${c.f.record.d} · รายได้รวม ${money(c.d.earnings)}`),
      el('button', { class: 'btn primary', onclick: () => this.leaveCareer() }, 'กลับเมนูหลัก')));
  }

  scr_career() {
    const c = this.career, d = c.d, f = c.f;
    if (!c) return null;
    const rank = c.myRank();
    const side = el('div', { class: 'side' },
      el('div', { class: 'card' },
        el('div', { style: { fontSize: '20px', fontWeight: 800 } }, f.name), f.nick ? el('div', { class: 'muted' }, `"${f.nick}"`) : null,
        el('div', { class: 'muted small' }, c.dateStr),
        el('div', { class: 'stat-grid', style: { marginTop: '8px' } },
          el('span', { class: 'k' }, '🥊 สถิติโปร'), el('b', {}, `${f.record.w}-${f.record.l}-${f.record.d}`),
          el('span', { class: 'k' }, '🥉 สมัครเล่น'), el('span', {}, `${f.am.w}-${f.am.l}`),
          el('span', { class: 'k' }, '🏟️ สังกัด'), el('span', {}, PROMOTIONS[d.promo].short),
          el('span', { class: 'k' }, '🏅 อันดับ'), el('span', {}, d.champ ? '🏆 แชมป์' : rank ? `#${rank}` : d.regionalChamp ? 'แชมป์ภูมิภาค' : '-'),
          el('span', { class: 'k' }, '🎂 อายุ'), el('span', {}, `${f.age} ปี`),
          el('span', { class: 'k' }, '📈 ค่าพลังรวม'), el('b', {}, String(c.ovr())),
          el('span', { class: 'k' }, '💰 เงิน'), el('b', { style: { color: d.money < 0 ? '#ff6b6b' : '#9fe39f' } }, money(d.money)),
          el('span', { class: 'k' }, '💸 หนี้'), el('span', { style: { color: '#ff9b9b' } }, money(d.debt)),
          el('span', { class: 'k' }, '🔥 กระแส'), el('span', {}, `${Math.round(d.hype)}`),
          el('span', { class: 'k' }, '⭐ ชื่อเสียง'), el('span', {}, `${Math.round(d.fame)}`),
          el('span', { class: 'k' }, '🙂 ขวัญกำลังใจ'), el('span', {}, `${Math.round(d.morale)}`),
          el('span', { class: 'k' }, '😓 ความล้า'), el('span', { style: { color: d.fatigue > 70 ? '#ff6b6b' : '' } }, `${Math.round(d.fatigue)}`),
          el('span', { class: 'k' }, '⚖️ น้ำหนัก'), el('span', {}, `${f.walkKg.toFixed(1)} / ลิมิต ${c.wc.kg.toFixed(1)} กก.`),
          el('span', { class: 'k' }, '🧠 สมองเสียหาย'), el('span', { style: { color: d.health.brainDamage > 40 ? '#ff6b6b' : '' } }, `${Math.round(d.health.brainDamage)}/100`),
        )),
      el('div', { class: 'card' }, el('h3', {}, '🩺 สุขภาพ'),
        d.health.suspension > 0 ? el('div', { style: { color: '#ffb020' } }, `⛔ พักการชกทางการแพทย์อีก ${d.health.suspension} สัปดาห์`) : null,
        ...(d.health.injuries.length ? d.health.injuries.map((x) => el('div', { class: 'small', style: { color: '#ffb3b3' } }, `• ${x.name} (${x.weeks} สัปดาห์)`)) : [el('div', { class: 'muted small' }, 'ไม่มีอาการบาดเจ็บ')])),
      d.debt > 0 && d.money > 1000 ? el('button', { class: 'btn small', onclick: () => { const pay = Math.min(d.debt, Math.floor(d.money / 1000) * 1000); d.money -= pay; d.debt -= pay; this.toast(`จ่ายหนี้ ${money(pay)}`); this.save(); this.refresh(); } }, '💸 จ่ายหนี้วิกเตอร์') : null,
      el('button', { class: 'btn small', onclick: () => this.ask('ประกาศแขวนนวม? อาชีพจะจบลงและไปสู่ฉากจบ', () => { c.retire(); this.save(); this.checkStory(); }, 'แขวนนวม') }, '🧤 ประกาศแขวนนวม'),
      el('button', { class: 'btn small ghost', onclick: () => this.leaveCareer() }, '← เมนูหลัก (บันทึกแล้ว)'),
    );
    const tabs = el('div', { class: 'tabs' });
    const unread = d.inbox.filter((m) => !m.read).length;
    for (const [k, t] of [['week', '📅 ซ้อม'], ['offers', `📩 ไฟต์${d.offers.length ? ` (${d.offers.length})` : ''}`], ['attrs', '📈 ค่าพลัง'], ['rank', '🏅 อันดับ'], ['inbox', `✉️${unread ? ` (${unread})` : ''}`], ['history', '📜 ประวัติ'], ['gym', '🏠 ยิม']]) {
      tabs.append(el('div', { class: 'tab' + (this.careerTab === k ? ' sel' : ''), onclick: () => { this.careerTab = k; if (k === 'inbox') d.inbox.forEach((m) => (m.read = true)); this.refresh(); } }, t));
    }
    const main = el('div', { class: 'main' }, el('div', { class: 'panel' }, tabs, this['ctab_' + this.careerTab](c)));
    return el('div', { class: 'screen dim' }, el('div', { class: 'career' }, side, main));
  }

  ctab_week(c) {
    const d = c.d;
    const box = el('div', {});
    if (d.booked) {
      const b = d.booked;
      const rep = c.scoutReport();
      box.append(el('div', { class: 'offer' },
        el('div', { class: 'vs' }, `🥊 ไฟต์ถัดไป: ${b.oppName} (${b.oppRec})`),
        el('div', {}, `${PROMOTIONS[b.promo].name} · ${b.rounds} ยก${b.title ? ' · 🏆 ชิงแชมป์' : ''} · อีก ${b.weeksOut} สัปดาห์`),
        el('div', { class: 'muted small' }, `ค่าตัว ${money(b.purse.show)} + ชนะ ${money(b.purse.win)}`),
        rep ? el('div', { class: 'small', style: { marginTop: '6px' } }, el('b', {}, 'รายงานคู่ชก: '), rep.join(' · ')) : null,
        el('div', { class: 'small', style: { marginTop: '4px' } }, '🎯 โอกาสชนะโดยประมาณ: ', el('b', {}, `${Math.round(c.winChance(b.oppRating) * 100)}%`)),
        el('div', { class: 'small', style: { marginTop: '4px', color: (c.f.walkKg - c.wc.kg) / c.f.walkKg > 0.07 ? '#ff9b6b' : '#9fe39f' } }, `ต้องตัดน้ำหนัก ${(Math.max(0, (c.f.walkKg - c.wc.kg) / c.f.walkKg) * 100).toFixed(1)}% ${(c.f.walkKg - c.wc.kg) / c.f.walkKg > 0.07 ? '— หนักเกินไป! เสี่ยงชั่งไม่ผ่านและหมดแรงกลางไฟต์ (คุมอาหาร/คาร์ดิโอ)' : ''}`)));
    } else if (d.health.suspension > 0) box.append(el('p', { class: 'muted' }, 'อยู่ระหว่างพักการชก — ใช้เวลานี้พักฟื้นและพัฒนาฝีมือ'));
    else box.append(el('p', { class: 'muted' }, 'ยังไม่มีไฟต์ — ดูแท็บข้อเสนอไฟต์ หรือรอให้โปรโมเตอร์ติดต่อมา (สร้างกระแสด้วยงานสื่อช่วยได้)'));
    const auto = d.autoPlan !== false;
    if (auto && d._apWeek !== d.week) { d.plan = c.autoPlan(); d._apWeek = d.week; }
    box.append(el('h3', {}, `🗓️ แผนซ้อม ${d.plan.length}/3`),
      el('div', { class: 'iconbar' },
        el('button', { class: 'iconbtn' + (auto ? ' sel' : ''), onclick: () => { d.autoPlan = true; this.save(); this.refresh(); } }, el('span', { class: 'pic' }, '🤖'), 'โค้ชจัดให้'),
        el('button', { class: 'iconbtn' + (!auto ? ' sel' : ''), onclick: () => { d.autoPlan = false; this.save(); this.refresh(); } }, el('span', { class: 'pic' }, '✋'), 'เลือกเอง')),
      el('div', { class: 'muted small' }, auto ? '🤖 โค้ชเลือกซ้อมจุดอ่อน พักเมื่อเหนื่อย และคุมน้ำหนักก่อนไฟต์ให้อัตโนมัติ (แตะกิจกรรมเพื่อเลือกเอง)' : '😓 = เหนื่อย · 💚 = พักฟื้น · แตะค้างดูคำอธิบาย'));
    const grid = el('div', { class: 'tiles', style: { gridTemplateColumns: 'repeat(auto-fill, minmax(104px, 1fr))', width: '100%' } });
    for (const [k, a] of Object.entries(ACTIVITIES)) {
      const n = d.plan.indexOf(k);
      grid.append(el('button', { class: 'tile small' + (n >= 0 ? ' sel' : ''), title: a.desc, onclick: () => { if (d.autoPlan !== false) d.autoPlan = false; c.togglePlan(k); this.refresh(); } },
        el('span', { class: 'pic' }, a.icon), el('span', {}, a.name), el('span', { class: 'sub' }, n >= 0 ? `✔ ช่อง ${n + 1}` : (a.fat > 0 ? '😓'.repeat(Math.min(3, Math.ceil(a.fat / 10))) : '💚'))));
    }
    box.append(grid);
    if (c.lastReport) {
      const g = Object.entries(c.lastReport.gains).filter(([, v]) => v > 0.05).map(([k, v]) => `${ATTR_LABEL[k]} +${v.toFixed(1)}`);
      box.append(el('div', { class: 'card', style: { marginTop: '10px' } }, el('b', {}, 'สัปดาห์ที่แล้ว: '), g.join(', ') || 'ไม่มีการพัฒนาค่าพลัง', ...c.lastReport.notes.map((n) => el('div', { class: 'small', style: { color: '#ffcf6a' } }, n))));
    }
    box.append(el('div', { class: 'row', style: { marginTop: '12px' } }, el('div', { class: 'grow' }),
      el('button', { class: 'btn', title: 'เดินเวลาไปเรื่อยๆ จนมีไฟต์ ข้อเสนอใหม่ หรือเหตุการณ์ในเนื้อเรื่อง', onclick: () => this.skipWeeks() }, '⏩ ข้ามไปเหตุการณ์ถัดไป'),
      el('button', { class: 'btn primary', onclick: () => this.nextWeek() }, d.booked && d.booked.weeksOut <= 1 ? '🥊 สัปดาห์ไฟต์! ▶' : '⏭️ สัปดาห์ถัดไป')));
    return box;
  }

  skipWeeks() {
    const c = this.career, d = c.d;
    const offers0 = d.offers.length;
    for (let i = 0; i < 16; i++) {
      const out = c.advanceWeek();
      this.save();
      if (out.fight) { this.go('weighin'); return; }
      if (d.pendingStory.length) { this.checkStory(); return; }
      if (d.offers.length > offers0 && !d.booked) { this.careerTab = 'offers'; this.refresh(); this.toast('📩 มีข้อเสนอไฟต์ใหม่!'); return; }
      if (out.notes.some((n) => n.includes('บาดเจ็บ'))) { this.refresh(); this.toast('🚑 บาดเจ็บระหว่างซ้อม ดูรายละเอียดด้านซ้าย'); return; }
    }
    this.refresh();
  }

  nextWeek() {
    const c = this.career;
    const out = c.advanceWeek();
    this.save();
    if (out.fight) { this.go('weighin'); return; }
    if (!this.checkStory()) this.refresh();
  }

  ctab_offers(c) {
    const d = c.d;
    const box = el('div', {});
    if (d.booked) box.append(el('p', { class: 'muted' }, 'คุณมีไฟต์ที่จองไว้แล้ว'));
    if (!d.offers.length) box.append(el('p', { class: 'muted' }, 'ยังไม่มีข้อเสนอใหม่'));
    const my = c.ovr();
    const best = d.offers.reduce((b, o) => (!b || Math.abs(o.oppRating - (my - 3)) < Math.abs(b.oppRating - (my - 3)) ? o : b), null);
    if (d.offers.length && !d.booked) box.append(el('button', { class: 'btn primary', style: { marginBottom: '8px' }, onclick: () => { c.acceptOffer(best.id); this.save(); this.careerTab = 'week'; this.refresh(); } }, `⭐ รับไฟต์ที่แนะนำ (โอกาสชนะ ~${Math.round(c.winChance(best.oppRating) * 100)}%)`));
    for (const o of d.offers) {
      const wc = Math.round(c.winChance(o.oppRating) * 100);
      box.append(el('div', { class: 'offer' }, o === best ? el('div', { class: 'small', style: { color: '#ffd36a', fontWeight: 800 } }, '⭐ แนะนำ') : null,
        el('div', { class: 'small', style: { color: wc >= 55 ? '#9fe39f' : wc >= 40 ? '#ffd36a' : '#ff8b8b' } }, `🎯 โอกาสชนะ ~${wc}% ${wc >= 55 ? '(ได้เปรียบ)' : wc >= 40 ? '(สูสี)' : '(ยากมาก)'}`),
        el('div', { class: 'vs' }, `vs ${o.oppName}`), el('div', { class: 'small' }, `สถิติ ${o.oppRec} · สไตล์ ${STYLES[o.oppStyle]?.name || o.oppStyle} · ค่าพลังรวม ~${o.oppRating}`),
        el('div', { class: 'small' }, `${PROMOTIONS[o.promo].name} · ${o.rounds} ยก · อีก ${o.weeksOut} สัปดาห์ ${o.short ? '⚡ แจ้งล่วงหน้าสั้น (+40% ค่าตัว แต่แคมป์สั้น)' : ''}`),
        el('div', { class: 'small' }, o.purse.show + o.purse.win > 0 ? `ค่าตัว ${money(o.purse.show)} + โบนัสชนะ ${money(o.purse.win)}` : 'สมัครเล่น: ไม่มีค่าตัว'),
        el('div', { class: 'small muted' }, `ข้อเสนอหมดอายุใน ${o.expires} สัปดาห์`),
        el('div', { class: 'row', style: { marginTop: '6px' } },
          el('button', { class: 'btn small primary', disabled: d.booked || d.health.suspension > 0 ? 'disabled' : null, onclick: () => { c.acceptOffer(o.id); this.save(); this.careerTab = 'week'; this.refresh(); } }, 'รับไฟต์'),
          o.purse.show > 0 ? el('button', { class: 'btn small', onclick: () => { this.toast(c.negotiate(o.id)); this.save(); this.refresh(); } }, 'ต่อรองค่าตัว') : null,
          el('button', { class: 'btn small', onclick: () => { c.declineOffer(o.id); this.save(); this.refresh(); } }, 'ปฏิเสธ'))));
    }
    return box;
  }

  ctab_attrs(c) {
    const box = el('div', {});
    const a = c.A;
    for (const [grp, list] of Object.entries(ATTRS)) {
      box.append(el('h3', {}, { striking: 'ยืนสู้', grappling: 'ปล้ำ/พื้น', physical: 'ร่างกาย', mental: 'จิตใจ' }[grp]));
      for (const [k, name] of list) box.append(el('div', { class: 'attr-row', style: { gridTemplateColumns: '1fr 40px' } }, el('span', {}, name), el('span', { class: 'val' }, String(Math.round(a[k]))), el('div', { class: 'attr-bar' }, el('div', { style: { width: a[k] + '%' } }))));
    }
    return box;
  }

  ctab_rank(c) {
    const d = c.d;
    const pr = d.promo === 'amateur' ? 'regional' : d.promo;
    const t = c.rankingTable(pr);
    const box = el('div', {}, el('h3', {}, `${PROMOTIONS[pr].name} — รุ่น ${c.wc.name}`));
    const list = el('div', { class: 'rank-list' });
    let r = 0;
    for (const x of t) {
      const lbl = x.champ ? 'C' : (r++, r <= 15 ? String(r) : 'NR');
      list.append(el('div', { class: x.me ? 'me' : '' }, el('span', { style: { width: '28px' } }, lbl), el('span', { class: 'grow' }, x.name + (x.nick ? ` "${x.nick}"` : '')), el('span', {}, `${x.rec.w}-${x.rec.l}${x.rec.d ? '-' + x.rec.d : ''}`)));
    }
    box.append(list);
    return box;
  }
  ctab_inbox(c) {
    return el('div', {}, ...c.d.inbox.slice(0, 30).map((m) => el('div', { class: 'inbox-item' + (m.important ? ' new' : '') }, el('b', {}, m.from), el('span', { class: 'muted small' }, ` · สัปดาห์ ${m.week}`), el('div', {}, m.text))));
  }
  ctab_history(c) {
    const h = c.f.history;
    if (!h.length) return el('p', { class: 'muted' }, 'ยังไม่มีไฟต์');
    return el('table', { class: 'cards' }, el('tr', {}, el('th', {}, 'ผล'), el('th', {}, 'คู่ชก'), el('th', {}, 'วิธี'), el('th', {}, 'ยก'), el('th', {}, 'เวที'), el('th', {}, 'รายได้')),
      ...h.map((x) => el('tr', {}, el('td', { style: { color: x.res === 'W' ? '#9fe39f' : x.res === 'L' ? '#ff6b6b' : '' } }, x.res), el('td', {}, x.opp), el('td', {}, `${x.method}${x.detail ? ' (' + x.detail + ')' : ''}`), el('td', {}, `${x.round} · ${x.time}`), el('td', {}, x.promo + (x.title ? ' 🏆' : '')), el('td', {}, money(x.purse)))));
  }
  ctab_gym(c) {
    const d = c.d;
    return el('div', {}, el('p', { class: 'muted' }, 'ยิมมีผลต่อความเร็วในการพัฒนาและค่าใช้จ่ายรายสัปดาห์ (ยิมครูเดชหัก 10% จากค่าตัวโปร)'),
      ...Object.entries(GYMS).map(([k, g]) => el('div', { class: 'offer' }, el('b', {}, g.name), d.gym === k ? el('span', { style: { color: '#9fe39f' } }, ' (ปัจจุบัน)') : null,
        el('div', { class: 'small muted' }, g.desc), el('div', { class: 'small' }, `ค่าบริการ ${money(g.fee)}/สัปดาห์ · ประสิทธิภาพการซ้อม x${g.mul}`),
        d.gym !== k ? el('button', { class: 'btn small', disabled: (g.minTier || 0) > c.tier ? 'disabled' : null, onclick: () => { d.gym = k; if (k !== 'irongate') { d.rel.coach -= 15; c.msg('ครูเดช', 'ไปเถอะ... ข้าเข้าใจ ถ้าวันไหนเอ็งเจ็บกลับมา ประตูยิมไม่เคยล็อก'); } this.save(); this.refresh(); } }, (g.minTier || 0) > c.tier ? 'ต้องมีชื่อเสียงมากกว่านี้' : 'ย้ายไปยิมนี้') : null)));
  }

  // ---------- fight week ----------
  scr_weighin() {
    const c = this.career, b = c.d.booked;
    if (!b) return this.scr_career();
    if (!this._wi) { this._wi = c.weighIn(); c.lastWeighIn = this._wi; }
    const wi = this._wi;
    return el('div', { class: 'screen solid' }, el('div', { class: 'panel', style: { width: 'min(640px, 100%)' } },
      el('h2', {}, '⚖️ ชั่งน้ำหนักอย่างเป็นทางการ'),
      el('p', {}, `น้ำหนักตัวปกติ ${wi.walk.toFixed(1)} กก. → ลิมิต ${wi.limit.toFixed(1)} กก. (ต้องรีดน้ำ ${(wi.cut * 100).toFixed(1)}%)`),
      el('p', { style: { color: wi.missed ? '#ff6b6b' : wi.severe ? '#ffb020' : '#9fe39f', fontWeight: 800, fontSize: '20px' } },
        wi.missed ? `❌ ชั่งไม่ผ่าน! เกินลิมิต ${Math.max(0.2, wi.walk * 0.01 * (wi.cut * 100 - 7)).toFixed(1)} กก. ถูกปรับ 20% ของค่าตัว` : wi.severe ? '⚠️ ผ่านแบบหวุดหวิด — ร่างกายขาดน้ำหนัก คาร์ดิโอและคางจะแย่ลงในไฟต์' : wi.cut > 0.04 ? '✅ ผ่าน — แต่รีดน้ำมาพอสมควร คาร์ดิโอลดลงเล็กน้อย' : '✅ ผ่านสบาย ร่างกายสดชื่น'),
      el('p', { class: 'muted small' }, 'งานวิจัยพบว่านักสู้ที่ตัดน้ำหนักมากกว่ามีโอกาสแพ้สูงขึ้น และการขาดน้ำทำให้หมดแรงเร็วขึ้นแม้รีไฮเดรตแล้ว 24 ชม.'),
      el('h3', {}, `คู่ชก: ${b.oppName} (${b.oppRec})`),
      el('div', { class: 'menu', style: { width: '100%' } },
        el('button', { class: 'btn primary', onclick: () => this.startCareerFight('play') }, '🥊 ขึ้นชก (ควบคุมเอง)'),
        el('button', { class: 'btn', onclick: () => this.startCareerFight('watch') }, '👀 ให้ AI ชกแทน (นั่งดูจากมุมโค้ช)'),
        el('button', { class: 'btn', onclick: () => this.simCareerFight() }, '⏩ จำลองผลทันที'))));
  }

  async startCareerFight(mode) {
    const c = this.career, b = c.d.booked;
    this.app.preview.clear(); this.app.preview.offset = 0.55; this.app.preview.zoom = 1;
    const face = await loadFaceCanvas(c.f.faceData);
    const me = c.myFightProfile(this._wi, face);
    const opp = c.oppFightProfile();
    this.close();
    const sc = this.app.startFight({
      red: me, blue: opp, playerSide: 'red', playerAI: mode === 'watch', rounds: b.rounds, roundLen: b.roundLen, aiLevel: clamp(this.app.save.settings.difficulty + (b.promo === 'major' ? 0.1 : b.promo === 'amateur' ? -0.15 : 0), 0.15, 1),
      brand: { amateur: 'WAREHOUSE 7', regional: 'IRON GATE', contender: 'PROVING', major: 'APEX' }[b.promo], title: `${PROMOTIONS[b.promo].short}${b.title ? ' · TITLE FIGHT' : ''}: ${me.name} vs ${opp.name}`,
    });
    sc.career = true;
    if (mode === 'watch') sc.player = sc.red; // view from player side; AI controls
  }

  simCareerFight() {
    const c = this.career;
    const res = c.simulate();
    res.missedWeight = this._wi && this._wi.missed;
    const notes = c.applyResult(res);
    this._wi = null;
    this.save();
    this.go('careerResult', { res, notes });
  }

  scr_careerResult({ res, notes }) {
    const c = this.career;
    return el('div', { class: 'screen solid' }, el('div', { class: 'panel', style: { width: 'min(640px, 100%)' } },
      el('div', { class: 'result-big ' + (res.won ? 'win' : 'loss') }, res.draw ? 'เสมอ' : res.won ? 'ชนะ!' : 'แพ้'),
      el('p', { style: { textAlign: 'center' } }, `${res.method} — ${res.detail || ''} · ยก ${res.round} ${res.time || ''}`),
      ...notes.map((n) => el('div', { class: 'small' }, '• ' + n)),
      el('button', { class: 'btn primary', style: { marginTop: '14px' }, onclick: () => { this.careerTab = 'week'; this.openCareer(); } }, 'กลับสู่ยิม ▶')));
  }

  // ---------- quick fight ----------
  scr_quick() {
    const q = this.qf = this.qf || { me: 'random', meStyle: 'boxing', opStyle: 'muaythai', opLevel: 1, rounds: 3, mode: 'play', wc: 'light' };
    const mine = this.app.save.fighters;
    const sel = (opts, cur, cb) => el('select', { onchange: (e) => { cb(e.target.value); this.refresh(); } }, ...opts.map(([v, t]) => el('option', { value: v, selected: String(v) === String(cur) ? 'selected' : null }, t)));
    const pics = (opts, cur, cb) => el('div', { class: 'iconbar' }, ...opts.map(([v, pic, t]) => el('button', { class: 'iconbtn' + (String(v) === String(cur) ? ' sel' : ''), onclick: () => { cb(v); this.refresh(); } }, el('span', { class: 'pic' }, pic), t)));
    const SP = { boxing: '🥊', muaythai: '🐘', wrestling: '🤼', bjj: '🐍', kickboxing: '🦵', judo: '🥋', sambo: '🐻', brawler: '👊' };
    const styles = STYLE_KEYS.map((k) => [k, SP[k], STYLES[k].name.split(' (')[0]]);
    return el('div', { class: 'screen dim' }, el('div', { class: 'panel', style: { width: 'min(640px, 100%)' } },
      el('h2', {}, '⚡ ไฟต์ด่วน'),
      el('h3', {}, '🧑 คุณ'),
      mine.length ? sel([['random', '🎲 สุ่มนักสู้ตามสไตล์'], ...mine.map((p, i) => [String(i), `👤 ${p.name}`])], q.me, (v) => (q.me = v)) : null,
      q.me === 'random' ? pics(styles, q.meStyle, (v) => (q.meStyle = v)) : null,
      el('h3', {}, '🆚 คู่ชก'), pics(styles, q.opStyle, (v) => (q.opStyle = v)),
      el('h3', {}, '📶 ระดับ'), pics([[0, '🥉', 'สมัครเล่น'], [1, '🥈', 'ภูมิภาค'], [2, '🥇', 'ท็อป'], [3, '🏆', 'แชมป์โลก']], q.opLevel, (v) => (q.opLevel = Number(v))),
      el('h3', {}, '🔔 จำนวนยก'), pics([[1, '1️⃣', '1 ยก'], [3, '3️⃣', '3 ยก'], [5, '5️⃣', '5 ยก']], q.rounds, (v) => (q.rounds = Number(v))),
      el('h3', {}, '🎮 โหมด'), pics([['play', '🎮', 'เล่นเอง'], ['watch', '🍿', 'ดู AI ชกกัน']], q.mode, (v) => (q.mode = v)),
      el('h3', {}, '⚖️ รุ่น'), sel(WEIGHT_CLASSES.map((w) => [w.id, w.name]), q.wc, (v) => (q.wc = v)),
      el('div', { class: 'row', style: { marginTop: '12px' } }, el('button', { class: 'btn primary', onclick: () => this.startQuick() }, '🥊 เริ่มไฟต์'), el('button', { class: 'btn', onclick: () => this.go('title') }, icon('back', 18), ' กลับ'))));
  }

  async startQuick(sandbox = false) {
    const q = this.qf || {};
    let me, face = null;
    if (q.me !== 'random' && this.app.save.fighters[Number(q.me)]) {
      const p = this.app.save.fighters[Number(q.me)];
      face = await loadFaceCanvas(p.faceData);
      me = { ...profileForFight(p, { ...p.attrs }), faceCanvas: face };
      me.attrs = { ...me.attrs }; for (const k in me.attrs) me.attrs[k] = clamp(me.attrs[k] + 18, 10, 99); // quick fight: pro level version
    } else me = makeNPC(Math.floor(rng() * 1e9), { tier: 2, wc: q.wc || 'light', style: q.meStyle || 'boxing' });
    const opp = makeNPC(Math.floor(rng() * 1e9), { tier: q.opLevel ?? 1, wc: q.wc || 'light', style: q.opStyle || 'muaythai' });
    this.stopBackground();
    this.close();
    if (this.sbPanel && !sandbox) { this.sbPanel.remove(); this.sbPanel = null; }
    this.dragMode = false; this.app.sandboxTimeScale = 1;
    const sc = this.app.startFight({ red: me, blue: opp, playerSide: 'red', playerAI: q.mode === 'watch', rounds: q.rounds || 3, roundLen: 300, aiLevel: this.app.save.settings.difficulty, sandbox, brand: 'APEX' });
    sc.quick = true;
    if (sandbox) { this.sandboxPanel(); }
  }

  // ---------- sandbox ----------
  scr_sandboxSetup() {
    this.qf = this.qf || { me: 'random', meStyle: 'boxing', opStyle: 'muaythai', opLevel: 1, rounds: 1, mode: 'play', wc: 'light' };
    const node = this.scr_quick();
    node.querySelector('h2').textContent = '🧪 แซนด์บ็อกซ์ — เลือกนักสู้เริ่มต้น';
    const btn = node.querySelector('.btn.primary');
    btn.textContent = '🧪 เข้าสู่แซนด์บ็อกซ์';
    btn.onclick = () => this.startQuick(true);
    return node;
  }

  sandboxPanel() {
    const sc = this.app.scene; if (!sc) return;
    if (this.sbPanel) this.sbPanel.remove();
    sc.clock = 1e9; sc.roundLen = 1e9;
    this.app.sandboxTimeScale = 1;
    this.dragMode = false;
    const settings = sc.sbs = { invincible: false, infStam: false, oneHit: false };
    const touch = TouchControls.wanted(this.app.save.settings.touch);
    const panel = el('div', { class: 'sandbox-panel' + (touch ? ' min' : '') });
    const F = () => [sc.red, sc.blue];
    this.sbTarget = 'blue';
    const pick = () => (this.sbTarget === 'red' ? sc.red : sc.blue);
    const B = (pic, t, fn, opts = {}) => {
      const b = el('button', { class: 'iconbtn' + (opts.sel ? ' sel' : ''), title: opts.tip || t, onclick: () => { fn(b); } }, el('span', { class: 'pic' }, pic), t);
      return b;
    };
    const group = (title, ...btns) => [el('div', { class: 'sb-title' }, title), el('div', { class: 'sb-grid' }, ...btns)];
    const radio = (b) => { for (const x of b.parentNode.children) x.classList.remove('sel'); b.classList.add('sel'); };
    const injure = (fn) => () => { const f = pick(); fn(f, f.health); f.fx.setDamage(f.damageView()); f.model.setInjuryVisuals(f.health); };
    const tog = (k) => (b) => { settings[k] = !settings[k]; b.classList.toggle('sel', settings[k]); };
    const speed = (v) => (b) => { this.app.sandboxTimeScale = v; radio(b); };
    const reset = () => { if (sc.grapple.link) sc.grapple.release(sc.red); sc.red.placeAt(-1.4, 0, Math.PI / 2); sc.blue.placeAt(1.4, 0, -Math.PI / 2); for (const f of F()) { f.state = 'stand'; f.ko = false; f.holdRag = false; f.rig.grab = null; } sc.result = null; sc.phase = 'fight'; };
    const limp = (f) => { f.holdRag = true; f.fall({ kind: 'limp', power: 0.3, dir: new THREE.Vector3(rng() - 0.5, 0, rng() - 0.5) }); };
    const getUp = (f) => { f.holdRag = false; f.ko = false; f.health.consc = Math.max(f.health.consc, 0.8); f.health.rocked = 0; f.rig.grab = null; };
    const head = el('div', { class: 'sb-head' }, el('b', {}, '🧪 แซนด์บ็อกซ์'), el('button', { class: 'iconbtn sb-min', onclick: () => panel.classList.toggle('min') }, el('span', { class: 'pic' }, '☰'), 'เมนู'));
    const body = el('div', { class: 'sb-body' },
      ...group('🎮 ใครคุม', B('🔴', 'คุมแดง', (b) => { this.setControl(sc, 'red'); radio(b); }, { sel: true }), B('🔵', 'คุมน้ำเงิน', (b) => { this.setControl(sc, 'blue'); radio(b); }), B('🤖', 'AI vs AI', (b) => { this.setControl(sc, 'aiai'); radio(b); }),
        B('🧍', 'คู่เป็นหุ่น', (b) => { this.setControl(sc, 'dummy'); radio(b); }), B('🎯', 'AI ตีหุ่น', (b) => { this.setControl(sc, 'dummyai'); radio(b); })),
      ...group('⏱️ เวลา', B('🐌', '0.1x', speed(0.1)), B('🐢', '0.3x', speed(0.3)), B('▶️', '1x', speed(1), { sel: true })),
      ...group('🪆 Ragdoll',
        B('✋', 'ลากร่าง', (b) => { this.dragMode = !this.dragMode; b.classList.toggle('sel', this.dragMode); this.toast(this.dragMode ? 'ลากตัวนักสู้ด้วยเมาส์หรือนิ้ว' : 'ปิดโหมดลากร่าง'); }, { tip: 'กดค้างที่ตัวนักสู้แล้วลาก' }),
        B('🪆', 'ตัวอ่อน', () => limp(pick())), B('💫', 'ล้มทั้งคู่', () => F().forEach(limp)), B('🧍', 'ลุกขึ้น', () => F().forEach(getUp)),
        B('🫸', 'ผลักล้ม', injure((f) => f.fall({ kind: 'trip', power: 0.9, dir: new THREE.Vector3(rng() - 0.5, 0, rng() - 0.5).normalize() })))),
      ...group('🎯 เป้าหมาย', B('🔵', 'น้ำเงิน', (b) => { this.sbTarget = 'blue'; radio(b); }, { sel: true }), B('🔴', 'แดง', (b) => { this.sbTarget = 'red'; radio(b); })),
      ...group('🩸 ทำให้บาดเจ็บ',
        B('🩸', 'คิ้วซ้าย', injure((f, h) => h.addCut(0.7, 0.355, 'browL', 1.3))), B('🩸', 'คิ้วขวา', injure((f, h) => h.addCut(0.3, 0.355, 'browR', 1.3))),
        B('🩸', 'หน้าผาก', injure((f, h) => h.addCut(0.5, 0.18, 'forehead', 1.6))), B('👃', 'จมูกหัก', injure((f, h) => { h.noseBroken = true; h.noseDeviation = 0.35; h.noseBleed = 0.9; h.nose = 1.2; })),
        B('👁️', 'ตาบวม', injure((f, h) => { h.swell.eyeL = 1.1; })), B('🦵', 'ขาตาย', injure((f, h) => { h.legs[f.lead] = 100; h.deadLeg[f.lead] = true; })),
        B('😵', 'มึนงง', injure((f, h) => { h.rocked = 6; h.consc = 0.4; })), B('💥', 'น็อก', injure((f, h) => { f.ko = true; h.consc = 0; f.fall({ kind: 'ko', dir: f.rig.F.dir(new THREE.Vector3(0, 0, -1), new THREE.Vector3()), power: 1.2, fencing: rng() < 0.6 }); })),
        B('🫃', 'หมัดตับ', injure((f, h) => { h.liverDelay = 0.4; }))),
      ...group('⚙️ กติกา', B('🛡️', 'อมตะ', tog('invincible')), B('♾️', 'แรงไม่หมด', tog('infStam')), B('💥', 'หมัดเดียวจอด', tog('oneHit'))),
      ...group('🧰 อื่นๆ',
        B('📷', 'กล้อง', () => { const c = this.app.world.cam; c.mode = c.mode === 'orbit' ? 'broadcast' : 'orbit'; c.orbitDist = 4; }), B('🔄', 'รีเซ็ต', reset),
        B('💚', 'รักษา', () => { for (const f of F()) { const nf = new (f.health.constructor)(f.attrs, {}); f.health = nf; f.fx.clearAll(); f.fx.setDamage(f.damageView()); f.model.setInjuryVisuals(nf); f.model.gloveBlood = 0; f.ko = false; } }),
        B('🧽', 'ล้างเลือด', () => { this.app.world.cleanMat(); this.app.blood.clear(); for (const f of F()) f.fx.wipe(1); }),
        B('🎲', 'คู่ชกใหม่', () => { this.qf.opStyle = STYLE_KEYS[Math.floor(rng() * STYLE_KEYS.length)]; this.startQuick(true); }),
        B('🚪', 'ออก', () => this.exitFight())),
    );
    panel.append(head, body);
    this.app.uiRoot.appendChild(panel);
    this.sbPanel = panel;
    const orig = sc.stepFixed.bind(sc);
    sc.stepFixed = (h) => {
      for (const f of F()) {
        if (settings.infStam) f.health.stamina = f.health.staminaMax;
        if (settings.invincible) { f.health.consc = Math.max(f.health.consc, 0.5); f.health.rocked = 0; f.health.brain = Math.min(f.health.brain, 20); }
        if (settings.oneHit) f.health.chin = 0.02;
      }
      sc.clock = 1e9;
      orig(h);
    };
  }

  // sandbox ragdoll dragging (mouse or finger): pick the nearest joint under the pointer and pull it
  pickBody(e) {
    const sc = this.app.scene; if (!sc || !sc.sandbox || !this.dragMode) return false;
    const rect = this.app.view.getBoundingClientRect();
    const ndc = new THREE.Vector2(((e.clientX - rect.left) / rect.width) * 2 - 1, -((e.clientY - rect.top) / rect.height) * 2 + 1);
    const ray = new THREE.Raycaster(); ray.setFromCamera(ndc, this.app.world.camera);
    const o = ray.ray.origin, d = ray.ray.direction;
    let best = null;
    for (const f of [sc.red, sc.blue]) {
      f.rig.pts.forEach((p, idx) => {
        const v = p.clone().sub(o); const t = v.dot(d); if (t < 0) return;
        const dist = v.addScaledVector(d, -t).length();
        if (dist < 0.32 && (!best || dist < best.dist)) best = { f, idx, t, dist };
      });
    }
    if (!best) return false;
    const f = best.f;
    if (f.rig.mode !== 'anim' || f.state === 'grapple') { if (sc.grapple.link) sc.grapple.release(f); }
    if (f.rig.mode === 'anim') f.fall({ kind: 'grab', power: 0 });
    f.rig.grab = { idx: best.idx, target: f.rig.pts[best.idx].clone() };
    this.drag = { f, t: best.t };
    return true;
  }
  moveDrag(e) {
    if (!this.drag) return;
    const rect = this.app.view.getBoundingClientRect();
    const ndc = new THREE.Vector2(((e.clientX - rect.left) / rect.width) * 2 - 1, -((e.clientY - rect.top) / rect.height) * 2 + 1);
    const ray = new THREE.Raycaster(); ray.setFromCamera(ndc, this.app.world.camera);
    const g = this.drag.f.rig.grab; if (!g) { this.drag = null; return; }
    g.target.copy(ray.ray.origin).addScaledVector(ray.ray.direction, this.drag.t);
    if (g.target.y < 0.05) g.target.y = 0.05;
  }
  endDrag() { if (this.drag) { this.drag.f.rig.grab = null; this.drag = null; } }

  setControl(sc, v) {
    const mkAI = (f) => new (sc._AI)(f, this.app.save.settings.difficulty);
    sc.ais.clear();
    sc.player = null;
    for (const f of [sc.red, sc.blue]) f.input = Fighter.blankInput();
    if (v === 'red') { sc.player = sc.red; sc.ais.set(sc.blue, mkAI(sc.blue)); }
    if (v === 'blue') { sc.player = sc.blue; sc.ais.set(sc.red, mkAI(sc.red)); }
    if (v === 'aiai') { sc.ais.set(sc.red, mkAI(sc.red)); sc.ais.set(sc.blue, mkAI(sc.blue)); }
    if (v === 'dummy') { sc.player = sc.red; }
    if (v === 'dummyai') { sc.ais.set(sc.red, mkAI(sc.red)); }
  }

  // ---------- in-fight overlays ----------
  scr_pause() {
    const sc = this.app.scene;
    const T = (pic, label, fn, cls = '') => el('button', { class: 'tile ' + cls, onclick: fn }, el('span', { class: 'pic' }, pic), el('span', {}, label));
    return el('div', { class: 'screen dim' }, el('div', { class: 'panel', style: { width: 'min(520px, 100%)' } },
      el('h2', {}, '⏸️ หยุดชั่วคราว'),
      el('div', { class: 'tiles', style: { gridTemplateColumns: 'repeat(2, 1fr)' } },
        T('▶️', 'เล่นต่อ', () => { sc.paused = false; this.close(); }, 'primary'),
        T('🎮', 'ปุ่มควบคุม', () => this.go('help')),
        T('📷', 'สลับกล้อง', () => { const c = this.app.world.cam; c.mode = c.mode === 'orbit' ? 'broadcast' : 'orbit'; c.orbitDist = 4.5; sc.paused = false; this.close(); }),
        T(sc.career ? '🏳️' : '🚪', sc.career ? 'โยนผ้า' : 'ออก', () => this.ask(sc.career ? 'โยนผ้ายอมแพ้? ไฟต์นี้จะนับเป็นแพ้ TKO' : 'ออกจากไฟต์นี้?', () => { sc.paused = false; this.close(); if (sc.career) { sc.endFight(sc.blue, 'TKO', 'ถอนตัว (Corner Stoppage)'); } else { this.exitFight(); } }, sc.career ? 'โยนผ้า' : 'ออก')))));
  }

  showCorner(sc, card) {
    if (sc.background || sc.sandbox) { setTimeout(() => sc.nextRound({}), 200); return; }
    this.go('corner', { sc, card });
  }
  scr_corner({ sc }) {
    const me = sc.player || sc.red;
    const opp = me.opp;
    const h = me.health;
    const ch = this.cornerChoices = this.cornerChoices || { treatCuts: true, enswell: true, water: true, strategy: 'balanced' };
    const advice = [];
    if (opp.stats.sigLanded > me.stats.sigLanded + 8) advice.push('เอ็งโดนมากกว่าชก! ยกการ์ด ขยับหัว อย่ายืนนิ่ง');
    if (opp.health.legs[opp.lead] > 45) advice.push('ขาหน้ามันเริ่มเสียแล้ว เตะน่องต่อ!');
    if (opp.health.swell.eyeL > 0.5 || opp.health.swell.eyeR > 0.5) advice.push('ตามันบวม มันมองไม่เห็นฝั่งนั้น — วนไปทางนั้นแล้วปล่อยหมัด');
    if (me.stats.tdAtt > 0 && me.stats.td === 0) advice.push('มันกันเทคดาวน์ได้ ยิงหลังปล่อยหมัดชุด (level change ตอนมันสวน)');
    if (h.stamina < 40) advice.push('เอ็งหอบแล้ว ชกให้คุ้ม อย่าปล่อยหมัดลม หมัดที่พลาดเปลืองแรงที่สุด');
    if (opp.stats.td > 1) advice.push('มันพาลงพื้นได้ — อยู่ห่างกรง กด C สปรอลทันทีที่มันก้มตัว');
    if (!advice.length) advice.push('ทำต่อแบบนี้ แย็บนำ คุมระยะ อย่าโลภ');
    const [r, b] = sc.scoreSoFar();
    const myPts = me === sc.red ? r : b, opPts = me === sc.red ? b : r;
    const tick = (k, t) => el('label', { style: { display: 'block' } }, el('input', { type: 'checkbox', checked: ch[k] ? 'checked' : null, onchange: (e) => { ch[k] = e.target.checked; } }), ' ' + t);
    return el('div', { class: 'screen dim' }, el('div', { class: 'panel', style: { width: 'min(620px, 100%)' } },
      el('h2', {}, `🪑 พักยก — หลังยกที่ ${sc.round}`),
      el('div', { class: 'card' }, el('b', {}, 'ครูเดช: '), ...advice.map((a) => el('div', {}, '• ' + a))),
      el('div', { class: 'card', style: { marginTop: '8px' } }, el('b', {}, 'สภาพของคุณ'),
        el('div', { class: 'small' }, `สตามินา ${Math.round(h.stamina)}% (ถังสูงสุด ${Math.round(h.staminaMax)}%) · หมัดเข้าเป้า ${me.stats.sigLanded} ต่อ ${opp.stats.sigLanded}`),
        el('div', { class: 'small', style: { color: '#ffb3b3' } }, h.summary().join(' · ') || 'ยังไม่บาดเจ็บ'),
        el('div', { class: 'small muted' }, `โค้ชประเมินคะแนน: ${myPts > opPts ? 'เอ็งน่าจะนำ' : myPts < opPts ? 'เอ็งน่าจะตามหลัง' : 'สูสี'}`)),
      el('h3', {}, 'คัทแมน & ทีม'),
      el('div', { class: 'iconbar' }, ...[['treatCuts', '🩹', 'ห้ามเลือด'], ['enswell', '🧊', 'ประคบตา'], ['water', '💧', 'จิบน้ำ']].map(([k, pic, t]) => el('button', { class: 'iconbtn' + (ch[k] ? ' sel' : ''), title: { treatCuts: 'กดแผล + อะดรีนาลีน 1:1000 + วาสลีน', enswell: 'Enswell เย็นลดบวมรอบตา', water: 'ฟื้นสตามินา' }[k], onclick: (e) => { ch[k] = !ch[k]; e.currentTarget.classList.toggle('sel', ch[k]); } }, el('span', { class: 'pic' }, pic), t))),
      el('button', { class: 'btn primary', style: { marginTop: '12px' }, onclick: () => { this.close(); sc.nextRound(ch); } }, `🔔 ยกที่ ${sc.round + 1}`)));
  }

  onFightEnd(sc) {
    if (sc.background) { setTimeout(() => { if (this.app.scene === sc) { this.app.endScene(); this.backgroundFight(); } }, 3000); return; }
    if (sc.sandbox) return;
    this.go('result', { sc });
  }

  scr_result({ sc }) {
    const r = sc.result, me = sc.player || sc.red, opp = me.opp;
    const won = r.winner === me, draw = !r.winner;
    const st = (f) => f.stats;
    const row = (t, a, b) => el('tr', {}, el('td', {}, String(a)), el('th', {}, t), el('td', {}, String(b)));
    const cards = r.cards[0].length ? el('table', { class: 'cards' }, el('tr', {}, el('th', {}, 'กรรมการ'), ...r.cards[0].map((_, i) => el('th', {}, `ยก ${i + 1}`)), el('th', {}, 'รวม')),
      ...r.cards.map((j, k) => el('tr', {}, el('td', {}, `${k + 1}`), ...j.map(([a, b]) => el('td', {}, `${a}-${b}`)), el('td', {}, `${r.totals[k][0]}-${r.totals[k][1]}`)))) : null;
    return el('div', { class: 'screen dim' }, el('div', { class: 'panel', style: { width: 'min(700px, 100%)', maxHeight: '92vh', overflow: 'auto' } },
      el('div', { class: 'result-big ' + (won ? 'win' : 'loss') }, draw ? 'เสมอ' : won ? 'คุณชนะ!' : sc.player ? 'คุณแพ้' : `${r.winner.name} ชนะ`),
      el('p', { style: { textAlign: 'center', fontSize: '18px' } }, `${r.method} — ${r.detail} · ยก ${r.round} เวลา ${r.time}`),
      cards,
      el('h3', {}, 'สถิติไฟต์'),
      el('table', { class: 'cards' }, el('tr', {}, el('th', {}, sc.red.name), el('th', {}, ''), el('th', {}, sc.blue.name)),
        row('หมัด/เตะเข้าเป้า (สำคัญ)', `${st(sc.red).sigLanded}/${st(sc.red).sigThrown}`, `${st(sc.blue).sigLanded}/${st(sc.blue).sigThrown}`),
        row('เข้าหัว / ลำตัว / ขา', `${st(sc.red).head}/${st(sc.red).body}/${st(sc.red).leg}`, `${st(sc.blue).head}/${st(sc.blue).body}/${st(sc.blue).leg}`),
        row('น็อกดาวน์', st(sc.red).kd, st(sc.blue).kd), row('เทคดาวน์', `${st(sc.red).td}/${st(sc.red).tdAtt}`, `${st(sc.blue).td}/${st(sc.blue).tdAtt}`),
        row('พยายามล็อก', st(sc.red).subAtt, st(sc.blue).subAtt), row('เวลาคุมพื้น', fmtTime(st(sc.red).ctrl), fmtTime(st(sc.blue).ctrl)),
        row('เสียเลือด', `${Math.round(sc.red.health.bloodLoss)} ml`, `${Math.round(sc.blue.health.bloodLoss)} ml`)),
      el('h3', {}, 'อาการบาดเจ็บ'),
      el('div', { class: 'small' }, el('b', {}, sc.red.name + ': '), sc.red.health.summary().join(', ') || 'ไม่มี'),
      el('div', { class: 'small' }, el('b', {}, sc.blue.name + ': '), sc.blue.health.summary().join(', ') || 'ไม่มี'),
      el('div', { class: 'row', style: { marginTop: '14px' } },
        sc.career ? el('button', { class: 'btn primary', onclick: () => this.finishCareerFight(sc) }, 'ต่อไป ▶')
          : [el('button', { class: 'btn primary', onclick: () => { this.close(); this.startQuick(); } }, '🔁 ไฟต์ใหม่'), el('button', { class: 'btn', onclick: () => this.exitFight() }, 'เมนูหลัก')])));
  }

  exitFight() {
    this.endTutorial();
    if (this.sbPanel) { this.sbPanel.remove(); this.sbPanel = null; }
    this.dragMode = false; this.app.sandboxTimeScale = 1;
    this.app.endScene(); this.go('title'); this.backgroundFight();
  }

  finishCareerFight(sc) {
    const c = this.career, me = sc.red, opp = sc.blue, r = sc.result;
    const won = r.winner === me, draw = !r.winner;
    const h = me.health;
    const res = {
      won, draw, method: r.method.startsWith('DEC') ? 'DEC' : r.method, detail: r.detail, round: r.round, time: r.time,
      sig: me.stats.sigLanded, td: me.stats.td,
      perf: won && r.method !== 'DEC' && rng() < 0.55,
      fotn: me.stats.sigLanded > 20 && opp.stats.sigLanded > 20 && rng() < 0.45,
      dominant: won && r.totals && r.totals.every(([a, b]) => a - b >= 3),
      missedWeight: this._wi && this._wi.missed,
      health: { brain: h.brain, cuts: h.cuts, noseBroken: h.noseBroken, orbital: h.orbitalBroken, jaw: h.jawBroken, hand: h.handBroken[0] || h.handBroken[1], ribs: h.ribCracked, limb: h.submissionInjury, legs: h.legs[0] > 60 || h.legs[1] > 60, koLoss: !won && (r.method === 'KO'), knockdowns: opp.stats.kd },
    };
    const notes = c.applyResult(res);
    this._wi = null;
    this.save();
    this.app.endScene();
    this.go('careerResult', { res, notes });
  }
}
