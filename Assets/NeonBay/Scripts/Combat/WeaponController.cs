using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace NeonBay
{
    /// <summary>Player weapons: hitscan guns, melee, ADS, reloads, grenades and a procedurally built first-person viewmodel.</summary>
    public class WeaponController : MonoBehaviour
    {
        public int slot;
        public bool Aiming { get; private set; }
        public bool Reloading => reloadTimer > 0f;
        public bool Holstered { get; private set; }
        public bool ScopeActive => Aiming && aimBlend > 0.85f && Current != null && Current.Def.scoped;
        public float SpreadNow { get; private set; }
        public float HitMarker;
        public bool HitMarkerKill;
        public bool Blocking { get; private set; }

        WeaponInstance fists;
        public bool forceFists;
        public WeaponInstance Current => forceFists ? fists : Holstered ? null : (Game.Inventory != null && Game.Inventory.slots[slot] != null ? Game.Inventory.slots[slot] : fists);
        public WeaponDef CurrentDef => Current?.Def;

        PlayerController pc;
        Transform vmRoot, vmSway, vmWeapon, muzzle, rightHand, leftHand;
        WeaponInstance builtFor;
        bool builtHolster;
        float cooldown, reloadTimer, swapTimer, aimBlend, bloom;
        float meleePhase = -1f; int meleeCombo; bool meleeHitDone;
        float bashTimer = -1f;
        Vector3 swayPos; Vector3 swayRot;
        float wallPull;
        float grenadeCooldown;
        Light flashLight;
        float flashTimer;
        Material skinMat, sleeveMat, gunMat, accentMat, darkMat;

        void Start()
        {
            pc = GetComponent<PlayerController>();
            fists = new WeaponInstance("fists");
            vmRoot = new GameObject("ViewModel").transform;
            vmRoot.SetParent(pc.Cam.transform, false);
            vmSway = new GameObject("Sway").transform;
            vmSway.SetParent(vmRoot, false);
            var fl = new GameObject("MuzzleLight");
            fl.transform.SetParent(pc.Cam.transform, false);
            fl.transform.localPosition = new Vector3(0.15f, -0.1f, 0.8f);
            flashLight = fl.AddComponent<Light>();
            flashLight.type = LightType.Point; flashLight.range = 9f; flashLight.intensity = 0f; flashLight.color = new Color(1f, 0.75f, 0.4f);
            flashLight.shadows = LightShadows.None;
            var p = Game.Profile ?? new CharacterProfile();
            skinMat = Mats.Lit(Palette.SkinTones[Mathf.Clamp(p.skin, 0, Palette.SkinTones.Length - 1)], null, p.skin == Palette.SkinTones.Length - 1 ? 0.85f : 0.35f, p.skin == Palette.SkinTones.Length - 1 ? 0.8f : 0f);
            sleeveMat = Mats.Lit(p.jacket, Tex.Metal.albedo, 0.25f);
            darkMat = Mats.Lit(new Color(0.08f, 0.08f, 0.09f), Tex.Metal.albedo, 0.55f, 0.7f, Tex.Metal.normal);
            gunMat = Mats.Lit(new Color(0.22f, 0.23f, 0.25f), Tex.Metal.albedo, 0.6f, 0.85f, Tex.Metal.normal);
            Game.Stats.dmg.filter = FilterIncoming;
            Rebuild();
        }

        DamageInfo FilterIncoming(DamageInfo d)
        {
            d.amount *= Game.EnemyDamageMult * Game.Stats.DamageTakenMult;
            if (Game.Activities != null && Game.Activities.FightActive) d.amount = Mathf.Min(d.amount, Mathf.Max(0f, Game.Stats.dmg.health - 1f));
            if (Blocking && (d.type == DamageType.Melee || d.type == DamageType.Ballistic))
            {
                var toSrc = d.source != null ? (d.source.transform.position - transform.position).Flat().normalized : -d.direction.Flat();
                if (Vector3.Dot(toSrc, transform.forward) > 0.3f)
                {
                    d.amount *= d.type == DamageType.Melee ? 0.25f : 0.8f;
                    Game.Stats.UseStamina(8f);
                    Game.Audio?.Play2D("shield_hit", 0.6f);
                }
            }
            return d;
        }

        public void OnLoadoutChanged() { builtFor = null; }

        public void Holster(bool h)
        {
            Holstered = h;
            Aiming = false;
            reloadTimer = 0f;
            builtFor = null;
        }

        void Update()
        {
            if (pc == null || pc.Cam == null) return;
            float dt = Game.Manager != null && Game.Manager.SlowMotion ? Time.unscaledDeltaTime * 0.8f : Time.deltaTime;
            bool playing = Game.IsPlaying && pc.controlEnabled && !pc.InVehicle;
            if (Current != builtFor || builtHolster != Holstered) Rebuild();
            vmRoot.gameObject.SetActive(!pc.InVehicle && !pc.cameraOverride);
            if (dt <= 0f) return;

            cooldown -= dt; swapTimer -= dt; grenadeCooldown -= dt;
            HitMarker = Mathf.MoveTowards(HitMarker, 0f, dt * 4f);
            flashTimer -= dt;
            flashLight.intensity = flashTimer > 0f ? 3.5f : 0f;

            if (playing) HandleInput(dt);
            else { Aiming = false; Blocking = false; }

            var def = CurrentDef;
            float targetAim = Aiming ? 1f : 0f;
            aimBlend = Mathf.MoveTowards(aimBlend, targetAim, dt * 7f);
            if (def != null && !def.IsMelee)
            {
                float baseFov = Game.Settings != null ? Game.Settings.fov : 78f;
                pc.fovOverride = aimBlend > 0.01f ? Mathf.Lerp(baseFov, def.scoped ? def.adsFov : baseFov * 0.72f, aimBlend) : -1f;
                pc.sensitivityMult = Mathf.Lerp(1f, def.scoped ? 0.3f : 0.65f, aimBlend);
            }
            else { pc.fovOverride = -1f; pc.sensitivityMult = 1f; }

            // spread / bloom
            var stats = Game.Stats;
            float moving = Mathf.Clamp01(pc.Velocity.Flat().magnitude / 6f);
            if (stats != null && stats.HasPerk("run_and_gun")) moving *= 0.2f;
            bloom = Mathf.MoveTowards(bloom, 0f, dt * 5f);
            if (def != null)
            {
                float s = Mathf.Lerp(def.spread, def.adsSpread, aimBlend);
                s *= 1f + moving * 1.2f + bloom + (pc.Grounded ? 0f : 1.5f);
                if (pc.Crouching) s *= 0.75f;
                s *= stats != null ? stats.SpreadMult : 1f;
                SpreadNow = s;
            }
            AnimateViewmodel(dt);
        }

        void HandleInput(float dt)
        {
            // switching
            if (forceFists) { HandleCombat(dt); return; }
            for (int i = 0; i < 4; i++)
                if (InputHub.Down(Btn.Weapon1 + i) && !(Game.Hacking != null && Game.Hacking.Scanning)) SelectSlot(i);
            float sc = InputHub.Scroll;
            if (Mathf.Abs(sc) > 0.01f && !(Game.Hacking != null && Game.Hacking.Scanning))
            {
                int dir = sc > 0 ? -1 : 1;
                for (int k = 1; k <= 4; k++)
                {
                    int s = (slot + dir * k + 8) % 4;
                    if (Game.Inventory.slots[s] != null) { SelectSlot(s); break; }
                }
            }
            if (InputHub.Down(Btn.Holster)) { Holster(!Holstered); Game.Audio?.Play2D("swap", 0.5f); }
            HandleCombat(dt);
        }

        void HandleCombat(float dt)
        {
            var w = Current;
            var def = w?.Def;
            if (def == null) { Aiming = false; return; }
            if (Game.Hacking != null && Game.Hacking.Scanning) { Aiming = false; return; }

            bool canAct = swapTimer <= 0f && meleePhase < 0f && bashTimer < 0f;
            Blocking = def.IsMelee && InputHub.Held(Btn.Aim) && canAct && Game.Stats.stamina > 5f;
            Aiming = !def.IsMelee && InputHub.Held(Btn.Aim) && !Reloading && !pc.Sprinting;

            if (def.IsMelee)
            {
                if (InputHub.Down(Btn.Fire) && canAct && cooldown <= 0f && !Blocking) StartMelee(def);
                UpdateMelee(dt, def, w);
            }
            else
            {
                if (Reloading)
                {
                    reloadTimer -= dt;
                    if (reloadTimer <= 0f) FinishReload(w);
                }
                else if (canAct)
                {
                    bool trigger = def.auto ? InputHub.Held(Btn.Fire) : InputHub.Down(Btn.Fire);
                    if (trigger && cooldown <= 0f && !pc.Sprinting)
                    {
                        if (w.ammoInMag > 0) Fire(w, def);
                        else if (InputHub.Down(Btn.Fire)) { Game.Audio?.Play2D("empty"); TryReload(w); cooldown = 0.25f; }
                    }
                    if (InputHub.Down(Btn.Reload)) TryReload(w);
                }
                if (InputHub.Down(Btn.Melee) && canAct && !Reloading) { bashTimer = 0f; meleeHitDone = false; Game.Audio?.Play2D("swing", 0.6f); }
                if (bashTimer >= 0f)
                {
                    bashTimer += dt;
                    if (bashTimer > 0.12f && !meleeHitDone) { meleeHitDone = true; MeleeHit(25f, 2.2f, DamageType.Melee, false); }
                    if (bashTimer > 0.45f) bashTimer = -1f;
                }
            }

            if (InputHub.Down(Btn.Grenade) && grenadeCooldown <= 0f) ThrowGrenade();
            if (InputHub.Down(Btn.Ability)) Game.Stats.TryChronoweave();
            if (InputHub.Down(Btn.Ability2)) Game.Stats.TryCamo();
        }

        public void SelectSlot(int i)
        {
            if (i == slot && !Holstered) return;
            slot = i;
            Holstered = false;
            reloadTimer = 0f;
            float q = Game.Stats != null && Game.Stats.HasPerk("quick_draw") ? 0.7f : 1f;
            swapTimer = 0.35f * q;
            Game.Audio?.Play2D("swap", 0.5f);
        }

        // ----------------------------------------------------------------- guns
        void Fire(WeaponInstance w, WeaponDef def)
        {
            var stats = Game.Stats;
            cooldown = 1f / (def.fireRate * (stats != null ? stats.FireRateMult : 1f));
            w.ammoInMag--;
            var cam = pc.Cam.transform;
            float spread = SpreadNow;
            for (int p = 0; p < def.pellets; p++)
            {
                var dir = Quaternion.AngleAxis(Random.Range(0f, 360f), cam.forward) * Quaternion.AngleAxis(Random.Range(0f, spread), cam.right) * cam.forward;
                Vector3 end = cam.position + dir * def.range;
                if (Physics.Raycast(cam.position, dir, out var hit, def.range, Layers.ShootMask, QueryTriggerInteraction.Ignore))
                {
                    end = hit.point;
                    ApplyHit(hit, dir, def, w, p == 0);
                }
                if (p < 3) Game.Fx?.Tracer(muzzle.position, end, def.accent);
            }
            Game.Fx?.MuzzleFlash(muzzle.position, cam.forward, def.accent);
            flashTimer = 0.04f;
            Game.Audio?.Play2D(def.sound, 0.85f, Random.Range(0.94f, 1.06f));
            GameEvents.RaiseNoise(transform.position, 70f, gameObject);
            float rm = stats != null ? stats.RecoilMult : 1f;
            pc.AddRecoil(def.recoil * rm * Mathf.Lerp(1f, 0.6f, aimBlend), Random.Range(-0.35f, 0.35f) * def.recoil * rm);
            bloom = Mathf.Min(2.5f, bloom + def.recoil * 0.15f);
            CameraFX.Shake(def.recoil * 0.012f * (def.cls == WeaponClass.Shotgun || def.cls == WeaponClass.Sniper ? 2.5f : 1f));
            kick += 1f;
            if (w.ammoInMag <= 0 && Game.Inventory.Ammo(def.ammo) > 0) TryReload(w);
        }

        void ApplyHit(RaycastHit hit, Vector3 dir, WeaponDef def, WeaponInstance w, bool primary)
        {
            var target = Damageable.Resolve(hit.collider, out float mult, out bool head);
            var stats = Game.Stats;
            if (target != null && target != stats.dmg)
            {
                float dmg = def.damage * w.DamageMult * Game.PlayerDamageMult * mult;
                float dist = hit.distance;
                if (dist > def.range * 0.5f) dmg *= Mathf.Lerp(1f, 0.55f, (dist - def.range * 0.5f) / (def.range * 0.5f));
                if (head && stats.HasPerk("headhunter")) dmg *= 1.35f;
                bool crit = Random.value < stats.CritChance;
                if (crit) dmg *= 1f + stats.CritDamage;
                var npc = target.GetComponent<NPC>();
                bool stealth = npc != null && !npc.Aware;
                if (stealth && stats.HasPerk("assassin")) dmg *= 2f;
                target.ApplyDamage(new DamageInfo { amount = dmg, type = def.damageType, point = hit.point, direction = dir, source = gameObject, headshot = head, crit = crit, fromPlayer = true, force = def.damage * 0.08f * def.pellets, stealth = stealth });
                HitMarker = 1f;
                HitMarkerKill = target.isDead;
                if (primary) Game.Audio?.Play2D(head ? "headshot" : "hitmarker", 0.6f);
                Game.Fx?.Impact(hit.point, hit.normal, target.isRobotic ? 2 : 1);
                Game.UI?.DamageNumber(hit.point, dmg, crit, head);
            }
            else
            {
                Game.Fx?.Impact(hit.point, hit.normal, 0);
                if (primary) Game.Fx?.Decal(hit.point, hit.normal, hit.collider.transform);
                var rb = hit.rigidbody;
                if (rb != null && !rb.isKinematic) rb.AddForceAtPosition(dir * def.damage * 0.5f, hit.point, ForceMode.Impulse);
            }
        }

        void TryReload(WeaponInstance w)
        {
            var def = w.Def;
            if (def == null || def.IsMelee || Reloading || w.ammoInMag >= def.mag) return;
            if (Game.Inventory.Ammo(def.ammo) <= 0) { Game.UI?.Notify("No " + Items.Get(Weapons.AmmoItem(def.ammo))?.name, Palette.Red); return; }
            reloadTimer = def.reload * (Game.Stats != null ? Game.Stats.ReloadMult : 1f);
            reloadDuration = reloadTimer;
            Aiming = false;
            Game.Audio?.Play2D("reload", 0.7f);
        }
        float reloadDuration = 1f;

        void FinishReload(WeaponInstance w)
        {
            var def = w.Def;
            int need = def.mag - w.ammoInMag;
            w.ammoInMag += Game.Inventory.TakeAmmo(def.ammo, need);
            Game.Audio?.Play2D("reload_end", 0.7f);
        }

        // ----------------------------------------------------------------- melee
        void StartMelee(WeaponDef def)
        {
            meleePhase = 0f; meleeHitDone = false; meleeCombo++;
            cooldown = 1f / def.fireRate;
            Game.Stats.UseStamina(7f);
            Game.Audio?.Play2D(def.cls == WeaponClass.Fists ? "swing" : def.sound == "slash" ? "swing" : "swing", 0.6f, Random.Range(0.9f, 1.1f));
        }

        void UpdateMelee(float dt, WeaponDef def, WeaponInstance w)
        {
            if (meleePhase < 0f) return;
            meleePhase += dt / (0.9f / def.fireRate);
            if (meleePhase > 0.35f && !meleeHitDone)
            {
                meleeHitDone = true;
                float dmg = def.damage * w.DamageMult * Game.Stats.MeleeMult * Game.PlayerDamageMult;
                bool hit = MeleeHit(dmg, def.meleeRange, DamageType.Melee, def.bleed);
                if (hit) Game.Audio?.Play2D(def.cls == WeaponClass.Melee && def.bleed ? "slash" : "punch", 0.9f);
            }
            if (meleePhase >= 1f) meleePhase = -1f;
        }

        bool MeleeHit(float dmg, float range, DamageType type, bool bleed)
        {
            var cam = pc.Cam.transform;
            var center = cam.position + cam.forward * (range * 0.55f);
            var cols = Physics.OverlapSphere(center, range * 0.6f, Layers.ShootMask, QueryTriggerInteraction.Ignore);
            var done = new HashSet<Damageable>();
            bool any = false;
            var stats = Game.Stats;
            foreach (var c in cols)
            {
                var d = Damageable.Resolve(c, out float mult, out bool head);
                if (d == null || d == stats.dmg || done.Contains(d) || d.isDead) continue;
                var to = d.transform.position - cam.position;
                if (Vector3.Dot(to.Flat().normalized, cam.forward.Flat().normalized) < 0.3f) continue;
                done.Add(d);
                var npc = d.GetComponent<NPC>();
                bool stealth = npc != null && !npc.Aware;
                float m = (stealth && stats.HasPerk("assassin")) ? 2f : 1f;
                bool crit = Random.value < stats.CritChance;
                float amount = dmg * m * (crit ? 1f + stats.CritDamage : 1f) * (head ? 1.3f : 1f);
                float force = stats.HasCyber("piston_fists") ? 18f : 5f;
                d.ApplyDamage(new DamageInfo { amount = amount, type = type, point = c.ClosestPoint(cam.position), direction = cam.forward, source = gameObject, crit = crit, headshot = head, fromPlayer = true, force = force, stealth = stealth });
                if (bleed && npc != null) npc.ApplyBleed(amount * 0.4f);
                Game.Fx?.Impact(c.ClosestPoint(cam.position), -cam.forward, d.isRobotic ? 2 : 1);
                Game.UI?.DamageNumber(d.transform.position + Vector3.up * 1.6f, amount, crit, false);
                HitMarker = 1f; HitMarkerKill = d.isDead;
                any = true;
            }
            if (any)
            {
                pc.Shake(0.15f);
                CameraFX.HitStop(stats.HasCyber("piston_fists") ? 0.07f : 0.04f);
                CameraFX.FovPunch(-1.5f);
                CameraFX.Kick(new Vector3(1.5f, meleeCombo % 2 == 0 ? -1f : 1f, 0));
            }
            GameEvents.RaiseNoise(transform.position, 8f, gameObject);
            return any;
        }

        // ----------------------------------------------------------------- grenades
        void ThrowGrenade()
        {
            string type = InputHub.Held(Btn.Sprint) && Game.Inventory.Has("emp") ? "emp" : Game.Inventory.Has("frag") ? "frag" : Game.Inventory.Has("emp") ? "emp" : null;
            if (type == null) { Game.UI?.Notify("No grenades", Palette.Red); return; }
            Game.Inventory.Remove(type);
            grenadeCooldown = 0.8f;
            var cam = pc.Cam.transform;
            Grenade.Throw(cam.position + cam.forward * 0.6f + cam.right * 0.15f, cam.forward * 17f + Vector3.up * 4f + pc.Velocity * 0.5f, type == "emp", gameObject);
            Game.Audio?.Play2D("swing", 0.5f, 0.8f);
        }

        // ----------------------------------------------------------------- viewmodel
        float kick;

        void Rebuild()
        {
            builtFor = Current;
            builtHolster = Holstered;
            for (int i = vmSway.childCount - 1; i >= 0; i--) Destroy(vmSway.GetChild(i).gameObject);
            var def = CurrentDef;
            muzzle = null; vmWeapon = null;
            if (def == null) return;

            accentMat = Mats.Cached("accent" + ColorUtility.ToHtmlStringRGB(def.accent) + Current.tier, () => Mats.Unlit(Color.Lerp(def.accent, Current.RarityColor, 0.4f) * 2.5f));
            var weaponRoot = new GameObject("Weapon").transform;
            weaponRoot.SetParent(vmSway, false);
            vmWeapon = weaponRoot;
            var s = def.size;

            // arms
            rightHand = Arm("RightArm", new Vector3(0.2f, -0.24f, 0.28f), new Vector3(8, -6, 0));
            leftHand = Arm("LeftArm", new Vector3(-0.2f, -0.26f, 0.32f), new Vector3(10, 8, 0));

            if (def.cls == WeaponClass.Fists)
            {
                weaponRoot.localPosition = Vector3.zero;
                return;
            }
            if (def.IsMelee)
            {
                weaponRoot.localPosition = new Vector3(0.2f, -0.2f, 0.4f);
                Part(weaponRoot, new Vector3(0, 0, -0.1f), new Vector3(0.035f, 0.035f, 0.22f), darkMat);
                Part(weaponRoot, new Vector3(0, 0, 0.02f), new Vector3(0.09f, 0.02f, 0.03f), gunMat);
                var blade = Part(weaponRoot, new Vector3(0, 0, s.z * 0.5f + 0.03f), new Vector3(s.x, s.y, s.z), def.bleed ? Mats.Cached("blade", () => Mats.Lit(new Color(0.8f, 0.85f, 0.9f), null, 0.95f, 1f)) : darkMat);
                if (def.bleed) Part(weaponRoot, new Vector3(0, s.y * 0.5f, s.z * 0.5f + 0.03f), new Vector3(0.005f, 0.006f, s.z), accentMat);
                weaponRoot.localRotation = Quaternion.Euler(-40, 0, 0);
                return;
            }

            weaponRoot.localPosition = new Vector3(0.17f, -0.17f, 0.36f);
            Part(weaponRoot, new Vector3(0, 0, 0), new Vector3(s.x, s.y * 0.6f, s.z), gunMat);                     // body
            Part(weaponRoot, new Vector3(0, -s.y * 0.45f, -s.z * 0.28f), new Vector3(s.x * 0.8f, s.y * 0.9f, 0.055f), darkMat, Quaternion.Euler(15, 0, 0)); // grip
            Part(weaponRoot, new Vector3(0, s.y * 0.38f, s.z * 0.05f), new Vector3(s.x * 0.7f, s.y * 0.18f, s.z * 0.7f), darkMat); // top rail
            Part(weaponRoot, new Vector3(s.x * 0.51f, 0, 0), new Vector3(0.004f, 0.012f, s.z * 0.8f), accentMat);   // light strip
            Part(weaponRoot, new Vector3(-s.x * 0.51f, 0, 0), new Vector3(0.004f, 0.012f, s.z * 0.8f), accentMat);
            var barrelLen = def.cls == WeaponClass.Sniper ? 0.45f : def.cls == WeaponClass.Shotgun ? 0.25f : 0.12f;
            Part(weaponRoot, new Vector3(0, s.y * 0.08f, s.z * 0.5f + barrelLen * 0.5f), new Vector3(s.x * 0.45f, s.x * 0.45f, barrelLen), darkMat);
            if (def.mag > 6) Part(weaponRoot, new Vector3(0, -s.y * 0.5f, s.z * 0.08f), new Vector3(s.x * 0.7f, s.y * 0.75f, 0.05f), darkMat, Quaternion.Euler(-8, 0, 0));
            if (def.cls == WeaponClass.Rifle || def.cls == WeaponClass.Sniper || def.cls == WeaponClass.Shotgun || def.cls == WeaponClass.Tech)
                Part(weaponRoot, new Vector3(0, -s.y * 0.1f, -s.z * 0.55f), new Vector3(s.x * 0.8f, s.y * 0.8f, 0.2f), darkMat);   // stock
            if (def.cls == WeaponClass.Revolver)
                Part(weaponRoot, new Vector3(0, s.y * 0.05f, s.z * 0.05f), new Vector3(s.x * 1.4f, s.x * 1.4f, 0.07f), gunMat);
            if (def.scoped)
            {
                Part(weaponRoot, new Vector3(0, s.y * 0.62f, s.z * 0.05f), new Vector3(0.05f, 0.05f, 0.3f), darkMat);
                Part(weaponRoot, new Vector3(0, s.y * 0.62f, s.z * 0.05f + 0.151f), new Vector3(0.04f, 0.04f, 0.002f), accentMat);
            }
            else Part(weaponRoot, new Vector3(0, s.y * 0.5f, -s.z * 0.1f), new Vector3(0.012f, 0.012f, 0.012f), accentMat); // holo sight dot
            var m = new GameObject("Muzzle").transform;
            m.SetParent(weaponRoot, false);
            m.localPosition = new Vector3(0, s.y * 0.08f, s.z * 0.5f + barrelLen + 0.02f);
            muzzle = m;
        }

        Transform Arm(string name, Vector3 pos, Vector3 euler)
        {
            var root = new GameObject(name).transform;
            root.SetParent(vmSway, false);
            root.localPosition = pos;
            root.localRotation = Quaternion.Euler(euler);
            Part(root, new Vector3(0, 0, -0.22f), new Vector3(0.085f, 0.085f, 0.38f), sleeveMat);
            Part(root, new Vector3(0, 0, -0.04f), new Vector3(0.09f, 0.09f, 0.03f), Mats.Cached("cuff" + ColorUtility.ToHtmlStringRGB((Game.Profile ?? new CharacterProfile()).accent), () => Mats.Unlit((Game.Profile ?? new CharacterProfile()).accent * 2f)));
            var hand = Part(root, new Vector3(0, 0, 0.04f), new Vector3(0.075f, 0.05f, 0.1f), skinMat);
            Part(root, new Vector3(0.0f, 0.03f, 0.06f), new Vector3(0.07f, 0.02f, 0.06f), skinMat);
            return root;
        }

        Transform Part(Transform parent, Vector3 pos, Vector3 size, Material m, Quaternion? rot = null)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            Destroy(go.GetComponent<Collider>());
            go.layer = Layers.Player;
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localRotation = rot ?? Quaternion.identity;
            go.transform.localScale = size;
            var r = go.GetComponent<MeshRenderer>();
            r.sharedMaterial = m;
            r.shadowCastingMode = ShadowCastingMode.Off;
            r.receiveShadows = false;
            return go.transform;
        }

        void AnimateViewmodel(float dt)
        {
            var def = CurrentDef;
            // sway from mouse
            var look = Game.IsPlaying ? InputHub.Look : Vector2.zero;
            swayRot = Vector3.Lerp(swayRot, new Vector3(look.y * 1.2f, -look.x * 1.2f, -look.x * 1.5f), dt * 8f);
            float speed = pc.Velocity.Flat().magnitude;
            float t = Time.time * (pc.Sprinting ? 13f : 8.5f);
            float bobAmt = pc.Grounded ? Mathf.Clamp01(speed / 7f) * (1f - aimBlend * 0.85f) : 0f;
            var bob = new Vector3(Mathf.Sin(t * 0.5f) * 0.012f, -Mathf.Abs(Mathf.Cos(t * 0.5f)) * 0.012f, 0) * bobAmt * 1.6f;
            var breath = new Vector3(Mathf.Sin(Time.time * 1.3f) * 0.002f, Mathf.Sin(Time.time * 1.7f) * 0.002f, 0) * (1f - aimBlend);

            // wall pull back
            var cam = pc.Cam.transform;
            float pull = Physics.Raycast(cam.position, cam.forward, out var wh, 0.9f, Layers.ShootMask, QueryTriggerInteraction.Ignore) ? 1f - wh.distance / 0.9f : 0f;
            wallPull = Mathf.Lerp(wallPull, pull, dt * 10f);

            kick = Mathf.MoveTowards(kick, 0f, dt * 12f);
            var target = Vector3.zero;
            var rot = Vector3.zero;
            if (def != null && !def.IsMelee && vmWeapon != null)
            {
                var hip = new Vector3(0.17f, -0.17f, 0.36f);
                var ads = new Vector3(0f, -0.115f - def.size.y * 0.45f, 0.28f);
                vmWeapon.localPosition = Vector3.Lerp(hip, ads, aimBlend) + new Vector3(0, 0, -kick * 0.05f) + new Vector3(0, -wallPull * 0.08f, -wallPull * 0.15f);
                vmWeapon.localRotation = Quaternion.Euler(-kick * 4f - wallPull * 30f, wallPull * -20f, 0);
                if (Reloading)
                {
                    float rp = 1f - reloadTimer / Mathf.Max(0.01f, reloadDuration);
                    float dip = Mathf.Sin(rp * Mathf.PI);
                    vmWeapon.localPosition += new Vector3(0, -0.12f * dip, 0);
                    vmWeapon.localRotation *= Quaternion.Euler(25f * dip, 0, 35f * dip);
                }
                rightHand.localPosition = vmWeapon.localPosition + new Vector3(0.02f, -0.05f, -0.1f);
                rightHand.localRotation = Quaternion.Euler(6, -4, 0);
                var lh = vmWeapon.localPosition + new Vector3(-0.03f, -0.05f, def.size.z * 0.3f);
                if (Reloading) lh += new Vector3(0, -0.08f * Mathf.Sin((1f - reloadTimer / Mathf.Max(0.01f, reloadDuration)) * Mathf.PI * 2f), -0.1f);
                leftHand.localPosition = lh;
                leftHand.localRotation = Quaternion.Euler(10, 12, -30);
                // hide viewmodel when scoped
                vmSway.gameObject.SetActive(!ScopeActive);
            }
            else if (def != null)
            {
                vmSway.gameObject.SetActive(true);
                float mp = meleePhase >= 0f ? meleePhase : -1f;
                bool right = meleeCombo % 2 == 0;
                var rRest = new Vector3(0.2f, -0.24f, 0.3f); var lRest = new Vector3(-0.2f, -0.26f, 0.3f);
                if (Blocking) { rRest = new Vector3(0.1f, -0.1f, 0.32f); lRest = new Vector3(-0.1f, -0.1f, 0.34f); }
                Vector3 r = rRest, l = lRest;
                if (mp >= 0f)
                {
                    float punch = mp < 0.35f ? mp / 0.35f : 1f - (mp - 0.35f) / 0.65f;
                    if (def.cls == WeaponClass.Fists)
                    {
                        if (right) r = Vector3.Lerp(rRest, new Vector3(0.05f, -0.1f, 0.62f), punch);
                        else l = Vector3.Lerp(lRest, new Vector3(-0.05f, -0.1f, 0.62f), punch);
                    }
                    else
                    {
                        r = Vector3.Lerp(rRest, new Vector3(-0.1f, -0.15f, 0.5f), punch);
                    }
                }
                rightHand.localPosition = r; leftHand.localPosition = l;
                rightHand.localRotation = Quaternion.Euler(8, -6, 0);
                leftHand.localRotation = Quaternion.Euler(10, 8, 0);
                if (vmWeapon != null && def.cls == WeaponClass.Melee)
                {
                    vmWeapon.localPosition = r + new Vector3(0, 0.02f, 0.1f);
                    float swing = mp >= 0f ? Mathf.Sin(Mathf.Clamp01(mp) * Mathf.PI) : 0f;
                    vmWeapon.localRotation = Quaternion.Euler(-40 + swing * 90f, swing * (right ? -70f : 70f), swing * 40f);
                    if (Blocking) vmWeapon.localRotation = Quaternion.Euler(-10, -70, 80);
                }
            }
            if (bashTimer >= 0f && vmWeapon != null)
            {
                float b = Mathf.Sin(Mathf.Clamp01(bashTimer / 0.45f) * Mathf.PI);
                vmWeapon.localPosition += new Vector3(-0.1f * b, 0.05f * b, 0.15f * b);
                vmWeapon.localRotation *= Quaternion.Euler(0, -40 * b, -30 * b);
            }
            float swapDip = Mathf.Clamp01(swapTimer / 0.35f);
            vmSway.localPosition = bob + breath + new Vector3(0, -swapDip * 0.25f, 0) + (pc.Sprinting && def != null && !def.IsMelee ? new Vector3(0.04f, -0.04f, 0) : Vector3.zero);
            vmSway.localRotation = Quaternion.Euler(swayRot * (1f - aimBlend * 0.8f)) * (pc.Sprinting && def != null && !def.IsMelee ? Quaternion.Euler(10, -30, 10) : Quaternion.identity);
        }

        // ----------------------------------------------------------------- loadout helpers for new games
        public void GiveStarter(Origin o)
        {
            var inv = Game.Inventory;
            if (o == Origin.GutterKid) { inv.AddWeapon(new WeaponInstance("kite9", 1), true); inv.AddWeapon(new WeaponInstance("rebar"), true); }
            else if (o == Origin.CorpWashout) inv.AddWeapon(new WeaponInstance("kite9", 0), true);
            else inv.AddWeapon(new WeaponInstance("mauler", 0), true);
            inv.Add("ammo_light", 60, false);
            inv.Add("ammo_shells", o == Origin.BadlandsRunner ? 24 : 0, false);
            inv.Add("medkit", 2, false);
            inv.Add("frag", 1, false);
            inv.Add("noodle_cup", 2, false);
            slot = 0;
        }
    }
}
