// ===== Story mode: "สังเวียนเลือด" =====
// Original story & characters. Themes: debt, a crooked promoter, loyalty, and the real price of fighting (brain damage).
import { makeNPC, baseAttrs } from './npc.js';
import { rng, money, clamp } from './util.js';
import { PROMOTIONS } from './data.js';

export function storyNPCs(wc) {
  const darius = makeNPC(424242, { tier: 1, wc, style: 'wrestling', country: 'US', levelAdd: 6 });
  Object.assign(darius, { name: 'Darius Cole', nick: 'The Python', age: 24, stance: 'orthodox' });
  darius.look = { ...darius.look, skin: '#8d5a3b', hairStyle: 'cornrows', hairColor: '#141010', beard: 'goatee', muscle: 0.8, fat: 0.1, shorts: '#111111', shortsTrim: '#c9a227', tattoo: 'script', cauliflower: true, seed: 9001 };
  darius.attrs = baseAttrs('wrestling', 60, null); darius.attrs.punchPower = 64; darius.attrs.cardio = 70; darius.attrs.heart = 70;
  const ivan = makeNPC(777777, { tier: 3, wc, style: 'sambo', country: 'RU', levelAdd: 14 });
  Object.assign(ivan, { name: 'Ivan Morozov', nick: 'The Glacier', age: 31, stance: 'southpaw' });
  ivan.look = { ...ivan.look, skin: '#f3d2b5', hairStyle: 'buzz', hairColor: '#c9a165', beard: 'none', muscle: 0.75, fat: 0.12, shorts: '#ffffff', shortsTrim: '#0d47a1', tattoo: 'none', cauliflower: true, scar: true, seed: 3131 };
  ivan.attrs = baseAttrs('sambo', 84, null); ivan.attrs.chin = 88; ivan.attrs.cardio = 90; ivan.attrs.fightIQ = 90; ivan.attrs.punchPower = 84;
  return [
    { id: 'darius', story: true, fixed: darius, promo: 'regional', name: darius.name, nick: darius.nick, country: 'US', style: 'wrestling', record: { w: 9, l: 0, d: 0 }, age: 24, rating: 66, lastFight: 0, streak: 9, tier: 1 },
    { id: 'ivan', story: true, champ: true, fixed: ivan, promo: 'major', name: ivan.name, nick: ivan.nick, country: 'RU', style: 'sambo', record: { w: 24, l: 1, d: 0 }, age: 31, rating: 88, lastFight: 0, streak: 11, tier: 3 },
  ];
}

const S = (who, text) => ({ who, text });
const N = (text) => ({ who: '', text });

export const STORY = [
  {
    id: 'prologue', bg: '🌧️',
    scene: (c) => ({
      lines: [
        N('ท่าเรือเหล็ก — ย่านโกดังริมแม่น้ำ ที่ไฟถนนดับมากกว่าติด และเสียงเรือขนตู้คอนเทนเนอร์ดังทั้งคืน'),
        N(`สามเดือนก่อน "ต้น" เพื่อนรักของ ${c.f.name} ขึ้นชกไฟต์ใต้ดินของ "วิกเตอร์ สโตน" เพื่อหาเงินค่าผ่าตัดให้แม่... หมัดเดียวกลางยกสอง ต้นล้มลงไปแข็งทื่อ แขนชูขึ้นฟ้าเหมือนนักฟันดาบ แล้วไม่ได้ลุกขึ้นมาอีกเลย`),
        N('ตอนนี้ต้นนอนอยู่ใน ICU มีเลือดคั่งใต้เยื่อหุ้มสมอง ค่ารักษา 40,000 ดอลลาร์ — และวิกเตอร์ "ใจดี" ออกให้ก่อน... ในชื่อของคุณ'),
        S('เมย์ (น้องสาว)', 'พี่จะไปชกเหมือนพี่ต้นจริงๆ เหรอ... หนูเรียนพยาบาลนะพี่ หนูรู้ว่าสมองคนมันไม่ได้ซ่อมได้เหมือนเครื่องยนต์'),
        N('คืนนั้นคุณเดินไปที่ยิมเก่าใต้สะพาน ป้ายสังกะสีเขียนว่า "ท่าเรือเหล็ก" สีลอกจนอ่านแทบไม่ออก'),
        S('ครูเดช', 'มาหาข้าทำไม... ข้าเลิกปั้นนักมวยไปนานแล้ว (มือของเขาสั่นเล็กน้อยตอนจุดบุหรี่)'),
        S('ครูเดช', 'แต่ถ้าเอ็งจะชกจริง ข้ามีกฎข้อเดียว — ชกแบบคนที่อยากแก่ตาย ไม่ใช่ตายตอนหนุ่ม'),
      ],
      choices: [
        { text: '"ผมจะชกเพื่อใช้หนี้ และเพื่อต้น"', fx: (c) => { c.d.morale += 5; c.d.rel.coach += 5; c.d.flags.forTon = true; } },
        { text: '"ผมอยากเป็นแชมป์โลก ไม่ใช่แค่ใช้หนี้"', fx: (c) => { c.d.hype += 5; c.d.flags.dream = true; } },
        { text: '"ผมไม่มีทางเลือกอื่นแล้วครู"', fx: (c) => { c.d.rel.family += 5; c.d.rel.may += 5; } },
      ],
    }),
  },
  {
    id: 'firstFight', bg: '🏚️', when: (c) => c.d.week >= 2 && !c.d.booked && c.f.am.w + c.f.am.l === 0 && c.d.promo === 'amateur',
    scene: (c) => ({
      lines: [
        S('ครูเดช', 'ข้าหาไฟต์สมัครเล่นให้เอ็งแล้ว ศึกโกดัง 7 อีกสามสัปดาห์ ไม่มีค่าตัว มีแต่ถ้วยพลาสติกกับคนดูขี้เมา'),
        S('ครูเดช', 'จำไว้ — ยกการ์ดขึ้น คางลง หายใจ อย่าเปิดหน้าแลกเพราะอยากให้คนดูปรบมือ'),
      ],
      choices: [{ text: 'รับไฟต์', fx: (c) => { const o = c.makeOffer({ promo: 'amateur', weeksOut: 3 }); if (o) { c.d.offers.push(o); c.acceptOffer(o.id); } } }],
    }),
  },
  {
    id: 'firstResult', bg: '🏆', afterFight: (c) => c.f.am.w + c.f.am.l === 1,
    scene: (c) => {
      const won = c.f.am.w === 1;
      return {
        lines: won ? [S('ครูเดช', 'ไม่เลว... แต่เอ็งโดนหมัดฟรีไปสามหมัดในยกสอง ข้านับ ทุกหมัดที่โดนมันไม่หายไปไหน มันสะสมอยู่ในหัวเอ็ง'), S('เมย์', 'พี่! หนูดูไลฟ์ในมือถือ... พี่ชนะ! แต่ทำไมคิ้วพี่บวมแบบนั้น')]
          : [S('ครูเดช', 'แพ้ไม่ใช่เรื่องใหญ่ เรื่องใหญ่คือเอ็งเรียนอะไรจากมัน'), S('ครูเดช', 'กลับไปซ้อม ข้าจะสอนวิธีไม่ให้โดนชกฟรีให้เอ็งเอง')],
        choices: [{ text: 'กลับไปซ้อมต่อ', fx: (c) => { c.d.rel.coach += 3; } }],
      };
    },
  },
  {
    id: 'turnPro', bg: '🕴️',
    scene: (c) => ({
      lines: [
        N('รถเบนซ์สีดำจอดหน้ายิม ผู้ชายในสูทสีถ่านเดินเข้ามา กลิ่นน้ำหอมราคาแพงกลบกลิ่นเหงื่อและยาหม่อง'),
        S('วิกเตอร์ สโตน', 'ได้ข่าวว่าเด็กของครูเดชชกเก่ง... ยินดีด้วย ฉันคือเจ้าหนี้ของนายนะ จำได้ไหม'),
        S('วิกเตอร์ สโตน', `ฉันมีเวที Iron Gate FC ค่าตัวดี ให้ฉันเป็นผู้จัดการ ฉันจะหัก 20% ไปลดหนี้ทุกไฟต์ — หนี้ ${money(c.d.debt)} จะหมดเร็วกว่าที่คิด`),
        S('ครูเดช', '(กระซิบ) ไอ้นี่แหละที่จัดไฟต์ให้ต้นทั้งที่รู้ว่าต้นโดนน็อกมาสองอาทิตย์ก่อน...'),
      ],
      choices: [
        { text: 'เซ็นสัญญาให้วิกเตอร์เป็นผู้จัดการ (ไฟต์มาเร็ว หักหนี้อัตโนมัติ)', fx: (c) => { c.d.flags.viktorManaged = true; c.d.rel.viktor += 25; c.d.rel.coach -= 10; c.d.promo = 'regional'; c.msg('Iron Gate FC', 'ยินดีต้อนรับสู่ Iron Gate FC — ไฟต์มืออาชีพไฟต์แรกของคุณกำลังจะมา'); c.d.weeksSinceOffer = 5; } },
        { text: 'เทิร์นโปรกับครูเดชเอง (อิสระ แต่หนี้ยังเดินดอก)', fx: (c) => { c.d.flags.independent = true; c.d.rel.coach += 10; c.d.rel.viktor -= 15; c.d.promo = 'regional'; c.msg('วิกเตอร์ สโตน', 'ก็ได้... แต่หนี้ยังเดินดอก 1% ทุกเดือนนะ อย่าลืมล่ะ'); } },
      ],
    }),
  },
  {
    id: 'annaIntro', bg: '📰', when: (c) => c.d.promo !== 'amateur' && c.d.week >= 14,
    scene: () => ({
      lines: [
        S('แอนนา ลี (นักข่าว)', 'ฉันทำข่าวเรื่องไฟต์ใต้ดินของวิกเตอร์มาสองปีแล้ว ต้นไม่ใช่คนแรกที่โดนแบบนี้ — มีอีกสามคนที่ไม่ได้กลับบ้าน'),
        S('แอนนา ลี (นักข่าว)', 'ถ้าคุณรู้อะไร หรือวันไหนเขาขอให้คุณทำอะไรแปลกๆ... โทรหาฉัน'),
      ],
      choices: [
        { text: 'รับนามบัตร "ผมจะติดต่อไป"', fx: (c) => { c.d.flags.annaContact = true; c.d.rel.journalist += 20; } },
        { text: '"ผมไม่อยากยุ่ง ผมแค่อยากชก"', fx: (c) => { c.d.rel.journalist -= 5; } },
      ],
    }),
  },
  {
    id: 'dariusIntro', bg: '🎤', when: (c) => c.d.promo === 'regional' && c.f.record.w >= 1,
    scene: () => ({
      lines: [
        N('งานแถลงข่าว Iron Gate FC — แฟลชกล้องรัวไม่หยุด'),
        S('Darius "The Python" Cole', '9-0 ไม่เคยแพ้ พ่อฉันเป็นแชมป์ปล้ำทีมชาติ ส่วนแก... มาจากยิมที่หลังคารั่ว ครูก็มือสั่นจนผูกเชือกรองเท้าเองไม่ได้'),
        S('Darius "The Python" Cole', 'บอกครูแกด้วยนะ — ถ้าเจอกันเมื่อไหร่ ฉันจะส่งแกไปนอนเตียงข้างๆ เพื่อนแก'),
      ],
      choices: [
        { text: 'ตอกกลับกลางเวที (กระแส+ คู่ปรับ+)', fx: (c) => { c.d.hype += 12; c.d.rel.rival += 20; } },
        { text: 'นิ่ง แล้วพูดว่า "เจอกันในกรง"', fx: (c) => { c.d.fame += 3; c.d.rel.coach += 5; c.d.hype += 4; } },
        { text: 'ผลักเขาลงจากเวที (กระแส++ โดนปรับ $500)', fx: (c) => { c.d.hype += 20; c.d.rel.rival += 30; c.d.money -= 500; } },
      ],
    }),
  },
  {
    id: 'tonUpdate', bg: '🏥', when: (c) => c.d.week >= 22,
    scene: (c) => ({
      lines: [
        N('โรงพยาบาลรัฐ ตึกผู้ป่วยระบบประสาท ชั้น 4'),
        S('เมย์', 'พี่ต้นตื่นแล้ว... แต่พูดได้ทีละคำ จำชื่อพี่ได้ แต่จำไม่ได้ว่าวันนี้วันอะไร'),
        S('หมอ', `ถ้าจะฟื้นฟูให้ได้มากที่สุด ต้องผ่าตัดและทำกายภาพเข้มข้น ค่าใช้จ่ายประมาณ 15,000 ดอลลาร์ ยิ่งเร็วยิ่งดีครับ`),
        S('ต้น', '...ชก... อย่า... ชก... แบบ... ผม...'),
      ],
      choices: [
        { text: `จ่ายเลย ${money(15000)}${c.d.money < 15000 ? ' (เงินไม่พอ — ต้องติดหนี้)' : ''}`, fx: (c) => { c.d.money -= 15000; c.d.flags.paidTon = true; c.d.rel.family += 15; c.d.rel.may += 15; c.d.morale += 8; } },
        { text: 'สัญญาว่าจะหาเงินมาให้ได้ในไม่ช้า', fx: (c) => { c.d.flags.promiseTon = true; c.d.morale -= 3; } },
      ],
    }),
  },
  {
    id: 'payTon', bg: '🏥', when: (c) => c.d.flags.promiseTon && !c.d.flags.paidTon && c.d.money >= 20000,
    scene: () => ({
      lines: [S('เมย์', 'พี่... ตอนนี้พี่มีเงินพอแล้วนะ คุณหมอบอกว่าพี่ต้นยังรอได้อีกไม่นาน')],
      choices: [
        { text: 'จ่ายค่าผ่าตัดให้ต้น $15,000', fx: (c) => { c.d.money -= 15000; c.d.flags.paidTon = true; c.d.rel.may += 20; c.d.morale += 10; } },
        { text: 'ยังก่อน ผมต้องใช้เงินลงแคมป์', fx: (c) => { c.d.rel.may -= 20; c.d.flags.neglectTon = true; } },
      ],
    }),
  },
  {
    id: 'diveOffer', bg: '🎲', when: (c) => c.d.promo === 'regional' && c.f.record.w >= 3 && c.d.booked && c.d.booked.promo === 'regional' && !c.d.booked.title && c.d.booked.weeksOut >= 1,
    scene: (c) => ({
      lines: [
        N('ลานจอดรถหลังยิม ตีหนึ่ง วิกเตอร์ยืนพิงรถ บุหรี่ไฟแดงวาบในความมืด'),
        S('วิกเตอร์ สโตน', `ไฟต์กับ ${c.d.booked.oppName} — แกต้องแพ้ในยกที่สอง ฉันวางเดิมพันไว้ก้อนใหญ่`),
        S('วิกเตอร์ สโตน', 'ทำตามที่บอก หนี้ลด 20,000 ไม่ทำ... ก็ลองดู ท่าเรือมันมืด คนตกน้ำกันบ่อย'),
      ],
      choices: [
        { text: 'ยอมล้มมวย (ต้องแพ้ไฟต์นี้)', fx: (c) => { c.d.booked.fixed = true; c.d.flags.acceptedDive = true; c.d.rel.viktor += 15; c.msg('วิกเตอร์ สโตน', 'ฉลาดมาก ยกสอง อย่าลืม', true); } },
        { text: 'ปฏิเสธ "ผมไม่ล้มมวย"', fx: (c) => { c.d.flags.refusedDive = true; c.d.rel.viktor -= 30; c.d.rel.coach += 10; } },
        { text: 'แอบอัดเสียงไว้ แล้วปฏิเสธ', fx: (c) => { c.d.flags.refusedDive = true; c.d.flags.evidence = true; c.d.rel.viktor -= 30; c.d.rel.journalist += 10; } },
      ],
    }),
  },
  {
    id: 'diveResult', bg: '💰', afterFight: (c) => c.d.flags.acceptedDive && !c.d.flags.diveDone,
    scene: (c) => {
      c.d.flags.diveDone = true;
      if (c.d.flags.tookDive && !c.d.flags.defiedFix) return {
        lines: [S('วิกเตอร์ สโตน', 'เด็กดี หนี้ลด 20,000 แล้ว... ฉันชอบคนที่รู้จักที่ทางของตัวเอง'), S('ครูเดช', '(เงียบ ไม่มองหน้าคุณตลอดทั้งสัปดาห์)')],
        choices: [{ text: '...', fx: (c) => { c.d.debt = Math.max(0, c.d.debt - 20000); c.d.rel.coach -= 25; c.d.morale -= 15; } }],
      };
      return {
        lines: [N('คุณชนะ ทั้งที่รับปากว่าจะแพ้'), N('สองคืนต่อมา ชายสามคนดักรอคุณหน้าห้องเช่า...'), S('ชายในเสื้อฮู้ด', 'คุณวิกเตอร์ฝากมา — เงินที่เขาเสีย แกต้องชดใช้')],
        choices: [{ text: 'สู้กลับ (ข้างถนนไม่มีกติกา)', fx: (c) => { c.d.health.injuries.push({ name: 'มือหักจากการทะเลาะวิวาท', weeks: 7, attr: 'punchPower', severe: true }); c.d.debt += 10000; c.d.rel.viktor -= 40; c.d.flags.viktorEnemy = true; } }],
      };
    },
  },
  {
    id: 'regionalTitle', bg: '🏆', when: (c) => c.d.promo === 'regional' && c.f.record.w >= Math.max(5, c.d.titleRetryAt || 0) && !c.d.regionalChamp && !c.d.booked,
    scene: (c) => ({
      lines: [
        S('โปรโมเตอร์ IGFC', `แฟนๆ อยากเห็นไฟต์นี้มานานแล้ว — ชิงแชมป์ Iron Gate รุ่น ${c.wc.name} 5 ยก`),
        S('Darius "The Python" Cole', c.d.flags.dariusLost ? 'มาขอโดนอีกรอบเหรอ? ได้... คราวนี้ฉันจะไม่ปล่อยให้กรรมการช่วยแก' : 'ในที่สุดก็หนีไม่ได้แล้วนะ... ข้าจะกดแกกับพื้นห้ายก แล้วทุบจนกรรมการสงสาร'),
        S('ครูเดช', 'มันจะยิงขาเอ็งตั้งแต่วินาทีแรก — สปรอล (C) ให้ไว แล้วลงโทษมันด้วยเข่าตอนมันก้มตัว'),
      ],
      choices: [{ text: 'รับไฟต์ชิงแชมป์', fx: (c) => { const o = c.makeOffer({ promo: 'regional', oppId: 'darius', title: 'regional', weeksOut: 6, story: 'darius' }); if (o) { c.d.offers.push(o); c.acceptOffer(o.id); } } }],
    }),
  },
  {
    id: 'contenderCall', bg: '📞', when: (c) => c.d.regionalChamp && c.d.promo === 'regional' && !c.d.booked && c.f.record.w >= (c.d.contenderRetryAt || 0),
    scene: () => ({
      lines: [
        S('มาร์คัส เฮล (แมตช์เมกเกอร์ AFC)', 'ผมดูไฟต์ชิงแชมป์ของคุณแล้ว... Proving Grounds Series สัปดาห์หน้ายังว่างอยู่หนึ่งที่'),
        S('มาร์คัส เฮล (แมตช์เมกเกอร์ AFC)', 'ชนะอย่างเดียวไม่พอนะ ผมอยากเห็น "ช่วงเวลา" — ถ้าคุณทำให้คนลุกจากเก้าอี้ได้ สัญญา AFC เป็นของคุณ'),
      ],
      choices: [{ text: 'ไปพิสูจน์ตัวเอง', fx: (c) => { c.d.promo = 'contender'; const o = c.makeOffer({ promo: 'contender', weeksOut: 5 }); if (o) { c.d.offers.push(o); c.acceptOffer(o.id); } } }],
    }),
  },
  {
    id: 'coachTremor', bg: '🫨', when: (c) => c.d.week >= 34,
    scene: () => ({
      lines: [
        N('ครูเดชทำแก้วน้ำหล่นแตกเป็นครั้งที่สามของสัปดาห์'),
        S('ครูเดช', 'หมอบอกว่ามันชื่อ CTE... สมองเสื่อมจากการโดนกระแทกซ้ำๆ ข้าชกมา 180 ไฟต์ ซ้อมสปาร์หนักทุกวันพุธมายี่สิบปี'),
        S('ครูเดช', 'บางวันข้าจำชื่อเมียข้าไม่ได้ ข้าไม่อยากให้เอ็งเป็นแบบข้า... ตั้งแต่วันนี้ เราลดสปาร์หนักลง ซ้อมให้ฉลาดขึ้น เอ็งว่าไง'),
      ],
      choices: [
        { text: 'ตกลง ซ้อมแบบฉลาด (สมองเสียหายจากสปาร์ลดลงครึ่ง แต่พัฒนาช้าลงเล็กน้อย)', fx: (c) => { c.d.flags.smartTraining = true; c.d.rel.coach += 15; } },
        { text: '"ผมยังหนุ่ม ผมต้องซ้อมหนักเท่านั้นถึงจะเป็นแชมป์"', fx: (c) => { c.d.rel.coach -= 10; c.d.flags.grind = true; } },
      ],
    }),
  },
  {
    id: 'afcSigned', bg: '✍️',
    scene: (c) => ({
      lines: [
        N(`${PROMOTIONS.major.name} — เวทีที่ใหญ่ที่สุดในโลก`),
        S('มาร์คัส เฮล (แมตช์เมกเกอร์ AFC)', 'ยินดีต้อนรับครับ สัญญา 4 ไฟต์ ค่าตัวพื้นฐาน 12,000 + โบนัสชนะ — ไต่อันดับให้ได้ แล้วเราจะคุยเรื่องเข็มขัด'),
        S('Ivan "The Glacier" Morozov (แชมป์)', 'ยินดีต้อนรับสู่โลกของผู้ใหญ่ ที่นี่ไม่มีใครสนใจว่าแกมาจากไหน — สนใจแค่ว่าแกลุกขึ้นได้กี่ครั้ง'),
      ],
      choices: [{ text: 'เริ่มบทใหม่', fx: (c) => { c.d.hype += 10; c.d.fame += 5; } }],
    }),
  },
  {
    id: 'testify', bg: '⚖️', when: (c) => c.d.flags.annaContact && (c.d.flags.evidence || c.d.flags.refusedDive || c.d.flags.viktorEnemy) && c.d.week >= 50,
    scene: (c) => ({
      lines: [
        S('แอนนา ลี (นักข่าว)', 'ตำรวจสืบสวนกลางเปิดคดีวิกเตอร์แล้ว — ล้มมวย ฟอกเงิน และการตายของนักชกใต้ดินสามคน'),
        S('แอนนา ลี (นักข่าว)', c.d.flags.evidence ? 'เทปที่คุณอัดไว้คือหลักฐานชิ้นสำคัญที่สุด... แต่ถ้าคุณขึ้นให้การ ชื่อคุณจะอยู่ทุกหน้าหนังสือพิมพ์' : 'ถ้าคุณขึ้นให้การเรื่องที่เขาขอให้คุณล้มมวย คดีจะแน่นขึ้นมาก'),
      ],
      choices: [
        { text: 'ขึ้นให้การ', fx: (c) => { c.d.flags.exposed = true; c.d.debt = 0; c.d.fame += 15; c.d.rel.journalist += 20; c.msg('ข่าวด่วน', '🚔 วิกเตอร์ สโตน ถูกจับกุม! หนี้ทั้งหมดของคุณถูกศาลสั่งเป็นโมฆะ', true); } },
        { text: 'เงียบไว้ ไม่อยากเสี่ยง', fx: (c) => { c.d.rel.journalist -= 20; c.d.flags.silent = true; } },
      ],
    }),
  },
  {
    id: 'brainWarning', bg: '🧠', when: (c) => c.d.health.brainDamage >= 35,
    scene: (c) => ({
      lines: [
        S('หมอประสาทวิทยา', 'ผลสแกน MRI กับการตรวจความจำของคุณ... เราเห็นจุดเลือดออกเล็กๆ หลายจุด (microbleeds) และการตอบสนองที่ช้าลง'),
        S('หมอประสาทวิทยา', `ความเสียหายสะสมตอนนี้ราว ${Math.round(c.d.health.brainDamage)}% ของเกณฑ์อันตราย ทุกการน็อก ทุกวันสปาร์หนัก มันบวกเข้าไป และมันไม่ลดลง`),
        S('เมย์', 'พี่... หนูขอร้อง'),
      ],
      choices: [
        { text: 'ซ้อมแบบฉลาดขึ้น ลดสปาร์หนัก', fx: (c) => { c.d.flags.smartTraining = true; c.d.rel.may += 10; } },
        { text: 'ชกต่อ ผมยังไหว', fx: (c) => { c.d.rel.may -= 10; c.d.flags.ignoredDoctor = true; } },
        { text: 'ประกาศเลิกชก', fx: (c) => { c.retire(); } },
      ],
    }),
  },
  {
    id: 'brainSevere', bg: '🩻', when: (c) => c.d.health.brainDamage >= 65 && !c.d.retired,
    scene: () => ({
      lines: [
        N('เช้านี้คุณยืนหน้าตู้เย็นนานสามนาที... จำไม่ได้ว่าเดินมาเอาอะไร'),
        S('เมย์', 'หนูเห็นพี่พูดตะกุกตะกักเหมือนครูเดชแล้วนะ... ได้โปรด พอเถอะ'),
      ],
      choices: [
        { text: 'เลิกชก', fx: (c) => { c.retire(); } },
        { text: 'อีกไฟต์เดียว', fx: (c) => { c.d.flags.oneMore = true; c.d.rel.may -= 20; } },
      ],
    }),
  },
  {
    id: 'titleShot', bg: '🥇', when: (c) => c.d.promo === 'major' && !c.d.champ && !c.d.booked && (c.myRank() || 99) <= 3 && c.f.record.w >= (c.d.titleShotRetryAt || 0),
    scene: (c) => {
      const champ = c.d.rosters.major.find((n) => n.champ) || c.d.rosters.major[0];
      return {
        lines: [
          S('มาร์คัส เฮล (แมตช์เมกเกอร์ AFC)', `ถึงเวลาแล้ว — ไฟต์ชิงแชมป์โลก 5 ยก พบกับ ${champ.name}${champ.nick ? ` "${champ.nick}"` : ''}`),
          S('ครูเดช', 'ข้าอาจจำวันนี้ไม่ได้ในอีกห้าปี... แต่เอ็งต้องจำมันให้ได้ทั้งชีวิต'),
        ],
        choices: [{ text: 'รับไฟต์ชิงแชมป์โลก', fx: (c) => { const o = c.makeOffer({ promo: 'major', oppId: champ.id, title: 'major', weeksOut: 8, story: 'title' }); if (o) { c.d.offers.push(o); c.acceptOffer(o.id); } } }],
      };
    },
  },
  {
    id: 'dariusRematch', bg: '🐍', when: (c) => c.d.promo === 'major' && !c.d.booked && (c.d.flags.dariusWon || c.d.flags.dariusLost) && (c.myRank() || 99) <= 12 && c.d.week > 70,
    scene: (c) => {
      const [n] = c.findNPC('darius');
      if (n && n.promo !== 'major') { c.d.rosters.regional = c.d.rosters.regional.filter((x) => x.id !== 'darius'); n.promo = 'major'; n.tier = 3; n.rating += 10; c.d.rosters.major.push(n); }
      return {
        lines: [S('Darius "The Python" Cole', c.d.flags.dariusWon ? 'ครั้งนั้นแกโชคดี ตอนนี้ฉันอยู่ AFC แล้ว รีแมตช์ ต่อหน้าคนทั้งโลก' : 'จำได้ไหมว่าใครเป็นคนทำให้แกนอนบนพื้น? มาอีกรอบสิ')],
        choices: [
          { text: 'รับรีแมตช์', fx: (c) => { const o = c.makeOffer({ promo: 'major', oppId: 'darius', weeksOut: 6, story: 'darius2' }); if (o) { c.d.offers.push(o); c.acceptOffer(o.id); } } },
          { text: 'ไม่สน ฉันมองที่เข็มขัด', fx: (c) => { c.d.rel.rival += 10; } },
        ],
      };
    },
  },
  {
    id: 'autoEnd', bg: '⌛', when: (c) => !c.d.retired && (c.f.age >= 40 || c.d.health.brainDamage >= 92),
    scene: (c) => ({
      lines: [N(c.f.age >= 40 ? 'ร่างกายบอกคุณชัดเจน — ถึงเวลาแขวนนวมแล้ว' : 'คณะกรรมการกีฬาไม่ต่ออายุใบอนุญาตชกของคุณ ด้วยเหตุผลทางการแพทย์')],
      choices: [{ text: 'ยอมรับ', fx: (c) => c.retire() }],
    }),
  },
  {
    id: 'ending', bg: '🌅',
    scene: (c) => endingScene(c),
  },
];

export function storyById(id) { return STORY.find((s) => s.id === id); }

function endingScene(c) {
  const d = c.d, f = c.f, bd = d.health.brainDamage;
  const lines = [];
  const rec = `${f.record.w}-${f.record.l}-${f.record.d}`;
  lines.push(N(`${f.name}${f.nick ? ` "${f.nick}"` : ''} — สถิติอาชีพ ${rec} · ชนะน็อก ${d.stats.koWins} · ซับมิชชัน ${d.stats.subWins} · รายได้รวม ${money(d.earnings)}`));
  if (d.titles.length) lines.push(N('เกียรติยศ: ' + d.titles.join(' · ')));
  let title;
  if (d.champ || d.titles.some((t) => t.includes('โลก'))) {
    if (bd < 40) { title = 'ตำนานที่ยังจำชื่อตัวเองได้'; lines.push(N('คุณทำในสิ่งที่น้อยคนทำได้ — ขึ้นไปถึงจุดสูงสุด แล้วลงมาด้วยตัวเอง พร้อมความทรงจำครบถ้วน')); }
    else { title = 'ราคาของเข็มขัด'; lines.push(N('เข็มขัดแขวนอยู่บนผนัง แต่บางเช้าคุณต้องอ่านป้ายใต้มันเพื่อจำว่าได้มันมาอย่างไร')); }
  } else if (d.flags.tookDive && !d.flags.exposed) { title = 'หนี้เลือด'; lines.push(N('คุณใช้หนี้ด้วยการล้มมวย แต่ไม่มีวันลบมันออกจากใจได้ — ในวงการ ชื่อของคุณถูกกระซิบพร้อมคำว่า "ซื้อได้"')); }
  else if (bd < 25) { title = 'ไม่มีเข็มขัด แต่มีชีวิต'; lines.push(N('คุณไม่ได้เป็นแชมป์ แต่คุณเดินออกจากกรงด้วยขาตัวเอง และยังจำวันเกิดน้องสาวได้ทุกปี')); }
  else { title = 'นักสู้ที่ไม่เคยถอย'; lines.push(N('คุณให้ทุกอย่างกับกรงแปดเหลี่ยม — แฟนๆ จำการต่อสู้ของคุณได้ แม้บางวันคุณเองจะจำไม่ได้')); }
  if (d.flags.exposed) lines.push(N('วิกเตอร์ สโตน ถูกตัดสินจำคุก 18 ปี เวทีใต้ดินที่ท่าเรือเหล็กปิดตัวลงตลอดกาล'));
  else if (d.debt > 0) lines.push(N(`หนี้ที่เหลือ ${money(d.debt)} ยังคงตามหลอกหลอน — วิกเตอร์ยังคงรอที่ลานจอดรถหลังยิม`));
  lines.push(N(d.flags.paidTon ? 'ต้นเดินได้อีกครั้งด้วยไม้เท้า วันนี้เขาเป็นคนเปิดประตูยิมท่าเรือเหล็กทุกเช้า' : 'ต้นยังพูดได้ทีละคำ... เมย์ยังคงไปเยี่ยมเขาทุกวันอาทิตย์'));
  lines.push(N(d.flags.smartTraining ? 'ครูเดชอาการทรุดลงช้าๆ แต่ยังจำชื่อคุณได้เสมอ "ลูกศิษย์ที่ชกแบบคนอยากแก่ตาย"' : 'ครูเดชจากไปอย่างสงบในฤดูฝนปีหนึ่ง โดยไม่ทันได้รู้ว่าคุณมาเยี่ยม'));
  lines.push(N(`🧠 สมองเสียหายสะสม: ${Math.round(bd)}/100`));
  return { lines, title, choices: [{ text: '🏁 จบเรื่อง', fx: (c) => { c.d.ended = true; c.d.endingTitle = title; } }] };
}
