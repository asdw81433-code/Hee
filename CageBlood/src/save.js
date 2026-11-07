// ===== Persistence (localStorage, guarded) =====
const KEY = 'cageblood_save_v1';
export const DEFAULT_SETTINGS = {
  potato: 0.75, brightness: 1.4, touch: 'auto', gore: 1, volume: 0.8, clockScale: 3, difficulty: 0.3, assist: 1, preset: 'easy', controls: 'simple', ragdoll: 'full', replay: true, refPatience: 0.5, showHints: true, settingsV: 2,
};

export function loadSave() {
  let s = null;
  try { s = JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { s = null; }
  if (!s || typeof s !== 'object') s = {};
  const fresh = !s.settings;
  s.settings = { ...DEFAULT_SETTINGS, ...(s.settings || {}) };
  // v2: the game got easier by default (simple controls, easy preset, shorter rounds) - apply to old saves too
  if ((s.settings.settingsV || 1) < 2) Object.assign(s.settings, { controls: 'simple', preset: 'easy', difficulty: 0.3, assist: 1, clockScale: Math.max(3, s.settings.clockScale || 3), settingsV: 2 });
  // phones/tablets: lighter default render scale
  if (fresh && typeof matchMedia !== 'undefined' && matchMedia('(pointer: coarse)').matches) s.settings.potato = 0.55;
  s.fighters = Array.isArray(s.fighters) ? s.fighters : [];
  s.career = s.career || null;
  return s;
}
export function writeSave(s) {
  try { localStorage.setItem(KEY, JSON.stringify(s)); return true; } catch (e) { console.warn('save failed', e); return false; }
}
export function exportSave(s) { return btoa(unescape(encodeURIComponent(JSON.stringify(s)))); }
export function importSave(str) { return JSON.parse(decodeURIComponent(escape(atob(str.trim())))); }

export const PRESETS = {
  easy: { difficulty: 0.3, assist: 1 },
  normal: { difficulty: 0.55, assist: 0.4 },
  hard: { difficulty: 0.75, assist: 0 },
  pro: { difficulty: 0.95, assist: 0 },
};
