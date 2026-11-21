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

1. **Modelling happens in Blender.** `tools/blender/build_characters.py` builds the base mesh
   (Skin modifier + Subdivision), head (deformed quad sphere), metaball hair/beards, garments
   fitted from the body surface (copied faces pushed along normals, so they share the body's
   shape keys and weights), shoes, hats, glasses and accessories, all rigged to one armature
   with the game's bone names. It also builds a LOD1 set (`*_LOD1`: hand-decimated body,
   low-poly head, decimated props) and writes a garment-coverage bitmask into the body's
   `CoverMask` colour attribute. Output: `assets/characters/westbridge_characters.glb`
   (+ the editable `.blend` and preview renders).
2. `CharacterAssetLibrary` loads the glb once and caches every part in skeleton space
   (vertices, normals, bone names + weights, blend-shape deltas, cover mask).
   `CharacterAssetBuilder` turns a `CharacterAppearance` into a part list, bakes the body/head
   shape keys (Female/Heavy/Thin/Muscular, HeadWide/HeadLong/JawWide/JawNarrow), applies face
   tweaks (eye size/spacing, nose, brows, mouth), drops body triangles under worn clothes,
   and merges everything into ONE vertex-coloured skinned surface → one draw call.
   `build_skeleton()` places identity-rotation rests at the asset joints (identical to
   `HumanoidDef`), so animation clips, FaceRig, ProceduralRig and ragdolls are unchanged.
   Fallback: if the asset is missing or `Settings.character_assets` is off, `HumanoidDef` +
   `CharacterMeshFactory` build the old procedural character.
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

## 5. City (Priority 1: 10 districts + streaming)

* `CityMap` = the 17x12 grid of 58 m cells (`cell_type`, `cell_kind`, `cell_district`),
  road kinds on every grid edge (`vedge`/`hedge`: street, dirt, bridge, highway crossing),
  street names and an analytic terrain `height_at` (hills, river valley, lake, coast, flat
  harbour quays) + `road_height_at` (level bridges).
* `CityBuilder` builds in **two passes**. The *data pass* runs every cell generator with
  `GeoBatch.enabled = false` (same code, same per-cell seed) to create places, jobs, the
  pedestrian network, lamp positions and the skyline HLOD. The *visual pass* (`load_cell`)
  replays one cell with geometry enabled and isolates all data side effects (swapped
  `PedGraph`, restored rings/spots, seats re-bound by position). `update_streaming` loads
  cells within `view_distance + 70 m` nearest-first under a ~6 ms budget, unloads beyond
  `+160 m`; cells within 70 m load immediately (teleports, fast movement).
  `stats.mismatch` counts any cell whose visual pass diverges (tested to stay 0).
* `CityBlocks` = the original town generators (unchanged output). `DistrictBlocks`
  extends it for every other cell; on sloped cells `X()/W()` follow the terrain and
  buildings get stone foundations (`pad`). `RoadBuilder` builds each cell's own edges,
  intersections, bridges and the Route 9 section, plus a far-LOD road mesh.
* Network: block rings + crosswalks between neighbouring blocks; intersection nodes chained
  along dirt roads, bridges, highway crossings and edge-of-town streets and tied to block
  corners; unused intersections are pruned; remote places link to the nearest node.
  One connected component (tested).
* Always loaded: far ground + far roads (1 mesh), skyline, water, outer landscape,
  forest MultiMesh chunks (near/far), backdrop mountains, world bounds.
* Only 8 street lights + 3 interior lights are real OmniLights following the camera.
* `MapScreen` draws the grid, roads, districts, places, player and waypoint.

## 6. Economy (Priority 2: jobs, money, shopping)

```
ItemDB (static data)          Economy (Node, savable "economy")              UI
  ITEMS ~50 items               inventory {id: count}, bank, debt              ServicePoint (Interactable at each
  BY_TYPE: what each            job {place, title, wage, start, end,             place's door; spawned in
    place type sells              rank, shifts, good, misses, mode...}           CityBuilder.load_cell)
  BUYS: buy-back lists          experience, history, rent_due_min                  -> GameWorld.open_place_menu
  PRICE_MULT by price level     buy / sell / use_item / deposit / withdraw     PlaceMenu: Shop/Sell/Work/Bank/Room/Bag
                                apply / quit / shift_state / start_shift       WorkMinigame (orders/timing/typing)
                                finish_shift (pay, time skip, promotion)         -> done(perf, tips)
                                _on_hour/_on_day: missed shifts, interest,       -> fade_sleep -> finish_shift
                                  rent, debt                                   InventoryUI (BAG / I)
                                delivery shifts: 3 targets, waypoint,          NPCDialog "Give item"
                                  arrival check in _process, deadline
```

- Job openings are counted against the NPCs who actually hold that job (`NPCData.job`), so a full workplace has no opening for the player.
- `required_experience(wage) = clamp((wage-17)/2, 0, 12)` shifts.
- Shift window: 45 min before → 1.5 h after the start. Lateness is deducted from paid hours. A day the player was hired after the shift began is never counted as missed.
- Pay: `wage × 1.2^rank × hours × (0.6 + 0.6 × performance) + tips`. A good shift (perf ≥ 0.65, < 30 min late) counts toward promotion (every 5) and clears a warning every 3. 3 missed shifts gets the player fired.
- Courier jobs exist at Central Station, Harbor Logistics and the Post Office. Their deadline is the route length / 3 m per game minute + 45 min.
- The old quick-buy counters at a door (`SimpleInteractable` coffee/food) are disabled when a ServicePoint takes that spot. The menu's "Have now" button does the same thing. Counters inside interiors stay as they were.

## 7. Roadmap (next phases)

| Phase | Content | Status |
|---|---|---|
| 1 | Project, player, camera, small city, interaction, mobile UI | ✅ |
| 2 | NPCs, personality, utility AI, routines, LOD simulation | ✅ |
| Physics/Anim | Hybrid animation, balance PID, impacts, partial/full ragdoll, recovery, foot IK, lab | ✅ |
| 3 | Deeper memory use, gossip/rumours, social groups (leader, meeting place, rules), jealousy, forgiveness, emotional contagion, more reactions | next |
| 4 / P2 | Jobs with gameplay (orders/timing/typing minigames, courier runs), economy, shops, sell-back, inventory, bank, rent, gifts | ✅ |
| 5 | Drivable cars (sedan, pickup, van, bike), traffic AI with lights, accidents | |
| 6 | Housing market, furniture placement (buy/place/move/rotate/sell) | |
| 7 | Phone UI: contacts, messages, map, social feed, bank, jobs, calendar, camera | |
| 8 | Police: wanted levels, witnesses' reports (already emitted as `police_report` events), arrests | |
| P1 | 10 districts, 104 blocks, terrain, Route 9, bridges, two-pass generation + streaming, map | ✅ |
| 9 | Activities, collectibles, NPC Creator | |
| 10 | Optimization on real devices, Android build, bug fixing | |
