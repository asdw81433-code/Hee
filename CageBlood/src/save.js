// ===== Persistence (localStorage, guarded) =====
const KEY = 'cageblood_save_v1';
export const DEFAULT_SETTINGS = {
  potato: 0.75, brightness: 1.4, touch: 'auto', gore: 1, volume: 0.8, clockScale: 2, difficulty: 0.6, replay: true, refPatience: 0.5, showHints: true,
};

export function loadSave() {
  let s = null;
  try { s = JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { s = null; }
  if (!s || typeof s !== 'object') s = {};
  const fresh = !s.settings;
  s.settings = { ...DEFAULT_SETTINGS, ...(s.settings || {}) };
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
