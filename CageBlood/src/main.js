// ===== Entry =====
import { World } from './render.js';
import { BloodSystem } from './blood.js';
import { Audio } from './audio.js';
import { Keys } from './input.js';
import { HUD } from './hud.js';
import { FightScene } from './fight.js';
import { makeNPC } from './npc.js';
import { UI } from './ui.js';
import { loadSave } from './save.js';
import { Preview } from './preview.js';

class App {
  constructor() {
    this.view = document.getElementById('view3d');
    this.uiRoot = document.getElementById('ui');
    this.world = new World(this.view);
    this.blood = new BloodSystem(this.world);
    this.audio = new Audio();
    this.keys = new Keys();
    this.hud = new HUD(this.uiRoot);
    this.save = loadSave();
    this.applySettings();
    this.scene = null;
    this.warp = Number(new URLSearchParams(location.search).get('warp') || 0);
    this.last = performance.now();
    this.preview = new Preview(this);
    this.ui = new UI(this);
    const kick = () => { this.audio.init(); this.audio.resume(); };
    window.addEventListener('pointerdown', kick); window.addEventListener('keydown', kick);
    requestAnimationFrame((t) => this.loop(t));
    this.ui.boot();
  }
  applySettings() {
    const s = this.save.settings;
    this.world.setPotato(s.potato);
    this.blood.gore = s.gore;
    this.audio.setVolume(s.volume);
  }
  startFight(opts) {
    if (this.scene) this.scene.dispose();
    this.preview.clear();
    this.scene = new FightScene(this, { settings: this.save.settings, clockScale: this.save.settings.clockScale, ...opts });
    this.hud.show(!opts.background);
    return this.scene;
  }
  endScene() {
    if (this.scene) { this.scene.dispose(); this.scene = null; }
    this.hud.show(false);
  }
  onFightEnd(scene) { this.ui.onFightEnd(scene); }
  showCorner(scene, card) { this.ui.showCorner(scene, card); }
  loop(t) {
    const dt = Math.min(0.1, (t - this.last) / 1000);
    this.last = t;
    try {
      if (this.preview.f) this.preview.update(dt);
      else if (this.scene && this.warp) { for (let i = 0; i < this.warp; i++) this.scene.update(1 / 60, i === this.warp - 1); }
      else if (this.scene) this.scene.update(dt);
      else { this.world.cam.mode = 'orbit'; this.world.cam.orbitYaw += dt * 0.1; this.world.updateCamera(dt, null, null, {}); this.world.render(dt); }
      this.ui.frame(dt);
    } catch (e) {
      console.error(e);
      this.ui.error && this.ui.error(e);
    }
    requestAnimationFrame((tt) => this.loop(tt));
  }
}

const boot = () => { if (!window.__game) window.__game = new App(); };
if (document.readyState === 'loading') window.addEventListener('DOMContentLoaded', boot); else boot();
export { makeNPC };
