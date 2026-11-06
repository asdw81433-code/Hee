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
    this.root.append(this.keysHint, this.visL, this.visR, this.bloodL, this.bloodR, this.hurtV, this.top, this.msg, this.feedBox, this.posBox, this.subBox, this.dmgPanel, this.hint);
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
        el('div', { class: 'bar stam' }, el('div', { class: 'fill' })), el('div', { class: 'bar cond' }, el('div', { class: 'fill' }))];
    };
    this.redBox.innerHTML = ''; this.blueBox.innerHTML = '';
    this.redBox.append(...mk(sc.red)); this.blueBox.append(...mk(sc.blue));
    clearTimeout(this._kh);
    if (sc.player && !sc.opts.playerAI && !sc.background) {
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

  tick(sc, dt) {
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
    this.clockBox.innerHTML = sc.sandbox ? '<div class="rnd">SANDBOX</div><div class="time">∞</div>' : `<div class="rnd">ROUND ${sc.round}/${sc.rounds}</div><div class="time">${ph || fmtTime(sc.clock)}</div>`;
    // ground position + hints
    const L = sc.grapple.link;
    const p = sc.player;
    if (L && L.type === 'ground') {
      this.posBox.classList.remove('hidden');
      const isTop = p ? L.top === p : null;
      const hint = p == null ? '' : isTop ? 'W ไล่ตำแหน่ง · J/K/U/I ทุบ · Y ศอก · G ล็อก · S ลุกยืน' : 'Space กันหน้า · W สวีป · A/D หนีตำแหน่ง · S ลุกขึ้น · G ล็อกจากล่าง';
      this.posBox.innerHTML = `<b>${POS_NAMES[L.pos]}</b> — ${L.top.name} อยู่บน<br><span>${hint}</span>${L.attempt ? `<div class="att">${L.attempt.f.name}: ${({ advance: 'ไล่ตำแหน่ง', sweep: 'สวีป', escape: 'หนีตำแหน่ง', getup: 'ลุกขึ้น' })[L.attempt.kind]}...</div>` : ''}`;
    } else if (L && L.type === 'clinch') {
      this.posBox.classList.remove('hidden');
      this.posBox.innerHTML = '<b>คลินช์</b><br><span>H เข่า · Y ศอก · J/K หมัดสั้น · G ทุ่ม · W ดันติดกรง · S/F ถอยออก</span>';
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
