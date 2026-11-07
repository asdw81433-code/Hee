// ===== Character creator: identity, body, hand-drawn face, fighting style & attributes =====
import { el, clamp, makeRng, hashStr } from './util.js';
import { WEIGHT_CLASSES, wcById, STYLES, ATTRS, ATTR_LABEL, COUNTRIES, SKIN_TONES, HAIR_COLORS, HAIR_STYLES, BEARDS, SHORTS_COLORS, NICKNAMES } from './data.js';
import { FACE_W, FACE_H, mkCanvas, paintFace, drawFaceGuides } from './face.js';
import { baseAttrs } from './npc.js';
import { drawHeadThumb } from './hair.js';

const START_POINTS = 25;
const START_MAX = 72;

export function defaultProfile() {
  const seed = Math.floor(Math.random() * 1e9);
  const r = makeRng(seed);
  return {
    id: 'p' + Date.now().toString(36),
    name: 'ธนา ศรีสุข', nick: 'Iron', country: 'TH', age: 21,
    wc: 'light', height: 1.76, walkKg: 74, reachMul: 1.0, stance: 'orthodox', style: 'muaythai',
    look: { skin: SKIN_TONES[3], hairColor: HAIR_COLORS[0], hairStyle: 'buzz', beard: 'stubble', muscle: 0.5, fat: 0.15, shorts: '#b71c1c', shortsTrim: '#f9a825', tattoo: 'sakyant', cauliflower: false, chestHair: false, scar: false, seed, eyeColor: '#3b2414' },
    alloc: {},
    faceData: null,
    record: { w: 0, l: 0, d: 0 },
  };
}

export function computeAttrs(p) {
  const base = baseAttrs(p.style, 40, null);
  const a = {};
  for (const k in base) a[k] = clamp(base[k] + (p.alloc[k] || 0), 15, 99);
  // body build influences physical stats
  a.strength = clamp(a.strength + Math.round((p.look.muscle - 0.5) * 16), 15, 99);
  a.cardio = clamp(a.cardio - Math.round(p.look.fat * 14) + Math.round((0.5 - p.look.muscle) * 4), 15, 99);
  a.punchSpeed = clamp(a.punchSpeed - Math.round(p.look.fat * 8), 15, 99);
  return a;
}

export function loadFaceCanvas(dataURL) {
  return new Promise((res) => {
    const c = mkCanvas(FACE_W, FACE_H);
    if (!dataURL) return res(null);
    const img = new Image();
    img.onload = () => { c.getContext('2d').drawImage(img, 0, 0, FACE_W, FACE_H); res(c); };
    img.onerror = () => res(null);
    img.src = dataURL;
  });
}

export function profileForFight(p, attrs) {
  const wc = wcById(p.wc);
  return {
    id: p.id, name: p.name, nick: p.nick, country: p.country, style: p.style, stance: p.stance,
    height: p.height, weightKg: wc.kg * 1.06, reachMul: p.reachMul, look: p.look, attrs: attrs || p.attrs || computeAttrs(p),
    record: p.record, careerHealth: p.careerHealth,
  };
}

export class Creator {
  constructor(ui, onDone, onCancel, opts = {}) {
    this.ui = ui; this.app = ui.app;
    this.p = opts.profile ? JSON.parse(JSON.stringify(opts.profile)) : defaultProfile();
    this.p.alloc = this.p.alloc || {};
    this.onDone = onDone; this.onCancel = onCancel;
    this.title = opts.title || 'สร้างนักสู้ของคุณ';
    this.tab = 'id';
    this.face = mkCanvas(FACE_W, FACE_H);
    this.fctx = this.face.getContext('2d', { willReadFrequently: true });
    this.faceEdited = !!this.p.faceData;
    this.undo = [];
    this.tool = { kind: 'brush', size: 6, color: '#3a2418', alpha: 0.85, sym: false, guides: true };
    if (this.p.faceData) loadFaceCanvas(this.p.faceData).then((c) => { if (c) { this.fctx.drawImage(c, 0, 0); this.refreshPreview(); } });
    else this.autoFace();
    this.face.style.touchAction = 'none';
    this.setupCanvas();
  }

  setupCanvas() {
    const disp = this.face;
    let drawing = false, last = null;
    const pos = (e) => { const r = disp.getBoundingClientRect(); return [(e.clientX - r.left) / r.width * FACE_W, (e.clientY - r.top) / r.height * FACE_H]; };
    const stroke = (a, bpt) => {
      const c = this.fctx, t = this.tool;
      const doLine = (x0, y0, x1, y1) => {
        if (t.kind === 'blur') {
          c.save(); c.beginPath(); c.arc(x1, y1, t.size * 1.5, 0, 6.28); c.clip(); c.filter = 'blur(2px)'; c.drawImage(this.face, 0, 0); c.restore(); return;
        }
        c.save(); c.globalAlpha = t.kind === 'eraser' ? 1 : t.alpha; c.strokeStyle = t.kind === 'eraser' ? this.p.look.skin : t.color; c.lineWidth = t.size; c.lineCap = 'round'; c.lineJoin = 'round';
        c.beginPath(); c.moveTo(x0, y0); c.lineTo(x1, y1); c.stroke(); c.restore();
      };
      doLine(a[0], a[1], bpt[0], bpt[1]);
      if (this.tool.sym) doLine(FACE_W - a[0], a[1], FACE_W - bpt[0], bpt[1]);
    };
    disp.addEventListener('pointerdown', (e) => {
      const p = pos(e);
      if (this.tool.kind === 'pick') {
        const d = this.fctx.getImageData(Math.floor(p[0]), Math.floor(p[1]), 1, 1).data;
        this.tool.color = '#' + [d[0], d[1], d[2]].map((x) => x.toString(16).padStart(2, '0')).join('');
        this.tool.kind = 'brush'; this.ui.refresh(); return;
      }
      this.pushUndo();
      drawing = true; last = p; disp.setPointerCapture(e.pointerId); stroke(p, [p[0] + 0.01, p[1]]);
      this.faceEdited = true;
    });
    disp.addEventListener('pointermove', (e) => { if (!drawing) return; const p = pos(e); stroke(last, p); last = p; });
    const end = () => { if (drawing) { drawing = false; this.refreshPreview(); } };
    disp.addEventListener('pointerup', end); disp.addEventListener('pointercancel', end);
  }

  autoFace(newSeed) {
    if (newSeed) this.p.look.seed = Math.floor(Math.random() * 1e9);
    paintFace(this.fctx, this.p.look, this.p.look.seed);
    this.faceEdited = false;
  }

  render() {
    const root = el('div', { class: 'screen' });
    const wrap = el('div', { class: 'creator' });
    const left = el('div', { class: 'left panel' + (this.peek ? ' peek' : '') });
    const right = el('div', { class: 'right' });
    left.append(el('h2', {}, this.title));
    const tabs = el('div', { class: 'tabs' });
    for (const [k, t] of [['id', '🪪 ตัวตน'], ['body', '💪 ร่างกาย'], ['face', '🎨 วาดหน้า'], ['style', '🥋 สไตล์']]) {
      tabs.append(el('div', { class: 'tab' + (this.tab === k ? ' sel' : ''), onclick: () => { this.tab = k; this.ui.refresh(); } }, t));
    }
    left.append(tabs);
    const body = el('div', {});
    if (this.tab === 'id') this.tabId(body);
    if (this.tab === 'body') this.tabBody(body);
    if (this.tab === 'face') this.tabFace(body);
    if (this.tab === 'style') this.tabStyle(body);
    left.append(body);
    const nav = el('div', { class: 'row', style: { marginTop: '14px' } },
      el('button', { class: 'btn ghost', onclick: () => this.onCancel() }, '← ยกเลิก'),
      el('div', { class: 'grow' }),
      el('button', { class: 'btn small', title: 'ซ่อนแผงเพื่อดูตัวละคร 3D', onclick: () => { this.peek = !this.peek; this.ui.refresh(); } }, this.peek ? '📋 แสดงแผง' : '👁 ดูตัว'),
      this.tab !== 'style' ? el('button', { class: 'btn', onclick: () => { this.tab = { id: 'body', body: 'face', face: 'style' }[this.tab]; this.ui.refresh(); } }, 'ถัดไป →')
        : el('button', { class: 'btn primary', onclick: () => this.finish() }, '✔ ยืนยันนักสู้'));
    left.append(nav);
    // right side: info card over 3D preview
    const info = el('div', { class: 'panel', style: { position: 'absolute', right: '16px', bottom: '16px', width: '300px', fontSize: '13px' } });
    const a = computeAttrs(this.p);
    const ovr = Math.round(Object.values(a).reduce((s, v) => s + v, 0) / Object.values(a).length);
    const wc = wcById(this.p.wc);
    info.append(el('div', { style: { fontWeight: 800, fontSize: '18px' } }, this.p.name, this.p.nick ? el('span', { class: 'muted' }, ` "${this.p.nick}"`) : null),
      el('div', { class: 'muted' }, `${wc.name} · ${(this.p.height * 100).toFixed(0)} ซม. · ${STYLES[this.p.style].name}`),
      el('div', {}, `ค่าพลังรวม (OVR): `, el('b', {}, String(ovr)), el('span', { class: 'muted' }, ' — ระดับสมัครเล่น')),
      el('div', { class: 'row', style: { marginTop: '6px' } },
        el('button', { class: 'btn small', onclick: () => { this.app.preview.zoom = this.app.preview.zoom < 0.6 ? 1 : 0.45; } }, '🔍 ซูมหน้า/ตัว'),
        el('button', { class: 'btn small', onclick: () => { this.app.preview.shadowbox = !this.app.preview.shadowbox; } }, '🥊 ชกลม เปิด/ปิด')));
    wrap.append(left, right);
    root.append(wrap, info);
    return root;
  }

  field(label, input) { return el('div', { class: 'field' }, el('label', {}, label), input); }
  set(path, v, preview = true) {
    const ks = path.split('.'); let o = this.p;
    for (let i = 0; i < ks.length - 1; i++) o = o[ks[i]];
    o[ks[ks.length - 1]] = v;
    if (preview) this.refreshPreview();
  }

  tabId(b) {
    b.append(
      this.field('ชื่อ-นามสกุล', el('input', { type: 'text', value: this.p.name, maxlength: 28, oninput: (e) => { this.p.name = e.target.value || 'ไม่ระบุชื่อ'; } })),
      this.field('ฉายา (ไม่บังคับ)', el('div', { class: 'row' }, el('input', { type: 'text', value: this.p.nick, maxlength: 20, class: 'grow', style: { width: 'auto', flex: 1 }, oninput: (e) => { this.p.nick = e.target.value; } }),
        el('button', { class: 'btn small', onclick: () => { this.p.nick = NICKNAMES[Math.floor(Math.random() * NICKNAMES.length)]; this.ui.refresh(); } }, '🎲 สุ่ม'))),
      this.field('สัญชาติ', el('select', { onchange: (e) => { this.p.country = e.target.value; } }, ...COUNTRIES.map(([c, n]) => el('option', { value: c, selected: c === this.p.country ? 'selected' : null }, n)))),
      this.field('อายุเริ่มต้น', el('select', { onchange: (e) => { this.p.age = Number(e.target.value); } }, ...[18, 19, 20, 21, 22, 23, 24, 25, 26, 28, 30].map((n) => el('option', { value: n, selected: n === this.p.age ? 'selected' : null }, `${n} ปี${n <= 21 ? ' (พัฒนาเร็ว)' : n >= 28 ? ' (ประสบการณ์ แต่พัฒนาช้า)' : ''}`)))),
      this.field('การยืน (Stance)', this.pics([['orthodox', '🦶⬅️', 'ซ้ายนำ (Orthodox)'], ['southpaw', '➡️🦶', 'ขวานำ (Southpaw)']], this.p.stance, (v) => this.set('stance', v))),
      el('p', { class: 'muted small' }, 'อายุมีผลต่อการพัฒนา: นักสู้มีช่วงพีคราว 27-32 ปี หลังจากนั้นความเร็ว คาร์ดิโอ และความทนจะค่อยๆ ลดลง'),
    );
  }

  chips(opts, cur, cb) {
    const c = el('div', { class: 'chips' });
    for (const [v, t] of opts) c.append(el('div', { class: 'chip' + (v === cur ? ' sel' : ''), onclick: () => { cb(v); this.ui.refresh(); } }, t));
    return c;
  }
  pics(opts, cur, cb) {
    return el('div', { class: 'iconbar' }, ...opts.map(([v, pic, t]) => el('button', { class: 'iconbtn' + (v === cur ? ' sel' : ''), onclick: () => { cb(v); this.ui.refresh(); } }, el('span', { class: 'pic' }, pic), t)));
  }
  headThumbs(list, kind) {
    const wrap = el('div', { class: 'thumbs' });
    const look = this.p.look;
    for (const [id, name] of list) {
      const c = mkCanvas(64, 64);
      drawHeadThumb(c.getContext('2d'), 64, look, kind === 'hair' ? id : look.hairStyle, kind === 'beard' ? id : look.beard);
      const cur = kind === 'hair' ? look.hairStyle : look.beard;
      wrap.append(el('div', { class: 'thumb' + (cur === id ? ' sel' : ''), title: name, onclick: () => {
        if (kind === 'hair') look.hairStyle = id; else look.beard = id;
        if (!this.faceEdited) this.autoFace();
        this.refreshPreview(); this.ui.refresh();
      } }, c, name));
    }
    return wrap;
  }
  swatches(list, cur, cb) {
    const c = el('div', { class: 'swatches' });
    for (const col of list) c.append(el('div', { class: 'swatch' + (col === cur ? ' sel' : ''), style: { background: col }, onclick: () => { cb(col); this.ui.refresh(); } }));
    return c;
  }
  slider(label, min, max, step, val, cb, fmt = (v) => v) {
    const out = el('span', { class: 'muted' }, ' ' + fmt(val));
    return this.field(el('span', {}, label, out), el('input', { type: 'range', min, max, step, value: val, oninput: (e) => { const v = Number(e.target.value); out.textContent = ' ' + fmt(v); cb(v); }, onchange: () => this.refreshPreview() }));
  }

  tabBody(b) {
    const wc = wcById(this.p.wc);
    b.append(
      this.field('รุ่นน้ำหนัก (ต้องลดน้ำหนักให้ได้ตามลิมิตก่อนชั่งทุกไฟต์)', el('select', { onchange: (e) => { this.p.wc = e.target.value; const w = wcById(this.p.wc); this.p.height = w.h; this.p.walkKg = Math.round(w.kg * 1.05); this.p.look.fat = w.id === 'heavy' ? 0.35 : 0.15; this.refreshPreview(); this.ui.refresh(); } },
        ...WEIGHT_CLASSES.map((w) => el('option', { value: w.id, selected: w.id === this.p.wc ? 'selected' : null }, `${w.name} — ${w.lb} ปอนด์ (${w.kg.toFixed(1)} กก.)`)))),
      this.slider('ส่วนสูง', Math.round((wc.h - 0.12) * 100), Math.round((wc.h + 0.12) * 100), 1, Math.round(this.p.height * 100), (v) => { this.p.height = v / 100; }, (v) => `${v} ซม.`),
      this.slider('ช่วงแขน (Reach)', 92, 108, 1, Math.round(this.p.reachMul * 100), (v) => { this.p.reachMul = v / 100; }, (v) => `${Math.round(this.p.height * 100 * v / 100)} ซม.`),
      this.slider('น้ำหนักตัวปกติ (Walk-around)', Math.round(wc.kg), Math.round(wc.kg * 1.2), 1, this.p.walkKg, (v) => { this.p.walkKg = v; }, (v) => `${v} กก. (ต้องลด ${Math.max(0, ((v - wc.kg) / v) * 100).toFixed(1)}%)`),
      this.slider('กล้ามเนื้อ', 0, 100, 1, Math.round(this.p.look.muscle * 100), (v) => { this.p.look.muscle = v / 100; }, (v) => `${v}%`),
      this.slider('ไขมัน', 0, 70, 1, Math.round(this.p.look.fat * 100), (v) => { this.p.look.fat = v / 100; }, (v) => `${v}%`),
      el('h3', {}, 'สีผิว'), this.swatches(SKIN_TONES, this.p.look.skin, (c) => { this.p.look.skin = c; if (!this.faceEdited) this.autoFace(); this.refreshPreview(); }),
      el('h3', {}, '💇 ทรงผม'), this.headThumbs(HAIR_STYLES, 'hair'),
      el('h3', {}, 'สีผม'), this.swatches(HAIR_COLORS, this.p.look.hairColor, (c) => { this.p.look.hairColor = c; if (!this.faceEdited) this.autoFace(); this.refreshPreview(); }),
      el('h3', {}, '🧔 หนวดเครา'), this.headThumbs(BEARDS, 'beard'),
      el('h3', {}, 'กางเกง'), this.swatches(SHORTS_COLORS, this.p.look.shorts, (c) => this.set('look.shorts', c)),
      el('h3', {}, 'ขอบกางเกง'), this.swatches(SHORTS_COLORS, this.p.look.shortsTrim, (c) => this.set('look.shortsTrim', c)),
      el('h3', {}, '🖋️ รอยสัก'), this.pics([['none', '🚫', 'ไม่มี'], ['sakyant', '🕉️', 'สักยันต์'], ['tribal', '〰️', 'ลายชนเผ่า'], ['script', '✍️', 'ตัวอักษร']], this.p.look.tattoo, (v) => this.set('look.tattoo', v)),
      el('h3', {}, '✨ รายละเอียด'), el('div', { class: 'iconbar' }, ...[['cauliflower', '👂', 'หูกะหล่ำ'], ['chestHair', '🐻', 'ขนหน้าอก'], ['scar', '🩹', 'แผลเป็น']].map(([v, pic, t]) => el('button', { class: 'iconbtn' + (this.p.look[v] ? ' sel' : ''), onclick: () => { this.p.look[v] = !this.p.look[v]; if (v === 'scar' && !this.faceEdited) this.autoFace(); this.refreshPreview(); this.ui.refresh(); } }, el('span', { class: 'pic' }, pic), t))),
    );
  }

  tabFace(b) {
    const wrapC = el('div', { class: 'face-canvas-wrap' });
    const disp = this.face; // draw directly
    const guide = mkCanvas(FACE_W, FACE_H);
    if (this.tool.guides) drawFaceGuides(guide.getContext('2d'));
    guide.style.pointerEvents = 'none';
    wrapC.append(disp, guide);
    const t = this.tool;
    const tools = el('div', { class: 'tools' },
      el('div', { class: 'chips' }, ...[['brush', '🖌 พู่กัน'], ['eraser', '🧽 ลบ (สีผิว)'], ['blur', '💧 เบลอ/เกลี่ย'], ['pick', '💉 ดูดสี']].map(([k, n]) => el('div', { class: 'chip' + (t.kind === k ? ' sel' : ''), onclick: () => { t.kind = k; this.ui.refresh(); } }, n))),
      this.slider('ขนาดพู่กัน', 1, 40, 1, t.size, (v) => { t.size = v; }),
      this.slider('ความทึบ', 5, 100, 1, Math.round(t.alpha * 100), (v) => { t.alpha = v / 100; }, (v) => `${v}%`),
      el('div', { class: 'row' }, el('label', {}, 'สี'), el('input', { type: 'color', value: t.color, oninput: (e) => { t.color = e.target.value; } })),
      this.swatches(['#1a0f0a', '#3a2418', '#5c3a26', '#8a5a3c', '#e9e2d6', '#ffffff', '#3b5a7a', '#4f6b3a', '#9a3c3c', '#c06060', '#d8a47f', this.p.look.skin], t.color, (c) => { t.color = c; t.kind = 'brush'; }),
      el('div', { class: 'chips' },
        el('div', { class: 'chip' + (t.sym ? ' sel' : ''), onclick: () => { t.sym = !t.sym; this.ui.refresh(); } }, '⇋ สมมาตร'),
        el('div', { class: 'chip' + (t.guides ? ' sel' : ''), onclick: () => { t.guides = !t.guides; this.ui.refresh(); } }, '⌗ เส้นนำ')),
      el('button', { class: 'btn small', onclick: () => this.doUndo() }, '↶ ย้อนกลับ'),
      el('button', { class: 'btn small', onclick: () => { this.pushUndo(); this.autoFace(true); this.refreshPreview(); this.ui.refresh(); } }, '🎲 สุ่มใบหน้าสมจริง'),
      el('button', { class: 'btn small', onclick: () => { this.pushUndo(); this.fctx.fillStyle = this.p.look.skin; this.fctx.fillRect(0, 0, FACE_W, FACE_H); this.faceEdited = true; this.refreshPreview(); } }, '⬜ หน้าเปล่า (วาดเองทั้งหมด)'),
      el('label', { class: 'btn small', style: { display: 'block' } }, '📷 นำเข้ารูปถ่าย/รูปวาด', el('input', { type: 'file', accept: 'image/*', style: { display: 'none' }, onchange: (e) => this.importImage(e.target.files[0]) })),
    );
    b.append(el('p', { class: 'muted small' }, 'วาดหน้าตัวละครลงบนหัวเหลี่ยม เส้นนำช่วยวางตำแหน่ง คิ้ว/ตา/จมูก/ปาก ให้ตรงกับจุดที่ระบบบาดแผลใช้ (แผลแตกเหนือคิ้ว ตาบวม จมูกหัก จะขึ้นตรงตำแหน่งจริง)'),
      el('div', { class: 'face-editor' }, wrapC, tools));
  }

  importImage(file) {
    if (!file) return;
    const img = new Image();
    img.onload = () => {
      this.pushUndo();
      const s = Math.max(FACE_W / img.width, FACE_H / img.height);
      const w = img.width * s, h = img.height * s;
      this.fctx.drawImage(img, (FACE_W - w) / 2, (FACE_H - h) / 2, w, h);
      this.faceEdited = true; this.refreshPreview();
      URL.revokeObjectURL(img.src);
    };
    img.src = URL.createObjectURL(file);
  }
  pushUndo() { this.undo.push(this.fctx.getImageData(0, 0, FACE_W, FACE_H)); if (this.undo.length > 25) this.undo.shift(); }
  doUndo() { const d = this.undo.pop(); if (d) { this.fctx.putImageData(d, 0, 0); this.refreshPreview(); } }

  tabStyle(b) {
    const used = Object.values(this.p.alloc).reduce((s, v) => s + v, 0);
    const left = START_POINTS - used;
    b.append(el('h3', {}, 'พื้นฐานการต่อสู้'));
    const sc = el('div', { class: 'tiles', style: { gridTemplateColumns: 'repeat(auto-fill, minmax(118px, 1fr))' } });
    const pic = { boxing: '🥊', muaythai: '🐘', wrestling: '🤼', bjj: '🐍', kickboxing: '🦵', judo: '🥋', sambo: '🐻', brawler: '👊' };
    for (const k in STYLES) {
      sc.append(el('button', { class: 'tile small' + (this.p.style === k ? ' sel' : ''), title: STYLES[k].desc, onclick: () => { this.p.style = k; this.p.alloc = {}; if (k === 'wrestling' || k === 'bjj' || k === 'judo') this.p.look.cauliflower = true; this.refreshPreview(); this.ui.refresh(); } },
        el('span', { class: 'pic' }, pic[k]), el('span', {}, STYLES[k].name.split(' (')[0])));
    }
    b.append(el('p', { class: 'muted small' }, STYLES[this.p.style].desc));
    b.append(sc);
    b.append(el('h3', {}, `แต้มพัฒนาเริ่มต้น: เหลือ ${left} แต้ม`), el('p', { class: 'muted small' }, 'นักสู้เริ่มที่ระดับสมัครเล่น พัฒนาต่อได้ด้วยการซ้อมในโหมดอาชีพ'));
    const a = computeAttrs(this.p);
    for (const [grp, list] of Object.entries(ATTRS)) {
      b.append(el('div', { class: 'muted small', style: { marginTop: '8px' } }, { striking: 'ยืนสู้', grappling: 'ปล้ำ/พื้น', physical: 'ร่างกาย', mental: 'จิตใจ' }[grp]));
      for (const [k, name] of list) {
        const v = a[k];
        b.append(el('div', { class: 'attr-row' }, el('span', {}, name), el('span', { class: 'val' }, String(v)),
          el('button', { class: 'btn small', disabled: !(this.p.alloc[k] > 0) ? 'disabled' : null, onclick: () => { this.p.alloc[k] = (this.p.alloc[k] || 0) - 1; this.ui.refresh(); } }, '−'),
          el('button', { class: 'btn small', disabled: left <= 0 || v >= START_MAX ? 'disabled' : null, onclick: () => { this.p.alloc[k] = (this.p.alloc[k] || 0) + 1; this.ui.refresh(); } }, '+'),
          el('div', { class: 'attr-bar' }, el('div', { style: { width: v + '%' } }))));
      }
    }
  }

  refreshPreview() {
    clearTimeout(this._pt);
    this._pt = setTimeout(() => {
      const c = mkCanvas(FACE_W, FACE_H); c.getContext('2d').drawImage(this.face, 0, 0);
      this.app.preview.show(profileForFight(this.p, computeAttrs(this.p)), c);
    }, 120);
  }

  finish() {
    this.p.faceData = this.face.toDataURL('image/png');
    this.p.attrs = computeAttrs(this.p);
    this.p.weightKg = wcById(this.p.wc).kg * 1.06;
    this.onDone(this.p);
  }
}
