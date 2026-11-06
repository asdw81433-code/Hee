// ===== Strike library =====
// Timings are based on motion-capture data of boxers (the jab is the fastest strike, ~0.3-0.4 s delivery)
// and on the kinetic chain: feet -> hips -> torso -> arm. Hip/torso yaw values are in "lead-side" units
// (multiplied by the stance mirror at runtime). Base bladed stance yaw is -0.55.
// mass = effective striking mass factor; nominal = typical effector speed in m/s used to normalize kinetic energy.
export const MOVES = {
  jab: { name: 'Jab', limb: 'hand', side: 'lead', kind: 'punch', path: 'straight', zone: 'head', wind: 0.035, ext: 0.12, hold: 0.035, ret: 0.15,
    stam: 1.6, mass: 0.42, nominal: 6.5, pelvisYaw: -0.38, chestYaw: 0.12, shiftZ: 0.05, shiftX: 0.02, roll: 1.4, crouch: 0.0 },
  cross: { name: 'Cross', limb: 'hand', side: 'rear', kind: 'punch', path: 'straight', zone: 'head', wind: 0.07, ext: 0.15, hold: 0.045, ret: 0.19,
    stam: 3.2, mass: 0.85, nominal: 7.5, pelvisYaw: 0.28, chestYaw: 0.38, shiftZ: 0.09, shiftX: 0.05, roll: 1.4, pivot: 0.75 },
  leadHook: { name: 'Lead Hook', limb: 'hand', side: 'lead', kind: 'punch', path: 'hook', zone: 'head', wind: 0.09, ext: 0.17, hold: 0.045, ret: 0.21,
    stam: 3.4, mass: 0.9, nominal: 7.5, windYaw: -0.25, pelvisYaw: -1.05, chestYaw: -0.3, shiftZ: 0.03, shiftX: 0.04, roll: 0.3, leadPivot: 0.8 },
  rearHook: { name: 'Rear Hook', limb: 'hand', side: 'rear', kind: 'punch', path: 'hook', zone: 'head', wind: 0.1, ext: 0.19, hold: 0.045, ret: 0.23,
    stam: 3.8, mass: 0.95, nominal: 8, windYaw: -0.75, pelvisYaw: 0.5, chestYaw: 0.4, shiftZ: 0.07, shiftX: 0.06, roll: 0.3, pivot: 0.9 },
  leadUpper: { name: 'Lead Uppercut', limb: 'hand', side: 'lead', kind: 'punch', path: 'upper', zone: 'head', wind: 0.1, ext: 0.16, hold: 0.04, ret: 0.21,
    stam: 3.2, mass: 0.85, nominal: 6.5, windYaw: -0.35, pelvisYaw: -0.85, chestYaw: -0.2, windDip: 0.09, rise: 0.03, shiftX: 0.05, roll: -1.2 },
  rearUpper: { name: 'Rear Uppercut', limb: 'hand', side: 'rear', kind: 'punch', path: 'upper', zone: 'head', wind: 0.11, ext: 0.17, hold: 0.04, ret: 0.22,
    stam: 3.6, mass: 0.95, nominal: 7, windYaw: -0.7, pelvisYaw: 0.15, chestYaw: 0.3, windDip: 0.1, rise: 0.03, shiftX: 0.05, roll: -1.2, pivot: 0.6 },
  jabBody: { name: 'Body Jab', limb: 'hand', side: 'lead', kind: 'punch', path: 'straight', zone: 'body', wind: 0.05, ext: 0.13, hold: 0.04, ret: 0.17,
    stam: 2, mass: 0.45, nominal: 6.5, pelvisYaw: -0.38, chestYaw: 0.1, shiftZ: 0.08, crouch: 0.16, chestPitch: 0.25, roll: 1.4 },
  crossBody: { name: 'Body Cross', limb: 'hand', side: 'rear', kind: 'punch', path: 'straight', zone: 'body', wind: 0.08, ext: 0.16, hold: 0.045, ret: 0.2,
    stam: 3.4, mass: 0.85, nominal: 7.5, pelvisYaw: 0.25, chestYaw: 0.3, shiftZ: 0.1, crouch: 0.17, chestPitch: 0.3, roll: 1.4, pivot: 0.75 },
  leadHookBody: { name: 'Liver Hook', limb: 'hand', side: 'lead', kind: 'punch', path: 'hookLow', zone: 'body', wind: 0.1, ext: 0.18, hold: 0.045, ret: 0.22,
    stam: 3.6, mass: 0.95, nominal: 7.5, windYaw: -0.3, pelvisYaw: -1.0, chestYaw: -0.25, crouch: 0.15, chestPitch: 0.15, chestRoll: 0.25, shiftX: 0.07, roll: 0.3, leadPivot: 0.8 },
  rearHookBody: { name: 'Body Hook', limb: 'hand', side: 'rear', kind: 'punch', path: 'hookLow', zone: 'body', wind: 0.1, ext: 0.19, hold: 0.045, ret: 0.23,
    stam: 3.8, mass: 0.95, nominal: 8, windYaw: -0.75, pelvisYaw: 0.45, chestYaw: 0.35, crouch: 0.15, chestPitch: 0.15, chestRoll: -0.25, shiftX: 0.06, roll: 0.3, pivot: 0.9 },
  // ---- kicks (shin is the striking surface for roundhouses) ----
  leadLowKick: { name: 'Calf Kick', limb: 'foot', side: 'lead', kind: 'kick', path: 'round', zone: 'leg', wind: 0.1, ext: 0.2, hold: 0.06, ret: 0.24,
    stam: 4, mass: 0.75, nominal: 8, pelvisYaw: -1.05, lean: 0.18, chamberH: 0.35, sweep: 0.22, calf: true },
  rearLowKick: { name: 'Leg Kick', limb: 'foot', side: 'rear', kind: 'kick', path: 'round', zone: 'leg', wind: 0.13, ext: 0.24, hold: 0.07, ret: 0.28,
    stam: 5.5, mass: 1.0, nominal: 9, pelvisYaw: 1.05, lean: 0.25, chamberH: 0.42, sweep: 0.25, supportPivot: 1.2 },
  rearBodyKick: { name: 'Body Kick', limb: 'foot', side: 'rear', kind: 'kick', path: 'round', zone: 'body', wind: 0.15, ext: 0.27, hold: 0.08, ret: 0.32,
    stam: 7, mass: 1.15, nominal: 9.5, pelvisYaw: 1.2, lean: 0.35, chamberH: 0.6, sweep: 0.28, supportPivot: 1.4 },
  rearHeadKick: { name: 'Head Kick', limb: 'foot', side: 'rear', kind: 'kick', path: 'round', zone: 'head', wind: 0.17, ext: 0.3, hold: 0.08, ret: 0.36,
    stam: 8.5, mass: 1.35, nominal: 10, pelvisYaw: 1.3, lean: 0.55, chamberH: 0.85, sweep: 0.3, supportPivot: 1.55 },
  leadBodyKick: { name: 'Switch Kick', limb: 'foot', side: 'lead', kind: 'kick', path: 'round', zone: 'body', wind: 0.16, ext: 0.24, hold: 0.07, ret: 0.3,
    stam: 6, mass: 0.95, nominal: 9, pelvisYaw: -1.15, lean: 0.3, chamberH: 0.55, sweep: 0.25, supportPivot: 1.2 },
  leadHeadKick: { name: 'Lead Head Kick', limb: 'foot', side: 'lead', kind: 'kick', path: 'round', zone: 'head', wind: 0.17, ext: 0.27, hold: 0.07, ret: 0.33,
    stam: 7, mass: 1.15, nominal: 9.5, pelvisYaw: -1.2, lean: 0.5, chamberH: 0.8, sweep: 0.28, supportPivot: 1.3 },
  teep: { name: 'Teep', limb: 'foot', side: 'lead', kind: 'kick', path: 'teep', zone: 'body', wind: 0.12, ext: 0.18, hold: 0.08, ret: 0.24,
    stam: 3.5, mass: 0.4, nominal: 6, pelvisYaw: -0.45, lean: -0.25, push: 2.6 },
  knee: { name: 'Knee', limb: 'knee', side: 'rear', kind: 'knee', path: 'knee', zone: 'body', wind: 0.1, ext: 0.17, hold: 0.06, ret: 0.22,
    stam: 4.5, mass: 1.0, nominal: 5.5, pelvisYaw: 0.15, lean: -0.3, shiftZ: 0.12 },
  elbow: { name: 'Elbow', limb: 'elbow', side: 'rear', kind: 'elbow', path: 'elbow', zone: 'head', wind: 0.07, ext: 0.13, hold: 0.04, ret: 0.18,
    stam: 3.2, mass: 0.8, nominal: 6, windYaw: -0.75, pelvisYaw: 0.55, chestYaw: 0.5, shiftZ: 0.08 },
  leadElbow: { name: 'Lead Elbow', limb: 'elbow', side: 'lead', kind: 'elbow', path: 'elbow', zone: 'head', wind: 0.06, ext: 0.12, hold: 0.04, ret: 0.17,
    stam: 2.8, mass: 0.7, nominal: 5.5, windYaw: -0.3, pelvisYaw: -1.0, chestYaw: -0.4, shiftZ: 0.05 },
};

// Keyboard binding -> move id given modifiers
export function resolveStrike(key, body, high) {
  switch (key) {
    case 'jab': return body ? 'jabBody' : 'jab';
    case 'cross': return body ? 'crossBody' : 'cross';
    case 'leadHook': return body ? 'leadHookBody' : 'leadHook';
    case 'rearHook': return body ? 'rearHookBody' : 'rearHook';
    case 'leadUpper': return 'leadUpper';
    case 'rearUpper': return 'rearUpper';
    case 'leadKick': return high ? 'leadHeadKick' : body ? 'leadLowKick' : 'leadBodyKick';
    case 'rearKick': return high ? 'rearHeadKick' : body ? 'rearLowKick' : 'rearBodyKick';
    case 'teep': return 'teep';
    case 'knee': return 'knee';
    case 'elbow': return 'elbow';
    default: return key;
  }
}
