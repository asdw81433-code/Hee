using UnityEngine;
using UnityEngine.Rendering;

namespace NeonBay
{
    public class Appearance
    {
        public Color skin = Palette.SkinTones[2];
        public bool chromeSkin;
        public int hair = 2;
        public Color hairColor = Palette.HairColors[0];
        public int beard;
        public Color beardColor = Palette.HairColors[0];
        public int brows;
        public bool female;
        public float jaw = 0.5f;        // 0 narrow .. 1 square
        public float noseWidth = 1f;
        public float muscle = 0.4f;     // 0 soft .. 1 shredded
        public Color jacket = new Color(0.15f, 0.15f, 0.18f);
        public Color pants = new Color(0.1f, 0.1f, 0.12f);
        public Color accent = Palette.Cyan;
        public float height = 1f;
        public float bulk = 1f;
        public bool helmet, mask, visor, tattoo, chromeArm;
        public Color eyes = Palette.Cyan;
        public int outfit;              // 0 street clothes, 1 boxing trunks + gloves
        public int sleeves = 2;         // 0 tank, 1 short, 2 long
        public Color trunks = new Color(0.7f, 0.05f, 0.1f);
        public Color gloves = new Color(0.75f, 0.04f, 0.06f);
        public Color boots = new Color(0.08f, 0.08f, 0.09f);

        public Appearance Clone() => (Appearance)MemberwiseClone();

        public static Appearance FromProfile(CharacterProfile p)
        {
            var hc = Palette.HairColors[Mathf.Clamp(p.hairColor, 0, Palette.HairColors.Length - 1)];
            return new Appearance
            {
                skin = Palette.SkinTones[Mathf.Clamp(p.skin, 0, Palette.SkinTones.Length - 1)],
                chromeSkin = p.skin == Palette.SkinTones.Length - 1,
                hair = Mathf.Clamp(p.hairStyle, 0, BodyBuilder.HairStyles - 1),
                hairColor = hc,
                beard = Mathf.Clamp(p.beard, 0, BodyBuilder.BeardStyles - 1),
                beardColor = p.beardColor < 0 ? hc * 0.85f : Palette.HairColors[Mathf.Clamp(p.beardColor, 0, Palette.HairColors.Length - 1)],
                brows = Mathf.Clamp(p.brows, 0, BodyBuilder.BrowStyles - 1),
                female = p.female,
                jaw = p.jaw,
                muscle = p.muscle,
                jacket = p.jacket,
                pants = new Color(0.08f, 0.08f, 0.1f),
                accent = p.accent,
                height = p.height,
                bulk = p.frame == 0 ? 0.9f : p.frame == 1 ? 1f : 1.2f,
                tattoo = p.faceTattoo,
                eyes = p.eyeColor,
                chromeArm = p.origin == Origin.BadlandsRunner,
                trunks = Boxing.TrunkColors[Mathf.Clamp(p.trunksColor, 0, Boxing.TrunkColors.Length - 1)],
                gloves = Boxing.GloveColors[Mathf.Clamp(p.gloveColor, 0, Boxing.GloveColors.Length - 1)],
            };
        }

        public static Appearance Random(FactionId f, Rng r)
        {
            var a = new Appearance
            {
                skin = r.Pick(Palette.SkinTones),
                hair = r.Range(0, BodyBuilder.HairStyles),
                hairColor = r.Pick(Palette.HairColors),
                height = r.Range(0.92f, 1.08f),
                bulk = r.Range(0.9f, 1.15f),
                eyes = r.Pick(Palette.Neon),
                female = r.Chance(0.35f),
                jaw = r.Range(0.1f, 1f),
                noseWidth = r.Range(0.9f, 1.2f),
                muscle = r.Range(0.1f, 0.7f),
                brows = r.Chance(0.85f) ? r.Range(0, 3) : 3,
                sleeves = r.Chance(0.7f) ? 2 : r.Range(0, 2),
            };
            a.chromeSkin = a.skin == Palette.SkinTones[Palette.SkinTones.Length - 1];
            // natural hair colours are far more common than neon dye
            if (r.Chance(0.65f)) a.hairColor = Palette.HairColors[r.Range(0, 4)];
            a.beard = a.female ? 0 : r.Chance(0.55f) ? r.Range(1, BodyBuilder.BeardStyles) : 0;
            a.beardColor = a.hairColor * 0.85f;
            if (a.female)
            {
                a.height *= 0.95f; a.bulk = Mathf.Min(a.bulk, 1.05f);
                a.hair = r.Pick(4, 6, 7, 8, 9, 10, 12, 13, 1, 5);
            }
            switch (f)
            {
                case FactionId.Jackals:
                    a.jacket = r.Chance(0.5f) ? new Color(0.5f, 0.22f, 0.05f) : new Color(0.08f, 0.07f, 0.06f); a.pants = new Color(0.12f, 0.1f, 0.08f);
                    a.accent = Palette.Orange; a.hair = r.Chance(0.6f) ? r.Pick(5, 11) : a.hair; a.chromeArm = r.Chance(0.4f); a.tattoo = true; a.sleeves = r.Pick(0, 1, 2); break;
                case FactionId.Lotus:
                    a.jacket = r.Chance(0.5f) ? new Color(0.05f, 0.05f, 0.06f) : new Color(0.35f, 0.03f, 0.08f); a.pants = new Color(0.04f, 0.04f, 0.05f);
                    a.accent = Palette.Magenta; a.hair = r.Chance(0.5f) ? r.Pick(4, 9, 12) : 2; a.visor = r.Chance(0.4f); a.sleeves = 2; break;
                case FactionId.Helix:
                    a.jacket = new Color(0.82f, 0.84f, 0.86f); a.pants = new Color(0.25f, 0.27f, 0.3f); a.accent = Palette.White; a.helmet = true; a.visor = true; a.bulk *= 1.1f; a.sleeves = 2; break;
                case FactionId.Police:
                    a.jacket = new Color(0.07f, 0.1f, 0.22f); a.pants = new Color(0.05f, 0.06f, 0.12f); a.accent = Palette.Blue; a.helmet = true; a.visor = true; a.bulk *= 1.08f; a.sleeves = 2; break;
                case FactionId.Raiders:
                    a.jacket = new Color(0.35f, 0.24f, 0.15f); a.pants = new Color(0.2f, 0.15f, 0.1f); a.accent = Palette.Red; a.mask = true; a.chromeArm = r.Chance(0.5f); a.bulk *= 1.05f; a.hair = r.Pick(7, 0, 11, 5); break;
                case FactionId.Saints:
                    a.jacket = new Color(0.08f, 0.2f, 0.12f); a.pants = new Color(0.05f, 0.06f, 0.05f); a.accent = Palette.Green; a.visor = true; break;
                default:
                    a.jacket = Color.HSVToRGB(r.Value, r.Range(0.2f, 0.7f), r.Range(0.15f, 0.7f));
                    a.pants = Color.HSVToRGB(r.Value, r.Range(0f, 0.4f), r.Range(0.08f, 0.35f));
                    a.accent = r.Pick(Palette.Neon); a.visor = r.Chance(0.15f); a.tattoo = r.Chance(0.2f); break;
            }
            return a;
        }
    }

    /// <summary>
    /// A procedural humanoid with a 17-bone skeleton, skinned anatomy, a face rig, injuries, spring-driven hit reactions,
    /// code-driven animation (walk/run/aim/cower/melee + IK for boxing) and a full physics ragdoll.
    /// </summary>
    public class HumanoidRig : MonoBehaviour
    {
        public Transform hips, torso, chest, neck, head, jaw, shoulderL, shoulderR, elbowL, elbowR, handL, handR, thighL, thighR, kneeL, kneeR, ankleL, ankleR;
        public Transform weapon;
        public Damageable owner;
        public Appearance look;
        public FaceRig face;
        public InjuryState injury;
        public RagdollController ragdollCtl;
        public SkinnedMeshRenderer bodyRenderer, headRenderer;
        public int lod;
        public bool ragdolled;
        float phase;
        float crouchBlend, aimBlend, cowerBlend, idleT;
        int posedFrame = -1, lookFrame = -1;
        Vector3 lookTarget;
        float lookYaw, lookPitch;

        // additive spring reactions (degrees)
        Vector3 headSnap, headSnapV, chestSnap, chestSnapV, hipSnap, hipSnapV;

        int farFrame = -1; bool far;
        public bool forceNear;
        public bool FarFromCamera
        {
            get
            {
                if (forceNear) return false;
                if (farFrame == Time.frameCount) return far;
                farFrame = Time.frameCount;
                var c = Game.Cam;
                far = c == null || hips == null || (c.transform.position - hips.position).sqrMagnitude > 26f * 26f;
                return far;
            }
        }

        public float Scale => transform.lossyScale.y;

        public static HumanoidRig Build(Transform parent, Appearance a, Damageable owner, bool hitboxes, int lod = 0)
        {
            var rootGo = new GameObject("Rig");
            rootGo.transform.SetParent(parent, false);
            var rig = rootGo.AddComponent<HumanoidRig>();
            rig.owner = owner;
            rig.look = a;
            rig.lod = lod;
            rootGo.transform.localScale = Vector3.one * Mathf.Clamp(a.height, 0.85f, 1.15f);
            BodyBuilder.BuildSkeleton(rig, rootGo.transform, a);
            BodyBuilder.BuildBody(rig, a, lod);
            BodyBuilder.BuildHead(rig, a, lod);
            if (lod < 2)
            {
                rig.face = FaceRig.Build(rig, a, lod);
                BodyBuilder.BuildStrands(rig, a, lod);
            }
            if (lod < 2) rig.injury = InjuryState.Attach(rig, a);
            if (hitboxes || lod < 2) rig.BuildColliders(hitboxes ? owner : null, a);
            rig.ragdollCtl = rootGo.AddComponent<RagdollController>();
            rig.ragdollCtl.Init(rig);
            Util.SetLayerRecursive(rootGo, Layers.Actors);
            rig.phase = Random.Range(0f, 6.28f);
            return rig;
        }

        void BuildColliders(Damageable owner, Appearance a)
        {
            float b = BodyBuilder.Dims.Of(a).b;
            Box(hips, new Vector3(0, -0.03f, 0), new Vector3(0.3f * b, 0.2f, 0.2f * b), owner, 0.9f, false);
            Capsule(torso, new Vector3(0, 0.1f, 0), 0.12f * b, 0.28f, 1, owner, 1f, false);
            Box(chest, new Vector3(0, 0.12f, 0), new Vector3(0.36f * b, 0.3f, 0.22f * b), owner, 1f, false);
            Sphere(head, new Vector3(0, 0.13f, 0.01f), 0.115f, owner, 2.2f, true);
            Capsule(shoulderL, new Vector3(0, -0.145f, 0), 0.05f * b, 0.36f, 1, owner, 0.6f, false);
            Capsule(shoulderR, new Vector3(0, -0.145f, 0), 0.05f * b, 0.36f, 1, owner, 0.6f, false);
            Capsule(elbowL, new Vector3(0, -0.17f, 0), 0.045f, 0.42f, 1, owner, 0.55f, false);
            Capsule(elbowR, new Vector3(0, -0.17f, 0), 0.045f, 0.42f, 1, owner, 0.55f, false);
            Capsule(thighL, new Vector3(0, -0.22f, 0), 0.075f * b, 0.52f, 1, owner, 0.7f, false);
            Capsule(thighR, new Vector3(0, -0.22f, 0), 0.075f * b, 0.52f, 1, owner, 0.7f, false);
            Capsule(kneeL, new Vector3(0, -0.22f, 0), 0.055f, 0.5f, 1, owner, 0.6f, false);
            Capsule(kneeR, new Vector3(0, -0.22f, 0), 0.055f, 0.5f, 1, owner, 0.6f, false);
            Box(ankleL, new Vector3(0, -0.03f, 0.05f), new Vector3(0.09f, 0.06f, 0.25f), owner, 0.5f, false);
            Box(ankleR, new Vector3(0, -0.03f, 0.05f), new Vector3(0.09f, 0.06f, 0.25f), owner, 0.5f, false);
        }

        static GameObject HB(Transform bone, Damageable owner, float mult, bool isHead)
        {
            var go = new GameObject("HB_" + bone.name);
            go.transform.SetParent(bone, false);
            if (owner != null)
            {
                var hb = go.AddComponent<Hitbox>();
                hb.owner = owner; hb.multiplier = mult; hb.head = isHead;
            }
            return go;
        }
        static void Box(Transform bone, Vector3 c, Vector3 size, Damageable o, float mult, bool isHead) { var bc = HB(bone, o, mult, isHead).AddComponent<BoxCollider>(); bc.center = c; bc.size = size; }
        static void Sphere(Transform bone, Vector3 c, float r, Damageable o, float mult, bool isHead) { var sc = HB(bone, o, mult, isHead).AddComponent<SphereCollider>(); sc.center = c; sc.radius = r; }
        static void Capsule(Transform bone, Vector3 c, float r, float h, int dir, Damageable o, float mult, bool isHead) { var cc = HB(bone, o, mult, isHead).AddComponent<CapsuleCollider>(); cc.center = c; cc.radius = r; cc.height = h; cc.direction = dir; }

        public void AttachWeapon(WeaponDef def)
        {
            if (weapon != null) Destroy(weapon.gameObject);
            if (def == null || def.cls == WeaponClass.Fists) return;
            var go = new GameObject("NpcWeapon");
            go.transform.SetParent(handR, false);
            go.transform.localPosition = new Vector3(0, -0.06f, 0.02f);
            go.transform.localRotation = Quaternion.Euler(90, 0, 0);
            var body = GameObject.CreatePrimitive(PrimitiveType.Cube);
            Destroy(body.GetComponent<Collider>());
            body.transform.SetParent(go.transform, false);
            body.transform.localScale = def.IsMelee ? new Vector3(0.04f, 0.04f, def.size.z) : new Vector3(def.size.x, def.size.y * 0.7f, def.size.z);
            body.transform.localPosition = new Vector3(0, 0, def.size.z * 0.4f);
            body.GetComponent<MeshRenderer>().sharedMaterial = Mats.Cached("npc_gun", () => Mats.Lit(new Color(0.1f, 0.1f, 0.11f), null, 0.6f, 0.8f));
            var strip = GameObject.CreatePrimitive(PrimitiveType.Cube);
            Destroy(strip.GetComponent<Collider>());
            strip.transform.SetParent(go.transform, false);
            strip.transform.localScale = new Vector3(def.size.x * 1.05f, 0.01f, def.size.z * 0.7f);
            strip.transform.localPosition = new Vector3(0, def.size.y * 0.36f, def.size.z * 0.4f);
            strip.GetComponent<MeshRenderer>().sharedMaterial = Mats.Cached("npcacc" + ColorUtility.ToHtmlStringRGB(def.accent), () => Mats.Unlit(def.accent * 2.5f));
            weapon = go.transform;
            Util.SetLayerRecursive(go, Layers.Actors);
        }

        public Vector3 MuzzlePos => weapon != null ? weapon.position + weapon.forward * 0.5f : (handR != null ? handR.position : transform.position + Vector3.up * 1.4f);
        public Vector3 HeadPos => head != null ? head.TransformPoint(new Vector3(0, 0.13f, 0.02f)) : transform.position + Vector3.up * 1.7f;
        public Vector3 ChestPos => chest != null ? chest.TransformPoint(new Vector3(0, 0.1f, 0.05f)) : transform.position + Vector3.up * 1.3f;
        public Transform NearestBone(Vector3 p)
        {
            Transform best = hips; float bd = float.MaxValue;
            foreach (var t in new[] { hips, torso, chest, head, shoulderL, elbowL, shoulderR, elbowR, thighL, kneeL, thighR, kneeR })
            {
                if (t == null) continue;
                // compare against the middle of the bone, not its joint
                var mid = t == head ? t.TransformPoint(new Vector3(0, 0.12f, 0)) : t == chest || t == torso ? t.TransformPoint(new Vector3(0, 0.12f, 0)) : t == hips ? t.position : t.TransformPoint(new Vector3(0, -0.15f, 0));
                float d = (mid - p).sqrMagnitude;
                if (d < bd) { bd = d; best = t; }
            }
            return best;
        }

        public Vector3 ChinPos => head != null ? head.TransformPoint(new Vector3(0, 0.04f, 0.09f)) : transform.position + Vector3.up * 1.6f;

        // ================================================================== street animation
        public void Animate(float speed, bool aiming, bool crouch, float dt, bool cower = false, bool melee = false, float meleeT = 0f)
        {
            if (ragdolled || hips == null) return;
            posedFrame = Time.frameCount;
            float amp = Mathf.Clamp01(speed / 4.5f);
            float run = Mathf.Clamp01((speed - 3.6f) / 3f);
            float stride = Mathf.Lerp(1.35f, 2.5f, run);
            phase += dt * (Mathf.PI * 2f * speed / stride + 0.0001f);
            idleT += dt;
            crouchBlend = Mathf.MoveTowards(crouchBlend, crouch || cower ? 1f : 0f, dt * 4f);
            cowerBlend = Mathf.MoveTowards(cowerBlend, cower ? 1f : 0f, dt * 5f);
            aimBlend = Mathf.MoveTowards(aimBlend, aiming ? 1f : 0f, dt * 6f);
            float s = Mathf.Sin(phase), c = Mathf.Cos(phase);
            float cr = crouchBlend;

            // legs
            float A = (26f + run * 16f) * amp;
            float kneeK = (38f + run * 50f) * amp;
            float thL = -s * A, thR = s * A;
            float knL = Mathf.Max(0f, c) * kneeK + 4f + amp * 6f, knR = Mathf.Max(0f, -c) * kneeK + 4f + amp * 6f;
            thighL.localRotation = Quaternion.Euler(thL - 68f * cr, 0, -2f);
            thighR.localRotation = Quaternion.Euler(thR - 68f * cr, 0, 2f);
            kneeL.localRotation = Quaternion.Euler(knL + 104f * cr, 0, 0);
            kneeR.localRotation = Quaternion.Euler(knR + 104f * cr, 0, 0);
            ankleL.localRotation = Quaternion.Euler(-(thL - 68f * cr) * 0.55f - (knL + 104f * cr) * 0.45f + Mathf.Max(0f, s) * 18f * amp, 0, 2f);
            ankleR.localRotation = Quaternion.Euler(-(thR - 68f * cr) * 0.55f - (knR + 104f * cr) * 0.45f + Mathf.Max(0f, -s) * 18f * amp, 0, -2f);

            // pelvis and spine
            float idleSway = Mathf.Sin(idleT * 0.7f) * (1f - amp);
            float bob = Mathf.Abs(c) * (0.02f + run * 0.03f) * amp;
            hips.localPosition = new Vector3(s * 0.018f * amp + idleSway * 0.012f, 0.98f - 0.33f * cr - 0.015f * run + bob - 0.02f * amp, 0);
            hips.localRotation = Quaternion.Euler(3f * run, s * 7f * amp, idleSway * 2f);
            float breathe = Mathf.Sin(idleT * (1.3f + run * 1.5f));
            torso.localRotation = Quaternion.Euler(3f * amp + 9f * run + 16f * cr + cowerBlend * 18f, -s * 5f * amp, -idleSway * 1.5f);
            chest.localRotation = Quaternion.Euler(breathe * 1.2f + 3f * run, -s * 7f * amp + aimBlend * 12f, 0);
            neck.localRotation = Quaternion.Euler(-4f * amp - 8f * run - 10f * cr + cowerBlend * 12f, s * 3f * amp, 0);
            head.localRotation = Quaternion.Euler(-(3f * amp + 9f * run) * 0.5f + breathe * 0.8f, 0, 0);

            // arms
            float armA = (24f + run * 26f) * amp * (1f - aimBlend);
            float elb = -(14f + 18f * amp + 62f * run);
            var restL = Quaternion.Euler(s * armA, 0, -5f - run * 4f);
            var restR = Quaternion.Euler(-s * armA, 0, 5f + run * 4f);
            var elbL = Quaternion.Euler(elb - Mathf.Max(0f, -s) * 18f * amp, 0, 0);
            var elbR = Quaternion.Euler(elb - Mathf.Max(0f, s) * 18f * amp, 0, 0);
            if (cowerBlend > 0.01f)
            {
                restL = Quaternion.Slerp(restL, Quaternion.Euler(-150f, 0, -25f), cowerBlend);
                restR = Quaternion.Slerp(restR, Quaternion.Euler(-150f, 0, 25f), cowerBlend);
                elbL = Quaternion.Slerp(elbL, Quaternion.Euler(-105f, 0, 0), cowerBlend);
                elbR = Quaternion.Slerp(elbR, Quaternion.Euler(-105f, 0, 0), cowerBlend);
            }
            if (melee)
            {
                float k = Mathf.Sin(Mathf.Clamp01(meleeT) * Mathf.PI);
                float wind = Mathf.Clamp01(1f - meleeT * 3f);
                restR = Quaternion.Euler(-55f - 45f * k + 20f * wind, -10f + 30f * k, 25f - 10f * k);
                elbR = Quaternion.Euler(-95f + 75f * k, 0, 0);
                restL = Quaternion.Euler(-60f, 25f, -20f);
                elbL = Quaternion.Euler(-110f, 0, 0);
                chest.localRotation *= Quaternion.Euler(0, -20f * wind + 25f * k, 0);
            }
            shoulderL.localRotation = Quaternion.Slerp(restL, Quaternion.Euler(-72f, 38f, 0), aimBlend);
            shoulderR.localRotation = Quaternion.Slerp(restR, Quaternion.Euler(-86f, -4f, 0), aimBlend);
            elbowL.localRotation = Quaternion.Slerp(elbL, Quaternion.Euler(-40f, 0, 0), aimBlend);
            elbowR.localRotation = Quaternion.Slerp(elbR, Quaternion.Euler(-6f, 0, 0), aimBlend);
            handL.localRotation = Quaternion.Euler(0, 0, 0);
            handR.localRotation = Quaternion.Euler(-aimBlend * 4f, 0, 0);
        }

        /// <summary>Marks the pose as freshly written this frame (for custom posers like the boxing system).</summary>
        public void MarkPosed() => posedFrame = Time.frameCount;

        public void LookAt(Vector3 worldPos)
        {
            if (ragdolled || head == null) return;
            lookTarget = worldPos;
            lookFrame = Time.frameCount;
            if (face != null) face.lookTarget = worldPos;
        }

        // ================================================================== IK helpers (used by boxing)
        /// <summary>Two-bone arm IK. target = wrist position, elbowHint = where the elbow should point, backOfHand = knuckle orientation.</summary>
        public void ArmIK(bool right, Vector3 target, Vector3 elbowHint, Vector3 backOfHand)
        {
            var sh = right ? shoulderR : shoulderL;
            var el = right ? elbowR : elbowL;
            var hd = right ? handR : handL;
            float sc = Scale;
            float L1 = 0.29f * sc, L2 = 0.26f * sc;
            var a = sh.position;
            var d = target - a;
            float dist = Mathf.Clamp(d.magnitude, Mathf.Abs(L1 - L2) + 0.02f * sc, L1 + L2 - 0.002f);
            var dir = d.sqrMagnitude > 1e-8f ? d.normalized : -chest.up;
            var hint = Vector3.ProjectOnPlane(elbowHint - a, dir);
            if (hint.sqrMagnitude < 1e-6f) hint = Vector3.ProjectOnPlane(-chest.up, dir);
            hint.Normalize();
            float cosA = Mathf.Clamp((L1 * L1 + dist * dist - L2 * L2) / (2f * L1 * dist), -1f, 1f);
            float angA = Mathf.Acos(cosA);
            var elbowPos = a + (dir * Mathf.Cos(angA) + hint * Mathf.Sin(angA)) * L1;
            var wrist = a + dir * dist;
            var up1 = (elbowPos - a).normalized;
            var f1 = Vector3.ProjectOnPlane(wrist - elbowPos, up1);
            if (f1.sqrMagnitude < 1e-6f) f1 = Vector3.ProjectOnPlane(-hint, up1);
            sh.rotation = Quaternion.LookRotation(f1.normalized, -up1);
            var up2 = (wrist - elbowPos).normalized;
            var f2 = Vector3.ProjectOnPlane(backOfHand, up2);
            if (f2.sqrMagnitude < 1e-6f) f2 = Vector3.ProjectOnPlane(chest.forward, up2);
            el.rotation = Quaternion.LookRotation(f2.normalized, -up2);
            hd.localRotation = Quaternion.identity;
        }

        /// <summary>Two-bone leg IK with a flat foot facing footForward.</summary>
        public void LegIK(bool right, Vector3 ankleTarget, Vector3 kneeForward, Vector3 footForward)
        {
            var th = right ? thighR : thighL;
            var kn = right ? kneeR : kneeL;
            var an = right ? ankleR : ankleL;
            float sc = Scale;
            float L1 = 0.44f * sc, L2 = 0.43f * sc;
            var a = th.position;
            var d = ankleTarget - a;
            float dist = Mathf.Clamp(d.magnitude, 0.25f * sc, L1 + L2 - 0.003f);
            var dir = d.normalized;
            var hint = Vector3.ProjectOnPlane(kneeForward, dir);
            if (hint.sqrMagnitude < 1e-6f) hint = Vector3.ProjectOnPlane(transform.forward, dir);
            hint.Normalize();
            float cosA = Mathf.Clamp((L1 * L1 + dist * dist - L2 * L2) / (2f * L1 * dist), -1f, 1f);
            float angA = Mathf.Acos(cosA);
            var kneePos = a + (dir * Mathf.Cos(angA) + hint * Mathf.Sin(angA)) * L1;
            var ankle = a + dir * dist;
            var up1 = (kneePos - a).normalized;
            var f1 = -Vector3.ProjectOnPlane(ankle - kneePos, up1);
            if (f1.sqrMagnitude < 1e-6f) f1 = Vector3.ProjectOnPlane(hint, up1);
            th.rotation = Quaternion.LookRotation(f1.normalized, -up1);
            var up2 = (ankle - kneePos).normalized;
            var f2 = Vector3.ProjectOnPlane(footForward, up2);
            if (f2.sqrMagnitude < 1e-6f) f2 = transform.forward;
            kn.rotation = Quaternion.LookRotation(f2.normalized, -up2);
            var ff = Vector3.ProjectOnPlane(footForward, Vector3.up);
            if (ff.sqrMagnitude > 1e-6f) an.rotation = Quaternion.LookRotation(ff.normalized, Vector3.up);
        }

        // ================================================================== reactions
        /// <summary>Physical + facial reaction to a hit. dirWorld = travel direction of the blow, power ~0..1.5.</summary>
        public void React(Vector3 dirWorld, Vector3 pointWorld, float power, bool headHit, bool bodyHit)
        {
            if (ragdolled || head == null) return;
            power = Mathf.Clamp(power, 0f, 2f);
            var dirHead = head.InverseTransformDirection(dirWorld.normalized);
            if (headHit)
            {
                headSnapV += new Vector3((dirHead.z * 0.75f - dirHead.y) * 420f, dirHead.x * 520f, -dirHead.x * 200f) * power;
                chestSnapV += new Vector3(-30f, dirHead.x * 60f, 0) * power;
            }
            if (bodyHit)
            {
                var dirChest = chest.InverseTransformDirection(dirWorld.normalized);
                chestSnapV += new Vector3(260f, dirChest.x * 160f, -dirChest.x * 120f) * power;
                hipSnapV += new Vector3(-90f, 0, 0) * power;
                headSnapV += new Vector3(120f, 0, 0) * power;
            }
            if (face != null) face.Hit(dirHead, power, bodyHit && !headHit);
        }

        void Spring(ref Vector3 x, ref Vector3 v, float k, float c, float dt, float limit)
        {
            v += (-x * k - v * c) * dt;
            x += v * dt;
            x = Vector3.ClampMagnitude(x, limit);
        }

        void LateUpdate()
        {
            float dt = Time.deltaTime;
            if (dt <= 0f) return;
            ragdollCtl?.LateTick(dt);
            if (ragdolled)
            {
                if (face != null && face.ko) face.Tick(dt);
                return;
            }
            bool posed = posedFrame == Time.frameCount;
            // look-at, split over neck and head
            bool looking = lookFrame == Time.frameCount || lookFrame == Time.frameCount - 1;
            float ty = 0f, tp = 0f;
            if (looking && chest != null)
            {
                var local = chest.InverseTransformDirection((lookTarget - head.position).normalized);
                ty = Mathf.Clamp(Mathf.Atan2(local.x, local.z) * Mathf.Rad2Deg, -65f, 65f);
                tp = Mathf.Clamp(-Mathf.Asin(Mathf.Clamp(local.y, -1f, 1f)) * Mathf.Rad2Deg, -35f, 35f);
            }
            else if (face != null) face.lookTarget = null;
            lookYaw = Util.Damp(lookYaw, ty, 7f, dt);
            lookPitch = Util.Damp(lookPitch, tp, 7f, dt);
            Spring(ref headSnap, ref headSnapV, 180f, 13f, dt, 55f);
            Spring(ref chestSnap, ref chestSnapV, 95f, 11f, dt, 35f);
            Spring(ref hipSnap, ref hipSnapV, 110f, 12f, dt, 20f);
            if (posed)
            {
                neck.localRotation *= Quaternion.Euler(lookPitch * 0.35f + headSnap.x * 0.35f, lookYaw * 0.4f + headSnap.y * 0.35f, headSnap.z * 0.35f);
                head.localRotation *= Quaternion.Euler(lookPitch * 0.65f + headSnap.x * 0.65f, lookYaw * 0.6f + headSnap.y * 0.65f, headSnap.z * 0.65f);
                chest.localRotation *= Quaternion.Euler(chestSnap);
                torso.localRotation *= Quaternion.Euler(hipSnap * 0.6f);
            }
            if (face != null && !FarFromCamera)
            {
                if (injury != null) { face.eyeClosureL = injury.EyeClosure(true); face.eyeClosureR = injury.EyeClosure(false); }
                face.Tick(dt);
            }
        }

        // ================================================================== ragdoll
        /// <summary>Death ragdoll: the body is detached from its owner and left as a corpse.</summary>
        public void Ragdoll(Vector3 force, Vector3 point)
        {
            if (ragdolled) return;
            ragdolled = true;
            if (face != null) { face.ko = true; face.Tick(0.016f); }
            foreach (var c in hips.GetComponentsInChildren<Hitbox>()) c.multiplier = 0f;
            ragdollCtl.Activate(force, point, true, 0.25f);
            var corpse = hips.gameObject.AddComponent<Corpse>();
            corpse.rb = ragdollCtl.HipsBody;
            if (weapon != null) weapon.SetParent(hips, true);
        }

        /// <summary>Non-lethal ragdoll that can recover (knockdowns).</summary>
        public void Knockdown(Vector3 force, Vector3 point, float stiffness = 0.35f)
        {
            if (ragdolled) return;
            ragdolled = true;
            ragdollCtl.Activate(force, point, false, stiffness);
        }

        public void RecoverFromRagdoll(Transform root, float floorY, float blend = 0.7f)
        {
            if (!ragdolled) return;
            ragdollCtl.Recover(root, floorY, blend);
            ragdolled = false;
            if (face != null) face.ko = false;
            headSnap = headSnapV = chestSnap = chestSnapV = hipSnap = hipSnapV = Vector3.zero;
        }
    }

    /// <summary>Freezes a ragdoll after it settles and removes it eventually.</summary>
    public class Corpse : MonoBehaviour
    {
        public Rigidbody rb;
        float t;
        bool frozen, relaxed;
        void Update()
        {
            t += Time.deltaTime;
            if (!relaxed && t > 0.3f)
            {
                // the stiff moment of the knockout passes and the body goes limp
                relaxed = true;
                foreach (var r in GetComponentsInChildren<Rigidbody>()) Util.SetDrag(r, 0.05f, 1.1f);
            }
            if (!frozen && t > 7f)
            {
                frozen = true;
                foreach (var j in GetComponentsInChildren<Joint>()) Destroy(j);
                foreach (var r in GetComponentsInChildren<Rigidbody>()) r.isKinematic = true;
            }
            if (t > 90f || (t > 10f && Game.HasPlayer && (Game.PlayerPos - transform.position).sqrMagnitude > 200f * 200f)) Destroy(gameObject);
        }
    }
}
