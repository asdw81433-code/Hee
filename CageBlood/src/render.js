// ===== Renderer, arena (octagon cage), crowd, mat blood stains, camera =====
import * as THREE from 'three';
import { mkCanvas } from './face.js';
import { clamp, lerp, damp, makeRng } from './util.js';

export const CAGE_APOTHEM = 4.5;
export const MAT_SIZE = 10.4; // meters covered by the mat texture
const OCT_N = 8;
const OCT_NORMALS = Array.from({ length: OCT_N }, (_, k) => {
  const a = (k / OCT_N) * Math.PI * 2 + Math.PI / 8;
  return [Math.cos(a), Math.sin(a)];
});

// clamp an xz position inside the octagon (with body radius r); returns true if clamped (touching cage)
export function cageClamp(pos, r) {
  let hit = false;
  for (const [nx, nz] of OCT_NORMALS) {
    const d = pos.x * nx + pos.z * nz;
    const lim = CAGE_APOTHEM - r;
    if (d > lim) { pos.x -= (d - lim) * nx; pos.z -= (d - lim) * nz; hit = true; }
  }
  return hit;
}
export function cageDist(pos) {
  let m = 1e9;
  for (const [nx, nz] of OCT_NORMALS) m = Math.min(m, CAGE_APOTHEM - (pos.x * nx + pos.z * nz));
  return m;
}

export class World {
  constructor(container) {
    this.container = container;
    this.renderer = new THREE.WebGLRenderer({ antialias: false, powerPreference: 'high-performance', preserveDrawingBuffer: false });
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.BasicShadowMap; // jaggy potato shadows
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.4;
    this.potato = 0.75;
    container.appendChild(this.renderer.domElement);
    this.renderer.domElement.className = 'game-canvas';
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color('#1b1d26');
    this.scene.fog = new THREE.Fog('#1b1d26', 16, 44);
    this.camera = new THREE.PerspectiveCamera(50, 1, 0.05, 120);
    this.camera.position.set(0, 2.2, 6);
    this.buildLights();
    this.buildArena();
    this.buildCrowd();
    this.cam = { mode: 'broadcast', pos: new THREE.Vector3(0, 2, 6), look: new THREE.Vector3(0, 1, 0), side: 1, shake: 0, orbitYaw: 0.6, orbitPitch: 0.35, orbitDist: 6, fov: 50 };
    this.resize();
    window.addEventListener('resize', () => this.resize());
    this.t = 0;
  }

  setPotato(v) { this.potato = v; this.resize(); }
  setBrightness(v) {
    this.renderer.toneMappingExposure = v;
    if (this.hemi) this.hemi.intensity = 1.0 + (v - 1) * 0.9;
  }
  resize() {
    const w = this.container.clientWidth || window.innerWidth, h = this.container.clientHeight || window.innerHeight;
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5) * this.potato);
    this.renderer.setSize(w, h, true);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  buildLights() {
    const s = this.scene;
    this.hemi = new THREE.HemisphereLight('#c4c9dc', '#5a4c40', 1.45);
    s.add(this.hemi);
    // arena house lights so the crowd and stands are readable
    const house = new THREE.PointLight('#ffe2c0', 60, 40, 1.4); house.position.set(0, 14, 0); s.add(house);
    // fill light that follows the camera (broadcast lighting on the cage)
    this.fill = new THREE.DirectionalLight('#fff0e0', 1.25);
    s.add(this.fill); s.add(this.fill.target);
    const key = new THREE.DirectionalLight('#fff4e0', 2.6);
    key.position.set(1.5, 12, 2.5);
    key.castShadow = true;
    key.shadow.mapSize.set(1024, 1024);
    const sc = key.shadow.camera; sc.left = -6; sc.right = 6; sc.top = 6; sc.bottom = -6; sc.near = 2; sc.far = 25;
    key.shadow.bias = -0.002;
    s.add(key);
    const rim1 = new THREE.DirectionalLight('#6fa0ff', 0.6); rim1.position.set(-8, 5, -6); s.add(rim1);
    const rim2 = new THREE.DirectionalLight('#ffb070', 0.45); rim2.position.set(8, 4, 6); s.add(rim2);
    this.keyLight = key;
  }

  buildArena() {
    const s = this.scene;
    // --- mat texture
    const N = 2048;
    this.matCanvas = mkCanvas(N, N);
    this.drawMat(this.matCanvas.getContext('2d'), N, 'APEX');
    this.matTex = new THREE.CanvasTexture(this.matCanvas);
    this.matTex.colorSpace = THREE.SRGBColorSpace;
    this.matTex.anisotropy = 4;
    const floor = new THREE.Mesh(new THREE.PlaneGeometry(MAT_SIZE, MAT_SIZE), new THREE.MeshLambertMaterial({ map: this.matTex }));
    floor.rotation.x = -Math.PI / 2;
    floor.receiveShadow = true;
    s.add(floor);
    // blood stain layer (transparent, darkens over time)
    const SN = 2048;
    this.stainCanvas = mkCanvas(SN, SN);
    this.sctx = this.stainCanvas.getContext('2d');
    this.stainTex = new THREE.CanvasTexture(this.stainCanvas);
    this.stainTex.colorSpace = THREE.SRGBColorSpace;
    const stain = new THREE.Mesh(new THREE.PlaneGeometry(MAT_SIZE, MAT_SIZE), new THREE.MeshPhongMaterial({ map: this.stainTex, transparent: true, depthWrite: false, shininess: 60, specular: new THREE.Color('#402020') }));
    stain.rotation.x = -Math.PI / 2; stain.position.y = 0.004; stain.receiveShadow = true;
    s.add(stain);
    this.stainDirty = false; this.stainAge = 0;
    // apron / platform outside cage
    const plat = new THREE.Mesh(new THREE.CylinderGeometry(6.4, 6.6, 1.0, 8, 1), new THREE.MeshLambertMaterial({ color: '#2b2d38', flatShading: true }));
    plat.position.y = -0.52; plat.rotation.y = Math.PI / 8; plat.receiveShadow = true;
    s.add(plat);
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(80, 80), new THREE.MeshLambertMaterial({ color: '#23252e' }));
    ground.rotation.x = -Math.PI / 2; ground.position.y = -1.0; s.add(ground);
    // --- cage fence
    const fence = mkCanvas(128, 128), fc = fence.getContext('2d');
    fc.clearRect(0, 0, 128, 128); fc.strokeStyle = 'rgba(30,30,34,1)'; fc.lineWidth = 3;
    for (let i = -128; i < 256; i += 32) { fc.beginPath(); fc.moveTo(i, 0); fc.lineTo(i + 128, 128); fc.stroke(); fc.beginPath(); fc.moveTo(i + 128, 0); fc.lineTo(i, 128); fc.stroke(); }
    const fenceTex = new THREE.CanvasTexture(fence);
    fenceTex.wrapS = fenceTex.wrapT = THREE.RepeatWrapping;
    const circR = CAGE_APOTHEM / Math.cos(Math.PI / OCT_N);
    const side = 2 * CAGE_APOTHEM * Math.tan(Math.PI / OCT_N);
    fenceTex.repeat.set(side / 0.18, 1.75 / 0.18);
    const fenceM = new THREE.MeshLambertMaterial({ map: fenceTex, transparent: true, alphaTest: 0.3, side: THREE.DoubleSide });
    const padM = new THREE.MeshLambertMaterial({ color: '#111114', flatShading: true });
    const postM = new THREE.MeshLambertMaterial({ color: '#202026', flatShading: true });
    const logoM = new THREE.MeshLambertMaterial({ color: '#a01818', flatShading: true });
    for (let k = 0; k < OCT_N; k++) {
      const a = (k / OCT_N) * Math.PI * 2 + Math.PI / 8;
      const g = new THREE.Group();
      g.position.set(Math.cos(a) * (CAGE_APOTHEM + 0.03), 0, Math.sin(a) * (CAGE_APOTHEM + 0.03));
      g.rotation.y = -a + Math.PI / 2;
      const panel = new THREE.Mesh(new THREE.PlaneGeometry(side, 1.75), fenceM);
      panel.position.y = 0.32 + 0.875; g.add(panel);
      this.fencePanels = this.fencePanels || [];
      this.fencePanels.push({ mesh: panel, nx: Math.cos(a), nz: Math.sin(a) });
      const pad = new THREE.Mesh(new THREE.BoxGeometry(side, 0.32, 0.14), padM); pad.position.y = 0.16; pad.receiveShadow = true; g.add(pad);
      const bannerC = mkCanvas(256, 32), bctx = bannerC.getContext('2d');
      bctx.fillStyle = '#121216'; bctx.fillRect(0, 0, 256, 32); bctx.fillStyle = ['#b01b1b', '#d8d8d8', '#c9a227'][k % 3];
      bctx.font = 'bold 22px Arial'; bctx.textAlign = 'center'; bctx.fillText(['APEX FC', 'IRONCLAD ENERGY', 'KRAKEN GEAR', 'FIGHT PASS+', 'APEX FC', 'MUAY CORP', 'BLACKTOP', 'RIOT BEER'][k], 128, 24);
      const bt = new THREE.CanvasTexture(bannerC); bt.colorSpace = THREE.SRGBColorSpace;
      const banner = new THREE.Mesh(new THREE.PlaneGeometry(side * 0.9, 0.22), new THREE.MeshBasicMaterial({ map: bt }));
      banner.position.set(0, 0.16, -0.075); banner.rotation.y = Math.PI; g.add(banner);
      const rail = new THREE.Mesh(new THREE.BoxGeometry(side, 0.12, 0.14), padM); rail.position.y = 0.32 + 1.75; g.add(rail);
      s.add(g);
      const pa = (k / OCT_N) * Math.PI * 2;
      const post = new THREE.Mesh(new THREE.BoxGeometry(0.16, 2.2, 0.16), postM);
      post.position.set(Math.cos(pa) * (circR + 0.05), 1.1, Math.sin(pa) * (circR + 0.05));
      post.castShadow = true; s.add(post);
      this.fencePanels.push({ mesh: post, nx: Math.cos(pa), nz: Math.sin(pa), post: true });
      const cap = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.12, 0.2), logoM); cap.position.copy(post.position); cap.position.y = 2.25; s.add(cap);
    }
    // overhead light rig
    const rig = new THREE.Mesh(new THREE.CylinderGeometry(3.2, 3.2, 0.25, 8, 1, true), new THREE.MeshBasicMaterial({ color: '#1a1a1a', side: THREE.DoubleSide }));
    rig.position.y = 8.5; s.add(rig);
    for (let k = 0; k < 8; k++) {
      const a = (k / 8) * Math.PI * 2;
      const l = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.15, 0.5), new THREE.MeshBasicMaterial({ color: '#fff8e0' }));
      l.position.set(Math.cos(a) * 3.2, 8.4, Math.sin(a) * 3.2); s.add(l);
    }
  }

  drawMat(ctx, N, brand) {
    const px = N / MAT_SIZE;
    ctx.fillStyle = '#d9d6cf'; ctx.fillRect(0, 0, N, N);
    const r = makeRng(42);
    // canvas weave noise
    for (let i = 0; i < 26000; i++) { ctx.fillStyle = r() < 0.5 ? 'rgba(0,0,0,0.035)' : 'rgba(255,255,255,0.05)'; ctx.fillRect(r() * N, r() * N, 3, 3); }
    // scuffs from old fights (realism: mat is never pristine)
    for (let i = 0; i < 70; i++) { ctx.fillStyle = `rgba(90,80,70,${0.02 + r() * 0.04})`; ctx.beginPath(); ctx.ellipse(r() * N, r() * N, 10 + r() * 60, 5 + r() * 20, r() * 3, 0, 6.28); ctx.fill(); }
    // octagon border
    const c = N / 2;
    ctx.save(); ctx.translate(c, c);
    ctx.strokeStyle = '#1b1b1f'; ctx.lineWidth = 0.55 * px;
    const circR = (CAGE_APOTHEM / Math.cos(Math.PI / 8)) * px;
    ctx.beginPath();
    for (let k = 0; k <= 8; k++) { const a = (k / 8) * Math.PI * 2; ctx.lineTo(Math.cos(a) * (circR + 0.0 * px), Math.sin(a) * (circR)); }
    ctx.stroke();
    // center logo
    ctx.rotate(-Math.PI / 2 * 0);
    ctx.fillStyle = 'rgba(160,20,20,0.85)';
    ctx.font = `900 ${Math.round(0.9 * px)}px Arial Black, Arial, sans-serif`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(brand, 0, 0);
    ctx.strokeStyle = 'rgba(20,20,20,0.75)'; ctx.lineWidth = 0.05 * px; ctx.strokeText(brand, 0, 0);
    ctx.font = `700 ${Math.round(0.22 * px)}px Arial`; ctx.fillStyle = 'rgba(25,25,25,0.7)';
    ctx.fillText('FIGHTING CHAMPIONSHIP', 0, 0.62 * px);
    // sponsor decals
    const sp = ['KRAKEN', 'IRONCLAD', 'RIOT', 'BLACKTOP'];
    for (let k = 0; k < 4; k++) {
      const a = (k / 4) * Math.PI * 2 + Math.PI / 4;
      ctx.save(); ctx.rotate(a); ctx.translate(0, -2.7 * px);
      ctx.fillStyle = 'rgba(20,30,90,0.55)'; ctx.font = `800 ${Math.round(0.4 * px)}px Arial`; ctx.fillText(sp[k], 0, 0);
      ctx.restore();
    }
    ctx.restore();
  }
  setBrand(brand) { this.drawMat(this.matCanvas.getContext('2d'), this.matCanvas.width, brand); this.matTex.needsUpdate = true; }

  // world xz -> stain canvas px
  stainPx(x, z) {
    const N = this.stainCanvas.width;
    return [(x / MAT_SIZE + 0.5) * N, (z / MAT_SIZE + 0.5) * N];
  }
  // Bloodstain pattern: elongation = 1/sin(impact angle), tail points in travel direction,
  // satellite spatter for fast drops, darker rim (drying edge)
  addStain(x, z, vel, volume) {
    const ctx = this.sctx, N = this.stainCanvas.width, pxm = N / MAT_SIZE;
    const [cx, cy] = this.stainPx(x, z);
    const speed = vel.length();
    const hz = Math.hypot(vel.x, vel.z);
    const ang = Math.atan2(Math.abs(vel.y), hz); // impact angle vs floor
    const sinA = clamp(Math.sin(ang), 0.15, 1);
    const dropD = Math.cbrt(volume * 6 / Math.PI) * 0.01; // meters (volume in ml)
    // drops flatten on impact: spread factor grows with impact speed (Weber number)
    const spread = 2.2 + Math.min(speed, 10) * 0.28;
    const w = Math.max(1.6, dropD * spread * pxm * 0.5);
    const L = w / sinA;
    const dir = Math.atan2(vel.z, vel.x);
    ctx.save(); ctx.translate(cx, cy); ctx.rotate(dir);
    const g = ctx.createRadialGradient(0, 0, w * 0.2, 0, 0, Math.max(w, L));
    g.addColorStop(0, 'rgba(120,4,8,0.95)'); g.addColorStop(0.75, 'rgba(105,2,6,0.95)'); g.addColorStop(1, 'rgba(70,0,4,0.95)');
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.ellipse(0, 0, L, w, 0, 0, Math.PI * 2); ctx.fill();
    // directional tail / wave castoff
    if (sinA < 0.8 && w > 1.5) {
      ctx.fillStyle = 'rgba(110,3,7,0.9)';
      ctx.beginPath(); ctx.ellipse(L * 1.25, 0, w * 0.5, w * 0.28, 0, 0, 6.28); ctx.fill();
    }
    ctx.restore();
    // satellites
    if (speed > 3.5) {
      const n = Math.min(8, Math.floor(speed * 0.8 * Math.random()));
      for (let i = 0; i < n; i++) {
        const a = dir + (Math.random() - 0.5) * 1.6, d = (L + Math.random() * L * 2.5);
        ctx.fillStyle = 'rgba(115,4,8,0.9)';
        ctx.beginPath(); ctx.arc(cx + Math.cos(a) * d, cy + Math.sin(a) * d, Math.max(0.6, w * (0.12 + Math.random() * 0.2)), 0, 6.28); ctx.fill();
      }
    }
    this.stainDirty = true;
  }
  // body dragging through blood smears it
  smearStain(x, z, dx, dz, radiusM = 0.12) {
    const ctx = this.sctx, N = this.stainCanvas.width, pxm = N / MAT_SIZE;
    const [cx, cy] = this.stainPx(x, z);
    const R = radiusM * pxm, ox = dx * pxm, oy = dz * pxm;
    if (Math.abs(ox) + Math.abs(oy) < 0.5) return;
    ctx.save(); ctx.globalAlpha = 0.45;
    ctx.beginPath(); ctx.arc(cx + ox, cy + oy, R, 0, 6.28); ctx.clip();
    ctx.drawImage(this.stainCanvas, cx - R, cy - R, R * 2, R * 2, cx - R + ox, cy - R + oy, R * 2, R * 2);
    ctx.restore();
    this.stainDirty = true;
  }
  cleanMat() { this.sctx.clearRect(0, 0, this.stainCanvas.width, this.stainCanvas.height); this.stainTex.needsUpdate = true; }
  // partial clean between rounds (towel + water - leaves faint brown marks)
  wipeMat() {
    const c = this.sctx;
    c.save(); c.globalCompositeOperation = 'destination-out'; c.fillStyle = 'rgba(0,0,0,0.55)'; c.fillRect(0, 0, c.canvas.width, c.canvas.height); c.restore();
    this.stainDirty = true;
  }

  buildCrowd() {
    const r = makeRng(99);
    const seats = [];
    for (let ring = 0; ring < 14; ring++) {
      const rad = 7.2 + ring * 0.85;
      const n = Math.floor(rad * 6.3);
      for (let i = 0; i < n; i++) {
        const a = (i / n) * Math.PI * 2 + r() * 0.03;
        if (r() < 0.06) continue;
        seats.push([Math.cos(a) * rad, ring * 0.45 - 0.6, Math.sin(a) * rad, a]);
      }
    }
    const bodyG = new THREE.BoxGeometry(0.42, 0.55, 0.3); bodyG.translate(0, 0.27, 0);
    const headG = new THREE.BoxGeometry(0.2, 0.22, 0.2); headG.translate(0, 0.66, 0);
    const mat = new THREE.MeshLambertMaterial({ flatShading: true });
    this.crowdBody = new THREE.InstancedMesh(bodyG, mat, seats.length);
    this.crowdHead = new THREE.InstancedMesh(headG, new THREE.MeshLambertMaterial({ flatShading: true }), seats.length);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), col = new THREE.Color();
    const shirt = ['#3a3a44', '#55555f', '#7a3030', '#30487a', '#e0e0e0', '#6a6a3a', '#8a5030', '#222228', '#4a4a52', '#8a8a8a', '#b02828', '#2a6a4a'];
    const skins = ['#f3d2b5', '#d8a47f', '#a8704b', '#6e432a', '#e8bd98'];
    seats.forEach(([x, y, z, a], i) => {
      q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), -a - Math.PI / 2);
      m.compose(new THREE.Vector3(x, y, z), q, new THREE.Vector3(1, 1, 1));
      this.crowdBody.setMatrixAt(i, m); this.crowdHead.setMatrixAt(i, m);
      this.crowdBody.setColorAt(i, col.set(shirt[Math.floor(r() * shirt.length)]));
      this.crowdHead.setColorAt(i, col.set(skins[Math.floor(r() * skins.length)]));
    });
    this.seats = seats;
    this.scene.add(this.crowdBody, this.crowdHead);
    // tiers
    for (let ring = 0; ring < 14; ring++) {
      const t = new THREE.Mesh(new THREE.CylinderGeometry(7.2 + ring * 0.85 + 0.45, 7.2 + ring * 0.85 + 0.45, 0.45, 24, 1, true), new THREE.MeshLambertMaterial({ color: ring % 2 ? '#2a2c38' : '#323544', side: THREE.DoubleSide }));
      t.position.y = ring * 0.45 - 0.82; this.scene.add(t);
    }
    this.crowdHype = 0.2; this.crowdT = 0;
  }
  animateCrowd(dt) {
    this.crowdT += dt;
    if (this.crowdT < 0.08) return;
    this.crowdT = 0;
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), p = new THREE.Vector3(), one = new THREE.Vector3(1, 1, 1);
    const hype = this.crowdHype, t = performance.now() / 1000;
    const n = this.seats.length;
    // update a subset each tick for performance
    const step = 3, off = Math.floor(t * 20) % step;
    for (let i = off; i < n; i += step) {
      const [x, y, z, a] = this.seats[i];
      const jump = hype > 0.5 ? Math.max(0, Math.sin(t * 9 + i * 1.7)) * 0.18 * hype : Math.sin(t * 2 + i) * 0.01;
      const stand = hype > 0.75 && (i % 3 === 0) ? 0.25 : 0;
      q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), -a - Math.PI / 2);
      p.set(x, y + jump + stand, z);
      m.compose(p, q, one);
      this.crowdBody.setMatrixAt(i, m); this.crowdHead.setMatrixAt(i, m);
    }
    this.crowdBody.instanceMatrix.needsUpdate = true; this.crowdHead.instanceMatrix.needsUpdate = true;
  }

  // --- camera ---
  updateCamera(dt, a, b, opts = {}) {
    const cam = this.cam;
    if (cam.mode === 'orbit') {
      const tgt = opts.focus || new THREE.Vector3(0, 1, 0);
      cam.look.lerp(tgt, 1 - Math.exp(-6 * dt));
      const cp = Math.cos(cam.orbitPitch);
      const want = new THREE.Vector3(Math.sin(cam.orbitYaw) * cp, Math.sin(cam.orbitPitch), Math.cos(cam.orbitYaw) * cp).multiplyScalar(cam.orbitDist).add(cam.look);
      cam.pos.lerp(want, 1 - Math.exp(-10 * dt));
    } else if (cam.mode === 'fixed') {
      // test / photo mode: camera set externally
    } else if (cam.mode === 'replay' && opts.replayCam) {
      cam.pos.copy(opts.replayCam.pos); cam.look.copy(opts.replayCam.look);
    } else {
      const mid = new THREE.Vector3().addVectors(a, b).multiplyScalar(0.5);
      const axis = new THREE.Vector3().subVectors(b, a); axis.y = 0;
      const sep = axis.length();
      if (sep > 1e-3) axis.divideScalar(sep); else axis.set(1, 0, 0);
      const perp = new THREE.Vector3(-axis.z, 0, axis.x);
      // keep the camera on the same side as last frame (no 180 flips)
      const curDir = new THREE.Vector3().subVectors(cam.pos, mid); curDir.y = 0;
      if (curDir.dot(perp) < 0) perp.negate();
      // bias camera away from the cage wall
      const ground = opts.ground;
      const dist = (ground ? 2.3 : 3.1) + sep * (ground ? 0.4 : 0.75) + (opts.zoom || 0);
      const h = ground ? 1.25 : 1.75;
      let want = mid.clone().addScaledVector(perp, dist); want.y = h;
      // If camera would be far outside cage, swing it along fight line
      const wr = Math.hypot(want.x, want.z);
      if (wr > 6.5) { want.multiplyScalar(6.5 / wr); want.y = h + 0.6; }
      // player-side bias: show more of opponent
      if (opts.playerPos) {
        const toP = new THREE.Vector3().subVectors(opts.playerPos, mid); toP.y = 0;
        want.addScaledVector(toP, -0.25);
      }
      const k = 1 - Math.exp(-3.2 * dt);
      cam.pos.lerp(want, k);
      const lookT = mid.clone(); lookT.y = ground ? 0.55 : 1.15;
      cam.look.lerp(lookT, 1 - Math.exp(-6 * dt));
    }
    this.camera.position.copy(cam.pos);
    if (cam.shake > 0.001) {
      const s = cam.shake;
      this.camera.position.x += (Math.random() - 0.5) * s * 0.12;
      this.camera.position.y += (Math.random() - 0.5) * s * 0.12;
      cam.shake *= Math.exp(-dt * 9);
    }
    this.camera.lookAt(cam.look);
    this.fill.position.copy(this.camera.position).add(new THREE.Vector3(0, 2, 0));
    this.fill.target.position.copy(cam.look);
    // hide fence panels between the camera and the action (broadcast-style see-through cage)
    if (this.fencePanels) for (const fp of this.fencePanels) {
      const d = this.camera.position.x * fp.nx + this.camera.position.z * fp.nz;
      fp.mesh.visible = d < (fp.post ? CAGE_APOTHEM * 1.02 : CAGE_APOTHEM - 0.2);
    }
    const tf = opts.fov || 50;
    if (Math.abs(this.camera.fov - tf) > 0.1) { this.camera.fov = lerp(this.camera.fov, tf, 1 - Math.exp(-4 * dt)); this.camera.updateProjectionMatrix(); }
  }

  render(dt) {
    this.t += dt;
    this.stainAge += dt;
    if (this.stainAge > 2) {
      this.stainAge = 0;
      const c = this.sctx;
      c.save(); c.globalCompositeOperation = 'source-atop'; c.fillStyle = 'rgba(50,16,6,0.025)'; c.fillRect(0, 0, c.canvas.width, c.canvas.height); c.restore();
      this.stainDirty = true;
    }
    if (this.stainDirty) { this.stainTex.needsUpdate = true; this.stainDirty = false; }
    this.animateCrowd(dt);
    this.renderer.render(this.scene, this.camera);
  }
}
