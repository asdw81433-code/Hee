// ===== Pictogram icon set (inline SVG, 24x24, stroke = currentColor) =====
const P = {
  fist: '<path d="M7 9V7.5a1.5 1.5 0 0 1 3 0V9M10 9V6.5a1.5 1.5 0 0 1 3 0V9M13 9V7a1.5 1.5 0 0 1 3 0v3M16 10V9a1.5 1.5 0 0 1 3 0v4a6 6 0 0 1-6 6h-2a6 6 0 0 1-6-6v-1a2 2 0 0 1 2-2h3"/>',
  jab: '<path d="M1 10h4M2 14h3"/><path d="M9 9V7.5a1.5 1.5 0 0 1 3 0V9M12 9V6.5a1.5 1.5 0 0 1 3 0V9M15 9V7a1.5 1.5 0 0 1 3 0v3M18 10V9a1.5 1.5 0 0 1 3 0v4a6 6 0 0 1-6 6h-1a6 6 0 0 1-6-6v-1a2 2 0 0 1 2-2h2"/>',
  hookL: '<path d="M19 19C9 19 5 14 5 7"/><path d="M2 10l3-3 3 3"/><circle cx="19" cy="19" r="2.5" fill="currentColor"/>',
  hookR: '<path d="M5 19c10 0 14-5 14-12"/><path d="M16 10l3-3 3 3"/><circle cx="5" cy="19" r="2.5" fill="currentColor"/>',
  upper: '<path d="M8 21c0-7 3-13 8-16"/><path d="M12 5h4.5V9.5"/><circle cx="8" cy="21" r="2" fill="currentColor"/>',
  kick: '<path d="M8 3v8l9 3h4"/><path d="M8 11l-2 10h3"/><circle cx="8" cy="3" r="1.5" fill="currentColor"/>',
  lowkick: '<path d="M8 3v8l9 7h3"/><path d="M8 11l-2 10h3"/><circle cx="8" cy="3" r="1.5" fill="currentColor"/>',
  headkick: '<path d="M8 6v8l9-8h3"/><path d="M8 14l-2 7h3"/><circle cx="8" cy="4" r="1.5" fill="currentColor"/>',
  knee: '<path d="M9 3v8l6-4 1 8"/><path d="M9 11l-1 10h3"/>',
  elbow: '<path d="M4 7h9l5 9"/><path d="M13 7l-2-3"/><circle cx="13" cy="7" r="2" fill="currentColor"/>',
  teep: '<path d="M3 21l5-9 4-1h9"/><path d="M21 8v6"/>',
  shield: '<path d="M12 3l7 3v6c0 5-3 8-7 9-4-1-7-4-7-9V6z"/>',
  shieldLow: '<path d="M12 3l7 3v6c0 5-3 8-7 9-4-1-7-4-7-9V6z"/><path d="M8 14h8"/>',
  dodge: '<circle cx="12" cy="7" r="3"/><path d="M3 16h18M6 13l-3 3 3 3M18 13l3 3-3 3"/>',
  duck: '<circle cx="12" cy="13" r="3"/><path d="M12 2v6M9 5l3 3 3-3M4 21h16"/>',
  check: '<path d="M10 3v8l5-2v9"/><path d="M10 11l-2 10"/><path d="M18 6l3 3"/>',
  clinch: '<path d="M3 13c0-5 4-8 9-8s9 3 9 8"/><path d="M7 13c0-3 2-5 5-5s5 2 5 5"/><path d="M3 13h4M17 13h4"/>',
  takedown: '<circle cx="7" cy="5" r="2"/><path d="M7 7l2 6 8 2M9 13l-4 6"/><path d="M15 19h6"/><path d="M19 9l2 4"/>',
  lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  pause: '<path d="M8 5v14M16 5v14"/>',
  play: '<path d="M7 4l13 8-13 8z" fill="currentColor"/>',
  body: '<circle cx="12" cy="4.5" r="2"/><path d="M8 8h8l-1 7h-6z"/><path d="M9 15l-1 6M15 15l1 6M8 8l-3 6M16 8l3 6"/>',
  target: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/>',
  up: '<path d="M12 20V5M6 11l6-6 6 6"/>',
  eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
  camera: '<rect x="3" y="7" width="18" height="13" rx="2"/><circle cx="12" cy="13.5" r="3.5"/><path d="M8 7l2-3h4l2 3"/>',
  back: '<path d="M15 18l-6-6 6-6"/>',
  expand: '<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/>',
  hand: '<path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V12M11 11V4.5a1.5 1.5 0 0 1 3 0V12M14 11.5V6a1.5 1.5 0 0 1 3 0v8a7 7 0 0 1-7 7h-1a6 6 0 0 1-5-3l-2.5-4a1.5 1.5 0 0 1 2.5-1.5L8 15"/>',
  rotate: '<rect x="7" y="2" width="10" height="20" rx="2"/><path d="M21 8a8 8 0 0 1-2 9"/><path d="M19 13v4h4"/>',
};

export function icon(name, size = 24, cls = '') {
  const s = document.createElement('span');
  s.className = 'ico ' + cls;
  s.innerHTML = `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${P[name] || P.target}</svg>`;
  return s;
}
