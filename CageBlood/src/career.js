// ===== Career simulation =====
// Weekly loop: plan training (fatigue / overtraining / sparring brain damage), money & expenses, aging & decline,
// injuries & medical suspensions, weight cuts, fight offers & contracts, a living NPC roster with rankings,
// promotion ladder (amateur -> regional -> contender series -> major), and story events.
import { makeRng, clamp, rng, money } from './util.js';
import { ALL_ATTRS, ATTR_LABEL, PROMOTIONS, wcById, STYLES } from './data.js';
import { makeNPC } from './npc.js';
import { STORY, storyNPCs } from './story.js';

export const ACTIVITIES = {
  sparHard: { name: 'สปาร์ริ่งหนัก', icon: '🥊', desc: 'พัฒนาเร็วทุกด้าน แต่เสี่ยงบาดเจ็บและสมองกระทบกระเทือนสะสม', fat: 26, attrs: ['punchSpeed', 'accuracy', 'headMove', 'blocking', 'takedown', 'tdDefense', 'fightIQ', 'composure', 'kickSpeed'], gain: 1.0, risk: 0.09, brain: 0.22 },
  sparLight: { name: 'สปาร์เบา (เทคนิค)', icon: '🤝', desc: 'พัฒนาไอคิวและจังหวะ ปลอดภัยกว่า', fat: 12, attrs: ['fightIQ', 'headMove', 'blocking', 'footwork', 'accuracy', 'composure'], gain: 0.6, risk: 0.02, brain: 0.02 },
  striking: { name: 'ล่อเป้า / กระสอบ', icon: '🎯', desc: 'หมัด เตะ ความแม่นยำ', fat: 13, attrs: ['punchPower', 'punchSpeed', 'accuracy', 'kickPower', 'kickSpeed'], gain: 0.85, risk: 0.015 },
  footwork: { name: 'ฟุตเวิร์ก & หลบหลีก', icon: '👣', desc: 'ฟุตเวิร์ก หลบศีรษะ ป้องกัน', fat: 10, attrs: ['footwork', 'headMove', 'blocking'], gain: 0.85, risk: 0.01 },
  wrestling: { name: 'มวยปล้ำ', icon: '🤼', desc: 'เทคดาวน์ กันเทคดาวน์ คุมด้านบน คลินช์', fat: 16, attrs: ['takedown', 'tdDefense', 'topControl', 'clinch', 'strength'], gain: 0.85, risk: 0.03 },
  bjj: { name: 'บราซิลเลียนยิวยิตสู', icon: '🥋', desc: 'จับล็อก แก้ล็อก เกมด้านล่าง', fat: 13, attrs: ['subOffense', 'subDefense', 'bottomGame', 'topControl'], gain: 0.85, risk: 0.025 },
  sc: { name: 'เวทเทรนนิ่ง (S&C)', icon: '🏋️', desc: 'ความแข็งแรง ฟื้นตัว พลังหมัด/เตะ', fat: 15, attrs: ['strength', 'recovery', 'punchPower', 'kickPower'], gain: 0.75, risk: 0.02 },
  cardio: { name: 'คาร์ดิโอ / วิ่ง / ว่ายน้ำ', icon: '🏃', desc: 'ถังน้ำมันใหญ่ขึ้น ช่วยลดน้ำหนัก', fat: 13, attrs: ['cardio', 'recovery'], gain: 1.0, risk: 0.01, kg: -0.3 },
  conditioning: { name: 'ฝึกความทนทาน', icon: '🧱', desc: 'ทนลำตัว ทนขา หัวใจนักสู้ (ไม่ได้ทำให้คางแข็งขึ้น)', fat: 15, attrs: ['bodyTough', 'legTough', 'heart'], gain: 0.75, risk: 0.03 },
  film: { name: 'ดูเทปคู่ชก', icon: '📼', desc: 'ไอคิวการต่อสู้ + วิเคราะห์จุดอ่อนคู่ชกที่จองไว้', fat: 2, attrs: ['fightIQ', 'composure'], gain: 0.5, risk: 0, scout: true },
  diet: { name: 'คุมอาหาร', icon: '🥗', desc: 'ลดน้ำหนักตัวปกติลง ~0.7 กก. ช่วยให้ตัดน้ำหนักง่ายขึ้น', fat: 3, attrs: [], gain: 0, risk: 0, kg: -0.7, morale: -3 },
  rest: { name: 'พักฟื้น / กายภาพบำบัด', icon: '🛌', desc: 'ลดความล้าก้อนใหญ่ แผลหายเร็วขึ้น', fat: -38, attrs: [], gain: 0, risk: 0, heal: 1, morale: 4 },
  media: { name: 'งานสื่อ / โซเชียล', icon: '🎤', desc: 'เพิ่มกระแส (Hype) และชื่อเสียง', fat: 3, attrs: [], gain: 0, risk: 0, hype: 5, fame: 1 },
  work: { name: 'ทำงานพิเศษ', icon: '🧾', desc: 'หาเงินเพิ่ม $350 (เหนื่อย และเสียเวลาซ้อม)', fat: 10, attrs: [], gain: 0, risk: 0.01, cash: 350, morale: -3 },
  family: { name: 'เวลากับครอบครัว', icon: '🏠', desc: 'ขวัญกำลังใจ และความสัมพันธ์', fat: -8, attrs: [], gain: 0, risk: 0, morale: 12, rel: 'family' },
};

export const GYMS = {
  irongate: { name: 'ยิมท่าเรือเหล็ก (ครูเดช)', fee: 0, mul: 1.0, bonus: {}, desc: 'ยิมเก่าโทรมๆ ของครูเดช ครูที่รู้จริง ห่วงสมองลูกศิษย์' },
  apexpi: { name: 'Apex Performance Institute', fee: 900, mul: 1.35, bonus: { sc: 1.3, cardio: 1.2 }, desc: 'ศูนย์ฝึกระดับโลก นักวิทยาศาสตร์การกีฬา ค่าตัวแพง', minTier: 2 },
  atlas: { name: 'Atlas Wrestling Club', fee: 450, mul: 1.15, bonus: { wrestling: 1.5 }, desc: 'โรงงานผลิตนักมวยปล้ำ', minTier: 1 },
  lotus: { name: 'Black Lotus BJJ', fee: 400, mul: 1.15, bonus: { bjj: 1.5 }, desc: 'สายดำเต็มยิม เกมพื้นอันตราย', minTier: 1 },
  siam: { name: 'Siam Thunder Muay Thai', fee: 380, mul: 1.15, bonus: { striking: 1.4, footwork: 1.2 }, desc: 'ค่ายมวยไทยแท้ ซ้อมหนักวันละสองรอบ', minTier: 1 },
};

const RANKED = 15;

export function overall(a) {
  const w = { punchPower: 1.2, punchSpeed: 1.1, accuracy: 1.1, kickPower: 0.8, kickSpeed: 0.7, headMove: 0.9, blocking: 0.8, footwork: 0.8, takedown: 1, tdDefense: 1, clinch: 0.6, topControl: 0.8, bottomGame: 0.6, subOffense: 0.8, subDefense: 0.8, strength: 0.8, cardio: 1.1, recovery: 0.6, chin: 1.1, bodyTough: 0.6, legTough: 0.5, composure: 0.7, fightIQ: 1, heart: 0.6 };
  let s = 0, n = 0;
  for (const k in w) { s += (a[k] ?? 50) * w[k]; n += w[k]; }
  return s / n;
}

export class Career {
  constructor(data) { this.d = data; }

  static create(profile) {
    const d = {
      v: 1, week: 0, startYear: 2026,
      f: { ...profile, record: { w: 0, l: 0, d: 0 }, am: { w: 0, l: 0 }, history: [], age: profile.age || 21, walkKg: profile.walkKg || wcById(profile.wc).kg * 1.1 },
      money: 1500, debt: 40000, fame: 0, hype: 5, morale: 65, fatigue: 10,
      health: { brainDamage: 0, scarL: 0, scarR: 0, noseBreaks: 0, injuries: [], suspension: 0 },
      promo: 'amateur', contract: null, gym: 'irongate', titles: [], regionalChamp: false, champ: false,
      plan: ['striking', 'cardio', 'bjj'], offers: [], booked: null, scout: 0,
      rel: { coach: 55, family: 60, rival: 0, journalist: 0, viktor: 0, may: 70 },
      flags: {}, inbox: [], seenStory: {}, pendingStory: [], earnings: 0, retired: false, rosterSeed: Math.floor(Math.random() * 1e9),
      lastFightWeek: -10, weeksSinceOffer: 0, sponsor: null, stats: { koWins: 0, subWins: 0, decWins: 0, koLoss: 0, bonuses: 0, sigLanded: 0, takedowns: 0 },
    };
    const c = new Career(d);
    c.buildRosters();
    c.msg('ครูเดช', 'ยินดีต้อนรับสู่ยิมท่าเรือเหล็ก วางแผนซ้อมสัปดาห์ละ 3 อย่าง แล้วกด "สัปดาห์ถัดไป" — อย่าลืมพักบ้าง ร่างกายเราไม่ใช่เหล็ก');
    c.queueStory('prologue');
    return c;
  }

  get f() { return this.d.f; }
  get A() { return this.d.f.attrs; }
  get wc() { return wcById(this.f.wc); }
  get tier() { return PROMOTIONS[this.d.promo].tier; }
  get dateStr() {
    const y = this.d.startYear + Math.floor(this.d.week / 52);
    const w = (this.d.week % 52) + 1;
    return `ปี ${y} · สัปดาห์ที่ ${w}`;
  }
  ovr() { return Math.round(overall(this.A)); }
  msg(from, text, important = false) { this.d.inbox.unshift({ week: this.d.week, from, text, read: false, important }); if (this.d.inbox.length > 60) this.d.inbox.pop(); }
  queueStory(id) { if (!this.d.seenStory[id] && !this.d.pendingStory.includes(id)) this.d.pendingStory.push(id); }

  // ---------- rosters ----------
  buildRosters() {
    const d = this.d, wc = this.f.wc;
    d.rosters = {};
    const sizes = { amateur: 14, regional: 16, contender: 10, major: 28 };
    for (const pr of Object.keys(sizes)) {
      const tier = PROMOTIONS[pr].tier;
      const list = [];
      for (let i = 0; i < sizes[pr]; i++) {
        const seed = (d.rosterSeed + tier * 1000 + i * 7919) >>> 0;
        const levelAdd = pr === 'major' ? (sizes[pr] - i) * 0.55 : (sizes[pr] - i) * 0.3;
        const n = makeNPC(seed, { tier, wc, levelAdd });
        list.push({ id: n.id, seed, tier, levelAdd, name: n.name, nick: n.nick, country: n.country, style: n.style, record: n.record, age: n.age, rating: Math.round(overall(n.attrs)), lastFight: -Math.floor(Math.random() * 12), streak: 0 });
      }
      d.rosters[pr] = list;
    }
    // story characters
    for (const s of storyNPCs(wc)) d.rosters[s.promo].push(s);
    this.sortRoster('regional'); this.sortRoster('major');
  }
  npcProfile(n) {
    if (n.fixed) return { ...n.fixed, record: n.record, id: n.id };
    const p = makeNPC(n.seed, { tier: n.tier, wc: this.f.wc, levelAdd: n.levelAdd });
    p.record = n.record; p.name = n.name; p.nick = n.nick; p.age = n.age;
    return p;
  }
  findNPC(id) { for (const pr in this.d.rosters) { const n = this.d.rosters[pr].find((x) => x.id === id); if (n) return [n, pr]; } return [null, null]; }
  score(n) { return n.rating * 0.6 + n.record.w * 2.2 - n.record.l * 2.6 + (n.streak || 0) * 2 + (n.champ ? 100 : 0); }
  sortRoster(pr) { this.d.rosters[pr].sort((a, b) => this.score(b) - this.score(a)); }
  myScore() { const r = this.f.record; return overall(this.A) * 0.6 + r.w * 2.2 - r.l * 2.6 + (this.d.streak || 0) * 2 + (this.d.champ ? 100 : 0); }
  myRank() {
    if (this.d.promo !== 'major') return null;
    if (this.d.champ) return 0;
    const list = this.d.rosters.major;
    const s = this.myScore();
    let r = 1; for (const n of list) { if (n.champ) continue; if (this.score(n) > s) r++; }
    return r <= RANKED ? r : null;
  }
  rankingTable(pr = this.d.promo) {
    const list = this.d.rosters[pr].map((n) => ({ name: n.name, nick: n.nick, rec: n.record, score: this.score(n), champ: !!n.champ, me: false, id: n.id }));
    list.push({ name: this.f.name, nick: this.f.nick, rec: this.f.record, score: this.myScore() + (pr === 'major' && this.d.champ ? 100 : 0), champ: pr === 'major' ? this.d.champ : pr === 'regional' && this.d.regionalChamp, me: pr === this.d.promo, id: 'me' });
    list.sort((a, b) => b.score - a.score);
    return list;
  }

  // NPC world keeps moving: other fighters fight each other
  simWorld() {
    const r = rng;
    for (const pr of ['regional', 'contender', 'major']) {
      const list = this.d.rosters[pr];
      for (const n of list) {
        if (this.d.booked && this.d.booked.oppId === n.id) continue;
        if (this.d.week - n.lastFight > 10 && r() < 0.08) {
          const o = list[Math.floor(r() * list.length)];
          if (o === n || this.d.week - o.lastFight < 8 || (this.d.booked && this.d.booked.oppId === o.id)) continue;
          const pa = 1 / (1 + Math.exp(-(n.rating - o.rating) / 6));
          const [w, l] = r() < pa ? [n, o] : [o, n];
          w.record.w++; l.record.l++; w.streak = Math.max(0, w.streak || 0) + 1; l.streak = Math.min(0, l.streak || 0) - 1;
          w.rating = clamp(w.rating + 0.6, 30, 95); l.rating = clamp(l.rating - 0.3, 30, 95);
          n.lastFight = o.lastFight = this.d.week;
          if (l.champ && pr === 'major') { l.champ = false; w.champ = true; this.msg('ข่าววงการ', `🏆 ${w.name} ล้มแชมป์ ${l.name} คว้าเข็มขัด ${PROMOTIONS.major.short} รุ่น ${this.wc.name}!`); }
        }
      }
      this.sortRoster(pr);
    }
  }

  // ---------- weekly loop ----------
  togglePlan(act) {
    const p = this.d.plan;
    const i = p.indexOf(act);
    if (i >= 0) p.splice(i, 1); else if (p.length < 3) p.push(act); else { p.shift(); p.push(act); }
  }

  // coach-made weekly plan: rest when tired, cut weight before fights, otherwise train the weakest areas
  autoPlan() {
    const d = this.d, f = this.f, A = this.A;
    const cut = Math.max(0, (f.walkKg - this.wc.kg) / f.walkKg);
    if (d.fatigue > 58 || d.health.injuries.some((x) => x.severe)) return ['rest', 'family', cut > 0.05 ? 'diet' : 'film'];
    if (d.booked && d.booked.weeksOut <= 1) return ['rest', cut > 0.04 ? 'diet' : 'film', 'sparLight'];
    const pool = ['striking', 'wrestling', 'bjj', 'sc', 'cardio', 'footwork', 'conditioning', 'sparLight'];
    const need = (act) => { const at = ACTIVITIES[act].attrs; return at.reduce((s, k) => s + (100 - (A[k] ?? 50)), 0) / at.length; };
    const ranked = pool.map((a) => [a, need(a) + (rng() * 6)]).sort((x, y) => y[1] - x[1]).map((x) => x[0]);
    const plan = ranked.slice(0, 2);
    if (cut > 0.05) plan.push('diet');
    else if (d.money < 300) plan.push('work');
    else if (d.fatigue > 35) plan.push('rest');
    else plan.push(d.hype < 20 ? 'media' : ranked[2]);
    return plan;
  }
  winChance(rating) {
    const me = overall(this.fightAttrs(null));
    return 1 / (1 + Math.exp(-(me - rating) / 5.5));
  }

  ageFactor() { const a = this.f.age; return a <= 23 ? 1.25 : a <= 27 ? 1.05 : a <= 31 ? 0.85 : a <= 34 ? 0.6 : 0.4; }

  advanceWeek() {
    const d = this.d, f = this.f, A = f.attrs;
    const out = { gains: {}, notes: [], fight: false };
    if (d.retired) return out;
    const gym = GYMS[d.gym];
    const injuredBad = d.health.injuries.some((x) => x.severe);
    if (d.autoPlan !== false && d._apWeek !== d.week) d.plan = this.autoPlan();
    d._apWeek = -1;
    // --- training
    for (const act of d.plan) {
      const def = ACTIVITIES[act];
      if (!def) continue;
      if ((act === 'sparHard' || act === 'sparLight') && (d.health.suspension > 0 || injuredBad)) { out.notes.push(`ข้าม ${def.name}: อยู่ในช่วงพักการชก/บาดเจ็บ`); continue; }
      const fatMul = clamp(1 - d.fatigue / 140, 0.3, 1);
      const morMul = 0.75 + d.morale / 200;
      const gm = gym.mul * (gym.bonus[act] || 1) * (d.flags.smartTraining && act === 'sparHard' ? 0.85 : 1);
      for (const k of def.attrs) {
        const cur = A[k];
        const g = 1.6 * def.gain * Math.pow(Math.max(0.05, 1.12 - cur / 100), 1.35) * this.ageFactor() * fatMul * morMul * gm * (0.7 + rng() * 0.6) * (injuredBad ? 0.5 : 1);
        A[k] = clamp(cur + g, 10, 99);
        out.gains[k] = (out.gains[k] || 0) + g;
      }
      d.fatigue = clamp(d.fatigue + def.fat * (d.flags.smartTraining ? 0.9 : 1), 0, 100);
      if (def.brain) d.health.brainDamage = clamp(d.health.brainDamage + def.brain * (d.flags.smartTraining ? 0.5 : 1), 0, 100);
      if (def.kg) f.walkKg = Math.max(this.wc.kg * 0.98, f.walkKg + def.kg);
      if (def.morale) d.morale = clamp(d.morale + def.morale, 0, 100);
      if (def.cash) d.money += def.cash;
      if (def.hype) { d.hype = clamp(d.hype + def.hype, 0, 100); d.fame = clamp(d.fame + def.fame, 0, 100); }
      if (def.rel) d.rel[def.rel] = clamp(d.rel[def.rel] + 4, 0, 100);
      if (def.heal) for (const inj of d.health.injuries) inj.weeks -= 1;
      if (def.scout && d.booked) d.scout = Math.min(3, d.scout + 1);
      // training injuries (more likely when exhausted = overtraining)
      const risk = def.risk * (1 + Math.max(0, d.fatigue - 60) / 15);
      if (rng() < risk) this.trainingInjury(act, out);
    }
    if (!d.plan.includes('cardio') && !d.plan.includes('diet')) f.walkKg = Math.min(this.wc.kg * 1.2, f.walkKg + 0.15); // weight creeps back
    // natural recovery
    d.fatigue = clamp(d.fatigue - 14 - A.recovery * 0.08, 0, 100);
    if (d.fatigue > 85) { d.morale = clamp(d.morale - 4, 0, 100); out.notes.push('ร่างกายล้าสะสม (Overtraining) — เสี่ยงบาดเจ็บสูง พัฒนาช้าลง'); }
    // --- injuries heal
    for (const inj of d.health.injuries) inj.weeks -= 1;
    const healed = d.health.injuries.filter((x) => x.weeks <= 0);
    for (const h of healed) out.notes.push(`หายจากอาการ: ${h.name}`);
    d.health.injuries = d.health.injuries.filter((x) => x.weeks > 0);
    if (d.health.suspension > 0) { d.health.suspension--; if (d.health.suspension === 0) this.msg('คณะกรรมการกีฬา', 'สิ้นสุดการพักการชกทางการแพทย์ (Medical Suspension) แล้ว'); }
    // --- money
    const living = 220;
    const fee = gym.fee;
    d.money -= living + fee;
    if (d.sponsor) { d.money += d.sponsor.weekly; d.sponsor.weeks--; if (d.sponsor.weeks <= 0) { this.msg('สปอนเซอร์', `สัญญากับ ${d.sponsor.name} หมดลงแล้ว`); d.sponsor = null; } }
    if (d.flags.independent && !d.flags.exposed && d.debt > 0 && d.week % 4 === 3) { const it = Math.round(d.debt * 0.01); d.debt += it; this.msg('วิกเตอร์ สโตน', `ดอกเบี้ยเดือนนี้ ${money(it)} — หนี้รวม ${money(d.debt)}`); }
    if (d.money < 0) { d.morale = clamp(d.morale - 3, 0, 100); if (d.money < -3000) out.notes.push('⚠️ เงินติดลบหนัก — ค่าเช่าค้าง ต้องหางานพิเศษหรือหาไฟต์'); }
    // --- aging & decline
    d.week++;
    if (d.week % 52 === 0) {
      f.age++;
      this.msg('ครอบครัว', `สุขสันต์วันเกิดอายุ ${f.age} ปี 🎂`);
      if (f.age >= 32) out.notes.push('อายุเริ่มส่งผล: ความเร็วและคาร์ดิโอเริ่มถดถอย');
    }
    if (f.age >= 31) {
      const dec = (f.age - 30) * 0.035;
      for (const k of ['punchSpeed', 'kickSpeed', 'footwork', 'cardio', 'recovery', 'headMove']) A[k] = clamp(A[k] - dec * (0.5 + rng()), 10, 99);
      A.chin = clamp(A.chin - dec * 0.6, 10, 99);
    }
    // brain damage symptoms -> chin & composure erode
    A.chin = clamp(A.chin - d.health.brainDamage * 0.0015, 10, 99);
    d.hype = clamp(d.hype - 0.6, 0, 100);
    // sponsor offers when famous
    if (!d.sponsor && d.fame > 15 && rng() < 0.05 + d.fame / 1000) {
      const s = { name: ['Kraken Gear', 'Ironclad Energy', 'Riot Beer', 'Blacktop Apparel', 'Muay Corp'][Math.floor(rng() * 5)], weekly: Math.round(40 + d.fame * 9 + this.tier * 60), weeks: 26 };
      d.sponsor = s;
      this.msg('สปอนเซอร์', `🤝 ${s.name} เซ็นสัญญาสนับสนุน ${money(s.weekly)}/สัปดาห์ เป็นเวลา ${s.weeks} สัปดาห์`, true);
    }
    this.simWorld();
    // --- offers
    d.weeksSinceOffer++;
    if (!d.booked) this.maybeOffers();
    else {
      d.booked.weeksOut--;
      if (d.booked.weeksOut <= 0) out.fight = true;
    }
    // expire offers
    d.offers = d.offers.filter((o) => --o.expires > 0);
    // story triggers
    for (const ev of STORY) if (!d.seenStory[ev.id] && !d.pendingStory.includes(ev.id) && ev.when && ev.when(this)) d.pendingStory.push(ev.id);
    this.lastReport = out;
    return out;
  }

  trainingInjury(act, out) {
    const pool = [
      { name: 'ข้อเท้าพลิก', weeks: 3, attr: 'footwork' }, { name: 'ซี่โครงช้ำ', weeks: 3, attr: 'cardio' }, { name: 'นิ้วหัก', weeks: 5, attr: 'punchPower', severe: true },
      { name: 'คิ้วแตกจากการสปาร์', weeks: 3, attr: 'chin', cut: true }, { name: 'เข่าเคล็ด', weeks: 4, attr: 'kickPower' }, { name: 'ไหล่อักเสบ', weeks: 4, attr: 'strength' },
      { name: 'หมอนรองกระดูกปลิ้น', weeks: 8, attr: 'takedown', severe: true }, { name: 'ซี่โครงร้าว', weeks: 6, attr: 'bodyTough', severe: true },
    ];
    const inj = { ...pool[Math.floor(rng() * pool.length)] };
    if (act === 'sparHard' && rng() < 0.25) { inj.name = 'โดนน็อกในการสปาร์ (Concussion)'; inj.weeks = 4; inj.severe = true; this.d.health.brainDamage += 1.5; }
    if (inj.cut) this.d.health.scarL += 0.2;
    this.d.health.injuries.push(inj);
    out.notes.push(`🚑 บาดเจ็บระหว่างซ้อม: ${inj.name} (${inj.weeks} สัปดาห์)`);
    this.msg('หมอประจำยิม', `บาดเจ็บ: ${inj.name} — ต้องพักประมาณ ${inj.weeks} สัปดาห์`, true);
  }

  // ---------- offers ----------
  maybeOffers() {
    const d = this.d;
    if (d.health.suspension > 0 || d.offers.length >= 3) return;
    const chance = d.promo === 'amateur' ? 0.4 : d.promo === 'regional' ? 0.3 : 0.25;
    if (d.weeksSinceOffer < 2 || rng() > chance + d.weeksSinceOffer * 0.03) return;
    d.weeksSinceOffer = 0;
    const o = this.makeOffer();
    if (o) { d.offers.push(o); this.msg(PROMOTIONS[o.promo].short, `📩 ข้อเสนอไฟต์ใหม่: พบกับ ${o.oppName} (${o.oppRec}) อีก ${o.weeksOut} สัปดาห์ ${o.short ? '⚡ แจ้งล่วงหน้าสั้น' : ''}`); }
  }

  makeOffer(opts = {}) {
    const d = this.d, pr = opts.promo || d.promo;
    const list = d.rosters[pr];
    let cands;
    if (pr === 'major') {
      const myR = this.myRank() ?? (RANKED + 4);
      cands = list.filter((n) => !n.champ && !n.story).map((n, i) => ({ n, i })).filter(({ i }) => Math.abs(i + 1 - myR) <= 5).map((x) => x.n);
    } else cands = list.filter((n) => !n.story);
    cands = cands.filter((n) => d.week - n.lastFight > 4);
    if (opts.oppId) cands = list.filter((n) => n.id === opts.oppId);
    if (!cands.length) return null;
    const n = cands[Math.floor(rng() * cands.length)];
    const short = !opts.oppId && rng() < 0.15;
    const weeksOut = opts.weeksOut || (short ? 1 + Math.floor(rng() * 2) : 4 + Math.floor(rng() * 5));
    const purse = this.purseFor(pr, opts.title, short);
    const rounds = opts.title ? 5 : PROMOTIONS[pr].rounds;
    return { id: 'o' + d.week + '_' + Math.floor(rng() * 1e6), promo: pr, oppId: n.id, oppName: n.name + (n.nick ? ` "${n.nick}"` : ''), oppRec: `${n.record.w}-${n.record.l}${n.record.d ? '-' + n.record.d : ''}`, oppStyle: n.style, oppRating: n.rating, weeksOut, short, purse, rounds, roundLen: PROMOTIONS[pr].roundLen, title: opts.title || null, expires: 3, story: opts.story || null };
  }

  purseFor(pr, title, short) {
    const d = this.d, hype = 1 + d.hype / 220;
    let show = 0, win = 0;
    if (pr === 'amateur') { show = 0; win = 0; }
    else if (pr === 'regional') { show = 900 + d.f.record.w * 250; win = show; }
    else if (pr === 'contender') { show = 5000; win = 5000; }
    else {
      const r = this.myRank();
      show = 10000 + (r ? (RANKED + 1 - r) * 2200 : 0) + d.f.record.w * 300;
      win = show;
      if (title) { show = d.champ ? 300000 + (d.defenses || 0) * 50000 : 100000; win = d.champ ? 100000 : 0; }
    }
    if (title === 'regional') { show *= 2; win *= 2; }
    const m = hype * (short ? 1.4 : 1);
    return { show: Math.round(show * m / 10) * 10, win: Math.round(win * m / 10) * 10 };
  }

  acceptOffer(id) {
    const d = this.d;
    const o = d.offers.find((x) => x.id === id);
    if (!o) return;
    d.booked = { ...o };
    d.offers = [];
    d.scout = 0;
    this.msg('ผู้จัดการ', `✍️ เซ็นสัญญาแล้ว! ไฟต์กับ ${o.oppName} อีก ${o.weeksOut} สัปดาห์ — วางแผนแคมป์ให้ดี`);
    if (o.short) d.morale = clamp(d.morale + 3, 0, 100);
  }
  declineOffer(id) {
    const d = this.d;
    d.offers = d.offers.filter((x) => x.id !== id);
    d.hype = clamp(d.hype - 2, 0, 100);
  }
  negotiate(id) {
    const d = this.d, o = d.offers.find((x) => x.id === id);
    if (!o || o.negotiated) return 'ต่อรองไปแล้ว';
    o.negotiated = true;
    const p = 0.25 + d.hype / 150 + (d.promo === 'major' && this.myRank() ? 0.15 : 0);
    if (rng() < p) { o.purse.show = Math.round(o.purse.show * 1.25); o.purse.win = Math.round(o.purse.win * 1.25); return 'สำเร็จ! โปรโมเตอร์ยอมเพิ่มค่าตัว 25%'; }
    if (rng() < 0.35) { d.offers = d.offers.filter((x) => x.id !== id); return 'โปรโมเตอร์ไม่พอใจ ถอนข้อเสนอไปแล้ว'; }
    return 'โปรโมเตอร์ยืนยันตัวเลขเดิม';
  }

  // ---------- fight night ----------
  weighIn() {
    const d = this.d, f = this.f, lim = this.wc.kg;
    const cut = Math.max(0, (f.walkKg - lim) / f.walkKg);
    let missed = false;
    if (cut > 0.08 && rng() < (cut - 0.08) * 7) missed = true;
    if (cut > 0.11 && rng() < 0.3) missed = true;
    return { walk: f.walkKg, limit: lim, cut, missed, severe: cut > 0.07 };
  }

  // attributes for fight night: injuries, fatigue, weight cut, morale
  fightAttrs(wi) {
    const d = this.d, a = { ...this.A };
    for (const inj of d.health.injuries) if (inj.attr) a[inj.attr] = Math.max(10, a[inj.attr] - (inj.severe ? 18 : 9));
    const fat = d.fatigue / 100;
    a.cardio -= fat * 18; a.recovery -= fat * 10;
    if (wi) {
      const c = wi.cut;
      if (c > 0.04) { a.cardio -= (c - 0.04) * 260; a.chin -= (c - 0.04) * 200; a.strength -= (c - 0.04) * 80; }
    }
    a.composure += (d.morale - 50) * 0.15;
    for (const k in a) a[k] = clamp(Math.round(a[k]), 10, 99);
    return a;
  }

  myFightProfile(wi, faceCanvas) {
    const f = this.f;
    return {
      id: 'me', name: f.name, nick: f.nick, country: f.country, style: f.style, stance: f.stance, height: f.height,
      weightKg: this.wc.kg * (wi && wi.cut > 0.06 ? 1.09 : 1.05), reachMul: f.reachMul, look: f.look, attrs: this.fightAttrs(wi),
      record: d0(f.record), careerHealth: { brainDamage: this.d.health.brainDamage, scarL: this.d.health.scarL, scarR: this.d.health.scarR }, faceCanvas,
    };
  }
  oppFightProfile() {
    const [n] = this.findNPC(this.d.booked.oppId);
    const p = this.npcProfile(n);
    p.weightKg = this.wc.kg * 1.06;
    return p;
  }
  scoutReport() {
    const b = this.d.booked; if (!b) return null;
    const [n] = this.findNPC(b.oppId); if (!n) return null;
    const p = this.npcProfile(n);
    const lines = [`สไตล์: ${STYLES[p.style]?.name || p.style}`, `สเตนซ์: ${p.stance === 'southpaw' ? 'เซาท์พอว์' : 'ออร์โธด็อกซ์'}`, `สูง ${(p.height * 100).toFixed(0)} ซม.`];
    if (this.d.scout >= 1) { const a = p.attrs; const best = Object.entries(a).sort((x, y) => y[1] - x[1]).slice(0, 3).map(([k]) => ATTR_LABEL[k]); lines.push('จุดแข็ง: ' + best.join(', ')); }
    if (this.d.scout >= 2) { const a = p.attrs; const worst = Object.entries(a).sort((x, y) => x[1] - y[1]).slice(0, 3).map(([k]) => ATTR_LABEL[k]); lines.push('จุดอ่อน: ' + worst.join(', ')); }
    if (this.d.scout >= 3) lines.push(`ค่าพลังรวมโดยประมาณ: ${n.rating}`);
    return lines;
  }

  // quick simulation when the player chooses not to fight manually
  simulate() {
    const me = overall(this.fightAttrs(this.lastWeighIn));
    const [n] = this.findNPC(this.d.booked.oppId);
    const p = 1 / (1 + Math.exp(-(me - n.rating) / 5.5));
    const won = rng() < p;
    const r = rng();
    const method = r < 0.33 ? 'KO' : r < 0.45 ? 'TKO' : r < 0.6 ? 'SUB' : 'DEC';
    const rounds = this.d.booked.rounds;
    const round = method === 'DEC' ? rounds : 1 + Math.floor(rng() * rounds);
    return { won, draw: false, method, detail: method === 'DEC' ? 'Unanimous Decision (เอกฉันท์)' : method === 'SUB' ? 'Rear-Naked Choke' : 'Punches', round, time: '2:31', sim: true,
      health: { brain: won ? 10 + rng() * 15 : 20 + rng() * 25, cuts: rng() < 0.35 ? [{ region: 'browL', depth: 0.6 }] : [], noseBroken: rng() < 0.05, koLoss: !won && method === 'KO' }, sig: Math.round(20 + rng() * 40), td: Math.floor(rng() * 3), fotn: rng() < 0.1, perf: won && method !== 'DEC' && rng() < 0.3 };
  }

  // ---------- post fight ----------
  applyResult(res) {
    const d = this.d, f = this.f, b = d.booked;
    const [n, pr] = this.findNPC(b.oppId);
    const notes = [];
    const won = res.won, draw = res.draw;
    const isAm = b.promo === 'amateur';
    const rec = isAm ? f.am : f.record;
    if (draw) { if (!isAm) rec.d++; } else if (won) rec.w++; else rec.l++;
    if (n) { if (draw) n.record.d = (n.record.d || 0) + 1; else if (won) { n.record.l++; n.streak = Math.min(0, n.streak || 0) - 1; } else { n.record.w++; n.streak = Math.max(0, n.streak || 0) + 1; } n.lastFight = d.week; }
    d.streak = won ? Math.max(0, d.streak || 0) + 1 : draw ? 0 : Math.min(0, d.streak || 0) - 1;
    // money
    let purse = b.purse.show + (won ? b.purse.win : 0);
    if (res.missedWeight) { const fine = Math.round(purse * 0.2); purse -= fine; notes.push(`ชั่งน้ำหนักไม่ผ่าน: ถูกปรับ ${money(fine)} (20%)`); }
    let bonus = 0;
    if (!isAm) {
      const bonusAmt = b.promo === 'major' ? 50000 : b.promo === 'contender' ? 10000 : 2000;
      if (res.perf) { bonus += bonusAmt; notes.push(`🏅 โบนัส Performance of the Night ${money(bonusAmt)}`); d.stats.bonuses++; }
      if (res.fotn) { bonus += bonusAmt; notes.push(`🔥 โบนัส Fight of the Night ${money(bonusAmt)}`); d.stats.bonuses++; }
    }
    const coachCut = d.gym === 'irongate' && !isAm ? Math.round(purse * 0.1) : 0;
    const mgr = d.flags.viktorManaged && !isAm ? Math.round(purse * 0.2) : 0;
    const net = purse + bonus - coachCut - mgr;
    d.money += net; d.earnings += purse + bonus;
    if (purse + bonus > 0) notes.push(`ค่าตัว ${money(purse)}${bonus ? ' + โบนัส ' + money(bonus) : ''}${coachCut ? ` · ครูเดช 10% (${money(coachCut)})` : ''}${mgr ? ` · วิกเตอร์หัก 20% (${money(mgr)})` : ''} → รับสุทธิ ${money(net)}`);
    if (d.flags.viktorManaged && mgr > 0) d.debt = Math.max(0, d.debt - mgr);
    // stats
    if (won) { if (res.method.startsWith('KO') || res.method.startsWith('TKO')) d.stats.koWins++; else if (res.method.startsWith('SUB')) d.stats.subWins++; else d.stats.decWins++; }
    d.stats.sigLanded += res.sig || 0; d.stats.takedowns += res.td || 0;
    // fame / hype / morale
    const finish = res.method !== 'DEC';
    d.fame = clamp(d.fame + (won ? (finish ? 6 : 3) : 1) * (1 + this.tier * 0.5), 0, 100);
    d.hype = clamp(d.hype + (won ? (finish ? 14 : 7) : -10), 0, 100);
    d.morale = clamp(d.morale + (won ? 12 : -14), 0, 100);
    d.fatigue = clamp(d.fatigue + 30, 0, 100);
    // health consequences
    const h = res.health || {};
    const brain = (h.brain || 0) * 0.05 + (h.koLoss ? 3.5 : 0) + (h.knockdowns || 0) * 0.7;
    d.health.brainDamage = clamp(d.health.brainDamage + brain, 0, 100);
    let susp = 2;
    if (h.koLoss) susp = 9; else if (!won && res.method.startsWith('TKO')) susp = 6; else if ((h.brain || 0) > 40) susp = 4;
    const add = (name, weeks, attr, severe) => { d.health.injuries.push({ name, weeks, attr, severe }); susp = Math.max(susp, weeks); };
    for (const c of h.cuts || []) {
      if (c.depth > 0.4) { add(`แผลเย็บ ${c.region === 'browL' ? 'คิ้วซ้าย' : c.region === 'browR' ? 'คิ้วขวา' : ''}`, c.depth > 0.8 ? 5 : 3, null, false); if (c.region === 'browL') d.health.scarL += 0.25; if (c.region === 'browR') d.health.scarR += 0.25; }
    }
    if (h.noseBroken) { add('จมูกหัก', 6, 'cardio', true); d.health.noseBreaks++; }
    if (h.orbital) add('กระดูกเบ้าตาแตก (ผ่าตัด)', 12, 'chin', true);
    if (h.jaw) add('กรามหัก (ดามลวด)', 10, 'chin', true);
    if (h.hand) add('มือหัก', 8, 'punchPower', true);
    if (h.ribs) add('ซี่โครงร้าว', 6, 'bodyTough', true);
    if (h.limb) add(h.limb, 16, 'strength', true);
    if (h.legs) add('ขาช้ำหนัก', 2, 'footwork', false);
    d.health.suspension = Math.max(d.health.suspension, susp);
    notes.push(`พักการชกทางการแพทย์ ${susp} สัปดาห์`);
    if (brain > 4) notes.push(`🧠 สมองกระทบกระเทือนสะสมเพิ่มขึ้น (${Math.round(d.health.brainDamage)}/100)`);
    // history
    f.history.unshift({ week: d.week, date: this.dateStr, opp: b.oppName, promo: PROMOTIONS[b.promo].short, res: draw ? 'D' : won ? 'W' : 'L', method: res.method, detail: res.detail, round: res.round, time: res.time, purse: purse + bonus, title: b.title });
    // titles & promotion ladder
    if (b.title === 'regional' && !won) { delete d.seenStory.regionalTitle; d.titleRetryAt = f.record.w + 3; notes.push('พลาดเข็มขัดภูมิภาค — ชนะอีก 3 ไฟต์เพื่อขอรีแมตช์'); }
    if (b.title === 'major' && !won && !d.champ) { delete d.seenStory.titleShot; d.titleShotRetryAt = f.record.w + 2; }
    if (b.title === 'regional' && won) { d.regionalChamp = true; d.titles.push(`แชมป์ ${PROMOTIONS.regional.short} รุ่น ${this.wc.name}`); notes.push('🏆 คุณคือแชมป์ภูมิภาค!'); }
    if (b.title === 'major') {
      if (won) {
        const champ = d.rosters.major.find((x) => x.champ); if (champ) champ.champ = false;
        if (!d.champ) { d.champ = true; d.titles.push(`แชมป์โลก ${PROMOTIONS.major.short} รุ่น ${this.wc.name}`); notes.push('🏆🏆 แชมป์โลก! เข็มขัดเป็นของคุณ'); }
        else { d.defenses = (d.defenses || 0) + 1; notes.push(`🏆 ป้องกันแชมป์สำเร็จ ครั้งที่ ${d.defenses}`); }
      } else if (d.champ) { d.champ = false; if (n) n.champ = true; notes.push('เสียเข็มขัดแชมป์...'); }
    }
    if (b.promo === 'amateur' && f.am.w + f.am.l >= 3 && f.am.w >= 2) this.queueStory('turnPro');
    if (b.promo === 'contender') {
      if (won && (finish || res.dominant)) { d.promo = 'major'; d.contract = { promo: 'major', fightsLeft: 4 }; notes.push(`✍️ ได้สัญญากับ ${PROMOTIONS.major.name}!`); this.queueStory('afcSigned'); }
      else if (won) { notes.push('ชนะ แต่ไม่โดดเด่นพอ — แมตช์เมกเกอร์อยากเห็นอีกไฟต์ (ชนะอีก 2 ไฟต์ในภูมิภาค)'); d.promo = 'regional'; delete d.seenStory.contenderCall; d.contenderRetryAt = f.record.w + 2; }
      else { d.promo = 'regional'; notes.push('พลาดสัญญา AFC — ชนะอีก 3 ไฟต์ในภูมิภาคเพื่อรับโอกาสใหม่'); delete d.seenStory.contenderCall; d.contenderRetryAt = f.record.w + 3; }
    }
    if (b.story && won) d.flags[b.story + 'Won'] = true;
    if (b.story && !won) d.flags[b.story + 'Lost'] = true;
    if (b.fixed) d.flags.tookDive = d.flags.tookDive || !won;
    if (b.fixed && won) d.flags.defiedFix = true;
    if (d.contract && d.contract.fightsLeft) d.contract.fightsLeft--;
    d.booked = null; d.lastFightWeek = d.week; d.scout = 0;
    // story hooks (after-fight events, plus regular triggers that need "no fight booked")
    for (const ev of STORY) if (!d.seenStory[ev.id] && !d.pendingStory.includes(ev.id) && ev.afterFight && ev.afterFight(this, res)) d.pendingStory.push(ev.id);
    for (const ev of STORY) if (!d.seenStory[ev.id] && !d.pendingStory.includes(ev.id) && ev.when && ev.when(this)) d.pendingStory.push(ev.id);
    return notes;
  }

  retire() { this.d.retired = true; this.queueStory('ending'); }
}

function d0(r) { return { w: r.w, l: r.l, d: r.d }; }
