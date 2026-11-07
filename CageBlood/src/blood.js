// ===== Blood & sweat particle system =====
// Droplets are simulated ballistically (gravity + quadratic air drag scaled by drop size; blood density ~1.06 g/cm3).
// On landing they leave stains whose elongation follows the bloodstain-pattern rule width/length = sin(impact angle),
// with satellite spatter for fast drops. Drops hitting a fighter are painted onto their face/torso canvases and run
// down with gravity. Stains darken (oxidize) over time and get smeared by bodies rolling through them.
import * as THREE from 'three';
import { clamp } from './util.js';
import { cageDist } from './render.js';

const MAX = 1600;
const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _s = new THREE.Vector3(), _up = new THREE.Vector3(0, 1, 0), _v = new THREE.Vector3();

export class BloodSystem {
  constructor(world) {
    this.world = world;
    this.gore = 1; // settings multiplier (0 = off)
    const geo = new THREE.IcosahedronGeometry(1, 0);
    this.mat = new THREE.MeshPhongMaterial({ color: '#6e0005', shininess: 90, specular: new THREE.Color('#5a2020'), flatShading: true });
    this.mesh = new THREE.InstancedMesh(geo, this.mat, MAX);
    this.mesh.count = 0; this.mesh.frustumCulled = false;
    world.scene.add(this.mesh);
    this.sweatMat = new THREE.MeshPhongMaterial({ color: '#cfd8e0', transparent: true, opacity: 0.55, shininess: 120, flatShading: true });
    this.sweatMesh = new THREE.InstancedMesh(geo, this.sweatMat, 500);
    this.sweatMesh.count = 0; this.sweatMesh.frustumCulled = false;
    world.scene.add(this.sweatMesh);
    this.parts = [];
    this.sweat = [];
  }

  // vol in ml (a single drop is ~0.05 ml)
  spawn(pos, vel, vol, kind = 'blood') {
    if (kind === 'blood' && this.gore <= 0) return;
    const list = kind === 'blood' ? this.parts : this.sweat;
    const cap = kind === 'blood' ? MAX : 500;
    if (list.length >= cap) list.shift();
    const r = Math.cbrt((vol * 3) / (4 * Math.PI)) * 0.01; // ml -> cm3 -> radius in m
    list.push({ p: pos.clone(), v: vel.clone(), vol, r: clamp(r, 0.0012, 0.012), life: 0, kind, owner: null });
  }

  // a spray of droplets in a cone around dir
  spray(pos, dir, n, speed, spread, totalVol, kind = 'blood') {
    if (kind === 'blood') { n = Math.round(n * this.gore); totalVol *= this.gore; }
    if (n <= 0) return;
    const per = totalVol / n;
    for (let i = 0; i < n; i++) {
      _v.set((Math.random() - 0.5) * 2, (Math.random() - 0.3) * 2, (Math.random() - 0.5) * 2).multiplyScalar(spread).add(dir).normalize();
      const sp = speed * (0.35 + Math.random() * 0.9);
      const vol = per * (0.2 + Math.random() * 1.8);
      this.spawn(pos.clone().addScaledVector(_v, 0.01), _v.clone().multiplyScalar(sp), vol, kind);
    }
  }

  update(dt, fighters) {
    const world = this.world;
    for (const list of [this.parts, this.sweat]) {
      for (let i = list.length - 1; i >= 0; i--) {
        const d = list[i];
        d.life += dt;
        // quadratic drag: small drops slow faster (k ~ 1/r)
        const sp = d.v.length();
        const drag = (0.00045 / Math.max(d.r, 0.001)) * sp;
        d.v.multiplyScalar(Math.max(0, 1 - drag * dt));
        d.v.y -= 9.81 * dt;
        d.p.addScaledVector(d.v, dt);
        let remove = false;
        // hit fighters (paint onto skin)
        if (d.life > 0.03 && fighters) {
          for (const f of fighters) {
            if (f.paintBlood && f.paintBlood(d.p, d.vol, d.kind, d.v)) { remove = true; break; }
          }
        }
        if (!remove && d.p.y <= 0.004) {
          if (d.kind === 'blood' && cageDist(d.p) > 0) world.addStain(d.p.x, d.p.z, d.v, d.vol);
          remove = true;
        }
        if (!remove && (d.life > 6 || cageDist(d.p) < -0.05)) remove = true;
        if (remove) list.splice(i, 1);
      }
    }
    // write instances (stretch along velocity: liquid drops elongate in flight)
    const writeList = (list, mesh) => {
      const n = Math.min(list.length, mesh.instanceMatrix.count);
      for (let i = 0; i < n; i++) {
        const d = list[i];
        const sp = d.v.length();
        const st = 1 + Math.min(sp * 0.12, 1.8);
        if (sp > 0.01) _q.setFromUnitVectors(_up, _v.copy(d.v).divideScalar(sp)); else _q.identity();
        _s.set(d.r, d.r * st, d.r);
        _m.compose(d.p, _q, _s);
        mesh.setMatrixAt(i, _m);
      }
      mesh.count = n;
      mesh.instanceMatrix.needsUpdate = true;
    };
    writeList(this.parts, this.mesh);
    writeList(this.sweat, this.sweatMesh);
  }

  clear() { this.parts.length = 0; this.sweat.length = 0; this.mesh.count = 0; this.sweatMesh.count = 0; }
}
