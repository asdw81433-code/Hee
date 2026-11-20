# Westbridge — Architecture & Roadmap

## 1. Module map

```
                       ┌──────────────── Autoloads ────────────────┐
                       │ EventBus  GameTime  Settings  SaveSystem  Game │
                       └───────▲──────────▲─────────▲────────▲──────┘
            signals (decoupled)│          │ time    │ config │ save sections ("savable" group)
┌──────────────┐  ┌────────────┴──┐  ┌────┴─────────┐  ┌───┴──────────┐  ┌───────────────┐
│ World        │  │ Player        │  │ NPC          │  │ UI           │  │ Character     │
│ CityBuilder  │  │ PlayerCtrl ◄──┼──┤ NPCManager   │  │ HUD/Touch    │  │ Appearance    │
│ CityBlocks   │  │ Camera        │  │ NPCBrain (AI)│  │ Pause/Settings│ │ MeshFactory   │
│ PedGraph     │  │ Interactor    │  │ NPCBody      │  │ Creator      │  │ CharacterModel│
│ Places       │  └──────┬────────┘  │ Reactions    │  │ NPCDialog    │  │ FaceRig       │
│ Environment  │         │extends    │ Data/Memory/ │  └──────────────┘  └──────┬────────┘
└──────────────┘  ┌──────▼───────────┴─Emotion/Pers.┤                           │ builds
                  │ HumanoidBody (CharacterBody3D) ◄┘  movement, step-up, landing│
                  │   ├─ CharacterModel ── Skeleton3D ─┬─ skinned mesh (1 draw)  ◄┘
                  │   │                                ├─ CharacterAnimator (AnimationTree)
                  │   │                                ├─ ProceduralRig  (SkeletonModifier3D)
                  │   │                                ├─ FaceRig        (SkeletonModifier3D)
                  │   │                                └─ RagdollRig     (PhysicalBoneSimulator3D, lazy)
                  │   └─ HumanoidPhysics: BalanceController(PID) · impacts · partial/full ragdoll · recovery
                  └────────────────────────────────────────────────────────────────────────┘
```

* **Every human** (player and NPCs) is a `HumanoidBody`. Controllers only set intent
  (`move_dir`, `desired_speed`, `wants_jump`, `crouching`); the body handles physics,
  animation and reactions. This guarantees NPCs and the player use the same systems.
* Systems talk through **EventBus** signals (`world_event`, `character_impacted`,
  `money_changed`, `npc_action_changed`, ...) — new modules (police, phone, news) subscribe
  without touching existing code.
* **Save system**: any node in group `savable` implements `save_key()`, `save_state()`,
  `load_state()`. Current sections: `time`, `game` (profile/wallet), `player`, `environment`, `npcs`.

## 2. Character pipeline

1. `CharacterAppearance` (Resource, serializable) → `HumanoidDef.bone_list(dims)` builds a
   Skeleton3D (SkeletonProfileHumanoid names + face bones, identity rest rotations).
2. `CharacterMeshFactory` writes one vertex-coloured, bone-weighted ArrayMesh (lathe tubes with
   2-bone weights at joints, ellipsoids, primitives). Clothing is part of the same mesh, so a
   character is one draw call. LOD1 is the same mesh at ~40% segments.
3. Modifier order on the skeleton each frame:
   `AnimationTree` → `ProceduralRig` (springs, lean, balance tilt, look-at, foot IK) →
   `FaceRig` (lids, brows, mouth, eyes) → `PhysicalBoneSimulator3D` (only while a ragdoll is active).
4. `AnimLibraryBuilder` bakes 54 clips from pose dictionaries (Euler degrees per bone). The
   locomotion clips are all 1.0 s and phase aligned so the BlendSpace can blend walk↔run
   without foot sliding; playback speed follows the stride frequency of the current speed.

## 3. Physics reaction flow

```
ImpactData(pos, dir, impulse, source, mass/velocity)
   └─ HumanoidPhysics.receive_impact
        ├─ body part (head/torso/arm_l/arm_r/legs) + blocking
        ├─ Δv = impulse / mass × height factor × (speed, fear)
        ├─ BalanceController.add_velocity / stun / leg sweep
        ├─ ProceduralRig.apply_hit (spring torques around bones near the hit)
        ├─ upper-body flinch clip (hit_front/back/left/right/head)
        └─ partial ragdoll (arm / head chain) for solid limb hits, or full ragdoll for huge ones
BalanceController.step (every physics tick)
   PID control limited by capacity(strength, skill, fatigue, injury, stun, friction)
   → STABLE / RECOVERING / STEP (body moves the feet) / FALL (capture point or drift too large)
RAGDOLL → settle → find free spot → face up/down → align body → blend influence 1→0 while
the get-up clip plays → NORMAL
```

## 4. NPC simulation & LOD

| Tier | Distance | What runs |
|---|---|---|
| 0 | < 20 m | pooled NPCBody, full mesh, face, foot IK, look-at, physics, AI tick ~0.3 s |
| 1 | 20–105 m | pooled NPCBody, light mesh, no face/IK, AI tick ~1 s |
| 2 | far / indoors | no body: position moves along PedGraph paths (×6 speed for buses/bikes), AI tick ~2 s |

* AI is **round-robin**: only a few NPCs are ticked per frame; time since the last tick is
  passed in, so the result does not depend on frame rate.
* After a time skip (sleeping) `NPCManager.fast_forward` replays the population in 15-minute steps.
* Event perception is local: only embodied NPCs within the radius **and with line of sight**
  react and form memories; others never learn about it (gossip/news arrive in Phase 3/7).

### Utility AI considerations
needs (hunger/energy/social/fun/hygiene) · 18 personality traits · emotions · time of day ·
weekday · weather · money · home food stock · job shift · day plan (meetups, sick days,
oversleeping) · distance/opening hours/price of places · inertia for the current action.
`NPCData.last_score_table` keeps the top scores so the in-game inspector shows *why*.

## 5. City

* `CityMap` holds the block grid and district names; `CityBlocks` builds each block into one
  `GeoBatch` (single mesh + shared `world.gdshader`) and one `StaticBody3D` of boxes.
* Distant blocks switch to a combined **skyline HLOD** mesh; forest is split into 120 m
  MultiMesh chunks with near (shadowed) and far (simple) versions; occluders on towers.
* Only 8 street lights + 3 interior lights are real OmniLights; they follow the camera to the
  nearest lamps at night. Emissive windows/signs are driven by the `night_factor` global uniform.
* `PedGraph` (AStar3D) = sidewalk rings + crosswalks + doors + interiors + park benches.
  `Place` objects (73) carry type, tags, hours, price, jobs, spots and occupants.

## 6. Roadmap (next phases)

| Phase | Content | Status |
|---|---|---|
| 1 | Project, player, camera, small city, interaction, mobile UI | ✅ |
| 2 | NPCs, personality, utility AI, routines, LOD simulation | ✅ |
| Physics/Anim | Hybrid animation, balance PID, impacts, partial/full ragdoll, recovery, foot IK, lab | ✅ |
| 3 | Deeper memory use, gossip/rumours, social groups (leader, meeting place, rules), jealousy, forgiveness, emotional contagion, more reactions | next |
| 4 | Jobs with gameplay (delivery, cashier, warehouse), economy, shops, inventory, rent | |
| 5 | Drivable cars (sedan, pickup, van, bike), traffic AI with lights, accidents | |
| 6 | Housing market, furniture placement (buy/place/move/rotate/sell) | |
| 7 | Phone UI: contacts, messages, map, social feed, bank, jobs, calendar, camera | |
| 8 | Police: wanted levels, witnesses' reports (already emitted as `police_report` events), arrests | |
| 9 | More districts (Beach, Hillside, Entertainment), activities, NPC Creator | |
| 10 | Optimization on real devices, Android build, bug fixing | |
