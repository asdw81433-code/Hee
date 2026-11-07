// ===== Synthesized audio (no asset files) =====
export class Audio {
  constructor() {
    this.ctx = null; this.vol = 0.8; this.crowdGain = null; this.enabled = true;
  }
  init() {
    if (this.ctx) return;
    try {
      this.ctx = new (window.AudioContext || window.webkitAudioContext)();
    } catch (e) { this.enabled = false; return; }
    const c = this.ctx;
    this.master = c.createGain(); this.master.gain.value = this.vol; this.master.connect(c.destination);
    // noise buffer
    const len = c.sampleRate * 2;
    this.noise = c.createBuffer(1, len, c.sampleRate);
    const d = this.noise.getChannelData(0);
    let b0 = 0, b1 = 0, b2 = 0;
    for (let i = 0; i < len; i++) { const w = Math.random() * 2 - 1; b0 = 0.997 * b0 + w * 0.029; b1 = 0.985 * b1 + w * 0.032; b2 = 0.95 * b2 + w * 0.048; d[i] = (b0 + b1 + b2 + w * 0.04) * 0.9; }
    this.white = c.createBuffer(1, c.sampleRate, c.sampleRate);
    const w = this.white.getChannelData(0); for (let i = 0; i < w.length; i++) w[i] = Math.random() * 2 - 1;
    // crowd bed
    const src = c.createBufferSource(); src.buffer = this.noise; src.loop = true;
    const bp = c.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 700; bp.Q.value = 0.6;
    const bp2 = c.createBiquadFilter(); bp2.type = 'peaking'; bp2.frequency.value = 1400; bp2.gain.value = 6;
    this.crowdGain = c.createGain(); this.crowdGain.gain.value = 0.05;
    src.connect(bp); bp.connect(bp2); bp2.connect(this.crowdGain); this.crowdGain.connect(this.master);
    src.start();
    this.crowdFilter = bp;
  }
  resume() { if (this.ctx && this.ctx.state === 'suspended') this.ctx.resume(); }
  setVolume(v) { this.vol = v; if (this.master) this.master.gain.value = v; }
  crowd(level) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.crowdGain.gain.setTargetAtTime(0.03 + level * 0.22, t, 0.4);
    this.crowdFilter.frequency.setTargetAtTime(600 + level * 900, t, 0.5);
  }
  _noise(dur, type, freq, q, gain, t0 = 0, buf) {
    const c = this.ctx, t = c.currentTime + t0;
    const s = c.createBufferSource(); s.buffer = buf || this.white;
    const f = c.createBiquadFilter(); f.type = type; f.frequency.value = freq; f.Q.value = q;
    const g = c.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(gain, t + 0.004); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    s.connect(f); f.connect(g); g.connect(this.master);
    s.start(t, Math.random() * 0.5); s.stop(t + dur + 0.05);
    return f;
  }
  _tone(freq, dur, gain, type = 'sine', t0 = 0, slide = 0) {
    const c = this.ctx, t = c.currentTime + t0;
    const o = c.createOscillator(); o.type = type; o.frequency.setValueAtTime(freq, t);
    if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(20, freq * slide), t + dur);
    const g = c.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(gain, t + 0.005); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g); g.connect(this.master); o.start(t); o.stop(t + dur + 0.05);
  }
  impact(zone, power, blocked) {
    if (!this.ctx) return;
    const p = Math.min(power, 2);
    if (blocked) { this._noise(0.08, 'lowpass', 900, 1, 0.25 + p * 0.15); this._tone(110, 0.08, 0.2, 'sine', 0, 0.6); return; }
    if (zone === 'head') {
      this._noise(0.06, 'highpass', 1800, 0.7, 0.35 + p * 0.3); // leather slap
      this._noise(0.14, 'lowpass', 500, 1, 0.3 + p * 0.35);
      this._tone(90 + Math.random() * 20, 0.16, 0.35 + p * 0.3, 'sine', 0, 0.5); // bone thud
    } else if (zone === 'body') {
      this._noise(0.18, 'lowpass', 320, 1.2, 0.45 + p * 0.3);
      this._tone(70, 0.2, 0.45 + p * 0.3, 'sine', 0, 0.55);
      this._noise(0.05, 'bandpass', 1200, 1, 0.15);
    } else {
      this._noise(0.07, 'bandpass', 1500, 0.8, 0.45 + p * 0.3); // shin on thigh slap
      this._tone(120, 0.12, 0.25 + p * 0.2, 'triangle', 0, 0.6);
    }
  }
  whoosh(kind) {
    if (!this.ctx) return;
    const f = this._noise(kind === 'kick' ? 0.22 : 0.13, 'bandpass', kind === 'kick' ? 500 : 900, 1.5, kind === 'kick' ? 0.12 : 0.07);
    f.frequency.exponentialRampToValueAtTime(kind === 'kick' ? 1500 : 2200, this.ctx.currentTime + 0.12);
  }
  exhale() { if (this.ctx) this._noise(0.09, 'bandpass', 3800, 2, 0.05); }
  step() { if (this.ctx && Math.random() < 0.35) this._noise(0.03, 'bandpass', 3000 + Math.random() * 2000, 4, 0.03); }
  slam() { if (!this.ctx) return; this._tone(55, 0.35, 0.7, 'sine', 0, 0.5); this._noise(0.3, 'lowpass', 250, 1, 0.6, 0, this.noise); this._noise(0.15, 'bandpass', 600, 1, 0.2); }
  cage() { if (!this.ctx) return; this._noise(0.4, 'bandpass', 2500, 6, 0.12); this._tone(400, 0.3, 0.05, 'square', 0, 0.9); }
  bell(n = 1) {
    if (!this.ctx) return;
    for (let k = 0; k < n; k++) for (const [f, g] of [[880, 0.3], [1320, 0.15], [2210, 0.1], [3020, 0.06]]) this._tone(f, 1.6, g, 'sine', k * 0.35);
  }
  roar() {
    if (!this.ctx) return;
    this._noise(2.5, 'bandpass', 900, 0.5, 0.5, 0, this.noise);
    this._noise(2.0, 'bandpass', 1600, 0.8, 0.25, 0.1, this.noise);
  }
  ooh() { if (!this.ctx) return; const f = this._noise(1.0, 'bandpass', 500, 3, 0.25, 0, this.noise); f.frequency.exponentialRampToValueAtTime(350, this.ctx.currentTime + 0.9); }
  ui() { if (this.ctx) this._tone(660, 0.06, 0.08, 'triangle'); }
}
