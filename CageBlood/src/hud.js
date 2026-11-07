// ===== In-fight HUD (DOM overlay) =====
import { el, fmtTime, clamp } from './util.js';
import { POS_NAMES } from './grapple.js';

export class HUD {
  constructor(root) {
    this.root = el('div', { class: 'hud hidden' });
    root.appendChild(this.root);
    this.top = el('div', { class: 'hud-top' });
    this.redBox = el('div', { class: 'hud-fighter red' });
    this.blueBox = el('div', { class: 'hud-fighter blue' });
    this.clockBox = el('div', { class: 'hud-clock' });
    this.top.append(this.redBox, this.clockBox, this.blueBox);
    this.msg = el('div', { class: 'hud-msg' });
    this.feedBox = el('div', { class: 'hud-feed' });
    this.posBox = el('div', { class: 'hud-pos hidden' });
    this.subBox = el('div', { class: 'hud-sub hidden' }, el('div', { class: 'sub-name' }), el('div', { class: 'sub-bar' }, el('div', { class: 'sub-fill' })), el('div', { class: 'sub-hint' }));
    this.visL = el('div', { class: 'vis vis-l' }); this.visR = el('div', { class: 'vis vis-r' });
    this.bloodL = el('div', { class: 'vis blood-l' }); this.bloodR = el('div', { class: 'vis blood-r' });
    this.hurtV = el('div', { class: 'vis hurt' });
    this.dmgPanel = el('div', { class: 'hud-dmg hidden' });
    this.hint = el('div', { class: 'hud-hint' }, 'Esc = หยุด/วิธีเล่น · Tab = สภาพร่างกาย');
    this.keysHint = el('div', { class: 'hud-keys hidden' });
    this.tip = el('div', { class: 'hud-tip hidden' });
    this.root.append(this.tip, this.keysHint, this.visL, this.visR, this.bloodL, this.bloodR, this.hurtV, this.top, this.msg, this.feedBox, this.posBox, this.subBox, this.dmgPanel, this.hint);
    this.msgT = 0; this.feeds = [];
    this.showDmg = false;
  }
  show(v) { this.root.classList.toggle('hidden', !v); }

  setupFight(sc) {
    this.show(true);
    this.feedBox.innerHTML = ''; this.feeds = [];
    const mk = (f) => {
      const rec = f.prof.record ? `${f.prof.record.w}-${f.prof.record.l}${f.prof.record.d ? '-' + f.prof.record.d : ''}` : '';
      return [el('div', { class: 'hf-name' }, f.name, f.prof.nick ? el('span', { class: 'nick' }, ` "${f.prof.nick}"`) : null), el('div', { class: 'hf-rec' }, rec + (f === sc.player ? ' · คุณ' : '')),
        el('div', { class: 'barrow' }, el('span', { class: 'bi', title: 'แรง (สตามินา)' }, '⚡'), el('div', { class: 'bar stam' }, el('div', { class: 'fill' }))),
        el('div', { class: 'barrow' }, el('span', { class: 'bi', title: 'สภาพ (ความรู้สึกตัว)' }, '❤️'), el('div', { class: 'bar cond' }, el('div', { class: 'fill' })))];
    };
    this.redBox.innerHTML = ''; this.blueBox.innerHTML = '';
    this.redBox.append(...mk(sc.red)); this.blueBox.append(...mk(sc.blue));
    clearTimeout(this._kh);
    const touch = document.getElementById('ui') && document.getElementById('ui').classList.contains('touchmode');
    if (touch && sc.player && !sc.opts.playerAI && !sc.background) {
      this.keysHint.innerHTML = (sc.settings.controls || 'simple') !== 'pro' ? 'จอยซ้าย = เดิน · <b>ต่อย</b> <b>เตะ</b> <b>ปล้ำ</b> = เกมเลือกท่าให้ตามระยะ · <b>การ์ด</b> กดค้าง · <b>หลบ</b> หลบหมัด/กันปล้ำ' : 'จอยซ้าย = เดิน/วน · ปุ่มขวา = หมัด เตะ การ์ด · <b>ลำตัว/ขา</b> และ <b>เตะหัว</b> คือปุ่มเปิด-ปิด · บนพื้น: ดันจอยขึ้น = ไล่ตำแหน่ง, ลง = ลุก, ซ้าย/ขวา = หนี';
      this.keysHint.classList.remove('hidden');
      this._kh = setTimeout(() => this.keysHint.classList.add('hidden'), 9000);
    } else if (sc.player && !sc.opts.playerAI && !sc.background && (sc.settings.controls || 'simple') !== 'pro') {
      this.keysHint.innerHTML = '<b>W A S D</b> เดิน · <b>J</b> ต่อย · <b>K</b> เตะ · <b>L</b> ปล้ำ/ล็อก · <b>Space</b> การ์ด (ค้าง) · <b>Shift</b> หลบ · <b>Esc</b> หยุด — เกมเลือกท่าให้ตามระยะอัตโนมัติ';
      this.keysHint.classList.remove('hidden');
      this._kh = setTimeout(() => this.keysHint.classList.add('hidden'), 14000);
    } else if (sc.player && !sc.opts.playerAI && !sc.background) {
      this.keysHint.innerHTML = '<b>W/S</b> เข้า-ออก · <b>A/D</b> วน · <b>J K U I N M</b> หมัด · <b>Shift</b>+หมัด = ลำตัว · <b>O/L</b> เตะ (<b>Shift</b> ขา · <b>Q</b> หัว) · <b>P</b> ถีบ · <b>H</b> เข่า · <b>Y</b> ศอก<br><b>Space</b> การ์ด · <b>Z/X</b> หลบ · <b>C</b> ก้ม/สปรอล · <b>E</b> บล็อกเตะ · <b>F</b> คลินช์ · <b>G</b> เทคดาวน์/ล็อก · <b>V</b>+หมัด หลอก · <b>Esc</b> คู่มือเต็ม';
      this.keysHint.classList.remove('hidden');
      this._kh = setTimeout(() => this.keysHint.classList.add('hidden'), 16000);
    } else this.keysHint.classList.add('hidden');
  }

  message(t, dur = 1.5, cls = '') {
    this.msg.textContent = t; this.msg.className = 'hud-msg show ' + cls; this.msgT = dur;
    if (!t) this.msg.className = 'hud-msg';
  }
  feed(html, cls = '') {
    if (window.__testLog) console.log('LOG ' + html.replace(/<[^>]+>/g, ''));
    const e = el('div', { class: 'feed-line ' + cls, html });
    this.feedBox.prepend(e);
    this.feeds.push(e);
    while (this.feedBox.children.length > 6) this.feedBox.lastChild.remove();
    setTimeout(() => e.classList.add('fade'), 7000);
  }
  toggleDamage() { this.showDmg = !this.showDmg; this.dmgPanel.classList.toggle('hidden', !this.showDmg); }

  // what to press right now (simple controls)
  contextTip(sc) {
    const p = sc.player;
    if (!p || sc.opts.playerAI || sc.tutorial || sc.phase !== 'fight') return '';
    const simple = (sc.settings.controls || 'simple') !== 'pro';
    if (!simple) return '';
    const touch = document.getElementById('ui').classList.contains('touchmode');
    const k = (key, btn) => (touch ? `[${btn}]` : `[${key}]`);
    const o = p.opp, L = sc.grapple.link;
    if (L && L.sub && L.sub.def === p) return `🔒 โดนล็อก! รัวกดปุ่มไหนก็ได้เร็วๆ เพื่อแก้`;
    if (L && L.sub && L.sub.att === p) return `🔒 กำลังล็อก! รัวกดปุ่มเพื่อบีบให้ตบ`;
    if (o.state === 'shoot' && p.state !== 'grapple') return `⚠️ เขาพุ่งเข้ามาปล้ำ! กด หลบ ${k('Shift', 'หลบ')}`;
    if (p.rig.mode === 'ragdoll' || p.state === 'down' || p.state === 'getup') return '😵 ล้มอยู่... กำลังลุกขึ้น';
    if (L && L.type === 'ground' && L.bot === p) return `⬇️ อยู่ด้านล่าง: ${k('L', 'ปล้ำ')} หนี/ลุก · ${k('Space', 'การ์ด')} ค้างไว้ปิดหน้า`;
    if (L && L.type === 'ground' && L.top === p) return `⬆️ อยู่ด้านบน: ${k('J', 'ต่อย')} ทุบ · ${k('L', 'ปล้ำ')} ไล่ตำแหน่ง/ล็อก`;
    if (p.health.rocked > 0) return `😵 มึน! ${k('Space', 'การ์ด')} ค้างไว้ แล้วถอยออก`;
    if (o.health.rocked > 0 || o.state === 'down') return `🔥 คู่ชกมึน! รัว ${k('J', 'ต่อย')} เลย`;
    if (p.clinch) return `🤼 คลินช์: ${k('K', 'เตะ')} = เข่า · ${k('J', 'ต่อย')} = ศอก · ${k('L', 'ปล้ำ')} = ทุ่ม`;
    const d = Math.hypot(o.rig.root.x - p.rig.root.x, o.rig.root.z - p.rig.root.z);
    if (d > 2.3) return `👉 เดินเข้าหาคู่ชก ${touch ? '(ดันจอยขึ้น)' : '[W]'}`;
    if (p.health.stamina < 25) return '🥵 แรงใกล้หมด ถอยออกมาหายใจก่อน';
    return '';
  }

  tick(sc, dt) {
    const tip = this.contextTip(sc);
    if (tip !== this._tip) { this._tip = tip; this.tip.textContent = tip; this.tip.classList.toggle('hidden', !tip); }
    if (this.msgT > 0) { this.msgT -= dt; if (this.msgT <= 0) this.msg.className = 'hud-msg'; }
    const bars = (box, f) => {
      const h = f.health;
      box.querySelector('.stam .fill').style.width = `${clamp(h.stamina, 0, 100)}%`;
      box.querySelector('.stam .fill').style.maxWidth = `${h.staminaMax}%`;
      const cond = clamp(h.consc * 100 - h.brain * 0.3, 0, 100);
      const cf = box.querySelector('.cond .fill');
      cf.style.width = `${cond}%`;
      cf.style.background = cond > 60 ? '#d8d8d8' : cond > 35 ? '#e0a020' : '#d02020';
    };
    bars(this.redBox, sc.red); bars(this.blueBox, sc.blue);
    const ph = sc.phase === 'corner' ? 'พักยก' : sc.phase === 'ended' ? 'จบ' : '';
    this.clockBox.innerHTML = sc.tutorial ? '<div class="rnd">TRAINING</div><div class="time">ฝึก</div>' : sc.sandbox ? '<div class="rnd">SANDBOX</div><div class="time">∞</div>' : `<div class="rnd">ROUND ${sc.round}/${sc.rounds}</div><div class="time">${ph || fmtTime(sc.clock)}</div>`;
    // ground position + hints
    const L = sc.grapple.link;
    const p = sc.player;
    if (L && L.type === 'ground') {
      this.posBox.classList.remove('hidden');
      const isTop = p ? L.top === p : null;
      const simple = (sc.settings.controls || 'simple') !== 'pro';
      const touch = document.getElementById('ui').classList.contains('touchmode');
      const hint = p == null ? '' : simple ? (isTop ? (touch ? 'ต่อย = ทุบ · ปล้ำ = ไล่ตำแหน่ง/ล็อก · หลบ = ลุกยืน' : 'J ทุบ · L ไล่ตำแหน่ง/ล็อก · Shift ลุกยืน') : (touch ? 'ปล้ำ = หนี/ลุก · การ์ด = ปิดหน้า · หลบ = หนีตำแหน่ง' : 'L หนี/ลุก · Space ปิดหน้า · Shift หนีตำแหน่ง'))
        : isTop ? 'W ไล่ตำแหน่ง · J/K/U/I ทุบ · Y ศอก · G ล็อก · S ลุกยืน' : 'Space กันหน้า · W สวีป · A/D หนีตำแหน่ง · S ลุกขึ้น · G ล็อกจากล่าง';
      this.posBox.innerHTML = `<b>${POS_NAMES[L.pos]}</b> — ${L.top.name} อยู่บน<br><span>${hint}</span>${L.attempt ? `<div class="att">${L.attempt.f.name}: ${({ advance: 'ไล่ตำแหน่ง', sweep: 'สวีป', escape: 'หนีตำแหน่ง', getup: 'ลุกขึ้น' })[L.attempt.kind]}...</div>` : ''}`;
    } else if (L && L.type === 'clinch') {
      this.posBox.classList.remove('hidden');
      this.posBox.innerHTML = (sc.settings.controls || 'simple') !== 'pro' ? '<b>คลินช์</b><br><span>เตะ = เข่า · ต่อย = ศอก · ปล้ำ = ทุ่ม · ดึงถอยหลังเพื่อออก</span>' : '<b>คลินช์</b><br><span>H เข่า · Y ศอก · J/K หมัดสั้น · G ทุ่ม · W ดันติดกรง · S/F ถอยออก</span>';
    } else this.posBox.classList.add('hidden');
    if (L && L.sub) {
      this.subBox.classList.remove('hidden');
      this.subBox.querySelector('.sub-name').textContent = `${L.sub.att.name} → ${L.sub.info.name}`;
      this.subBox.querySelector('.sub-fill').style.width = `${clamp(L.sub.prog, 0, 1) * 100}%`;
      this.subBox.querySelector('.sub-hint').textContent = p ? (L.sub.att === p ? 'รัว G / Space เพื่อบีบ!' : L.sub.def === p ? 'รัว Space / A / D เพื่อแก้ล็อก!' : '') : '';
    } else this.subBox.classList.add('hidden');
    // player's vision: swollen eyes & blood in eyes
    if (p) {
      const h = p.health;
      // screen left = player's left eye
      const sl = 1 - h.visionL, sr = 1 - h.visionR;
      this.visL.style.opacity = clamp(Math.max(0, (h.swell.eyeL - 0.45) / 0.5), 0, 0.92);
      this.visR.style.opacity = clamp(Math.max(0, (h.swell.eyeR - 0.45) / 0.5), 0, 0.92);
      this.bloodL.style.opacity = clamp(h.bloodInEye[1] * 0.9, 0, 0.85);
      this.bloodR.style.opacity = clamp(h.bloodInEye[0] * 0.9, 0, 0.85);
      this.hurtV.style.opacity = h.rocked > 0 ? clamp(h.rocked / 4, 0.25, 0.75) : clamp((1 - h.consc) * 0.8, 0, 0.6);
      this.root.classList.toggle('rocked', h.rocked > 0);
      if (this.showDmg) this.renderDamage(p);
    } else {
      for (const v of [this.visL, this.visR, this.bloodL, this.bloodR, this.hurtV]) v.style.opacity = 0;
      if (this.showDmg) this.renderDamage(sc.red);
    }
  }

  renderDamage(f) {
    const h = f.health;
    const col = (v) => `hsl(${clamp(120 - v * 120, 0, 120)},70%,45%)`;
    const head = clamp(h.brain / 70 + (1 - h.consc) * 0.5, 0, 1), body = clamp((h.liver + h.ribsL + h.ribsR) / 150, 0, 1);
    const legL = clamp(h.legs[0] / 100, 0, 1), legR = clamp(h.legs[1] / 100, 0, 1), armL = clamp(h.arms[0] / 100, 0, 1), armR = clamp(h.arms[1] / 100, 0, 1);
    const list = h.summary();
    this.dmgPanel.innerHTML = `<div class="dmg-title">${f.name} — สภาพร่างกาย</div>
      <svg viewBox="0 0 100 180" class="bodymap">
        <rect x="38" y="4" width="24" height="26" rx="3" fill="${col(head)}"/>
        <rect x="32" y="34" width="36" height="52" rx="3" fill="${col(body)}"/>
        <rect x="18" y="36" width="12" height="46" rx="3" fill="${col(armR)}"/>
        <rect x="70" y="36" width="12" height="46" rx="3" fill="${col(armL)}"/>
        <rect x="34" y="90" width="14" height="70" rx="3" fill="${col(legR)}"/>
        <rect x="52" y="90" width="14" height="70" rx="3" fill="${col(legL)}"/>
      </svg>
      <div class="dmg-stats">สตามินา ${Math.round(h.stamina)}/${Math.round(h.staminaMax)}<br>เสียเลือด ~${Math.round(h.bloodLoss)} ml<br>ตาซ้าย ${Math.round(h.visionL * 100)}% · ตาขวา ${Math.round(h.visionR * 100)}%<br>การเคลื่อนไหว ${Math.round(h.mobility * 100)}%</div>
      <ul>${list.map((x) => `<li>${x}</li>`).join('') || '<li>ยังไม่มีอาการบาดเจ็บ</li>'}</ul>`;
  }
}
