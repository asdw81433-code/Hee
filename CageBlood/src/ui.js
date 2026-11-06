// ===== Menus, career hub, story, corner, results, sandbox =====
import { el, money, clamp, rng, fmtTime } from './util.js';
import { makeNPC } from './npc.js';
import { Creator, computeAttrs, loadFaceCanvas, profileForFight, defaultProfile } from './creator.js';
import { Career, ACTIVITIES, GYMS, overall } from './career.js';
import { storyById } from './story.js';
import { writeSave, DEFAULT_SETTINGS, exportSave, importSave } from './save.js';
import { STYLES, PROMOTIONS, ATTRS, ATTR_LABEL, wcById, WEIGHT_CLASSES } from './data.js';
import { Fighter } from './fighter.js';
import { P } from './rig.js';

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
    const s = this.screen; if (!s) { this.layer.innerHTML = ''; return; }
    const fn = this['scr_' + s.name];
    this.layer.innerHTML = '';
    if (fn) { const node = fn.call(this, s.data); if (node) this.layer.appendChild(node); }
  }
  close() { this.screen = null; this.layer.innerHTML = ''; }
  toast(t, ms = 2500) { const e = el('div', { class: 'toast' }, t); this.app.uiRoot.appendChild(e); setTimeout(() => e.remove(), ms); }
  frame() {}
  error(e) { if (!this._errShown) { this._errShown = true; this.toast('เกิดข้อผิดพลาด: ' + e.message, 6000); } }

  bindKeys() {
    window.addEventListener('keydown', (e) => {
      const sc = this.app.scene;
      if (!sc || sc.background) return;
      if (sc.replay.playing && ['Space', 'Enter', 'Escape'].includes(e.code)) { sc.replay.stop(); return; }
      if (e.code === 'Escape') { if (this.screen && this.screen.name === 'pause') { this.close(); sc.paused = false; } else if (!this.screen && sc.phase !== 'ended') { sc.paused = true; this.go('pause'); } }
      if (e.code === 'Tab') this.app.hud.toggleDamage();
    });
  }
  bindOrbit() {
    const v = this.app.view; let drag = null;
    v.addEventListener('pointerdown', (e) => { if (this.app.world.cam.mode === 'orbit') drag = [e.clientX, e.clientY]; });
    window.addEventListener('pointerup', () => { drag = null; });
    window.addEventListener('pointermove', (e) => {
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
    return el('div', { class: 'screen dim' }, el('div', { style: { width: 'min(560px, 100%)' } },
      el('div', { class: 'title-logo' }, 'สังเวียนเลือด', el('span', { class: 'en' }, 'CAGE BLOOD')),
      el('div', { class: 'title-sub' }, 'MMA แซนด์บ็อกซ์ · ฟิสิกส์ร่างกายจริง · เลือดและอาการบาดเจ็บสมจริง · โหมดอาชีพพร้อมเนื้อเรื่อง'),
      el('div', { class: 'menu' },
        has ? el('button', { class: 'btn primary', onclick: () => this.openCareer() }, '▶ เล่นโหมดอาชีพต่อ', el('span', { class: 'desc' }, `${this.career.f.name} · ${this.career.dateStr}`)) : null,
        el('button', { class: 'btn' + (has ? '' : ' primary'), onclick: () => this.newCareer() }, '★ เริ่มอาชีพใหม่ (เนื้อเรื่อง)', el('span', { class: 'desc' }, 'สร้างนักสู้ของคุณ วาดหน้าเอง แล้วไต่จากสมัครเล่นสู่แชมป์โลก')),
        el('button', { class: 'btn', onclick: () => this.go('quick') }, '⚡ ไฟต์ด่วน', el('span', { class: 'desc' }, 'ชกทันที เลือกคู่ชกและสไตล์เอง')),
        el('button', { class: 'btn', onclick: () => this.go('sandboxSetup') }, '🧪 แซนด์บ็อกซ์', el('span', { class: 'desc' }, 'ทดลองทุกอย่าง: สโลว์โมชัน ทำให้บาดเจ็บ สลับฝั่ง กล้องอิสระ')),
        el('button', { class: 'btn', onclick: () => this.go('fighters') }, '👤 นักสู้ของฉัน / สร้างนักสู้'),
        el('button', { class: 'btn', onclick: () => this.go('help') }, '🎮 วิธีเล่น & ปุ่มควบคุม'),
        el('button', { class: 'btn', onclick: () => this.go('settings') }, '⚙️ ตั้งค่า'),
        el('button', { class: 'btn', onclick: () => this.go('research') }, '📚 ข้อมูลอ้างอิงที่ใช้สร้างเกม'),
      )));
  }

  scr_help() {
    const k = (x) => el('kbd', {}, x);
    const sec = (t, rows) => el('div', { class: 'card' }, el('h3', {}, t), ...rows.map(([a, b]) => el('div', {}, ...[].concat(a).map((x) => [k(x), ' ']), ' ', b)));
    return el('div', { class: 'screen dim' }, el('div', { class: 'panel', style: { width: 'min(1000px, 100%)', maxHeight: '92vh', overflow: 'auto' } },
      el('h2', {}, 'วิธีเล่น'),
      el('div', { class: 'help-grid' },
        sec('เคลื่อนที่', [[['W', 'S'], 'เดินหน้า/ถอยหลัง (เข้า-ออกจากคู่ชก)'], [['A', 'D'], 'วนซ้าย/ขวารอบคู่ชก'], [['Z', 'X'], 'หลบหัวซ้าย/ขวา (Slip)'], ['C', 'ก้มหลบ (Duck) / สปรอลกันเทคดาวน์']]),
        sec('หมัด (ใส่หัว · กด Shift ค้าง = เข้าลำตัว)', [['J', 'แย็บ (Jab)'], ['K', 'หมัดตรงหลัง (Cross)'], ['U', 'ฮุคหน้า'], ['I', 'ฮุคหลัง'], ['N', 'อัปเปอร์คัตหน้า'], ['M', 'อัปเปอร์คัตหลัง'], ['Y', 'ศอก (แผลแตกง่ายมาก)']]),
        sec('เตะ (ปกติ = ลำตัว · Shift = เตะขา · Q ค้าง = เตะหัว)', [['O', 'เตะเท้าหน้า (คาล์ฟคิก/สวิตช์คิก)'], ['L', 'เตะเท้าหลัง (เตะหนัก)'], ['P', 'ถีบ (Teep)'], ['H', 'เข่า'], ['E', 'ยกแข้งบล็อกเตะ (Check)']]),
        sec('ป้องกัน', [['Space', 'ยกการ์ดสูง (ค้าง)'], [['Space', 'Shift'], 'การ์ดต่ำป้องกันลำตัว'], ['V', 'ค้าง + กดหมัด = หลอก (Feint)']]),
        sec('ปล้ำ', [['F', 'เข้าคลินช์ (ในคลินช์ F/S = ถอยออก)'], ['G', 'ยิงเทคดาวน์ / ในคลินช์ = ทุ่ม / หลังสปรอลได้ = กิโยตีน'], ['W', 'ในคลินช์: ดันติดกรง']]),
        sec('บนพื้น', [['W', 'ด้านบน: ไล่ตำแหน่ง · ด้านล่าง: สวีป'], [['A', 'D'], 'ด้านล่าง: หนีตำแหน่ง'], ['S', 'ลุกขึ้นยืน'], ['G', 'จับล็อก (ซับมิชชัน)'], ['J/K/U/I/Y', 'ทุบ / ศอก จากด้านบน'], ['Space', 'ด้านล่าง: ปิดหน้า · ระหว่างโดนล็อก: รัวเพื่อแก้']]),
        sec('อื่นๆ', [['Esc', 'หยุดเกม'], ['Tab', 'แผนผังร่างกายและอาการบาดเจ็บ'], [['Space', 'Enter'], 'ข้ามรีเพลย์']]),
      ),
      el('div', { class: 'card', style: { marginTop: '12px' } }, el('h3', {}, 'เคล็ดลับความสมจริง'),
        el('ul', {},
          el('li', {}, 'หมัดที่ "หมุนหัว" (ฮุค อัปเปอร์คัต เข้าคาง/กราม) น็อกง่ายกว่าหมัดตรงเข้าหน้าผาก — หมัดหน้าผากทำให้คิ้วแตกแทน'),
          el('li', {}, 'หมัดสวน (โดนตอนคู่ชกกำลังพุ่งเข้ามา) แรงกว่าเพราะความเร็วสัมพัทธ์รวมกัน'),
          el('li', {}, 'หมัดเข้าตับ (ฮุคซ้ายเข้าลำตัวฝั่งขวาของคู่ชก) ทำให้ทรุดแบบหน่วงเวลา'),
          el('li', {}, 'เตะน่องสะสม → เส้นประสาทขาชา ขาทรุดเองเมื่อลงน้ำหนัก'),
          el('li', {}, 'เลือดไหลเข้าตาและตาบวมจะบังการมองเห็นจริงๆ — แพทย์อาจสั่งยุติการชก'),
          el('li', {}, 'ทุกการโดนชกสะสมเป็นความเสียหายของสมองในโหมดอาชีพ (คางจะอ่อนลงถาวร)'))),
      el('button', { class: 'btn', style: { marginTop: '12px' }, onclick: () => this.back() }, '← กลับ')));
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
    return el('div', { class: 'screen dim' }, el('div', { class: 'panel', style: { width: 'min(560px, 100%)' } },
      el('h2', {}, 'ตั้งค่า'),
      row(el('span', {}, 'ความละเอียดกราฟิก', o1), i1), row(el('span', {}, 'ระดับเลือด', o2), i2), row(el('span', {}, 'เสียง', o3), i3),
      row(el('span', {}, 'นาฬิกาในไฟต์', o4), i4), row(el('span', {}, 'ความยาก AI', o5), i5), row(el('span', {}, 'กรรมการหยุดไฟต์', o6), i6),
      el('label', {}, el('input', { type: 'checkbox', checked: s.replay ? 'checked' : null, onchange: (e) => { s.replay = e.target.checked; writeSave(this.app.save); } }), ' แสดงรีเพลย์ตอนน็อก'),
      el('h3', {}, 'สำรองเซฟ'),
      el('div', { class: 'row' },
        el('button', { class: 'btn small', onclick: () => { navigator.clipboard && navigator.clipboard.writeText(exportSave(this.app.save)); this.toast('คัดลอกรหัสเซฟแล้ว'); } }, 'คัดลอกรหัสเซฟ'),
        el('button', { class: 'btn small', onclick: () => { const t = prompt('วางรหัสเซฟ'); if (!t) return; try { const d = importSave(t); Object.assign(this.app.save, d); writeSave(this.app.save); this.career = this.app.save.career ? new Career(this.app.save.career) : null; this.toast('นำเข้าเซฟแล้ว'); } catch (e) { this.toast('รหัสไม่ถูกต้อง'); } } }, 'นำเข้าเซฟ'),
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
        el('button', { class: 'btn small', onclick: () => { if (confirm('ลบนักสู้นี้?')) { list.splice(i, 1); writeSave(this.app.save); this.refresh(); } } }, 'ลบ'))),
      el('div', { class: 'row', style: { marginTop: '10px' } },
        el('button', { class: 'btn primary', onclick: () => this.openCreator((p) => { list.push(p); writeSave(this.app.save); this.go('fighters'); }, () => this.go('fighters')) }, '+ สร้างนักสู้ใหม่'),
        el('button', { class: 'btn', onclick: () => this.go('title') }, '← กลับ'))));
  }

  openCreator(done, cancel, opts) {
    this.stopBackground();
    const cr = new Creator(this, (p) => { this.app.preview.clear(); this.creator = null; this.backgroundFight(); done(p); }, () => { this.app.preview.clear(); this.creator = null; this.backgroundFight(); cancel(); }, opts);
    this.creator = cr;
    cr.refreshPreview();
    this.go('creator');
  }
  scr_creator() { return this.creator ? this.creator.render() : null; }

  // ---------- career ----------
  newCareer() {
    if (this.career && !this.career.d.ended && !confirm('มีเซฟอาชีพอยู่แล้ว เริ่มใหม่จะเขียนทับ ต้องการเริ่มใหม่?')) return;
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
    loadFaceCanvas(this.career.f.faceData).then((c) => { if (this.screen && this.screen.name === 'career') { this.app.preview.offset = -0.9; this.app.preview.show(this.career.myFightProfile(null), c); } });
  }
  leaveCareer() { this.app.preview.clear(); this.app.preview.offset = 0.55; this.save(); this.go('title'); this.backgroundFight(); }

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
          el('span', { class: 'k' }, 'สถิติโปร'), el('b', {}, `${f.record.w}-${f.record.l}-${f.record.d}`),
          el('span', { class: 'k' }, 'สมัครเล่น'), el('span', {}, `${f.am.w}-${f.am.l}`),
          el('span', { class: 'k' }, 'สังกัด'), el('span', {}, PROMOTIONS[d.promo].short),
          el('span', { class: 'k' }, 'อันดับ'), el('span', {}, d.champ ? '🏆 แชมป์' : rank ? `#${rank}` : d.regionalChamp ? 'แชมป์ภูมิภาค' : '-'),
          el('span', { class: 'k' }, 'อายุ'), el('span', {}, `${f.age} ปี`),
          el('span', { class: 'k' }, 'ค่าพลังรวม'), el('b', {}, String(c.ovr())),
          el('span', { class: 'k' }, 'เงิน'), el('b', { style: { color: d.money < 0 ? '#ff6b6b' : '#9fe39f' } }, money(d.money)),
          el('span', { class: 'k' }, 'หนี้วิกเตอร์'), el('span', { style: { color: '#ff9b9b' } }, money(d.debt)),
          el('span', { class: 'k' }, 'กระแส (Hype)'), el('span', {}, `${Math.round(d.hype)}`),
          el('span', { class: 'k' }, 'ชื่อเสียง'), el('span', {}, `${Math.round(d.fame)}`),
          el('span', { class: 'k' }, 'ขวัญกำลังใจ'), el('span', {}, `${Math.round(d.morale)}`),
          el('span', { class: 'k' }, 'ความล้า'), el('span', { style: { color: d.fatigue > 70 ? '#ff6b6b' : '' } }, `${Math.round(d.fatigue)}`),
          el('span', { class: 'k' }, 'น้ำหนักตัว'), el('span', {}, `${f.walkKg.toFixed(1)} / ลิมิต ${c.wc.kg.toFixed(1)} กก.`),
          el('span', { class: 'k' }, 'สมองเสียหายสะสม'), el('span', { style: { color: d.health.brainDamage > 40 ? '#ff6b6b' : '' } }, `${Math.round(d.health.brainDamage)}/100`),
        )),
      el('div', { class: 'card' }, el('h3', {}, 'สุขภาพ'),
        d.health.suspension > 0 ? el('div', { style: { color: '#ffb020' } }, `⛔ พักการชกทางการแพทย์อีก ${d.health.suspension} สัปดาห์`) : null,
        ...(d.health.injuries.length ? d.health.injuries.map((x) => el('div', { class: 'small', style: { color: '#ffb3b3' } }, `• ${x.name} (${x.weeks} สัปดาห์)`)) : [el('div', { class: 'muted small' }, 'ไม่มีอาการบาดเจ็บ')])),
      d.debt > 0 && d.money > 1000 ? el('button', { class: 'btn small', onclick: () => { const pay = Math.min(d.debt, Math.floor(d.money / 1000) * 1000); d.money -= pay; d.debt -= pay; this.toast(`จ่ายหนี้ ${money(pay)}`); this.save(); this.refresh(); } }, '💸 จ่ายหนี้วิกเตอร์') : null,
      el('button', { class: 'btn small', onclick: () => { if (confirm('ประกาศเลิกชก? อาชีพจะจบลงพร้อมฉากจบ')) { c.retire(); this.save(); this.checkStory(); } } }, '🧤 ประกาศแขวนนวม'),
      el('button', { class: 'btn small ghost', onclick: () => this.leaveCareer() }, '← เมนูหลัก (บันทึกแล้ว)'),
    );
    const tabs = el('div', { class: 'tabs' });
    const unread = d.inbox.filter((m) => !m.read).length;
    for (const [k, t] of [['week', '📅 สัปดาห์นี้'], ['offers', `📩 ข้อเสนอไฟต์${d.offers.length ? ` (${d.offers.length})` : ''}`], ['attrs', '📈 ค่าพลัง'], ['rank', '🏅 อันดับ'], ['inbox', `✉️ ข้อความ${unread ? ` (${unread})` : ''}`], ['history', '📜 ประวัติ'], ['gym', '🏠 ยิม']]) {
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
        el('div', { class: 'small', style: { marginTop: '4px', color: (c.f.walkKg - c.wc.kg) / c.f.walkKg > 0.07 ? '#ff9b6b' : '#9fe39f' } }, `ต้องตัดน้ำหนัก ${(Math.max(0, (c.f.walkKg - c.wc.kg) / c.f.walkKg) * 100).toFixed(1)}% ${(c.f.walkKg - c.wc.kg) / c.f.walkKg > 0.07 ? '— หนักเกินไป! เสี่ยงชั่งไม่ผ่านและหมดแรงกลางไฟต์ (คุมอาหาร/คาร์ดิโอ)' : ''}`)));
    } else if (d.health.suspension > 0) box.append(el('p', { class: 'muted' }, 'อยู่ระหว่างพักการชก — ใช้เวลานี้พักฟื้นและพัฒนาฝีมือ'));
    else box.append(el('p', { class: 'muted' }, 'ยังไม่มีไฟต์ — ดูแท็บข้อเสนอไฟต์ หรือรอให้โปรโมเตอร์ติดต่อมา (สร้างกระแสด้วยงานสื่อช่วยได้)'));
    box.append(el('h3', {}, `แผนซ้อมสัปดาห์นี้ (เลือก 3 อย่าง) — ${d.plan.length}/3`));
    const grid = el('div', { class: 'activity' });
    for (const [k, a] of Object.entries(ACTIVITIES)) {
      grid.append(el('button', { class: 'btn small' + (d.plan.includes(k) ? ' sel' : ''), onclick: () => { c.togglePlan(k); this.refresh(); } }, `${a.icon} ${a.name}`, el('span', { class: 'desc' }, a.desc)));
    }
    box.append(grid);
    if (c.lastReport) {
      const g = Object.entries(c.lastReport.gains).filter(([, v]) => v > 0.05).map(([k, v]) => `${ATTR_LABEL[k]} +${v.toFixed(1)}`);
      box.append(el('div', { class: 'card', style: { marginTop: '10px' } }, el('b', {}, 'สัปดาห์ที่แล้ว: '), g.join(', ') || 'ไม่มีการพัฒนาค่าพลัง', ...c.lastReport.notes.map((n) => el('div', { class: 'small', style: { color: '#ffcf6a' } }, n))));
    }
    box.append(el('div', { class: 'row', style: { marginTop: '12px' } }, el('div', { class: 'grow' }),
      el('button', { class: 'btn primary', onclick: () => this.nextWeek() }, d.booked && d.booked.weeksOut <= 1 ? '🥊 สัปดาห์ไฟต์! ▶' : 'สัปดาห์ถัดไป ▶')));
    return box;
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
    for (const o of d.offers) {
      box.append(el('div', { class: 'offer' },
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
    this.app.preview.clear(); this.app.preview.offset = 0.55;
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
    const q = this.qf = this.qf || { me: 'random', meStyle: 'boxing', opStyle: 'muaythai', opLevel: 2, rounds: 3, mode: 'play', wc: 'light' };
    const mine = this.app.save.fighters;
    const sel = (opts, cur, cb) => el('select', { onchange: (e) => { cb(e.target.value); this.refresh(); } }, ...opts.map(([v, t]) => el('option', { value: v, selected: String(v) === String(cur) ? 'selected' : null }, t)));
    return el('div', { class: 'screen dim' }, el('div', { class: 'panel', style: { width: 'min(560px, 100%)' } },
      el('h2', {}, '⚡ ไฟต์ด่วน'),
      el('div', { class: 'field' }, el('label', {}, 'นักสู้ของคุณ'), sel([['random', '🎲 สุ่มนักสู้ (เลือกสไตล์)'], ...mine.map((p, i) => [String(i), `${p.name} (${STYLES[p.style].name})`])], q.me, (v) => (q.me = v))),
      q.me === 'random' ? el('div', { class: 'field' }, el('label', {}, 'สไตล์ของคุณ'), sel(STYLE_KEYS.map((k) => [k, STYLES[k].name]), q.meStyle, (v) => (q.meStyle = v))) : null,
      el('div', { class: 'field' }, el('label', {}, 'รุ่นน้ำหนัก'), sel(WEIGHT_CLASSES.map((w) => [w.id, w.name]), q.wc, (v) => (q.wc = v))),
      el('div', { class: 'field' }, el('label', {}, 'สไตล์คู่ชก'), sel(STYLE_KEYS.map((k) => [k, STYLES[k].name]), q.opStyle, (v) => (q.opStyle = v))),
      el('div', { class: 'field' }, el('label', {}, 'ระดับคู่ชก'), sel([[0, 'สมัครเล่น'], [1, 'โปรภูมิภาค'], [2, 'ระดับท็อป'], [3, 'ระดับแชมป์โลก']], q.opLevel, (v) => (q.opLevel = Number(v)))),
      el('div', { class: 'field' }, el('label', {}, 'จำนวนยก'), sel([[1, '1 ยก'], [3, '3 ยก'], [5, '5 ยก (ชิงแชมป์)']], q.rounds, (v) => (q.rounds = Number(v)))),
      el('div', { class: 'field' }, el('label', {}, 'โหมด'), sel([['play', 'คุณ vs AI'], ['watch', 'AI vs AI (ดูอย่างเดียว)']], q.mode, (v) => (q.mode = v))),
      el('div', { class: 'row' }, el('button', { class: 'btn primary', onclick: () => this.startQuick() }, '🥊 เริ่มไฟต์'), el('button', { class: 'btn', onclick: () => this.go('title') }, '← กลับ'))));
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
    const opp = makeNPC(Math.floor(rng() * 1e9), { tier: q.opLevel ?? 2, wc: q.wc || 'light', style: q.opStyle || 'muaythai' });
    this.stopBackground();
    this.close();
    const sc = this.app.startFight({ red: me, blue: opp, playerSide: 'red', playerAI: q.mode === 'watch', rounds: q.rounds || 3, roundLen: 300, aiLevel: this.app.save.settings.difficulty, sandbox, brand: 'APEX' });
    sc.quick = true;
    if (sandbox) { this.sandboxPanel(); }
  }

  // ---------- sandbox ----------
  scr_sandboxSetup() {
    this.qf = this.qf || { me: 'random', meStyle: 'boxing', opStyle: 'muaythai', opLevel: 2, rounds: 1, mode: 'play', wc: 'light' };
    const node = this.scr_quick();
    node.querySelector('h2').textContent = '🧪 แซนด์บ็อกซ์ — เลือกนักสู้เริ่มต้น';
    const btn = node.querySelector('.btn.primary');
    btn.textContent = '🧪 เข้าสู่แซนด์บ็อกซ์';
    btn.onclick = () => this.startQuick(true);
    return node;
  }

  sandboxPanel() {
    const sc = this.app.scene; if (!sc) return;
    sc.clock = 1e9; sc.roundLen = 1e9;
    this.app.sandboxTimeScale = 1;
    const settings = sc.sbs = { invincible: false, infStam: false, oneHit: false };
    const panel = el('div', { class: 'sandbox-panel' });
    const F = () => [sc.red, sc.blue];
    const btn = (t, fn) => el('button', { class: 'btn small', onclick: () => { fn(); } }, t);
    const pick = () => (this.sbTarget === 'red' ? sc.red : sc.blue);
    const injure = (fn) => () => { const f = pick(); fn(f, f.health); f.fx.setDamage(f.damageView()); f.model.setInjuryVisuals(f.health); };
    const ctlSel = el('select', { onchange: (e) => {
      this.setControl(sc, e.target.value);
    } }, ...[['red', 'คุณคุมฝั่งแดง / AI ฝั่งน้ำเงิน'], ['blue', 'คุณคุมฝั่งน้ำเงิน / AI ฝั่งแดง'], ['aiai', 'AI vs AI'], ['dummy', 'คุมแดง / น้ำเงินเป็นหุ่นยืนเฉย'], ['dummyai', 'AI แดง / น้ำเงินเป็นหุ่นยืนเฉย']].map(([v, t]) => el('option', { value: v }, t)));
    this.sbTarget = 'blue';
    const tgtSel = el('select', { onchange: (e) => { this.sbTarget = e.target.value; } }, el('option', { value: 'blue' }, 'เป้าหมาย: ฝั่งน้ำเงิน'), el('option', { value: 'red' }, 'เป้าหมาย: ฝั่งแดง'));
    const ts = el('input', { type: 'range', min: 0.05, max: 1.5, step: 0.05, value: 1, oninput: (e) => { this.app.sandboxTimeScale = Number(e.target.value); tsv.textContent = Number(e.target.value).toFixed(2) + 'x'; } });
    const tsv = el('b', {}, '1.00x');
    const tog = (k, t) => el('label', { style: { display: 'block' } }, el('input', { type: 'checkbox', onchange: (e) => { settings[k] = e.target.checked; } }), ' ' + t);
    panel.append(
      el('h3', {}, '🧪 แซนด์บ็อกซ์'),
      ctlSel,
      el('div', { class: 'field', style: { marginTop: '6px' } }, el('label', {}, 'ความเร็วเวลา ', tsv), ts),
      el('div', { class: 'row' }, btn('📷 กล้องอิสระ/ถ่ายทอด', () => { const c = this.app.world.cam; c.mode = c.mode === 'orbit' ? 'broadcast' : 'orbit'; c.orbitDist = 4; }), btn('🔄 รีเซ็ตตำแหน่ง', () => { if (sc.grapple.link) sc.grapple.release(sc.red); sc.red.placeAt(-1.4, 0, Math.PI / 2); sc.blue.placeAt(1.4, 0, -Math.PI / 2); for (const f of F()) { f.state = 'stand'; f.ko = false; } sc.result = null; sc.phase = 'fight'; })),
      el('h3', {}, 'ร่างกาย'),
      el('div', { class: 'row' }, btn('💚 รักษาทั้งคู่', () => { for (const f of F()) { const nf = new (f.health.constructor)(f.attrs, {}); f.health = nf; f.fx.clearAll(); f.fx.setDamage(f.damageView()); f.model.setInjuryVisuals(nf); f.model.gloveBlood = 0; f.ko = false; } }), btn('🧽 ล้างเลือดพื้น', () => { this.app.world.cleanMat(); this.app.blood.clear(); for (const f of F()) f.fx.wipe(1); })),
      tog('invincible', 'อมตะ (ไม่น็อก ไม่โดนหยุด)'), tog('infStam', 'สตามินาไม่จำกัด'), tog('oneHit', 'หมัดเดียวจอด (น็อกง่ายมาก)'),
      el('h3', {}, 'ทำให้บาดเจ็บ'), tgtSel,
      el('div', { class: 'row' },
        btn('🩸 คิ้วซ้ายแตก', injure((f, h) => h.addCut(0.7, 0.355, 'browL', 1.3))), btn('🩸 คิ้วขวาแตก', injure((f, h) => h.addCut(0.3, 0.355, 'browR', 1.3))),
        btn('🩸 หน้าผากแตก (ศอก)', injure((f, h) => h.addCut(0.5, 0.18, 'forehead', 1.6))), btn('👃 จมูกหัก', injure((f, h) => { h.noseBroken = true; h.noseDeviation = 0.35; h.noseBleed = 0.9; h.nose = 1.2; })),
        btn('👁 ตาบวมปิด', injure((f, h) => { h.swell.eyeL = 1.1; })), btn('🦵 ขาตาย (Dead leg)', injure((f, h) => { h.legs[f.lead] = 100; h.deadLeg[f.lead] = true; })),
        btn('😵 มึนงง (Rocked)', injure((f, h) => { h.rocked = 6; h.consc = 0.4; })), btn('💥 น็อกเลย', injure((f, h) => { f.ko = true; h.consc = 0; f.fall({ kind: 'ko', dir: f.rig.F.dir(f.rig.root.clone().set(0, 0, -1), f.rig.root.clone()), power: 1.2, fencing: rng() < 0.6 }); })),
        btn('🫸 ผลักล้ม', injure((f) => f.fall({ kind: 'trip', power: 0.8 }))), btn('🫃 หมัดตับ (ทรุด)', injure((f, h) => { h.liverDelay = 0.4; }))),
      el('h3', {}, 'นักสู้ใหม่'),
      el('div', { class: 'row' }, btn('🎲 สุ่มคู่ชกใหม่', () => { this.qf.opStyle = STYLE_KEYS[Math.floor(rng() * STYLE_KEYS.length)]; this.startQuick(true); })),
      el('button', { class: 'btn small ghost', style: { marginTop: '8px' }, onclick: () => { panel.remove(); this.app.sandboxTimeScale = 1; this.app.endScene(); this.go('title'); this.backgroundFight(); } }, '← ออกจากแซนด์บ็อกซ์'),
    );
    this.app.uiRoot.appendChild(panel);
    this.sbPanel = panel;
    sc.onEndHook = () => true; // sandbox never auto-ends
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
    return el('div', { class: 'screen dim' }, el('div', { class: 'panel', style: { width: 'min(420px, 100%)' } },
      el('h2', {}, '⏸ หยุดชั่วคราว'),
      el('div', { class: 'menu', style: { width: '100%' } },
        el('button', { class: 'btn primary', onclick: () => { sc.paused = false; this.close(); } }, '▶ เล่นต่อ'),
        el('button', { class: 'btn', onclick: () => this.go('help') }, '🎮 ปุ่มควบคุม'),
        el('button', { class: 'btn', onclick: () => { const c = this.app.world.cam; c.mode = c.mode === 'orbit' ? 'broadcast' : 'orbit'; c.orbitDist = 4.5; sc.paused = false; this.close(); } }, '📷 สลับกล้อง (ถ่ายทอด / อิสระ: ลากเมาส์)'),
        el('button', { class: 'btn', onclick: () => { if (!confirm(sc.career ? 'ยอมแพ้ไฟต์นี้? (นับเป็นแพ้ TKO - ถอนตัว)' : 'ออกจากไฟต์?')) return; sc.paused = false; this.close(); if (sc.career) { sc.endFight(sc.blue, 'TKO', 'ถอนตัว (Corner Stoppage)'); } else { this.exitFight(); } } }, sc.career ? '🏳 ยอมแพ้ (โยนผ้า)' : '🚪 ออกไปเมนูหลัก'))));
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
      tick('treatCuts', 'กดแผล + อะดรีนาลีน 1:1000 + วาสลีน (ลดเลือดไหล)'), tick('enswell', 'ประคบ Enswell เย็น (ลดบวมรอบตา)'), tick('water', 'จิบน้ำ + หายใจลึก (ฟื้นสตามินา)'),
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

  exitFight() { this.app.endScene(); this.go('title'); this.backgroundFight(); }

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
