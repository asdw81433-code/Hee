// ===== 3D preview of a fighter (creator / menus): shadowboxing in the empty octagon =====
import * as THREE from 'three';
import { Fighter } from './fighter.js';
import { rng } from './util.js';

const SHADOW = ['jab', 'cross', 'leadHook', 'jab', 'rearLowKick', 'cross', 'leadUpper', 'rearBodyKick', 'teep', 'jab', 'rearHook'];

export class Preview {
  constructor(app) {
    this.app = app;
    this.f = null;
    this.t = 0; this.acc = 0; this.nextT = 1;
    this.angle = 0.4;
    this.offset = 0.55; // screen offset (UI panel on the left)
    this.shadowbox = true;
    this.zoom = 1;
    this.game = { world: app.world, blood: app.blood, emit: () => {}, onImpact: () => {}, grapple: null, match: null, time: 0, ragdollBase: 0.24 };
  }
  show(profile, faceCanvas) {
    this.clear();
    const prof = { ...profile, faceCanvas };
    this.f = new Fighter(this.game, prof, { gloveColor: '#141414', gloveTrim: '#8b1010' });
    this.f.placeAt(0, 0, 0);
    this.f.state = 'stand';
    this.app.world.cleanMat();
    this.app.blood.clear();
    return this.f;
  }
  clear() { if (this.f) { this.f.dispose(); this.f = null; } }
  update(dt) {
    const f = this.f; if (!f) return;
    this.t += dt;
    this.acc += Math.min(dt, 0.05);
    f.relaxed = this.zoom < 0.6;
    if (this.shadowbox && !f.relaxed && this.t > this.nextT && !f.action) {
      f.input.strike = SHADOW[Math.floor(rng() * SHADOW.length)];
      this.nextT = this.t + 0.6 + rng() * 1.2;
    }
    // light footwork in place
    f.input.mx = Math.sin(this.t * 0.7) * 0.25; f.input.mz = Math.sin(this.t * 0.45) * 0.2;
    // keep near center
    const r = f.rig.root; if (Math.hypot(r.x, r.z) > 0.6) { f.input.mx = -r.x; f.input.mz = -r.z; }
    while (this.acc > 1 / 240) { this.acc -= 1 / 240; this.game.time += 1 / 240; f.step(1 / 240); }
    f.rig.yaw = 0;
    f.frame(dt);
    const w = this.app.world, cam = w.cam;
    cam.mode = 'fixed';
    this.angle += dt * 0.15;
    const a = Math.sin(this.angle) * 0.6;
    const d = 2.6 * this.zoom * (this.offset < 0 ? 1.6 : 1);
    const focusY = this.zoom < 0.6 ? f.rig.headCenter.y : 1.05;
    cam.pos.set(r.x + Math.sin(a) * d, focusY + 0.25 * this.zoom, r.z + Math.cos(a) * d);
    // shift look target so the fighter sits on the right side of the screen
    const right = new THREE.Vector3(Math.cos(a), 0, -Math.sin(a));
    cam.look.set(r.x, focusY, r.z).addScaledVector(right, -this.offset * this.zoom);
    w.updateCamera(dt, r, r, {});
    w.render(dt);
  }
}
