// ===== Blocky low-poly fighter model ("potato" graphics, flat shaded) =====
import * as THREE from 'three';
import { S, SEGS } from './rig.js';
import { shade } from './face.js';
import { lerp, clamp } from './util.js';

const ONE = new THREE.Vector3(1, 1, 1);

function box(w, h, d, y0 = 0, z0 = 0, x0 = 0) {
  const g = new THREE.BoxGeometry(w, h, d);
  g.translate(x0, y0 + h / 2, z0);
  return g;
}
function taper(g, topX, botX, topZ = 1, botZ = 1) {
  const p = g.attributes.position;
  g.computeBoundingBox();
  const { min, max } = g.boundingBox;
  for (let i = 0; i < p.count; i++) {
    const t = (p.getY(i) - min.y) / (max.y - min.y);
    p.setX(i, p.getX(i) * lerp(botX, topX, t));
    p.setZ(i, p.getZ(i) * lerp(botZ, topZ, t));
  }
  p.needsUpdate = true;
  g.computeVertexNormals();
  return g;
}
function remapFaceUV(g, face, u0, v0, u1, v1) {
  const uv = g.attributes.uv;
  for (let k = 0; k < 4; k++) {
    const i = face * 4 + k;
    uv.setXY(i, u0 + uv.getX(i) * (u1 - u0), v0 + uv.getY(i) * (v1 - v0));
  }
  uv.needsUpdate = true;
}
const lam = (color, extra = {}) => new THREE.MeshLambertMaterial({ color, flatShading: true, ...extra });

export class FighterModel {
  constructor(rig, look, fx, opts = {}) {
    this.rig = rig; this.look = look; this.fx = fx;
    const d = rig.d, sc = d.H / 1.8, bulk = look.muscle ?? 0.5, fat = look.fat ?? 0.15;
    this.group = new THREE.Group();
    this.segs = [];
    const isRef = opts.ref;
    const skinM = lam(look.skin);
    const skinDark = lam(shade(look.skin, -0.12));
    const shortsCol = isRef ? '#1b1b1f' : look.shorts || '#111111';
    const shortsM = lam(shortsCol);
    const shortsTrim = lam(isRef ? '#1b1b1f' : look.shortsTrim || shade(shortsCol, 0.35));
    this.gloveM = lam(isRef ? look.skin : opts.gloveColor || '#151515');
    this.gloveBase = new THREE.Color(isRef ? look.skin : opts.gloveColor || '#151515');
    this.gloveBlood = 0;
    const hairM = lam(look.hairColor || '#1a1410');
    const faceM = new THREE.MeshLambertMaterial({ map: fx.faceTex, emissive: new THREE.Color('#ffffff'), emissiveMap: fx.faceTex, emissiveIntensity: 0.22 });
    const torsoM = new THREE.MeshLambertMaterial({ map: fx.torsoTex });
    const shirtM = lam('#2a2a33');
    this.mats = [skinM, skinDark, shortsM, shortsTrim, this.gloveM, hairM, faceM, torsoM, shirtM];
    const mk = (si, parts) => {
      const g = new THREE.Group();
      g.matrixAutoUpdate = false;
      for (const [geo, mat] of parts) {
        const m = new THREE.Mesh(geo, mat);
        m.castShadow = true; m.receiveShadow = false;
        g.add(m);
      }
      this.group.add(g);
      this.segs[si] = g;
      return g;
    };
    // --- pelvis / shorts
    const pw = 0.34 * sc * (1 + fat * 0.25), pd = 0.21 * sc * (1 + fat * 0.3);
    mk(S.pelvis, [[box(pw, d.spineBase + 0.1 * sc, pd, -0.1 * sc), shortsM], [box(pw * 1.02, 0.035 * sc, pd * 1.02, d.spineBase - 0.03 * sc), shortsTrim]]);
    // --- abdomen (torso texture lower part)
    const aw = 0.3 * sc * (1 + fat * 0.35 + bulk * 0.05), ad = 0.19 * sc * (1 + fat * 0.5);
    const abdG = box(aw, d.abd + 0.01, ad);
    remapFaceUV(abdG, 4, 0, 0, 0.5, 0.4); remapFaceUV(abdG, 5, 0.5, 0, 1, 0.4);
    const torsoMats = isRef ? [shirtM, shirtM, shirtM, shirtM, shirtM, shirtM] : [skinM, skinM, skinM, skinM, torsoM, torsoM];
    mk(S.abdomen, [[abdG, torsoMats]]);
    // --- chest (tapered V)
    const cw = d.shW * 2 * 0.92, cd = 0.22 * sc * (1 + bulk * 0.2 + fat * 0.15);
    const chG = taper(box(cw, d.chest + 0.01, cd), 1.0, 0.78 + fat * 0.15, 1.0, 0.9);
    remapFaceUV(chG, 4, 0, 0.4, 0.5, 1); remapFaceUV(chG, 5, 0.5, 0.4, 1, 1);
    const delt = 0.12 * sc * (1 + bulk * 0.35);
    mk(S.chest, [[chG, torsoMats],
      [box(delt, delt * 0.9, delt, d.shY - delt * 0.55, 0, d.shW * 0.97), isRef ? shirtM : skinM],
      [box(delt, delt * 0.9, delt, d.shY - delt * 0.55, 0, -d.shW * 0.97), isRef ? shirtM : skinM],
      [box(cw * 0.55, 0.06 * sc, cd * 0.7, d.chest - 0.05 * sc, -0.01), isRef ? shirtM : skinM], // traps
    ]);
    // --- neck
    const nw = 0.115 * sc * (1 + bulk * 0.35);
    mk(S.neck, [[box(nw, d.neck * 1.6, nw * 0.95, -d.neck * 0.3), skinDark]]);
    // --- head
    const hw = 0.19 * sc, hh = d.headH, hd = 0.22 * sc;
    this.headDims = { hw, hh, hd };
    const headG = taper(box(hw, hh, hd), 1.0, 0.86, 1.0, 0.95);
    const hs = look.hairStyle || 'short';
    const headMats = [skinM, skinM, hs === 'bald' ? skinM : hairM, skinDark, faceM, hs === 'bald' || hs === 'buzz' ? skinM : hairM];
    const headParts = [[headG, headMats]];
    // ears (cauliflower for grapplers)
    const caul = look.cauliflower ? 1.5 : 1;
    headParts.push([box(0.022 * sc * caul, 0.065 * sc * caul, 0.045 * sc * caul, hh * 0.42, -0.01, hw * 0.5 + 0.008), skinDark]);
    headParts.push([box(0.022 * sc * caul, 0.065 * sc * caul, 0.045 * sc * caul, hh * 0.42, -0.01, -hw * 0.5 - 0.008), skinDark]);
    // nose bump (3D)
    this.noseMesh = new THREE.Mesh(box(0.034 * sc, 0.055 * sc, 0.03 * sc, -0.0275 * sc), skinM);
    this.noseMesh.position.set(0, hh * (1 - 0.6), hd / 2 + 0.01);
    this.noseMesh.castShadow = true;
    // hair styles
    const hairBox = (w, h, dd, y, z = 0, x = 0) => headParts.push([box(w, h, dd, y, z, x), hairM]);
    if (hs === 'short') { hairBox(hw * 1.06, 0.045 * sc, hd * 1.06, hh - 0.01); hairBox(hw * 1.04, hh * 0.55, 0.03 * sc, hh * 0.42, -hd / 2 - 0.01); }
    if (hs === 'buzz') { hairBox(hw * 1.02, 0.015 * sc, hd * 1.02, hh - 0.005); }
    if (hs === 'mohawk') { hairBox(0.045 * sc, 0.08 * sc, hd * 1.05, hh - 0.01); hairBox(0.045 * sc, hh * 0.6, 0.05 * sc, hh * 0.35, -hd / 2 - 0.02); }
    if (hs === 'bun') { hairBox(hw * 1.05, 0.035 * sc, hd * 1.05, hh - 0.01); hairBox(0.07 * sc, 0.07 * sc, 0.07 * sc, hh * 0.85, -hd / 2 - 0.04); }
    if (hs === 'cornrows') { for (let i = -2; i <= 2; i++) hairBox(0.022 * sc, 0.025 * sc, hd * 1.04, hh - 0.012, 0, i * 0.035 * sc); }
    if (hs === 'long') { hairBox(hw * 1.07, 0.05 * sc, hd * 1.07, hh - 0.01); hairBox(hw * 0.5, hh * 0.9 + 0.12 * sc, 0.045 * sc, -0.12 * sc + hh * 0.1, -hd / 2 - 0.02); }
    const headGrp = mk(S.head, headParts);
    headGrp.add(this.noseMesh);
    // swelling lumps
    const lumpM = lam('#7a3048');
    this.lumpMat = lumpM;
    this.lumps = {};
    const lumpPos = { eyeR: [-0.31, 0.43, 1], eyeL: [0.31, 0.43, 1], cheekR: [-0.26, 0.6, 1], cheekL: [0.26, 0.6, 1], forehead: [0, 0.2, 1.4], lip: [0, 0.78, 1] };
    for (const k in lumpPos) {
      const [u, v, s] = lumpPos[k];
      const m = new THREE.Mesh(box(0.06 * sc * s, 0.04 * sc, 0.03 * sc, -0.02 * sc), new THREE.MeshLambertMaterial({ color: look.skin, flatShading: true }));
      m.position.set(u * hw, hh * (1 - v), hd / 2 - 0.004);
      m.scale.set(0.001, 0.001, 0.001);
      m.visible = false;
      headGrp.add(m);
      this.lumps[k] = m;
    }
    // --- arms
    const ua = 0.095 * sc * (1 + bulk * 0.4), fa = 0.082 * sc * (1 + bulk * 0.3);
    for (const [su, sf, sh] of [[S.uarmL, S.farmL, S.handL], [S.uarmR, S.farmR, S.handR]]) {
      mk(su, [[taper(box(ua, d.uarm + 0.02, ua), 1.05, 0.85), isRef ? shirtM : skinM]]);
      mk(sf, [[taper(box(fa, d.farm + 0.01, fa * 0.95), 1.0, 0.8), skinM]]);
      const gw = isRef ? 0.07 * sc : 0.098 * sc;
      const gParts = isRef ? [[box(gw, 0.09 * sc, 0.04 * sc, -0.01), skinM]]
        : [[box(gw, 0.105 * sc, 0.09 * sc, -0.015), this.gloveM], [box(gw * 0.98, 0.03 * sc, 0.088 * sc, -0.035), lam(opts.gloveTrim || '#2b2b2b')]];
      mk(sh, gParts);
    }
    // --- legs
    const th = 0.15 * sc * (1 + bulk * 0.3 + fat * 0.2), sw = 0.105 * sc * (1 + bulk * 0.2);
    for (const [st, ss, sft] of [[S.thighL, S.shinL, S.footL], [S.thighR, S.shinR, S.footR]]) {
      const parts = isRef ? [[taper(box(th * 0.95, d.thigh + 0.02, th * 0.95), 1, 0.85), shortsM]]
        : [[taper(box(th, d.thigh + 0.02, th), 1, 0.75), skinM], [box(th * 1.12, d.thigh * 0.48, th * 1.12, -0.02), shortsM]];
      mk(st, parts);
      mk(ss, [[taper(box(sw, d.shin + 0.02, sw), 1.0, 0.68), isRef ? shortsM : skinM]]);
      const fh = 0.055 * sc;
      const footG = new THREE.BoxGeometry(0.085 * sc, fh, d.foot + 0.06 * sc);
      footG.translate(0, -d.ankle + fh / 2, (d.foot + 0.06 * sc) / 2 - 0.06 * sc);
      mk(sft, [[footG, isRef ? lam('#111111') : skinDark]]);
    }
  }

  update() {
    const rig = this.rig;
    for (let i = 0; i < SEGS.length; i++) {
      const g = this.segs[i], s = rig.seg[i];
      g.matrix.compose(s.pos, s.quat, ONE);
      g.matrixWorldNeedsUpdate = true;
    }
  }

  // Visual swelling & nose deformation from the injury model
  setInjuryVisuals(h) {
    for (const k in this.lumps) {
      const v = clamp(h.swell[k] || 0, 0, 1.2);
      const m = this.lumps[k];
      m.visible = v > 0.12;
      const s = 0.2 + v * 1.1;
      m.scale.set(s, s * (k.startsWith('eye') ? 1.1 : 1), s * 0.8 + v);
      m.material.color.set(this.look.skin).lerp(new THREE.Color('#6a2a4a'), clamp(v * 0.8, 0, 0.7));
    }
    // broken nose: deviated
    this.noseMesh.rotation.z = h.noseBroken ? h.noseDeviation : 0;
    this.noseMesh.material = this.mats[0];
    const gb = clamp(this.gloveBlood, 0, 1);
    this.gloveM.color.copy(this.gloveBase).lerp(new THREE.Color('#4a0606'), gb * 0.75);
  }

  dispose() {
    this.group.traverse((o) => { if (o.geometry) o.geometry.dispose(); });
    for (const m of this.mats) m.dispose();
    this.lumpMat.dispose();
  }
}
