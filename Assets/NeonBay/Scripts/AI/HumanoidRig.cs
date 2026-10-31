using UnityEngine;
using UnityEngine.Rendering;

namespace NeonBay
{
    public class Appearance
    {
        public Color skin = Palette.SkinTones[2];
        public bool chromeSkin;
        public int hair = 1;
        public Color hairColor = Palette.HairColors[0];
        public Color jacket = new Color(0.15f, 0.15f, 0.18f);
        public Color pants = new Color(0.1f, 0.1f, 0.12f);
        public Color accent = Palette.Cyan;
        public float height = 1f;
        public float bulk = 1f;
        public bool helmet, mask, visor, tattoo, chromeArm;
        public Color eyes = Palette.Cyan;

        public static Appearance FromProfile(CharacterProfile p)
        {
            return new Appearance
            {
                skin = Palette.SkinTones[Mathf.Clamp(p.skin, 0, Palette.SkinTones.Length - 1)],
                chromeSkin = p.skin == Palette.SkinTones.Length - 1,
                hair = p.hairStyle,
                hairColor = Palette.HairColors[Mathf.Clamp(p.hairColor, 0, Palette.HairColors.Length - 1)],
                jacket = p.jacket,
                pants = new Color(0.08f, 0.08f, 0.1f),
                accent = p.accent,
                height = p.height,
                bulk = p.frame == 0 ? 0.9f : p.frame == 1 ? 1f : 1.2f,
                tattoo = p.faceTattoo,
                eyes = p.eyeColor,
                chromeArm = p.origin == Origin.BadlandsRunner
            };
        }

        public static Appearance Random(FactionId f, Rng r)
        {
            var a = new Appearance
            {
                skin = r.Pick(Palette.SkinTones),
                hair = r.Range(0, 5),
                hairColor = r.Pick(Palette.HairColors),
                height = r.Range(0.92f, 1.08f),
                bulk = r.Range(0.9f, 1.15f),
                eyes = r.Pick(Palette.Neon),
            };
            a.chromeSkin = a.skin == Palette.SkinTones[Palette.SkinTones.Length - 1];
            switch (f)
            {
                case FactionId.Jackals:
                    a.jacket = r.Chance(0.5f) ? new Color(0.5f, 0.22f, 0.05f) : new Color(0.08f, 0.07f, 0.06f); a.pants = new Color(0.12f, 0.1f, 0.08f);
                    a.accent = Palette.Orange; a.hair = r.Chance(0.6f) ? 2 : a.hair; a.chromeArm = r.Chance(0.4f); a.tattoo = true; break;
                case FactionId.Lotus:
                    a.jacket = r.Chance(0.5f) ? new Color(0.05f, 0.05f, 0.06f) : new Color(0.35f, 0.03f, 0.08f); a.pants = new Color(0.04f, 0.04f, 0.05f);
                    a.accent = Palette.Magenta; a.hair = r.Chance(0.5f) ? 1 : 3; a.visor = r.Chance(0.4f); break;
                case FactionId.Helix:
                    a.jacket = new Color(0.82f, 0.84f, 0.86f); a.pants = new Color(0.25f, 0.27f, 0.3f); a.accent = Palette.White; a.helmet = true; a.visor = true; a.bulk *= 1.1f; break;
                case FactionId.Police:
                    a.jacket = new Color(0.07f, 0.1f, 0.22f); a.pants = new Color(0.05f, 0.06f, 0.12f); a.accent = Palette.Blue; a.helmet = true; a.visor = true; a.bulk *= 1.08f; break;
                case FactionId.Raiders:
                    a.jacket = new Color(0.35f, 0.24f, 0.15f); a.pants = new Color(0.2f, 0.15f, 0.1f); a.accent = Palette.Red; a.mask = true; a.chromeArm = r.Chance(0.5f); a.bulk *= 1.05f; break;
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

    /// <summary>A procedural humanoid built from primitives, with code-driven animation and a physics ragdoll on death.</summary>
    public class HumanoidRig : MonoBehaviour
    {
        public Transform hips, torso, head, shoulderL, shoulderR, elbowL, elbowR, thighL, thighR, kneeL, kneeR, handR;
        public Transform weapon;
        public Damageable owner;
        float phase;
        float crouchBlend, aimBlend;
        public bool ragdolled;
        float hipsY = 0.95f;
        Vector3 lookDir;

        public static HumanoidRig Build(Transform parent, Appearance a, Damageable owner, bool hitboxes)
        {
            var rootGo = new GameObject("Rig");
            rootGo.transform.SetParent(parent, false);
            var rig = rootGo.AddComponent<HumanoidRig>();
            rig.owner = owner;
            rootGo.transform.localScale = new Vector3(a.bulk * 0.5f + 0.5f, a.height, a.bulk * 0.5f + 0.5f);

            var skin = Mats.Cached("skin" + ColorUtility.ToHtmlStringRGB(a.skin) + a.chromeSkin, () => Mats.Lit(a.skin, null, a.chromeSkin ? 0.85f : 0.35f, a.chromeSkin ? 0.85f : 0f));
            var chrome = Mats.Cached("npc_chrome", () => Mats.Lit(new Color(0.75f, 0.77f, 0.8f), null, 0.9f, 1f));
            var jacket = Mats.Cached("jk" + ColorUtility.ToHtmlStringRGB(a.jacket), () => Mats.Lit(a.jacket, Tex.Metal.albedo, 0.3f, 0.05f));
            var pants = Mats.Cached("pt" + ColorUtility.ToHtmlStringRGB(a.pants), () => Mats.Lit(a.pants, null, 0.2f));
            var hairM = Mats.Cached("hr" + ColorUtility.ToHtmlStringRGB(a.hairColor), () => Mats.Lit(a.hairColor, null, 0.45f));
            var glow = Mats.Cached("glow" + ColorUtility.ToHtmlStringRGB(a.accent), () => Mats.Unlit(a.accent * 3f));
            var eyes = Mats.Cached("eye" + ColorUtility.ToHtmlStringRGB(a.eyes), () => Mats.Unlit(a.eyes * 4f));
            var dark = Mats.Cached("npc_dark", () => Mats.Lit(new Color(0.05f, 0.05f, 0.06f), null, 0.5f, 0.5f));
            var visor = Mats.Cached("visor" + ColorUtility.ToHtmlStringRGB(a.accent), () => Mats.Emissive(new Color(0.02f, 0.02f, 0.03f), a.accent * 1.5f, null, null, 0.95f, 0.5f));

            float b = a.bulk;
            rig.hips = Node("Hips", rootGo.transform, new Vector3(0, 0.95f, 0));
            rig.torso = Node("Torso", rig.hips, Vector3.zero);
            Part(rig.torso, new Vector3(0, 0.3f, 0), new Vector3(0.42f * b, 0.6f, 0.25f * b), jacket, hitboxes ? owner : null, 1f, false, PrimitiveType.Cube);
            Part(rig.torso, new Vector3(0, 0.02f, 0), new Vector3(0.36f * b, 0.12f, 0.22f * b), pants, null, 1, false, PrimitiveType.Cube);
            Part(rig.torso, new Vector3(0, 0.38f, 0.128f * b), new Vector3(0.03f, 0.35f, 0.01f), glow, null, 1, false, PrimitiveType.Cube);
            Part(rig.torso, new Vector3(0, 0.62f, 0), new Vector3(0.1f, 0.1f, 0.1f), skin, null, 1, false, PrimitiveType.Cube);

            rig.head = Node("Head", rig.torso, new Vector3(0, 0.78f, 0));
            Part(rig.head, Vector3.zero, new Vector3(0.22f, 0.26f, 0.24f), skin, hitboxes ? owner : null, 2.2f, true, PrimitiveType.Sphere);
            if (a.visor) Part(rig.head, new Vector3(0, 0.03f, 0.1f), new Vector3(0.2f, 0.06f, 0.06f), visor, null, 1, false, PrimitiveType.Cube);
            else
            {
                Part(rig.head, new Vector3(0.05f, 0.03f, 0.11f), new Vector3(0.035f, 0.02f, 0.01f), eyes, null, 1, false, PrimitiveType.Cube);
                Part(rig.head, new Vector3(-0.05f, 0.03f, 0.11f), new Vector3(0.035f, 0.02f, 0.01f), eyes, null, 1, false, PrimitiveType.Cube);
            }
            if (a.tattoo) Part(rig.head, new Vector3(0.08f, -0.03f, 0.095f), new Vector3(0.01f, 0.07f, 0.01f), glow, null, 1, false, PrimitiveType.Cube);
            if (a.helmet)
            {
                Part(rig.head, new Vector3(0, 0.05f, -0.01f), new Vector3(0.26f, 0.22f, 0.28f), jacket, null, 1, false, PrimitiveType.Sphere);
                Part(rig.head, new Vector3(0, 0.03f, 0.11f), new Vector3(0.22f, 0.07f, 0.07f), visor, null, 1, false, PrimitiveType.Cube);
            }
            else if (a.mask)
            {
                Part(rig.head, new Vector3(0, -0.04f, 0.09f), new Vector3(0.2f, 0.14f, 0.08f), chrome, null, 1, false, PrimitiveType.Cube);
                Part(rig.head, new Vector3(0, 0.03f, 0.12f), new Vector3(0.16f, 0.025f, 0.02f), glow, null, 1, false, PrimitiveType.Cube);
            }
            else
            {
                switch (a.hair)
                {
                    case 1: Part(rig.head, new Vector3(0, 0.08f, -0.02f), new Vector3(0.23f, 0.14f, 0.24f), hairM, null, 1, false, PrimitiveType.Sphere); break;
                    case 2: Part(rig.head, new Vector3(0, 0.15f, -0.02f), new Vector3(0.05f, 0.12f, 0.24f), hairM, null, 1, false, PrimitiveType.Cube); break;
                    case 3: Part(rig.head, new Vector3(0, 0.02f, -0.05f), new Vector3(0.24f, 0.3f, 0.22f), hairM, null, 1, false, PrimitiveType.Sphere); break;
                    case 4: Part(rig.head, new Vector3(0, 0.15f, -0.06f), new Vector3(0.09f, 0.09f, 0.09f), hairM, null, 1, false, PrimitiveType.Sphere); Part(rig.head, new Vector3(0, 0.07f, -0.02f), new Vector3(0.22f, 0.1f, 0.23f), hairM, null, 1, false, PrimitiveType.Sphere); break;
                }
            }

            var armMatR = a.chromeArm ? chrome : jacket;
            rig.shoulderL = Node("ShoulderL", rig.torso, new Vector3(-0.27f * b, 0.55f, 0));
            rig.shoulderR = Node("ShoulderR", rig.torso, new Vector3(0.27f * b, 0.55f, 0));
            Part(rig.shoulderL, new Vector3(0, -0.15f, 0), new Vector3(0.11f * b, 0.32f, 0.11f * b), jacket, hitboxes ? owner : null, 0.75f, false, PrimitiveType.Cube);
            Part(rig.shoulderR, new Vector3(0, -0.15f, 0), new Vector3(0.11f * b, 0.32f, 0.11f * b), armMatR, hitboxes ? owner : null, 0.75f, false, PrimitiveType.Cube);
            rig.elbowL = Node("ElbowL", rig.shoulderL, new Vector3(0, -0.31f, 0));
            rig.elbowR = Node("ElbowR", rig.shoulderR, new Vector3(0, -0.31f, 0));
            Part(rig.elbowL, new Vector3(0, -0.13f, 0), new Vector3(0.09f, 0.27f, 0.09f), skin, null, 1, false, PrimitiveType.Cube);
            Part(rig.elbowR, new Vector3(0, -0.13f, 0), new Vector3(0.09f, 0.27f, 0.09f), a.chromeArm ? chrome : skin, null, 1, false, PrimitiveType.Cube);
            if (a.chromeArm) Part(rig.elbowR, new Vector3(0, -0.13f, 0.047f), new Vector3(0.02f, 0.2f, 0.01f), glow, null, 1, false, PrimitiveType.Cube);
            rig.handR = Node("HandR", rig.elbowR, new Vector3(0, -0.29f, 0.02f));

            rig.thighL = Node("ThighL", rig.hips, new Vector3(-0.11f * b, 0, 0));
            rig.thighR = Node("ThighR", rig.hips, new Vector3(0.11f * b, 0, 0));
            Part(rig.thighL, new Vector3(0, -0.23f, 0), new Vector3(0.15f * b, 0.46f, 0.15f * b), pants, hitboxes ? owner : null, 0.7f, false, PrimitiveType.Cube);
            Part(rig.thighR, new Vector3(0, -0.23f, 0), new Vector3(0.15f * b, 0.46f, 0.15f * b), pants, hitboxes ? owner : null, 0.7f, false, PrimitiveType.Cube);
            rig.kneeL = Node("KneeL", rig.thighL, new Vector3(0, -0.46f, 0));
            rig.kneeR = Node("KneeR", rig.thighR, new Vector3(0, -0.46f, 0));
            Part(rig.kneeL, new Vector3(0, -0.22f, 0), new Vector3(0.13f, 0.44f, 0.13f), pants, null, 1, false, PrimitiveType.Cube);
            Part(rig.kneeR, new Vector3(0, -0.22f, 0), new Vector3(0.13f, 0.44f, 0.13f), pants, null, 1, false, PrimitiveType.Cube);
            Part(rig.kneeL, new Vector3(0, -0.46f, 0.05f), new Vector3(0.13f, 0.06f, 0.26f), dark, null, 1, false, PrimitiveType.Cube);
            Part(rig.kneeR, new Vector3(0, -0.46f, 0.05f), new Vector3(0.13f, 0.06f, 0.26f), dark, null, 1, false, PrimitiveType.Cube);
            Util.SetLayerRecursive(rootGo, Layers.Actors);
            return rig;
        }

        static Transform Node(string name, Transform parent, Vector3 pos)
        {
            var t = new GameObject(name).transform;
            t.SetParent(parent, false);
            t.localPosition = pos;
            return t;
        }

        static void Part(Transform parent, Vector3 pos, Vector3 size, Material m, Damageable owner, float mult, bool head, PrimitiveType type)
        {
            var go = GameObject.CreatePrimitive(type);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localScale = size;
            go.GetComponent<MeshRenderer>().sharedMaterial = m;
            var col = go.GetComponent<Collider>();
            if (owner != null)
            {
                var hb = go.AddComponent<Hitbox>();
                hb.owner = owner; hb.multiplier = mult; hb.head = head;
            }
            else Destroy(col);
        }

        public void AttachWeapon(WeaponDef def)
        {
            if (weapon != null) Destroy(weapon.gameObject);
            if (def == null || def.cls == WeaponClass.Fists) return;
            var go = new GameObject("NpcWeapon");
            go.transform.SetParent(handR, false);
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
        public Vector3 HeadPos => head != null ? head.position : transform.position + Vector3.up * 1.7f;

        public void Animate(float speed, bool aiming, bool crouch, float dt, bool cower = false, bool melee = false, float meleeT = 0f)
        {
            if (ragdolled) return;
            float amp = Mathf.Clamp01(speed / 4.5f);
            phase += dt * (2.2f + speed * 1.55f);
            crouchBlend = Mathf.MoveTowards(crouchBlend, crouch || cower ? 1f : 0f, dt * 4f);
            aimBlend = Mathf.MoveTowards(aimBlend, aiming ? 1f : 0f, dt * 6f);
            float s = Mathf.Sin(phase), c = Mathf.Cos(phase);
            float thigh = s * 32f * amp, thighO = -s * 32f * amp;
            float kneeA = Mathf.Max(0f, -c) * 55f * amp + 5f, kneeB = Mathf.Max(0f, c) * 55f * amp + 5f;
            float cr = crouchBlend;
            thighL.localRotation = Quaternion.Euler(thigh - 70f * cr, 0, 0);
            thighR.localRotation = Quaternion.Euler(thighO - 70f * cr, 0, 0);
            kneeL.localRotation = Quaternion.Euler(kneeA + 100f * cr, 0, 0);
            kneeR.localRotation = Quaternion.Euler(kneeB + 100f * cr, 0, 0);
            hips.localPosition = new Vector3(0, hipsY - 0.32f * cr + Mathf.Abs(c) * 0.03f * amp, 0);
            torso.localRotation = Quaternion.Euler(4f * amp + 18f * cr + (cower ? 20f : 0f), s * 4f * amp, 0);

            float armSwing = -s * 28f * amp * (1f - aimBlend);
            if (cower)
            {
                shoulderL.localRotation = Quaternion.Euler(-150f, 0, 20f);
                shoulderR.localRotation = Quaternion.Euler(-150f, 0, -20f);
                elbowL.localRotation = Quaternion.Euler(-70f, 0, 0);
                elbowR.localRotation = Quaternion.Euler(-70f, 0, 0);
            }
            else if (melee)
            {
                float k = Mathf.Sin(Mathf.Clamp01(meleeT) * Mathf.PI);
                shoulderR.localRotation = Quaternion.Euler(-60f - 70f * k, -20f + 50f * k, 0);
                elbowR.localRotation = Quaternion.Euler(-40f + 30f * k, 0, 0);
                shoulderL.localRotation = Quaternion.Euler(-50f, 20f, 0);
                elbowL.localRotation = Quaternion.Euler(-70f, 0, 0);
            }
            else
            {
                shoulderL.localRotation = Quaternion.Slerp(Quaternion.Euler(armSwing, 0, 6f), Quaternion.Euler(-75f, 35f, 0), aimBlend);
                shoulderR.localRotation = Quaternion.Slerp(Quaternion.Euler(-armSwing, 0, -6f), Quaternion.Euler(-85f, -5f, 0), aimBlend);
                elbowL.localRotation = Quaternion.Slerp(Quaternion.Euler(-15f - amp * 20f, 0, 0), Quaternion.Euler(-35f, 0, 0), aimBlend);
                elbowR.localRotation = Quaternion.Slerp(Quaternion.Euler(-15f - amp * 20f, 0, 0), Quaternion.Euler(-5f, 0, 0), aimBlend);
            }
            // breathing
            head.localRotation = Quaternion.Euler(Mathf.Sin(Time.time * 1.1f) * 2f, 0, 0);
        }

        public void LookAt(Vector3 worldPos)
        {
            if (ragdolled || head == null) return;
            var d = (worldPos - head.position);
            var local = torso.InverseTransformDirection(d.normalized);
            float yaw = Mathf.Clamp(Mathf.Atan2(local.x, local.z) * Mathf.Rad2Deg, -60f, 60f);
            float pitch = Mathf.Clamp(-Mathf.Asin(Mathf.Clamp(local.y, -1, 1)) * Mathf.Rad2Deg, -40f, 40f);
            head.localRotation = Quaternion.Euler(pitch, yaw, 0);
        }

        /// <summary>Turns the rig into a physics ragdoll (torso + head, two arms, two legs).</summary>
        public void Ragdoll(Vector3 force, Vector3 point)
        {
            if (ragdolled) return;
            ragdolled = true;
            var root = transform;
            var playerCol = Game.Player != null ? Game.Player.GetComponent<CharacterController>() : null;
            hips.SetParent(null, true);
            var hipsRb = hips.gameObject.AddComponent<Rigidbody>();
            hipsRb.mass = 30f;
            Util.SetDrag(hipsRb, 0.1f, 0.5f);
            hipsRb.interpolation = RigidbodyInterpolation.Interpolate;
            AddLimb(shoulderL, hipsRb, 4f);
            AddLimb(shoulderR, hipsRb, 4f);
            AddLimb(thighL, hipsRb, 8f);
            AddLimb(thighR, hipsRb, 8f);
            foreach (var c in hips.GetComponentsInChildren<Collider>())
            {
                if (playerCol != null) Physics.IgnoreCollision(c, playerCol);
                var hb = c.GetComponent<Hitbox>();
                if (hb != null) hb.multiplier = 0f;
            }
            hipsRb.AddForceAtPosition(force, point, ForceMode.Impulse);
            var corpse = hips.gameObject.AddComponent<Corpse>();
            corpse.rb = hipsRb;
            if (weapon != null) weapon.SetParent(hips, true);
        }

        void AddLimb(Transform t, Rigidbody parentRb, float mass)
        {
            t.SetParent(hips, true);
            var rb = t.gameObject.AddComponent<Rigidbody>();
            rb.mass = mass;
            Util.SetDrag(rb, 0.1f, 0.6f);
            // make sure the limb has a collider (forearms/shins had none)
            if (t.GetComponentInChildren<Collider>() == null)
            {
                var cap = t.gameObject.AddComponent<CapsuleCollider>();
                cap.radius = 0.06f; cap.height = 0.6f; cap.center = new Vector3(0, -0.3f, 0);
            }
            var j = t.gameObject.AddComponent<CharacterJoint>();
            j.connectedBody = parentRb;
            j.enableProjection = true;
            var low = j.lowTwistLimit; low.limit = -30f; j.lowTwistLimit = low;
            var high = j.highTwistLimit; high.limit = 60f; j.highTwistLimit = high;
            var s1 = j.swing1Limit; s1.limit = 60f; j.swing1Limit = s1;
        }
    }

    /// <summary>Freezes a ragdoll after it settles and removes it eventually.</summary>
    public class Corpse : MonoBehaviour
    {
        public Rigidbody rb;
        float t;
        bool frozen;
        void Update()
        {
            t += Time.deltaTime;
            if (!frozen && t > 7f)
            {
                frozen = true;
                foreach (var r in GetComponentsInChildren<Rigidbody>())
                {
                    var j = r.GetComponent<Joint>();
                    if (j != null) Destroy(j);
                    r.isKinematic = true;
                }
            }
            if (t > 90f || (t > 10f && Game.HasPlayer && (Game.PlayerPos - transform.position).sqrMagnitude > 200f * 200f)) Destroy(gameObject);
        }
    }
}
