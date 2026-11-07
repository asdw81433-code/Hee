// ===== Static game data =====
export const WEIGHT_CLASSES = [
  { id: 'fly', name: 'ฟลายเวท (Flyweight)', lb: 125, kg: 56.7, h: 1.66 },
  { id: 'bantam', name: 'แบนตัมเวท (Bantamweight)', lb: 135, kg: 61.2, h: 1.70 },
  { id: 'feather', name: 'เฟเธอร์เวท (Featherweight)', lb: 145, kg: 65.8, h: 1.74 },
  { id: 'light', name: 'ไลท์เวท (Lightweight)', lb: 155, kg: 70.3, h: 1.77 },
  { id: 'welter', name: 'เวลเตอร์เวท (Welterweight)', lb: 170, kg: 77.1, h: 1.80 },
  { id: 'middle', name: 'มิดเดิลเวท (Middleweight)', lb: 185, kg: 83.9, h: 1.85 },
  { id: 'lheavy', name: 'ไลท์เฮฟวี่เวท (Light Heavyweight)', lb: 205, kg: 93.0, h: 1.88 },
  { id: 'heavy', name: 'เฮฟวี่เวท (Heavyweight)', lb: 265, kg: 120.2, h: 1.92 },
];
export const wcById = (id) => WEIGHT_CLASSES.find((w) => w.id === id) || WEIGHT_CLASSES[3];

export const ATTRS = {
  striking: [
    ['punchPower', 'พลังหมัด'], ['punchSpeed', 'ความเร็วหมัด'], ['accuracy', 'ความแม่นยำ'],
    ['kickPower', 'พลังเตะ'], ['kickSpeed', 'ความเร็วเตะ'], ['headMove', 'หลบศีรษะ'],
    ['blocking', 'การป้องกัน'], ['footwork', 'ฟุตเวิร์ก'],
  ],
  grappling: [
    ['takedown', 'ทุ่ม/เทคดาวน์'], ['tdDefense', 'กันเทคดาวน์'], ['clinch', 'คลินช์'],
    ['topControl', 'คุมด้านบน'], ['bottomGame', 'เกมด้านล่าง'], ['subOffense', 'จับล็อก'],
    ['subDefense', 'แก้ล็อก'],
  ],
  physical: [
    ['strength', 'ความแข็งแรง'], ['cardio', 'คาร์ดิโอ'], ['recovery', 'ฟื้นตัว'],
    ['chin', 'คาง (ทนหมัด)'], ['bodyTough', 'ทนลำตัว'], ['legTough', 'ทนขา'],
  ],
  mental: [['composure', 'ความนิ่ง'], ['fightIQ', 'ไอคิวการต่อสู้'], ['heart', 'หัวใจนักสู้']],
};
export const ALL_ATTRS = [...ATTRS.striking, ...ATTRS.grappling, ...ATTRS.physical, ...ATTRS.mental].map((a) => a[0]);
export const ATTR_LABEL = Object.fromEntries([...ATTRS.striking, ...ATTRS.grappling, ...ATTRS.physical, ...ATTRS.mental]);

// Base profiles per background (amateur level ~40-55)
export const STYLES = {
  boxing: { name: 'มวยสากล (Boxing)', desc: 'หมัดคมและเร็ว หลบศีรษะดี แต่เตะและปล้ำอ่อน',
    mod: { punchPower: 12, punchSpeed: 14, accuracy: 12, headMove: 14, footwork: 12, blocking: 8, kickPower: -12, kickSpeed: -10, takedown: -10, bottomGame: -12, subOffense: -12, subDefense: -8 } },
  muaythai: { name: 'มวยไทย (Muay Thai)', desc: 'เตะหนัก เข่าศอก คลินช์ดี แข้งแข็ง',
    mod: { kickPower: 16, kickSpeed: 10, clinch: 14, legTough: 12, blocking: 8, bodyTough: 8, takedown: -10, bottomGame: -10, subOffense: -10, headMove: -4 } },
  wrestling: { name: 'มวยปล้ำ (Wrestling)', desc: 'เทคดาวน์และคุมด้านบนยอดเยี่ยม คาร์ดิโอดี',
    mod: { takedown: 18, tdDefense: 16, topControl: 16, strength: 10, cardio: 10, punchSpeed: -6, accuracy: -6, kickPower: -10, kickSpeed: -10, headMove: -6 } },
  bjj: { name: 'บราซิลเลียนยิวยิตสู (BJJ)', desc: 'จับล็อกอันตราย เกมด้านล่างแข็ง',
    mod: { subOffense: 20, subDefense: 18, bottomGame: 18, topControl: 8, punchPower: -8, punchSpeed: -8, accuracy: -6, kickPower: -8, headMove: -8 } },
  kickboxing: { name: 'คิกบ็อกซิ่ง (Kickboxing)', desc: 'สมดุลหมัดเตะ ฟุตเวิร์กคล่อง',
    mod: { kickSpeed: 12, kickPower: 8, punchSpeed: 8, footwork: 12, accuracy: 6, takedown: -10, bottomGame: -10, subOffense: -8, tdDefense: -4 } },
  judo: { name: 'ยูโด (Judo)', desc: 'ทุ่มในคลินช์เก่ง ทรงตัวดี',
    mod: { clinch: 16, takedown: 12, tdDefense: 12, strength: 8, topControl: 8, subOffense: 4, punchSpeed: -8, kickSpeed: -10, headMove: -8, kickPower: -8 } },
  sambo: { name: 'แซมโบ้ (Sambo)', desc: 'ปล้ำ + ล็อกขา ผสมหมัด ถึกทน',
    mod: { takedown: 12, subOffense: 10, topControl: 10, strength: 8, chin: 6, cardio: 6, kickSpeed: -8, headMove: -6, footwork: -6 } },
  brawler: { name: 'นักสู้ข้างถนน (Brawler)', desc: 'หมัดหนัก คางแข็ง ใจสู้ แต่เทคนิคน้อย',
    mod: { punchPower: 16, chin: 14, heart: 14, strength: 6, accuracy: -10, blocking: -8, fightIQ: -10, subDefense: -10, footwork: -8, headMove: -6 } },
};

export const COUNTRIES = [
  ['TH', 'ไทย'], ['US', 'สหรัฐฯ'], ['BR', 'บราซิล'], ['RU', 'รัสเซีย'], ['JP', 'ญี่ปุ่น'], ['KR', 'เกาหลีใต้'],
  ['MX', 'เม็กซิโก'], ['IE', 'ไอร์แลนด์'], ['GB', 'อังกฤษ'], ['NG', 'ไนจีเรีย'], ['PH', 'ฟิลิปปินส์'], ['CN', 'จีน'],
  ['NL', 'เนเธอร์แลนด์'], ['PL', 'โปแลนด์'], ['AU', 'ออสเตรเลีย'], ['GE', 'จอร์เจีย'], ['DA', 'ดาเกสถาน'], ['FR', 'ฝรั่งเศส'],
];

// Name pools (fictional, mixed nationalities)
export const FIRST_NAMES = {
  TH: ['สมชาย', 'อนุชา', 'ธนกร', 'กิตติ', 'วีระ', 'ณัฐพล', 'ปกรณ์', 'ศักดิ์ชัย', 'ชาตรี', 'ภานุ'],
  US: ['Jake', 'Tyler', 'Marcus', 'Cody', 'Derek', 'Shane', 'Logan', 'Trevor', 'Darnell', 'Austin'],
  BR: ['Thiago', 'Rafael', 'Diego', 'Gilberto', 'Renan', 'Caio', 'Leandro', 'Mauricio', 'Joao', 'Edson'],
  RU: ['Alexei', 'Dmitri', 'Sergei', 'Pavel', 'Nikolai', 'Ivan', 'Artem', 'Ruslan', 'Oleg', 'Viktor'],
  JP: ['Kenji', 'Takeshi', 'Ryo', 'Daiki', 'Shinya', 'Yuto', 'Kazuki', 'Hiro', 'Sho', 'Tatsuya'],
  KR: ['Min-jun', 'Ji-hoon', 'Hyun-woo', 'Seung-ho', 'Dong-hyun', 'Jae-won', 'Tae-yang'],
  MX: ['Alejandro', 'Carlos', 'Javier', 'Luis', 'Ricardo', 'Fernando', 'Hector', 'Raul', 'Sergio'],
  IE: ['Conor', 'Sean', 'Liam', 'Ciaran', 'Darragh', 'Padraig', 'Eoin'],
  GB: ['Tom', 'Harry', 'Jack', 'Callum', 'Ryan', 'Lewis', 'Danny', 'Kieran'],
  NG: ['Chukwuemeka', 'Tunde', 'Obinna', 'Femi', 'Kelechi', 'Ade', 'Ifeanyi'],
  PH: ['Rolando', 'Jerome', 'Eduard', 'Kevin', 'Mark', 'Jomar'],
  CN: ['Wei', 'Jun', 'Hao', 'Lei', 'Bo', 'Ming', 'Zhen'],
  NL: ['Ruud', 'Jesper', 'Sem', 'Daan', 'Bram', 'Thijs'],
  PL: ['Marcin', 'Krzysztof', 'Mateusz', 'Tomasz', 'Kamil', 'Lukasz'],
  AU: ['Brodie', 'Mitch', 'Jai', 'Hayden', 'Lachlan', 'Riley'],
  GE: ['Giorgi', 'Levan', 'Merab', 'Nika', 'Davit', 'Irakli'],
  DA: ['Magomed', 'Islam', 'Khabib', 'Shamil', 'Zubair', 'Ramazan', 'Abubakar'],
  FR: ['Benoit', 'Nassim', 'Hugo', 'Mathis', 'Yanis', 'Ciryl'],
};
export const LAST_NAMES = {
  TH: ['ศรีสุข', 'แก้วมณี', 'ทองดี', 'พึ่งบุญ', 'สิงห์ทอง', 'เพชรรัตน์', 'วงศ์ใหญ่', 'ใจกล้า', 'มั่นคง'],
  US: ['Walker', 'Brooks', 'Hayes', 'Miller', 'Carter', 'Dawson', 'Reed', 'Fletcher', 'Grant', 'Harlan'],
  BR: ['Souza', 'Oliveira', 'Barbosa', 'Moraes', 'Teixeira', 'Pereira', 'Lima', 'Machado', 'Rocha'],
  RU: ['Volkov', 'Petrov', 'Sokolov', 'Kuznetsov', 'Morozov', 'Orlov', 'Zaitsev', 'Belov'],
  JP: ['Tanaka', 'Sato', 'Yamamoto', 'Kobayashi', 'Inoue', 'Okada', 'Mori', 'Hayashi'],
  KR: ['Kim', 'Park', 'Choi', 'Jung', 'Kang', 'Yoon', 'Han'],
  MX: ['Hernandez', 'Ramirez', 'Lopez', 'Castillo', 'Vargas', 'Ortega', 'Mendoza', 'Rios'],
  IE: ['Murphy', 'Kelly', "O'Brien", 'Byrne', 'Walsh', 'Doyle', 'Quinn'],
  GB: ['Taylor', 'Edwards', 'Harris', 'Wilson', 'Price', 'Bennett', 'Shaw'],
  NG: ['Okafor', 'Adeyemi', 'Nwosu', 'Balogun', 'Eze', 'Okonkwo'],
  PH: ['Santos', 'Reyes', 'Dela Cruz', 'Bautista', 'Aquino'],
  CN: ['Zhang', 'Li', 'Wang', 'Liu', 'Chen', 'Song'],
  NL: ['de Vries', 'Jansen', 'Bakker', 'Visser', 'Smit'],
  PL: ['Nowak', 'Kowalski', 'Wisniewski', 'Zielinski', 'Mazur'],
  AU: ['Mitchell', 'Kennedy', 'Hughes', 'Fraser', 'Dunn'],
  GE: ['Beridze', 'Kapanadze', 'Gelashvili', 'Tsiklauri'],
  DA: ['Magomedov', 'Abdulaev', 'Gadzhiev', 'Aliev', 'Omarov', 'Ibragimov'],
  FR: ['Durand', 'Lefebvre', 'Moreau', 'Benali', 'Girard'],
};
export const NICKNAMES = ['The Hammer', 'Cobra', 'Iron', 'The Reaper', 'Blade', 'Thunder', 'The Butcher', 'Lightning', 'Mad Dog',
  'Silent', 'Pitbull', 'The Surgeon', 'Ghost', 'Rock', 'Python', 'Bulldozer', 'Wolf', 'Bonecrusher', 'Tsunami', 'Viper',
  'The Professor', 'Cyclone', 'Pretty Boy', 'Steel', 'Diesel', 'Scarface', 'The Machine', 'Savage', 'Kid Dynamite', 'Anaconda'];

export const SKIN_TONES = ['#f3d2b5', '#e8bd98', '#d8a47f', '#c68b62', '#a8704b', '#8d5a3b', '#6e432a', '#4f2f1e'];
export const HAIR_COLORS = ['#141010', '#2b1d14', '#4a3020', '#6b4528', '#a0703a', '#c9a165', '#e3d3b0', '#8c8c8c', '#7a1f12'];
export { HAIR_DEFS as HAIR_STYLES, BEARD_DEFS as BEARDS } from './hair.js';
export const SHORTS_COLORS = ['#111111', '#b71c1c', '#0d47a1', '#1b5e20', '#f9a825', '#ffffff', '#4a148c', '#e65100', '#00838f', '#c2185b'];

// Fictional promotions (career ladder)
export const PROMOTIONS = {
  amateur: { name: 'ศึกสมัครเล่น ท่าเรือเหล็ก', short: 'AMATEUR', rounds: 3, roundLen: 180, tier: 0 },
  regional: { name: 'Iron Gate Fighting Championship', short: 'IGFC', rounds: 3, roundLen: 300, tier: 1 },
  contender: { name: 'Proving Grounds Series', short: 'PGS', rounds: 3, roundLen: 300, tier: 2 },
  major: { name: 'Apex Fighting Championship', short: 'AFC', rounds: 3, roundLen: 300, tier: 3 },
};
