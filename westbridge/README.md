# WESTBRIDGE — City Life Simulator (Godot 4)

เกม 3D Open World Life Simulator มุมมองบุคคลที่ 3 สำหรับ Android (และ PC) สร้างด้วย **Godot 4 + GDScript**
**โมเดลตัวละครและเสื้อผ้าทั้งหมดปั้นใน Blender** (ไฟล์ `.blend` ต้นฉบับอยู่ใน `assets/characters/source/` เปิดแก้ต่อได้) แล้ว export เป็น glTF ให้เกมโหลด
ส่วนเมือง Animation และระบบเกมสร้างด้วยโค้ด ทุกชิ้นออกแบบเอง ไม่ได้ลอกจากเกมอื่น

> สถานะ: **Phase 1 + Phase 2 + ระบบฟิสิกส์/อนิเมชั่นตัวละครขั้นสูง** เสร็จแล้ว มีชุดทดสอบอัตโนมัติ 76 รายการและผ่านทั้งหมด
> ทดสอบกับ **Godot 4.7.1** (ใช้ API ของ 4.5 ขึ้นไป แต่แนะนำให้ใช้ 4.7.x)

---

## วิธีเปิดเล่น

1. ดาวน์โหลด Godot **4.7.1** (Standard) จาก godotengine.org
2. Godot → **Import** → เลือกไฟล์ `westbridge/project.godot`
3. กด **Run (F5)** ระบบจะเปิดเมนูหลัก จากนั้นเลือก **New game** → สร้างตัวละคร → **Start**

ปุ่มลัดสำหรับทดสอบ:
- เมนูหลัก → **Physics Lab** = สนามทดสอบฟิสิกส์ตัวละคร (ผลัก, ปาของ, ทางลาด, บันได, ตึกสูง 5 ม., พื้นน้ำแข็ง)
- **F3** = Physics Debug overlay (balance, impact force, physics state, animation, ragdoll, joint angles, recovery state)

### ปุ่มควบคุม

| มือถือ | คีย์บอร์ด/เมาส์ | การทำงาน |
|---|---|---|
| Joystick ซ้าย (ลอยตามนิ้ว) | WASD | เดิน; ดันจอยไม่สุด = เดิน, ดันสุด = วิ่ง |
| ลากครึ่งจอขวา | เมาส์ (คลิกเพื่อล็อกเมาส์) | หมุนกล้อง |
| RUN (เปิด/ปิด) | Shift | วิ่งเร็ว (ใช้ stamina) |
| JUMP | Space | กระโดด |
| USE / TALK | E | ใช้ของ เปิดประตู นั่ง คุยกับ NPC |
| PUNCH | คลิกซ้าย / J | ต่อย (สลับซ้าย/ขวา) |
| BLOCK (ค้าง) | คลิกขวา / K | ป้องกัน ลดแรงกระแทกจากด้านหน้า |
| CROUCH | C | ย่อตัว |
| — | Alt | เดินช้า |
| II | Esc | หยุดเกม / Save / Load / Settings |
| — | F5 / F9 | Quick save / Quick load |

ปุ่มบนจอ **ย้ายตำแหน่งได้**: Pause → Settings → Controls → *Edit button layout* แล้วลากปุ่มไปวางใหม่ ปรับขนาดและความโปร่งใสได้

---

## สิ่งที่ทำงานได้แล้ว

### ตัวละครสไตล์ Stylized: Character Base Mesh ปั้นใน Blender
- **Base mesh และชุดทั้งหมดสร้างใน Blender** ด้วย `tools/blender/build_characters.py` ซึ่งใช้ Skin modifier + Subdivision ทำตัว, Metaball ทำผมและเครา, ตัดเสื้อผ้าจากผิวตัวจริงให้พอดีตัว และมี Armature ที่ใช้ชื่อกระดูกเดียวกับเกม ผลลัพธ์มีดังนี้
  - `assets/characters/westbridge_characters.glb` โหลดเข้าเกม (88 ชิ้น + ชุด LOD1 อีก 79 ชิ้น)
  - `assets/characters/source/westbridge_characters.blend` เปิดใน Blender เพื่อปั้น/แก้ต่อได้ แต่ละชิ้นเป็น object แยก
  - `assets/characters/renders/sheet_*.png` แผ่นรวมภาพเรนเดอร์: turnaround หน้า/ข้าง/หลัง, เทียบขนาด, shape keys, ชุด 8 แบบ, ทรงผม/เครา/หมวก (ภาพแยกแต่ละมุมสร้างใหม่ได้ด้วย `--render` แล้วตามด้วย `python tools/blender/make_sheets.py`)
- สัดส่วนแบบ stylized ตามชีตอ้างอิง: หัวใหญ่ทรงสี่เหลี่ยมมน, ตาโตยื่นมีเปลือกตาบนปิดราว 1/4, คิ้วหนา, จมูกเล็ก, คอหนาสั้น, ตัวยาว ขาสั้น (สะโพก 0.77 ม.), เสื้อยืดทรงกล่อง, บูตอ้วน
  ทุกชิ้นปั้นใน "build space" แล้วแปลงไปยังโครงกระดูกสุดท้าย (`NEW_JOINTS`) ด้วยน้ำหนักกระดูกของชิ้นนั้นเอง (`reproportion()`) จึงปรับสัดส่วนทั้งชุดได้จากตารางเดียว และ `HumanoidDef` ในเกมใช้ตำแหน่งเดียวกัน
- Shape keys: Female / Heavy / Thin / Muscular (ตัว) และ HeadWide / HeadLong / JawWide / JawNarrow (หัว) ผูกกับแถบเลื่อนใน Character Creator
- ในเกม `CharacterAssetBuilder` จะเลือกชิ้นตามหน้าตาที่ตั้งไว้ อบ shape key ใส่สี แล้วรวมเป็น **skinned mesh เดียว = 1 draw call** ใช้ skeleton เดียวกับเดิม ทำให้ Animation, FaceRig, ragdoll และ balance ทำงานได้โดยไม่ต้องแก้
- ประหยัดสำหรับมือถือ: ผิวส่วนที่ถูกเสื้อผ้าบังจะถูกตัดทิ้ง (hidden-surface removal) และ NPC ที่อยู่ไกลใช้ชุด LOD1 ที่ปั้นมาจาก Blender เอง (~7.5–9.4k สามเหลี่ยมเมื่ออยู่ใกล้ / ~2.8–3.6k เมื่ออยู่ไกล)
- ถ้าไม่มีไฟล์ asset หรือปิด `character_assets` ใน Settings ระบบจะกลับไปใช้ตัวละครแบบ procedural เดิมโดยอัตโนมัติ
- สร้างโมเดลใหม่: `python tools/blender/build_characters.py [--render]` (ใช้ Blender 4.2+ หรือ `pip install bpy`) หรือ `blender -b -P tools/blender/build_characters.py -- --render`
- หัวทรงไข่ ตาโตมีเปลือกตาที่ขยับได้ คิ้ว ปาก จมูก หู แสดงอารมณ์ได้ (สุข, เศร้า, โกรธ, กลัว, ตกใจ, เหนื่อย) กะพริบตา กลอกตามองสิ่งต่างๆ ขยับปากตอนพูด
- Character Creator: เพศ, ส่วนสูง, น้ำหนัก, รูปร่าง (ผอม/ปกติ/อ้วน/กล้าม), สีผิว, อายุ, หน้า (กว้าง/สูง/กราม), ตา (ทรง/ขนาด/ระยะ/สี), คิ้ว, จมูก, ปาก, ทรงผม 11 แบบ, สีผม, เครา, หนวด
- เสื้อผ้า **แยกชิ้นและแสดงบนตัวจริง**: เสื้อ 7 แบบ, เสื้อคลุม 7 แบบ (รวมเสื้อเกราะตำรวจ), กางเกง/กระโปรง 5 แบบ, รองเท้า 4 แบบ, ถุงเท้า, หมวก 7 แบบ (รวมหมวกตำรวจ), แว่น 4 แบบ, กระเป๋า, เครื่องประดับ, นาฬิกา, เข็มขัด เปลี่ยนชุดได้ที่ตู้เสื้อผ้าในบ้าน

### ระบบอนิเมชั่น + ฟิสิกส์ตัวละครขั้นสูง
- **AnimationTree แบบหลายชั้น**: locomotion blend (idle → walk → jog → run → sprint ซิงก์ phase กัน), เดินกะเผลกตามค่าบาดเจ็บ, ย่อตัว, กระโดด/ตก/ลงพื้น, นั่ง, นอน, ลุก, เบรกตอนวิ่ง, เซ, ชั้น upper body (ต่อย, โบกมือ, คุย, กิน, ดื่ม, หัวเราะ, โกรธ, ชี้, เปิดประตู, โดนตี 5 ทิศ) และท่าถือค้าง (โทรศัพท์, ป้องกัน, กอดอก, ล้วงกระเป๋า, ถือของ, ร่ม, ทำงาน) ทุกการเปลี่ยนท่ามีการ cross-fade
- **54 Animation clips** ที่เขียนเป็น keyframe ด้วยโค้ด (*ไม่ใช่ motion capture* — ดูหมายเหตุด้านล่าง) ใช้ชื่อกระดูกตาม `SkeletonProfileHumanoid` จึงใส่ animation จริงจากไฟล์ glTF/FBX ทับได้ในภายหลัง
- **Procedural layer**: เอนตัวตามความเร่ง/เบรก, เอียงตัวเข้าโค้ง, เอนตามทางลาด, ท่าทางตามอารมณ์ (ห่อไหล่/อกผาย/ก้มหน้า), หันหัว+ตามองเป้าหมายแบบจำกัดองศา, **Foot IK สองข้อต่อ + ปรับสะโพก** (เท้าไม่ลอย/ไม่จมบนบันไดและทางลาด)
- **Balance controller**: โมเดล inverted pendulum + **PID controller** + ค่า reaction time, strength, fatigue, injury, stun, แรงเสียดทานพื้น → ทรงตัวด้วยการเอนตัว → **ก้าวเท้าแก้การเสียหลัก** (stepping strategy) → ถ้า capture point ไกลเกินจะก้าวทัน = **ล้ม**
- **Impact system**: ทุกแรงกระแทกมีตำแหน่ง ทิศ แรง ความเร็วและน้ำหนักวัตถุ (ใช้ reduced mass) แยกส่วนร่างกาย (หัว/ลำตัว/แขนซ้าย/แขนขวา/ขา) ซ้าย-ขวา-หน้า-หลังตอบสนองต่างกัน
- **Spring-damper hit reaction** ต่อกระดูก: ขายังเดินตาม animation แต่ลำตัว/แขน/หัวสะบัดตามแรงจริง
- **Partial ragdoll** (แขนหรือหัวที่โดนตีมีฟิสิกส์จริงแล้วค่อยๆ blend กลับ) และ **Full ragdoll** ด้วย `PhysicalBoneSimulator3D` + `PhysicalBone3D` 17 ชิ้น พร้อม joint limits (ConeTwist สำหรับสะโพก/ไหล่/คอ, Hinge สำหรับเข่า/ศอก/ข้อเท้า) ไม่ชนกันเองจนระเบิด ใช้ Jolt Physics
- **Ragdoll recovery อัจฉริยะ**: รอร่างนิ่ง → ตรวจพื้นที่ว่าง (ถ้าติดจะดิ้นแล้วลองใหม่) → ตรวจว่านอนหงายหรือคว่ำ → จัดทิศตัว → **blend จากฟิสิกส์ไป animation ลุก** (getup_back / getup_front) → เปิด balance → กลับมาควบคุมได้ ไม่มีการดีดตัว
- ขึ้น/ลงบันไดจริง (step-up + visual smoothing), เดินบนทางลาด 20°, ตกจากที่สูง (land / land_hard / ragdoll ตามความเร็ว), วิ่งชนกำแพง, ชนกับ NPC, พื้นน้ำแข็งลื่น
- NPC แต่ละคนมีค่าน้ำหนักตัว ความแข็งแรง การทรงตัว reaction time ความกลัว ความเหนื่อย ต่างกัน → ตอบสนองต่อแรงเดียวกันไม่เหมือนกัน
- Ragdoll rig สร้างเมื่อจำเป็นและถอดออกจาก scene tree เมื่อไม่ใช้ (ตัวละครที่ยืนเฉยๆ ไม่มีต้นทุนฟิสิกส์)

### Phase 1 — เมือง ผู้เล่น การควบคุม
- เมือง **WESTBRIDGE** 20 บล็อก ใน 4 ย่าน: **Maple Heights** (บ้านมีระเบียง รั้ว ตู้จดหมาย ทางรถ อพาร์ตเมนต์ สวนสาธารณะ สนามบาส สนามเด็กเล่น), **Old Town** (ตลาด, ร้านค้า, Rosie's Diner, ศาลากลาง+ลาน), **Downtown** (ตึกสำนักงาน, ธนาคาร, โรงแรม, ลานจอดรถ, QuickStop + ปั๊มน้ำมัน), **Industrial** (โกดังขนส่ง, อู่ซ่อมรถ)
- ถนนพร้อมเส้นจราจร ทางม้าลาย ฟุตบาทยกขอบ เสาไฟ เสาไฟฟ้า+สายไฟ ป้ายชื่อถนน ไฟจราจร ป้ายหยุด ป้ายรถเมล์ ถังขยะ หัวดับเพลิง รถจอด (รถขับได้มาใน Phase 5) ต้นไม้ ป่าสนรอบเมือง ภูเขา
- **73 สถานที่** มีชื่อ เวลาเปิด-ปิด และตำแหน่งงาน (95 ตำแหน่ง)
- **อาคารที่เข้าได้จริง**: ห้องของผู้เล่น (เตียง = นอนข้ามเวลา + บันทึกเกม, ตู้เสื้อผ้า, โซฟา), QuickStop (ชั้นวางของ, ตู้เย็น, เคาน์เตอร์), Rosie's Diner (บูธ, เคาน์เตอร์), อู่ซ่อมรถ ประตูมีฟิสิกส์จริง ประตูร้านเปิดเองเมื่อมีคนเดินเข้าใกล้ (ร้านที่ปิดจะเข้าไม่ได้)
- ของที่ใช้ได้: นั่งม้านั่ง/โซฟา, ตู้กดน้ำ, ซื้อกาแฟ/อาหาร/ของชำ (ใช้เงินจริงและเติมค่าความหิว/พลังงาน), ค้นถังขยะ, บอร์ดประกาศ
- เวลา 24 ชม. (1 วินาทีจริง = 1 นาทีในเกม), กลางวัน/กลางคืน/พระอาทิตย์ขึ้น-ตก, สภาพอากาศ (แดด, เมฆ, ฝน, ฝนหนัก, หมอก) ถนนเปียกหลังฝน ไฟถนน/ป้ายร้าน/หน้าต่างสว่างตอนกลางคืน
- ค่าสถานะผู้เล่น: health, stamina, hunger, energy
- Save/Load 4 slots, JSON + checksum + เขียนไฟล์แบบ atomic + **backup หมุนเวียน 2 ชุด** (ไฟล์เสียจะโหลดจาก backup อัตโนมัติ)
- Settings: Quality preset (Low/Medium/High), FPS 30/60, render scale, ระยะการมองเห็น, เงา, ความไวกล้อง, invert Y, ระยะกล้อง, touch controls, ขนาด/ความโปร่งใสปุ่ม, เสียง 4 ช่อง

### Phase 2 — NPC ที่มีชีวิต
- ประชากร 40/60/85 คน (ตาม quality) **ทุกคนเป็นคนจริงในระบบ** มีชื่อ อายุ เพศ หน้าตา เสื้อผ้า บ้าน งาน เงิน อาหารในตู้เย็น งานอดิเรก เป้าหมาย ประวัติชีวิต เวลาตื่น/นอน
- **บุคลิก 18 ค่า** (ความกล้า, ขี้กลัว, ก้าวร้าว, ใจดี, เห็นแก่ตัว, ซื่อสัตย์, ขี้อาย, มั่นใจ, ฉลาด, ขี้เกียจ, ทะเยอทะยาน, เป็นมิตร, ชอบเข้าสังคม, อดทน, หุนหันพลันแล่น, ระมัดระวัง, ภักดี, อยากรู้อยากเห็น) สร้างจาก 5 ปัจจัยหลักที่สัมพันธ์กัน บุคลิกจึงสอดคล้องกัน
- **Utility AI**: ให้คะแนน 13 การกระทำ (นอน, ทำงาน, กินที่บ้าน, กินข้างนอก, กาแฟ, ซื้อของชำ, เข้าสังคม, งานอดิเรก, พักบนม้านั่ง, พักผ่อนที่บ้าน, หลบฝน, เดินเล่น, หางาน) จากความต้องการ บุคลิก อารมณ์ เวลา สภาพอากาศ เงิน สถานที่ และแผนประจำวัน พร้อมเหตุผลที่อ่านได้
- **แผนประจำวันที่ยืดหยุ่น**: ตื่นสาย, ป่วย, โดดงาน, ไปสาย, นัดเพื่อนตอนเย็น, พักกินข้าวกลางวัน, ตกงานแล้วไปสมัครงาน (สัมภาษณ์ผ่าน/ไม่ผ่านตามบุคลิก)
- **อารมณ์ 11 ชนิด** เกิดจากเหตุการณ์และความต้องการ ส่งผลต่อสีหน้า ท่าเดิน ความเร็ว และการตัดสินใจ
- **ความทรงจำ**: เหตุการณ์ เวลา สถานที่ ใคร ความสำคัญ ความรู้สึก ความแรง ที่ค่อยๆ จาง (เรื่องเล็กลืม เรื่องใหญ่จำนาน) จำเฉพาะสิ่งที่เห็นเอง
- **ความสัมพันธ์แยก 7 ค่า** (friendship, trust, respect, fear, anger, attraction, jealousy) + ครอบครัว/คู่รัก/เพื่อนร่วมห้อง/เพื่อนร่วมงาน NPC ทักทาย โบกมือ หยุดคุยกัน และรู้จักคนใหม่เองโดยผู้เล่นไม่เกี่ยว
- **ตอบสนองต่อเหตุการณ์**: เมื่อผู้เล่นต่อย NPC เหยื่อจะสู้กลับ/หนี/ตะโกนตามบุคลิก คนที่ **มองเห็นจริง** (ตรวจ line-of-sight) จะเลือก หนี/เข้าช่วย/เผชิญหน้า/โทรแจ้งตำรวจ/ถ่ายวิดีโอ/ยืนดู/เมิน/เข้าข้างผู้ทำ ตามบุคลิกและความสัมพันธ์กับเหยื่อและผู้ทำ แล้วจดจำเหตุการณ์
- **คุยกับ NPC**: ชวนคุย, ถามเรื่องวันนี้ (บางคนโกหก), ชม, ด่า, ให้เงิน — คำตอบขึ้นกับบุคลิก อารมณ์ ความทรงจำ และความสัมพันธ์ ปุ่ม **Inspect (AI)** แสดงข้อมูลภายในทั้งหมด (คะแนน utility, แผน, ความสัมพันธ์, ความทรงจำ)
- **ประสิทธิภาพ**: NPC ไม่คิดทุกเฟรม (round-robin, ใกล้ ~0.3 วิ ไกล ~2 วิ), NPC ใกล้ได้ body จาก pool (16 ตัวที่ Medium) พร้อม AI + animation + physics เต็ม, ระยะกลางใช้ mesh เบา, ไกล/อยู่ในอาคารจำลองแบบ abstract บนเครือข่ายทางเดิน, จำลองย้อนหลังเมื่อนอนข้ามเวลา

---

## ผลการทดสอบ (`tools/run_tests.sh`)

| ชุดทดสอบ | ผล |
|---|---|
| คอมไพล์ทุกสคริปต์ (64 ไฟล์) | ผ่าน |
| Unit/Integration 40 รายการ (save/backup, mesh, animation, balance, memory, เมือง, AI, จำลอง 2 วัน) | 40/40 |
| Physics Lab 14 รายการ (ผลัก 3 ระดับ, ragdoll เสถียร, เข่า/ศอกงอถูกทิศ, ลุกขึ้น, ตกตึก, ของปา, บันได, ทางลาด, แรงเฉื่อย) | 14/14 |
| ทดสอบในเมือง 12 รายการ (NPC เดิน, ต่อยแล้วเหยื่อ/พยานตอบสนอง, ความทรงจำ, คุย, save, นอน, load) | 12/12 |

ประสิทธิภาพที่วัดได้ (PC, headless): logic ~3 ms + physics ~2 ms ต่อเฟรม กับ NPC body 16 ตัว, ~100 draw calls, ~300k สามเหลี่ยม/เฟรม (รวม shadow pass) ที่ quality Medium

---

## หมายเหตุตรงไปตรงมา

- **Animation เป็น keyframe ที่เขียนด้วยโค้ด ไม่ใช่ motion capture** ดูเป็นธรรมชาติในระดับเกม stylized เพราะมี blending, procedural layer และฟิสิกส์ช่วย แต่ไม่ละเอียดเท่า mocap ระบบรองรับการใส่ animation จริง (Mixamo/glTF ที่ใช้ humanoid rig) โดยตั้งชื่อ clip เดิม
- **ยังไม่ได้ build เป็น APK และยังไม่ได้ทดสอบบนมือถือจริง** มี `export_presets.cfg` (Android, arm64, landscape) ให้แล้ว ต้องติดตั้ง Android export templates + SDK + JDK 17 เอง ตัวเลขประสิทธิภาพข้างบนวัดบน PC ยังต้องวัดบนเครื่องจริงใน Phase 10
- ภาพหน้าจอระหว่างพัฒนาเรนเดอร์ด้วย software renderer ในเซิร์ฟเวอร์ ค่า FPS ในภาพจึงไม่ใช่ FPS จริง
- UI ยังเป็นภาษาอังกฤษ ถ้าจะใช้ภาษาไทยต้องใส่ฟอนต์ไทย (เช่น Noto Sans Thai)
- ระบบที่ยังไม่มี (ตามแผน): รถขับได้/จราจร (Phase 5), เศรษฐกิจเต็มรูปแบบ/งานแบบมีมินิเกม/ร้านค้า/inventory (Phase 4), ซื้อบ้าน/เฟอร์นิเจอร์ (Phase 6), โทรศัพท์/โซเชียล (Phase 7), ตำรวจ (Phase 8), NPC Creator, ขยายเมือง (Beach, Hillside, Entertainment)

---

## โครงสร้างโปรเจกต์

```
westbridge/
  project.godot, export_presets.cfg
  scenes/          main_menu, character_creator, game_world, physics_lab
  shaders/         world.gdshader (สีจาก vertex color + ลวดลายแบบ procedural, กลางคืน, ถนนเปียก)
  scripts/
    core/          event_bus, game_time, settings, save_system, game  (autoloads)
    character/     appearance, humanoid_def (กระดูก), character_asset_library/builder (โหลด+รวมโมเดล Blender),
                   procedural mesh builders (สำรอง), character_model, face_rig, humanoid_body
    animation/     anim_library_builder (54 clips), character_animator (AnimationTree)
    physics/       balance_controller, pid_controller, impact_data, procedural_rig, ragdoll_rig, humanoid_physics, thrown_object
    player/        player_controller, third_person_camera, player_interactor
    input/         player_input, touch_controls
    interaction/   interactable, door, seat, simple_interactables
    world/         city_map, city_builder, city_blocks, building_kit, props_kit, geo_batch, ped_graph, place, environment_controller, game_world
    npc/           npc_data, personality, npc_emotion, npc_memory, npc_generator, npc_manager, npc_body, ai/npc_brain, ai/npc_reactions
    ui/            ui_kit, hud, pause_menu, settings_menu, character_creator, main_menu, npc_dialog
    test/          physics_lab, world_test
  assets/characters/  westbridge_characters.glb, source/*.blend, renders/*.png
  tests/           test_runner (unit + integration), visual/char_preview, perf/lineup (ภาพตัวละครในเอนจิน)
  tools/           check.sh, run_tests.sh, env.sh, blender/build_characters.py + render_previews.py
  docs/            ARCHITECTURE.md
```

รายละเอียดสถาปัตยกรรมและแผน Phase ถัดไปอยู่ที่ [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
