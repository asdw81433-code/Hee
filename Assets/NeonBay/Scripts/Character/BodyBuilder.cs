using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace NeonBay
{
    /// <summary>
    /// Builds the procedural character: skeleton, one skinned body mesh (anatomy + outfit) and one skinned head mesh
    /// (face, jaw, lips, teeth, hair, beard). Meshes are cached by appearance key so crowds stay cheap.
    /// </summary>
    public static class BodyBuilder
    {
        public const int HairStyles = 14, BeardStyles = 10, BrowStyles = 5;

        public static string HairName(int h) => h switch
        {
            0 => "Bald", 1 => "Buzz Cut", 2 => "Crew Cut", 3 => "High-Top Fade", 4 => "Slick Undercut", 5 => "Neon Mohawk",
            6 => "Afro", 7 => "Dreadlocks", 8 => "Cornrows", 9 => "Man Bun", 10 => "Long & Loose", 11 => "Spiked",
            12 => "Ponytail", _ => "Messy Crop"
        };

        public static string BeardName(int b) => b switch
        {
            0 => "Clean Shaven", 1 => "Stubble", 2 => "Mustache", 3 => "Goatee", 4 => "Chin Strap", 5 => "Short Beard",
            6 => "Long Beard", 7 => "Mutton Chops", 8 => "Van Dyke", _ => "Viking Braid"
        };

        public static string BrowName(int b) => b switch { 0 => "Natural", 1 => "Heavy", 2 => "Arched", 3 => "Scarred", _ => "None" };

        // bone indices of the body skinned mesh
        const int H = 0, T = 1, C = 2, N = 3, HD = 4, SL = 5, EL = 6, WL = 7, SR = 8, ER = 9, WR = 10, TL = 11, KL = 12, AL = 13, TR = 14, KR = 15, AR = 16;
        // sub-meshes of the body
        const int SubSkin = 0, SubChrome = 1, SubTop = 2, SubBottom = 3, SubShoes = 4, SubGloves = 5, SubGlow = 6, SubAccent = 7, SubWhite = 8, BodySubs = 9;
        // sub-meshes of the head
        const int HSkin = 0, HHair = 1, HBeard = 2, HStubble = 3, HLips = 4, HChrome = 5, HGlow = 6, HVisor = 7, HHelmet = 8, HTeeth = 9, HMouth = 10, HeadSubs = 11;

        static readonly Dictionary<string, Mesh> meshCache = new Dictionary<string, Mesh>();
        static readonly Dictionary<string, Profile> profileCache = new Dictionary<string, Profile>();

        public struct Dims
        {
            public float b, m, f, sx, hx;
            public static Dims Of(Appearance a)
            {
                float b = Mathf.Round(Mathf.Clamp(a.bulk, 0.8f, 1.45f) * 10f) / 10f;
                float m = Mathf.Round(Mathf.Clamp01(a.muscle) * 3f) / 3f;
                float f = a.female ? 1f : 0f;
                return new Dims
                {
                    b = b, m = m, f = f,
                    sx = 0.168f + 0.05f * (b - 1f) + 0.012f * m - 0.018f * f,
                    hx = 0.088f + 0.015f * (b - 1f) + 0.012f * f
                };
            }
            public string Key => b.ToString("0.00") + "_" + m.ToString("0.00") + "_" + f;
        }

        // ===================================================================== skeleton
        static Transform Node(string name, Transform parent, Vector3 pos)
        {
            var t = new GameObject(name).transform;
            t.SetParent(parent, false);
            t.localPosition = pos;
            return t;
        }

        public static void BuildSkeleton(HumanoidRig rig, Transform root, Appearance a)
        {
            var d = Dims.Of(a);
            rig.hips = Node("Hips", root, new Vector3(0, 0.98f, 0));
            rig.torso = Node("Spine", rig.hips, new Vector3(0, 0.06f, 0));
            rig.chest = Node("Chest", rig.torso, new Vector3(0, 0.20f, 0));
            rig.neck = Node("Neck", rig.chest, new Vector3(0, 0.225f, -0.012f));
            rig.head = Node("Head", rig.neck, new Vector3(0, 0.095f, 0.012f));
            rig.jaw = Node("Jaw", rig.head, new Vector3(0, 0.11f, 0.01f));
            rig.shoulderL = Node("ShoulderL", rig.chest, new Vector3(-d.sx, 0.185f, -0.015f));
            rig.shoulderR = Node("ShoulderR", rig.chest, new Vector3(d.sx, 0.185f, -0.015f));
            rig.elbowL = Node("ElbowL", rig.shoulderL, new Vector3(0, -0.29f, 0));
            rig.elbowR = Node("ElbowR", rig.shoulderR, new Vector3(0, -0.29f, 0));
            rig.handL = Node("HandL", rig.elbowL, new Vector3(0, -0.26f, 0));
            rig.handR = Node("HandR", rig.elbowR, new Vector3(0, -0.26f, 0));
            rig.thighL = Node("ThighL", rig.hips, new Vector3(-d.hx, -0.05f, 0));
            rig.thighR = Node("ThighR", rig.hips, new Vector3(d.hx, -0.05f, 0));
            rig.kneeL = Node("KneeL", rig.thighL, new Vector3(0, -0.44f, 0));
            rig.kneeR = Node("KneeR", rig.thighR, new Vector3(0, -0.44f, 0));
            rig.ankleL = Node("AnkleL", rig.kneeL, new Vector3(0, -0.43f, 0));
            rig.ankleR = Node("AnkleR", rig.kneeR, new Vector3(0, -0.43f, 0));
        }

        public static Transform[] BodyBones(HumanoidRig r) => new[]
        {
            r.hips, r.torso, r.chest, r.neck, r.head, r.shoulderL, r.elbowL, r.handL, r.shoulderR, r.elbowR, r.handR,
            r.thighL, r.kneeL, r.ankleL, r.thighR, r.kneeR, r.ankleR
        };

        // ===================================================================== profiles
        public static Profile Trunk(Dims d, bool muscles)
        {
            string key = "trunk" + d.Key + muscles;
            if (profileCache.TryGetValue(key, out var cached)) return cached;
            float b = d.b, f = d.f, m = d.m;
            float depth = Mathf.Pow(b, 0.7f);
            float hw = (1f + 0.1f * f) * Mathf.Sqrt(b);
            float fat = Mathf.Max(0f, b - 1.05f) * (1f - m) * 2.2f;
            float ww = b * (1f - 0.09f * f) * (1f + fat * 0.25f);
            float cw = b * (1f - 0.08f * f);
            float sw = b * (1f - 0.12f * f) * (1f + 0.07f * m);
            var p = new Profile(
                new Ring(-0.15f, 0.06f, 0.05f, 0.06f),
                new Ring(-0.11f, 0.125f * hw, 0.082f * depth, 0.098f * depth),
                new Ring(-0.035f, 0.163f * hw, 0.094f * depth, 0.118f * depth),
                new Ring(0.05f, 0.152f * hw, 0.094f * depth * (1f + fat * 0.3f), 0.1f * depth),
                new Ring(0.13f, 0.133f * ww, 0.09f * depth * (1f + fat * 0.45f), 0.084f * depth),
                new Ring(0.22f, 0.148f * cw, 0.1f * depth * (1f + fat * 0.25f), 0.09f * depth),
                new Ring(0.315f, 0.163f * cw, 0.114f * depth, 0.1f * depth),
                new Ring(0.395f, 0.172f * sw, 0.108f * depth, 0.1f * depth),
                new Ring(0.448f, d.sx * 0.98f, 0.082f * depth, 0.09f * depth),
                new Ring(0.495f, 0.1f * Mathf.Sqrt(sw), 0.06f, 0.072f),
                new Ring(0.535f, 0.057f, 0.05f, 0.055f, 0f, 0.004f),
                new Ring(0.6f, 0.05f, 0.047f, 0.05f, 0f, 0.012f)
            ).Power(2.3f);
            if (muscles)
            {
                float mm = 0.35f + m * 0.65f;
                if (f < 0.5f)
                {
                    p.Bump(0.352f, 122f, 0.016f * mm + 0.004f, 0.045f, 22f).Bump(0.352f, 58f, 0.016f * mm + 0.004f, 0.045f, 22f);
                    p.Bump(0.302f, 120f, -0.007f * m, 0.012f, 24f).Bump(0.302f, 60f, -0.007f * m, 0.012f, 24f);
                }
                else
                {
                    p.Bump(0.335f, 120f, 0.038f, 0.048f, 22f).Bump(0.335f, 60f, 0.038f, 0.048f, 22f);
                    p.Bump(0.3f, 90f, -0.008f, 0.03f, 7f);
                }
                // six pack and linea alba
                for (int r = 0; r < 3; r++)
                {
                    float y = 0.085f + r * 0.065f;
                    p.Bump(y, 98f, 0.0055f * m * (1f - fat), 0.024f, 7f).Bump(y, 82f, 0.0055f * m * (1f - fat), 0.024f, 7f);
                }
                p.Bump(0.16f, 90f, -0.0035f * m, 0.1f, 3f);
                // obliques, lats, spine, traps, blades, glutes
                p.Bump(0.11f, 145f, 0.006f * m, 0.05f, 15f).Bump(0.11f, 35f, 0.006f * m, 0.05f, 15f);
                p.Bump(0.3f, 215f, 0.014f * mm, 0.075f, 22f).Bump(0.3f, 325f, 0.014f * mm, 0.075f, 22f);
                p.Bump(0.25f, 270f, -0.0065f, 0.2f, 6f);
                p.Bump(0.468f, 238f, 0.02f * mm + 0.004f, 0.035f, 26f).Bump(0.468f, 302f, 0.02f * mm + 0.004f, 0.035f, 26f);
                p.Bump(0.38f, 245f, 0.007f, 0.04f, 18f).Bump(0.38f, 295f, 0.007f, 0.04f, 18f);
                p.Bump(-0.045f, 245f, 0.018f + 0.01f * f, 0.05f, 28f).Bump(-0.045f, 295f, 0.018f + 0.01f * f, 0.05f, 28f);
                // collar bones and the throat notch
                p.Bump(0.462f, 118f, 0.004f, 0.008f, 22f).Bump(0.462f, 62f, 0.004f, 0.008f, 22f).Bump(0.47f, 90f, -0.006f, 0.015f, 8f);
                // sternocleidomastoid
                p.Bump(0.53f, 115f, 0.004f, 0.025f, 14f).Bump(0.53f, 65f, 0.004f, 0.025f, 14f);
            }
            profileCache[key] = p;
            return p;
        }

        /// <summary>Arm from the shoulder joint along -Y. side: -1 left, +1 right.</summary>
        public static Profile Arm(Dims d, int side, bool muscles)
        {
            string key = "arm" + d.Key + side + muscles;
            if (profileCache.TryGetValue(key, out var cached)) return cached;
            float ab = Mathf.Pow(d.b, 0.8f) * (1f + 0.12f * d.m) * (1f - 0.15f * d.f);
            var p = new Profile(
                new Ring(0.065f, 0.03f),
                new Ring(0.025f, 0.062f * ab, 0.058f * ab, 0.058f * ab),
                new Ring(-0.05f, 0.059f * ab, 0.054f * ab, 0.055f * ab),
                new Ring(-0.13f, 0.047f * ab, 0.05f * ab, 0.048f * ab),
                new Ring(-0.22f, 0.041f * ab, 0.042f * ab, 0.04f * ab),
                new Ring(-0.29f, 0.036f * ab, 0.035f * ab, 0.041f * ab),
                new Ring(-0.34f, 0.043f * ab, 0.041f * ab, 0.039f * ab),
                new Ring(-0.42f, 0.035f * ab, 0.029f * ab, 0.031f * ab),
                new Ring(-0.505f, 0.027f, 0.02f, 0.022f),
                new Ring(-0.55f, 0.024f, 0.019f, 0.02f)
            );
            if (muscles)
            {
                float outer = side > 0 ? 0f : 180f;
                float mm = 0.3f + d.m * 0.7f;
                p.Bump(-0.015f, outer, 0.011f * mm + 0.003f, 0.05f, 55f);
                p.Bump(-0.02f, side > 0 ? 40f : 140f, 0.006f * mm, 0.04f, 30f);
                p.Bump(-0.14f, 90f, 0.012f * mm + 0.002f, 0.048f, 34f);
                p.Bump(-0.12f, 270f, 0.009f * mm, 0.06f, 42f);
                p.Bump(-0.355f, side > 0 ? 45f : 135f, 0.007f * mm, 0.045f, 30f);
                p.Bump(-0.29f, 270f, 0.004f, 0.015f, 25f);
            }
            profileCache[key] = p;
            return p;
        }

        /// <summary>Leg from the hip joint along -Y.</summary>
        public static Profile Leg(Dims d, int side, bool muscles)
        {
            string key = "leg" + d.Key + side + muscles;
            if (profileCache.TryGetValue(key, out var cached)) return cached;
            float lb = Mathf.Pow(d.b, 0.75f) * (1f + 0.05f * d.f);
            var p = new Profile(
                new Ring(0.1f, 0.07f, 0.07f, 0.08f),
                new Ring(0.03f, 0.094f * lb, 0.085f * lb, 0.095f * lb),
                new Ring(-0.08f, 0.087f * lb, 0.084f * lb, 0.08f * lb),
                new Ring(-0.22f, 0.072f * lb, 0.075f * lb, 0.065f * lb),
                new Ring(-0.36f, 0.058f * lb, 0.06f * lb, 0.052f * lb),
                new Ring(-0.44f, 0.05f, 0.055f, 0.048f),
                new Ring(-0.52f, 0.05f * lb, 0.047f * lb, 0.06f * lb),
                new Ring(-0.6f, 0.051f * lb, 0.044f * lb, 0.068f * lb),
                new Ring(-0.72f, 0.04f, 0.038f, 0.042f),
                new Ring(-0.84f, 0.03f),
                new Ring(-0.89f, 0.026f)
            );
            if (muscles)
            {
                float inner = side > 0 ? 180f : 0f;
                float mm = 0.3f + d.m * 0.7f;
                p.Bump(-0.17f, 90f, 0.012f * mm + 0.003f, 0.08f, 34f);
                p.Bump(-0.35f, side > 0 ? 130f : 50f, 0.008f * mm, 0.035f, 22f);
                p.Bump(-0.2f, 270f, 0.008f * mm, 0.09f, 40f);
                p.Bump(-0.44f, 90f, 0.006f, 0.02f, 24f);
                p.Bump(-0.6f, side > 0 ? 255f : 285f, 0.012f * mm + 0.004f, 0.05f, 22f);
                p.Bump(-0.58f, side > 0 ? 300f : 240f, 0.009f * mm, 0.05f, 20f);
                p.Bump(-0.06f, inner, -0.004f, 0.08f, 30f);
            }
            profileCache[key] = p;
            return p;
        }

        static Profile Fist() => CachedProfile("fist", () => new Profile(
            new Ring(0.005f, 0.026f, 0.02f, 0.02f),
            new Ring(-0.03f, 0.038f, 0.022f, 0.024f),
            new Ring(-0.07f, 0.043f, 0.029f, 0.026f),
            new Ring(-0.095f, 0.037f, 0.031f, 0.02f),
            new Ring(-0.112f, 0.018f, 0.016f, 0.01f)
        ).Power(2.6f).Bump(-0.05f, 0f, 0.01f, 0.03f, 30f));

        static Profile Glove(int side) => CachedProfile("glove" + side, () => new Profile(
            new Ring(0.01f, 0.038f),
            new Ring(-0.035f, 0.05f, 0.05f, 0.048f),
            new Ring(-0.07f, 0.058f, 0.066f, 0.05f),
            new Ring(-0.12f, 0.066f, 0.086f, 0.056f),
            new Ring(-0.17f, 0.062f, 0.086f, 0.05f),
            new Ring(-0.21f, 0.046f, 0.066f, 0.036f),
            new Ring(-0.236f, 0.014f, 0.018f, 0.01f)
        ).Bump(-0.11f, side > 0 ? 180f : 0f, 0.022f, 0.035f, 35f).Bump(-0.2f, 90f, 0.006f, 0.02f, 50f));

        static Profile Shoe(bool boot) => CachedProfile("shoe" + boot, () => new Profile(
            new Ring(0f, 0.034f, 0.03f, 0.04f),
            new Ring(0.05f, 0.044f, 0.033f, 0.05f),
            new Ring(0.12f, 0.049f, 0.034f, 0.04f),
            new Ring(0.2f, 0.051f, 0.031f, 0.03f),
            new Ring(0.255f, 0.04f, 0.027f, 0.024f),
            new Ring(0.275f, 0.014f, 0.01f, 0.01f)
        ).Power(3f));

        static Profile CachedProfile(string key, Func<Profile> make)
        {
            if (!profileCache.TryGetValue(key, out var p)) { p = make(); profileCache[key] = p; }
            return p;
        }

        // ===================================================================== weights
        static BoneWeight W(params (int bone, float w)[] items)
        {
            Array.Sort(items, (x, y) => y.w.CompareTo(x.w));
            float s = 0; int n = Mathf.Min(4, items.Length);
            for (int i = 0; i < n; i++) s += Mathf.Max(0f, items[i].w);
            if (s <= 1e-5f) return Anatomy.Bone(items[0].bone);
            var bw = new BoneWeight();
            if (n > 0) { bw.boneIndex0 = items[0].bone; bw.weight0 = Mathf.Max(0, items[0].w) / s; }
            if (n > 1) { bw.boneIndex1 = items[1].bone; bw.weight1 = Mathf.Max(0, items[1].w) / s; }
            if (n > 2) { bw.boneIndex2 = items[2].bone; bw.weight2 = Mathf.Max(0, items[2].w) / s; }
            if (n > 3) { bw.boneIndex3 = items[3].bone; bw.weight3 = Mathf.Max(0, items[3].w) / s; }
            return bw;
        }

        static float S(float e0, float e1, float x) => Anatomy.Smooth(e0, e1, x);

        static WeightFn TrunkWeights(Dims d) => (y, th, p) =>
        {
            float a = S(-0.02f, 0.07f, y), b = S(0.17f, 0.29f, y), c = S(0.47f, 0.53f, y), e = S(0.57f, 0.6f, y);
            float sh = S(0.6f * d.sx, 1.0f * d.sx, Mathf.Abs(p.x)) * S(0.33f, 0.43f, y) * (1f - S(0.47f, 0.52f, y)) * 0.6f;
            int sBone = p.x > 0 ? SR : SL;
            return W((H, 1f - a), (T, a * (1f - b)), (C, b * (1f - c) * (1f - sh)), (N, c * (1f - e)), (HD, e), (sBone, sh * b));
        };

        static WeightFn ArmWeights(int side)
        {
            int s = side > 0 ? SR : SL, e = side > 0 ? ER : EL, w = side > 0 ? WR : WL;
            return (y, th, p) =>
            {
                float ce = S(-0.235f, -0.335f, y), cw = S(-0.49f, -0.535f, y), cc = S(0.0f, 0.065f, y) * 0.45f;
                return W((C, cc), (s, (1f - ce) * (1f - cc)), (e, ce * (1f - cw)), (w, cw));
            };
        }

        static WeightFn LegWeights(int side)
        {
            int t = side > 0 ? TR : TL, k = side > 0 ? KR : KL, a = side > 0 ? AR : AL;
            return (y, th, p) =>
            {
                float ck = S(-0.38f, -0.49f, y), ca = S(-0.82f, -0.88f, y), ch = S(0.0f, 0.1f, y) * 0.45f;
                return W((H, ch), (t, (1f - ck) * (1f - ch)), (k, ck * (1f - ca)), (a, ca));
            };
        }

        static WeightFn Fixed(int bone) { var bw = Anatomy.Bone(bone); return (y, th, p) => bw; }

        // ===================================================================== body mesh
        public static SkinnedMeshRenderer BuildBody(HumanoidRig rig, Appearance a, int lod)
        {
            var d = Dims.Of(a);
            bool boxer = a.outfit == 1;
            string key = "body|" + d.Key + "|" + a.outfit + "|" + a.sleeves + "|" + a.chromeArm + "|" + lod;
            var go = new GameObject("BodyMesh");
            go.transform.SetParent(rig.hips, false);
            var smr = go.AddComponent<SkinnedMeshRenderer>();
            var bones = BodyBones(rig);
            if (!meshCache.TryGetValue(key, out var mesh) || mesh == null)
            {
                mesh = MakeBodyMesh(rig, go.transform, a, d, lod);
                var bp = new Matrix4x4[bones.Length];
                for (int i = 0; i < bones.Length; i++) bp[i] = bones[i].worldToLocalMatrix * go.transform.localToWorldMatrix;
                mesh.bindposes = bp;
                meshCache[key] = mesh;
            }
            smr.sharedMesh = mesh;
            smr.bones = bones;
            smr.rootBone = rig.hips;
            smr.localBounds = new Bounds(new Vector3(0, -0.1f, 0), new Vector3(2.2f, 2.6f, 2.2f));
            smr.updateWhenOffscreen = false;
            smr.quality = SkinQuality.Auto;
            smr.shadowCastingMode = lod > 1 ? ShadowCastingMode.Off : ShadowCastingMode.On;

            var skin = Anatomy.Skin(a.skin, a.chromeSkin);
            var chrome = Mats.Cached("npc_chrome", () => Mats.Lit(new Color(0.75f, 0.77f, 0.8f), null, 0.9f, 1f));
            var mats = new Material[BodySubs];
            mats[SubSkin] = skin;
            mats[SubChrome] = chrome;
            mats[SubTop] = boxer ? Anatomy.Satin(a.trunks) : Anatomy.Cloth(a.jacket);
            mats[SubBottom] = boxer ? Anatomy.Satin(a.trunks) : Anatomy.Cloth(a.pants);
            mats[SubShoes] = boxer ? Anatomy.Leather(a.boots) : Mats.Cached("npc_dark", () => Mats.Lit(new Color(0.05f, 0.05f, 0.06f), null, 0.5f, 0.5f));
            mats[SubGloves] = boxer ? Anatomy.Leather(a.gloves) : skin;
            mats[SubGlow] = Anatomy.Glow(a.accent);
            mats[SubAccent] = Anatomy.Satin(boxer ? a.accent * 0.9f : a.accent * 0.6f);
            mats[SubWhite] = Mats.Cached("anat_white", () => Mats.Lit(new Color(0.92f, 0.92f, 0.9f), Anatomy.ClothTex, 0.2f));
            smr.sharedMaterials = mats;
            rig.bodyRenderer = smr;
            return smr;
        }

        static Matrix4x4 Space(Transform renderer, Transform bone) => renderer.worldToLocalMatrix * bone.localToWorldMatrix;

        static Mesh MakeBodyMesh(HumanoidRig rig, Transform rend, Appearance a, Dims d, int lod)
        {
            var md = new MeshData { skinned = true };
            md.Sub(BodySubs - 1);
            int q = lod == 0 ? 1 : 2;
            bool boxer = a.outfit == 1;
            var mHips = Space(rend, rig.hips);
            var trunk = Trunk(d, true);
            var trunkSmooth = Trunk(d, false);
            var tw = TrunkWeights(d);

            // --- skin
            Anatomy.Grid(md, SubSkin, trunk, trunk.YMin, trunk.YMax, 0, 360, 46 / q, 28 / q, mHips, tw, null, -1f, 0f, 1f, 2f);
            for (int side = -1; side <= 1; side += 2)
            {
                var sh = side > 0 ? rig.shoulderR : rig.shoulderL;
                var arm = Arm(d, side, true);
                int sub = side > 0 && a.chromeArm ? SubChrome : SubSkin;
                Anatomy.Grid(md, sub, arm, arm.YMin, arm.YMax, 0, 360, 34 / q, 16 / q, Space(rend, sh), ArmWeights(side), null, -1f, 0f, 1f, 2f);
                var th = side > 0 ? rig.thighR : rig.thighL;
                var leg = Leg(d, side, true);
                Anatomy.Grid(md, SubSkin, leg, leg.YMin, leg.YMax, 0, 360, 40 / q, 18 / q, Space(rend, th), LegWeights(side), null, -1f, 0f, 1f, 2f);
                // hands
                var hand = side > 0 ? rig.handR : rig.handL;
                int hb = side > 0 ? WR : WL;
                if (boxer)
                {
                    var g = Glove(side);
                    Anatomy.Grid(md, SubGloves, g, g.YMin, g.YMax, 0, 360, 18 / q, 16 / q, Space(rend, hand), Fixed(hb), null, -1f, 0f, 1f, 2f);
                    Anatomy.Grid(md, SubWhite, g, -0.05f, -0.02f, 0, 360, 3, 16 / q, Space(rend, hand), Fixed(hb), null, -1f, 0.0025f, 1f, 2f);
                }
                else
                {
                    var fp = Fist();
                    Anatomy.Grid(md, sub, fp, fp.YMin, fp.YMax, 0, 360, 10 / q, 12 / q, Space(rend, hand), Fixed(hb), null, -1f, 0f, 1f, 2f);
                    // thumb
                    var thumb = new List<Vector3> { new Vector3(-0.022f * side, -0.02f, 0.016f), new Vector3(-0.026f * side, -0.048f, 0.026f), new Vector3(-0.016f * side, -0.07f, 0.03f) };
                    Anatomy.Tube(md, sub, thumb, new List<float> { 0.012f, 0.011f, 0.009f }, Space(rend, hand), Anatomy.Bone(hb), 6);
                }
                // feet
                var ankle = side > 0 ? rig.ankleR : rig.ankleL;
                var shoe = Shoe(boxer);
                var footM = Space(rend, ankle) * Matrix4x4.TRS(new Vector3(0, -0.032f, -0.06f), Quaternion.Euler(90f, 0, 0), Vector3.one);
                Anatomy.Grid(md, SubShoes, shoe, shoe.YMin, shoe.YMax, 0, 360, 12 / q, 14 / q, footM, Fixed(side > 0 ? AR : AL), null, -1f, 0f, 1f, 2f);
            }

            // --- outfit
            if (boxer)
            {
                // trunks: high waisted satin with a contrast waistband, loose flared legs
                Anatomy.Grid(md, SubBottom, trunkSmooth, -0.15f, 0.125f, 0, 360, 14 / q, 28 / q, mHips, tw, null, -1f, 0.014f, 1f, 2f);
                Anatomy.Grid(md, SubAccent, trunkSmooth, 0.07f, 0.135f, 0, 360, 4, 28 / q, mHips, tw, null, -1f, 0.018f, 1f, 2f);
                for (int side = -1; side <= 1; side += 2)
                {
                    var th = side > 0 ? rig.thighR : rig.thighL;
                    var leg = Leg(d, side, false);
                    Anatomy.Grid(md, SubBottom, leg, -0.21f, 0.1f, 0, 360, 10 / q, 18 / q, Space(rend, th), LegWeights(side),
                        (y, t) => Mathf.Lerp(0.034f, 0.018f, S(-0.21f, 0.1f, y)), -1f, 0f, 1f, 2f);
                    // stripe down the side of the trunks
                    float stripe = side > 0 ? 0f : 180f;
                    Anatomy.Grid(md, SubAccent, leg, -0.205f, 0.06f, stripe - 9f, stripe + 9f, 6, 4, Space(rend, th), LegWeights(side),
                        (y, t) => Mathf.Lerp(0.036f, 0.02f, S(-0.21f, 0.1f, y)), -1f, 0.001f, 1f, 2f);
                    // boots and socks
                    Anatomy.Grid(md, SubShoes, leg, -0.87f, -0.61f, 0, 360, 8 / q, 18 / q, Space(rend, th), LegWeights(side), null, -1f, 0.009f, 1f, 2f);
                    Anatomy.Grid(md, SubWhite, leg, -0.625f, -0.585f, 0, 360, 2, 18 / q, Space(rend, th), LegWeights(side), null, -1f, 0.006f, 1f, 2f);
                }
                if (a.female)
                    Anatomy.Grid(md, SubAccent, trunk, 0.23f, 0.43f, 0, 360, 10 / q, 28 / q, mHips, tw, null, -1f, 0.006f, 1f, 2f);
            }
            else
            {
                // jacket / top
                float topLow = -0.045f;
                Anatomy.Grid(md, SubTop, trunkSmooth, topLow, 0.52f, 0, 360, 36 / q, 28 / q, mHips, tw,
                    (y, t) => 0.02f + 0.006f * S(0.45f, 0.52f, y), -1f, 0f, 1f, 2f);
                // glowing seam down the front of the jacket
                Anatomy.Grid(md, SubGlow, trunkSmooth, 0.18f, 0.46f, 86f, 94f, 6, 2, mHips, tw, null, -1f, 0.0235f, 1f, 2f);
                if (a.sleeves > 0)
                {
                    for (int side = -1; side <= 1; side += 2)
                    {
                        if (side > 0 && a.chromeArm) continue;
                        var sh = side > 0 ? rig.shoulderR : rig.shoulderL;
                        var arm = Arm(d, side, false);
                        float low = a.sleeves == 1 ? -0.15f : -0.47f;
                        Anatomy.Grid(md, SubTop, arm, low, 0.065f, 0, 360, (a.sleeves == 1 ? 8 : 24) / q, 16 / q, Space(rend, sh), ArmWeights(side), null, -1f, 0.014f, 1f, 2f);
                        if (a.sleeves == 2)
                            Anatomy.Grid(md, SubGlow, arm, -0.47f, -0.455f, 0, 360, 1, 16 / q, Space(rend, sh), ArmWeights(side), null, -1f, 0.016f, 1f, 2f);
                    }
                }
                // trousers
                Anatomy.Grid(md, SubBottom, trunkSmooth, -0.15f, 0.02f, 0, 360, 8 / q, 28 / q, mHips, tw, null, -1f, 0.016f, 1f, 2f);
                for (int side = -1; side <= 1; side += 2)
                {
                    var th = side > 0 ? rig.thighR : rig.thighL;
                    var leg = Leg(d, side, false);
                    Anatomy.Grid(md, SubBottom, leg, -0.83f, 0.1f, 0, 360, 36 / q, 18 / q, Space(rend, th), LegWeights(side),
                        (y, t) => 0.013f + 0.006f * S(-0.6f, -0.83f, y), -1f, 0f, 1f, 2f);
                }
            }
            return md.ToMesh("Body_" + d.Key);
        }

        // ===================================================================== head
        public static Profile HeadProfile(float jaw, bool fem)
        {
            string key = "head" + jaw.ToString("0.0") + fem;
            if (profileCache.TryGetValue(key, out var cached)) return cached;
            float j = 1f + 0.1f * jaw - (fem ? 0.08f : 0f);
            var p = new Profile(
                new Ring(-0.02f, 0.05f, 0.047f, 0.05f, 0f, 0f),
                new Ring(0.02f, 0.052f * j, 0.058f, 0.052f, 0f, 0.012f),
                new Ring(0.045f, 0.063f * j, 0.086f, 0.058f, 0f, 0.006f),
                new Ring(0.075f, 0.075f * j, 0.1f, 0.072f),
                new Ring(0.105f, 0.082f, 0.106f, 0.088f),
                new Ring(0.135f, 0.087f, 0.105f, 0.098f),
                new Ring(0.16f, 0.088f, 0.101f, 0.104f, 0f, -0.002f),
                new Ring(0.185f, 0.087f, 0.103f, 0.107f, 0f, -0.003f),
                new Ring(0.215f, 0.082f, 0.093f, 0.104f, 0f, -0.005f),
                new Ring(0.24f, 0.069f, 0.074f, 0.088f, 0f, -0.006f),
                new Ring(0.258f, 0.046f, 0.046f, 0.058f, 0f, -0.007f),
                new Ring(0.268f, 0.012f, 0.012f, 0.016f, 0f, -0.007f)
            ).Power(2.15f);
            p.Bump(0.045f, 90f, fem ? 0.005f : 0.008f, 0.015f, 20f);
            p.Bump(0.065f, 152f, 0.005f * jaw, 0.02f, 14f).Bump(0.065f, 28f, 0.005f * jaw, 0.02f, 14f);
            p.Bump(0.138f, 140f, 0.007f, 0.018f, 18f).Bump(0.138f, 40f, 0.007f, 0.018f, 18f);
            p.Bump(0.183f, 112f, fem ? 0.002f : 0.005f, 0.01f, 26f).Bump(0.183f, 68f, fem ? 0.002f : 0.005f, 0.01f, 26f);
            p.Bump(0.158f, 113f, -0.011f, 0.014f, 11f).Bump(0.158f, 67f, -0.011f, 0.014f, 11f);
            p.Bump(0.19f, 165f, -0.003f, 0.03f, 12f).Bump(0.19f, 15f, -0.003f, 0.03f, 12f);
            // lips and mouth line
            p.Bump(0.098f, 90f, fem ? 0.006f : 0.004f, 0.006f, 22f);
            p.Bump(0.083f, 90f, fem ? 0.007f : 0.005f, 0.0065f, 18f);
            p.Bump(0.0905f, 90f, -0.003f, 0.0028f, 23f);
            p.Bump(0.11f, 116f, -0.002f, 0.015f, 6f).Bump(0.11f, 64f, -0.002f, 0.015f, 6f);
            p.Bump(0.2f, 270f, 0.006f, 0.05f, 60f);
            profileCache[key] = p;
            return p;
        }

        public static readonly Vector3 EyeCenter = new Vector3(0.033f, 0.158f, 0.08f);
        public const float EyeRadius = 0.0135f;
        public static readonly Vector3 JawPivot = new Vector3(0f, 0.11f, 0.01f);

        /// <summary>How much of the face at (y, theta) follows the jaw.</summary>
        public static float Jawness(float y, float th)
        {
            float s = Mathf.Sin(th);
            float w = S(0.092f, 0.076f, y) * S(-0.2f, 0.35f, s);
            w *= S(-0.025f, 0.03f, y);
            return w;
        }

        static readonly float[] hlS = { -1f, -0.35f, -0.08f, 0.0f, 0.12f, 0.18f, 0.28f, 0.36f, 0.6f, 1f };
        static readonly float[] hlY = { 0.07f, 0.08f, 0.17f, 0.186f, 0.182f, 0.138f, 0.138f, 0.2f, 0.218f, 0.222f };

        /// <summary>Height of the natural hairline around the head (s = sin(theta), 1 = front).</summary>
        public static float Hairline(float s)
        {
            for (int i = 0; i < hlS.Length - 1; i++)
                if (s <= hlS[i + 1])
                {
                    float t = Mathf.InverseLerp(hlS[i], hlS[i + 1], s);
                    t = t * t * (3f - 2f * t);
                    return Mathf.Lerp(hlY[i], hlY[i + 1], t);
                }
            return hlY[hlY.Length - 1];
        }

        static float Bell(float x, float c, float w) { float k = (x - c) / w; return Mathf.Exp(-k * k); }

        static float HairThickness(int style, float y, float th, int seed)
        {
            float s = Mathf.Sin(th), c = Mathf.Cos(th);
            float line = Hairline(s);
            float mask = S(line - 0.004f, line + 0.007f, y);
            float noise = Mathf.PerlinNoise(th * 3.1f + seed, y * 41f + seed * 0.3f);
            float top = S(0.2f, 0.232f, y);
            switch (style)
            {
                case 1: return mask * (0.0028f + noise * 0.0008f);
                case 2: return mask * Mathf.Lerp(0.0055f, 0.014f, top) * (0.9f + noise * 0.2f);
                case 3: return mask * Mathf.Lerp(0.0016f, 0.038f * (0.9f + 0.6f * S(0.23f, 0.262f, y)), top);
                case 4:
                    {
                        float sides = 0.0017f;
                        float topT = 0.021f + 0.012f * S(0.2f, -0.9f, s) + 0.014f * S(0.6f, 0.95f, s) * S(0.2f, 0.225f, y);
                        return mask * Mathf.Lerp(sides, topT, S(0.195f, 0.222f, y));
                    }
                case 5: return mask * (0.0015f + 0.018f * Bell(c, 0f, 0.16f) * S(0.17f, 0.21f, y));
                case 6:
                    {
                        float m2 = S(line - 0.03f, line - 0.01f, y);
                        return m2 * (0.05f + 0.012f * noise + 0.012f * S(0.15f, 0.26f, y));
                    }
                case 7: return mask * 0.009f;
                case 8: return mask * (0.0022f + 0.0065f * Mathf.Max(0f, Mathf.Sin(th * 18f)) * S(0.12f, 0.2f, y));
                case 9: return mask * (0.0105f + 0.004f * top);
                case 10: return mask * (0.016f + 0.006f * noise) + S(0.6f, 0.95f, s) * S(0.17f, 0.2f, y) * (1f - mask) * 0.012f;
                case 11: return mask * (0.012f + 0.004f * noise);
                case 12: return mask * 0.0105f;
                case 13:
                    {
                        float fringe = S(0.55f, 0.95f, s) * S(0.188f, 0.21f, y) * (1f - mask) * (0.016f + 0.012f * noise);
                        return mask * (0.021f + 0.012f * noise) + fringe;
                    }
            }
            return 0f;
        }

        static float BeardRegion(float y, float th, out float chin, out float mus, out float jawBand, out float cheek)
        {
            float s = Mathf.Sin(th), c = Mathf.Cos(th);
            float front = S(-0.05f, 0.25f, s);
            // jaw line rises from the chin to the ear
            float jawLine = Mathf.Lerp(0.135f, 0.032f, S(0.2f, 0.95f, s));
            float cheekLine = Mathf.Lerp(0.14f, 0.105f, S(0.2f, 0.8f, s));
            bool lipZone = s > 0.8f && Mathf.Abs(c) < 0.5f && y > 0.074f && y < 0.101f;
            float region = front * S(-0.01f, 0.02f, y) * S(cheekLine + 0.006f, cheekLine - 0.004f, y);
            if (lipZone) region *= 0f;
            chin = S(0.72f, 0.88f, s) * S(-0.005f, 0.02f, y) * S(0.08f, 0.072f, y);
            mus = S(0.78f, 0.9f, s) * Bell(c, 0f, 0.42f) * S(0.098f, 0.103f, y) * S(0.118f, 0.11f, y);
            jawBand = front * Bell(y, jawLine, 0.012f) * S(0.15f, 0.25f, s);
            cheek = front * S(0.0f, 0.15f, s) * S(0.98f, 0.7f, s) * S(0.06f, 0.08f, y) * S(cheekLine + 0.006f, cheekLine - 0.004f, y);
            return region;
        }

        static float BeardThickness(int style, float y, float th)
        {
            float region = BeardRegion(y, th, out float chin, out float mus, out float jawBand, out float cheek);
            switch (style)
            {
                case 2: return mus * 0.0065f;
                case 3: return Mathf.Max(chin * 0.009f, mus * 0.005f, BeardRegion(y, th, out _, out _, out _, out _) * S(0.75f, 0.9f, Mathf.Sin(th)) * S(0.1f, 0.07f, y) * 0.006f);
                case 4: return jawBand * 0.006f;
                case 5: return Mathf.Max(region * 0.0085f + chin * 0.004f, mus * 0.0065f);
                case 6: return Mathf.Max(region * 0.013f + chin * 0.01f, mus * 0.008f);
                case 7: return Mathf.Max(region * S(0.75f, 0.55f, Mathf.Sin(th)) * 0.009f, mus * 0.007f, cheek * 0.006f);
                case 8: return Mathf.Max(chin * Bell(Mathf.Cos(th), 0f, 0.28f) * 0.012f, mus * 0.006f);
                case 9: return Mathf.Max(region * 0.012f + chin * 0.008f, mus * 0.008f);
            }
            return 0f;
        }

        public static SkinnedMeshRenderer BuildHead(HumanoidRig rig, Appearance a, int lod)
        {
            bool helmet = a.helmet;
            int hair = helmet || a.mask && a.hair == 6 ? 0 : a.hair;
            int beard = a.female ? 0 : a.beard;
            a.jaw = Mathf.Round(Mathf.Clamp01(a.jaw) * 2f) / 2f;
            a.noseWidth = a.noseWidth > 1.1f ? 1.2f : 1f;
            string key = "head|" + a.jaw.ToString("0.0") + "|" + a.female + "|" + hair + "|" + beard + "|" + helmet + "|" + a.mask + "|" + a.visor + "|" + a.tattoo + "|" + a.noseWidth.ToString("0.0") + "|" + lod;
            var go = new GameObject("HeadMesh");
            go.transform.SetParent(rig.head, false);
            var smr = go.AddComponent<SkinnedMeshRenderer>();
            var bones = new[] { rig.head, rig.jaw, rig.neck };
            if (!meshCache.TryGetValue(key, out var mesh) || mesh == null)
            {
                mesh = MakeHeadMesh(a, hair, beard, lod);
                var bp = new Matrix4x4[bones.Length];
                for (int i = 0; i < bones.Length; i++) bp[i] = bones[i].worldToLocalMatrix * go.transform.localToWorldMatrix;
                mesh.bindposes = bp;
                meshCache[key] = mesh;
            }
            smr.sharedMesh = mesh;
            smr.bones = bones;
            smr.rootBone = rig.head;
            smr.localBounds = new Bounds(new Vector3(0, 0.12f, 0), new Vector3(0.6f, 0.6f, 0.6f));
            smr.shadowCastingMode = lod > 1 ? ShadowCastingMode.Off : ShadowCastingMode.On;
            var skin = Anatomy.Skin(a.skin, a.chromeSkin);
            var beardCol = a.beardColor;
            var mats = new Material[HeadSubs];
            mats[HSkin] = skin;
            mats[HHair] = Anatomy.Hair(a.hairColor);
            mats[HBeard] = Anatomy.Hair(beardCol);
            mats[HStubble] = Anatomy.Stubble(beardCol * 0.8f);
            var lip = a.chromeSkin ? a.skin * 0.8f : Color.Lerp(a.skin, new Color(0.62f, 0.25f, 0.25f), a.female ? 0.45f : 0.28f);
            mats[HLips] = Mats.Cached("anat_lip" + ColorUtility.ToHtmlStringRGB(lip), () => Mats.Lit(lip, Anatomy.SkinTex, 0.55f, 0f, Anatomy.SkinNormal, 0.3f));
            mats[HChrome] = Mats.Cached("npc_chrome", () => Mats.Lit(new Color(0.75f, 0.77f, 0.8f), null, 0.9f, 1f));
            mats[HGlow] = Anatomy.Glow(a.accent);
            mats[HVisor] = Mats.Cached("visor" + ColorUtility.ToHtmlStringRGB(a.accent), () => Mats.Emissive(new Color(0.02f, 0.02f, 0.03f), a.accent * 1.5f, null, null, 0.95f, 0.5f));
            mats[HHelmet] = Anatomy.Cloth(a.jacket);
            mats[HTeeth] = a.outfit == 1 ? Anatomy.Glow(a.accent * 0.5f) : Mats.Cached("anat_teeth", () => Mats.Lit(new Color(0.9f, 0.88f, 0.8f), null, 0.7f));
            mats[HMouth] = Mats.Cached("anat_mouth", () => Mats.Lit(new Color(0.18f, 0.04f, 0.05f), null, 0.6f));
            smr.sharedMaterials = mats;
            rig.headRenderer = smr;
            return smr;
        }

        static Mesh MakeHeadMesh(Appearance a, int hair, int beard, int lod)
        {
            var md = new MeshData { skinned = true };
            md.Sub(HeadSubs - 1);
            int q = lod == 0 ? 1 : 2;
            var hp = HeadProfile(a.jaw, a.female);
            var id = Matrix4x4.identity;
            WeightFn headW = (y, th, p) =>
            {
                float jw = Jawness(y, th), nw = S(0.01f, -0.02f, y);
                return W((0, (1f - jw) * (1f - nw)), (1, jw * (1f - nw)), (2, nw));
            };
            // skull and face
            Anatomy.Grid(md, HSkin, hp, hp.YMin, hp.YMax, 0, 360, 50 / q, 36 / q, id, headW, null, -1f, 0f, 1f, 3f);
            // nose
            float nw2 = a.noseWidth;
            var nose = new List<Vector3> { new Vector3(0, 0.171f, 0.094f), new Vector3(0, 0.152f, 0.107f), new Vector3(0, 0.134f, 0.121f), new Vector3(0, 0.122f, 0.127f), new Vector3(0, 0.116f, 0.124f) };
            Anatomy.Tube(md, HSkin, nose, new List<float> { 0.0072f, 0.009f, 0.0115f * nw2, 0.0135f * nw2, 0.011f * nw2 }, id, Anatomy.Bone(0), 8 / q + 2);
            for (int side = -1; side <= 1; side += 2)
            {
                Anatomy.Ellipsoid(md, HSkin, new Vector3(0.0118f * side * nw2, 0.1155f, 0.115f), new Vector3(0.0095f * nw2, 0.0078f, 0.0085f), id, Anatomy.Bone(0), 5, 8);
                // ears
                Anatomy.Ellipsoid(md, HSkin, new Vector3(0.09f * side, 0.148f, -0.008f), new Vector3(0.012f, 0.028f, 0.019f), id, Anatomy.Bone(0), 6 / q + 2, 10 / q + 2);
                Anatomy.Ellipsoid(md, HSkin, new Vector3(0.098f * side, 0.15f, -0.013f), new Vector3(0.007f, 0.022f, 0.014f), id, Anatomy.Bone(0), 5, 8);
            }
            // lips
            if (!a.mask)
                Anatomy.Grid(md, HLips, hp, 0.076f, 0.102f, 62f, 118f, 10, 14, id, headW,
                    (y, th) => 0.0009f * S(0.62f, 0.86f, Mathf.Sin(th)) * (Bell(y, 0.0975f, 0.0045f) + Bell(y, 0.0825f, 0.0055f)), 0.0003f, 0.0003f, 1f, 3f);
            // mouth interior and teeth
            Anatomy.Ellipsoid(md, HMouth, new Vector3(0, 0.088f, 0.07f), new Vector3(0.028f, 0.014f, 0.028f), id, Anatomy.Blend(0, 1, 0.5f), 6, 10);
            if (lod == 0)
            {
                Anatomy.Ellipsoid(md, HTeeth, new Vector3(0, 0.0935f, 0.086f), new Vector3(0.021f, 0.0055f, 0.013f), id, Anatomy.Bone(0), 4, 10);
                Anatomy.Ellipsoid(md, HTeeth, new Vector3(0, 0.0845f, 0.084f), new Vector3(0.019f, 0.005f, 0.012f), id, Anatomy.Bone(1), 4, 10);
            }

            // hair
            int seed = hair * 13 + 7;
            if (hair > 0)
            {
                Anatomy.Grid(md, HHair, hp, 0.05f, hp.YMax, 0, 360, 44 / q, 48 / q, id, headW, (y, th) => HairThickness(hair, y, th, seed), 0.0006f, 0.0008f, 3f, 4f);
                HairExtras(md, hp, hair, id);
            }
            // beard (and stubble around partial styles)
            if (beard > 0)
            {
                bool stubbleOnly = beard == 1;
                bool stubbleBase = beard == 2 || beard == 3 || beard == 4 || beard == 7 || beard == 8;
                if (stubbleOnly || stubbleBase)
                    Anatomy.Grid(md, HStubble, hp, -0.015f, 0.145f, -30f, 210f, 26 / q, 40 / q, id, headW,
                        (y, th) => BeardRegion(y, th, out var ch, out var mu, out _, out _) > 0.05f || ch > 0.05f || mu > 0.05f ? 0.0011f : 0f, 0.0005f, 0.0004f, 2f, 3f);
                if (!stubbleOnly)
                    Anatomy.Grid(md, HBeard, hp, -0.015f, 0.145f, -30f, 210f, 32 / q, 48 / q, id, headW, (y, th) => BeardThickness(beard, y, th), 0.0006f, 0.0009f, 2f, 3f);
                if (beard == 6 || beard == 9)
                {
                    // chin mass hanging under the jaw
                    Anatomy.Ellipsoid(md, HBeard, new Vector3(0, 0.03f, 0.075f), new Vector3(0.05f, beard == 6 ? 0.04f : 0.03f, 0.03f), id, Anatomy.Bone(1), 6, 10);
                }
            }
            // gear: visor, mask, tattoo, helmet
            if (a.visor && !a.helmet)
                Anatomy.Grid(md, HVisor, hp, 0.145f, 0.172f, 35f, 145f, 3, 16, id, headW, null, -1f, 0.011f, 1f, 3f);
            if (a.mask)
            {
                Anatomy.Grid(md, HChrome, hp, 0.03f, 0.128f, 20f, 160f, 8, 18, id, headW, null, -1f, 0.009f, 1f, 3f);
                Anatomy.Grid(md, HGlow, hp, 0.092f, 0.097f, 55f, 125f, 1, 10, id, headW, null, -1f, 0.0105f, 1f, 3f);
            }
            if (a.tattoo && !a.mask)
                Anatomy.Grid(md, HGlow, hp, 0.08f, 0.15f, 42f, 46f, 6, 2, id, headW, null, -1f, 0.0006f, 1f, 3f);
            if (a.helmet)
            {
                Anatomy.Grid(md, HHelmet, hp, 0.11f, hp.YMax, 0, 360, 16, 28, id, headW,
                    (y, th) => Mathf.Sin(th) > 0.55f && y < 0.2f ? 0f : 0.02f, 0.001f, 0.002f, 1f, 3f);
                Anatomy.Grid(md, HVisor, hp, 0.14f, 0.2f, 40f, 140f, 4, 16, id, headW, null, -1f, 0.018f, 1f, 3f);
            }
            return md.ToMesh("Head");
        }

        static void HairExtras(MeshData md, Profile hp, int hair, Matrix4x4 id)
        {
            var hb = Anatomy.Bone(0);
            if (hair == 5 || hair == 11)
            {
                // spikes: cones growing out of the scalp
                int count = hair == 5 ? 8 : 13;
                for (int i = 0; i < count; i++)
                {
                    float y, th;
                    if (hair == 5)
                    {
                        float t = i / (float)(count - 1);
                        if (t < 0.5f) { th = Mathf.PI * 0.5f; y = Mathf.Lerp(0.222f, 0.265f, t / 0.5f); }
                        else { th = Mathf.PI * 1.5f; y = Mathf.Lerp(0.265f, 0.17f, (t - 0.5f) / 0.5f); }
                    }
                    else { float ang = i * 2.4f; th = ang; y = 0.205f + (i % 4) * 0.016f; }
                    var basePt = hp.PointOffset(y, th, 0.006f);
                    var nrm = hp.Normal(y, th);
                    var dir = (nrm + Vector3.back * 0.6f + Vector3.up * 0.2f).normalized;
                    float len = hair == 5 ? 0.055f + 0.02f * Mathf.Sin(i) : 0.04f + 0.012f * ((i * 7) % 3);
                    var path = new List<Vector3> { basePt - nrm * 0.004f, basePt + dir * len * 0.5f, basePt + dir * len };
                    Anatomy.Tube(md, HHair, path, new List<float> { hair == 5 ? 0.012f : 0.011f, 0.007f, 0.0015f }, id, hb, 6);
                }
            }
            if (hair == 9)
            {
                Anatomy.Ellipsoid(md, HHair, new Vector3(0, 0.25f, -0.075f), new Vector3(0.033f, 0.03f, 0.034f), id, hb, 7, 12);
                Anatomy.Grid(md, HGlow, new Profile(new Ring(-0.006f, 0.02f), new Ring(0.006f, 0.02f)), -0.006f, 0.006f, 0, 360, 1, 10,
                    Matrix4x4.TRS(new Vector3(0, 0.232f, -0.068f), Quaternion.Euler(-35f, 0, 0), Vector3.one), (y, t, p) => hb, null, -1f, 0.001f);
            }
        }

        // ===================================================================== hair strands with physics
        public static void BuildStrands(HumanoidRig rig, Appearance a, int lod)
        {
            int hair = a.helmet ? 0 : a.hair;
            var hp = HeadProfile(a.jaw, a.female);
            var hairMat = Anatomy.Hair(a.hairColor);
            var beardMat = Anatomy.Hair(a.beardColor);
            bool physics = lod == 0;
            if (hair == 7)
            {
                int n = lod == 0 ? 18 : 10;
                for (int i = 0; i < n; i++)
                {
                    float th = Mathf.Lerp(-30f, 210f, i / (float)(n - 1)) * Mathf.Deg2Rad + Mathf.PI; // around the back half
                    float y = 0.2f + 0.035f * Mathf.Sin(i * 1.7f);
                    var root = hp.PointOffset(y, th, 0.006f);
                    var outward = hp.Normal(y, th);
                    HairStrand.Create(rig, rig.head, root, (Vector3.down * 1.3f + outward).normalized, 4, 0.26f + 0.05f * Mathf.Sin(i * 2.1f), 0.012f, 0.008f, hairMat, physics, 0.6f, 0.15f);
                }
            }
            else if (hair == 10)
            {
                var root = hp.PointOffset(0.2f, Mathf.PI * 1.5f, 0.012f);
                HairStrand.Create(rig, rig.head, root, (Vector3.down + Vector3.back * 0.25f).normalized, 4, 0.26f, 0.065f, 0.04f, hairMat, physics, 0.5f, 0.25f, 0.35f);
                for (int side = -1; side <= 1; side += 2)
                {
                    var sroot = hp.PointOffset(0.19f, side > 0 ? 0.15f : Mathf.PI - 0.15f, 0.01f);
                    HairStrand.Create(rig, rig.head, sroot, (Vector3.down + Vector3.right * side * 0.15f).normalized, 3, 0.17f, 0.022f, 0.012f, hairMat, physics, 0.55f, 0.2f, 0.6f);
                }
            }
            else if (hair == 12)
            {
                var root = new Vector3(0, 0.215f, -0.098f);
                HairStrand.Create(rig, rig.head, root, (Vector3.down + Vector3.back * 0.6f).normalized, 5, 0.24f, 0.024f, 0.007f, hairMat, physics, 0.45f, 0.2f);
            }
            int beard = a.female ? 0 : a.beard;
            if (beard == 6 || beard == 9)
            {
                var root = new Vector3(0, 0.03f, 0.08f) - BodyBuilder.JawPivot;
                bool braid = beard == 9;
                HairStrand.Create(rig, rig.jaw, root, (Vector3.down + Vector3.forward * 0.25f).normalized, braid ? 4 : 3, braid ? 0.16f : 0.11f, braid ? 0.018f : 0.045f, braid ? 0.009f : 0.015f, beardMat, physics, 0.6f, 0.12f, braid ? 1f : 0.55f, braid);
            }
        }
    }

    /// <summary>
    /// A chain of hair (dreadlock, ponytail, beard braid) simulated with verlet integration. It inherits head motion,
    /// sags with gravity and springs back to its styled rest shape.
    /// </summary>
    public class HairStrand : MonoBehaviour
    {
        Transform anchor;
        Vector3 rootLocal, restDirLocal;
        Transform[] segs;
        Vector3[] pos, prev;
        float segLen;
        float stiffness, drag;
        bool physics;
        HumanoidRig rig;

        public static HairStrand Create(HumanoidRig rig, Transform anchor, Vector3 rootLocal, Vector3 dirLocal, int segments, float length,
            float r0, float r1, Material mat, bool physics, float stiffness, float drag, float flatten = 1f, bool braid = false)
        {
            var go = new GameObject("HairStrand");
            go.transform.SetParent(anchor, false);
            var hs = go.AddComponent<HairStrand>();
            hs.rig = rig;
            hs.anchor = anchor; hs.rootLocal = rootLocal; hs.restDirLocal = dirLocal.normalized;
            hs.segLen = length / segments; hs.stiffness = stiffness; hs.drag = drag; hs.physics = physics;
            hs.segs = new Transform[segments];
            hs.pos = new Vector3[segments + 1];
            hs.prev = new Vector3[segments + 1];
            for (int i = 0; i < segments; i++)
            {
                var s = new GameObject("Seg" + i);
                s.transform.SetParent(go.transform, false);
                var md = new MeshData();
                float ra = Mathf.Lerp(r0, r1, i / (float)segments), rb = Mathf.Lerp(r0, r1, (i + 1) / (float)segments);
                var path = new List<Vector3>();
                var rad = new List<float>();
                int steps = braid ? 6 : 3;
                for (int k = 0; k <= steps; k++)
                {
                    float t = k / (float)steps;
                    path.Add(new Vector3(0, -t * hs.segLen * 1.12f + hs.segLen * 0.06f, 0));
                    float r = Mathf.Lerp(ra, rb, t);
                    if (braid) r *= 0.8f + 0.35f * Mathf.Abs(Mathf.Sin(t * Mathf.PI * 2f + i));
                    rad.Add(r);
                }
                var m = Matrix4x4.Scale(new Vector3(1f, 1f, flatten));
                Anatomy.Tube(md, 0, path, rad, m, Anatomy.Bone(0), 7, braid ? 0f : 0.12f, i * 5);
                s.AddComponent<MeshFilter>().sharedMesh = md.ToMesh("Strand");
                var mr = s.AddComponent<MeshRenderer>();
                mr.sharedMaterial = mat;
                mr.shadowCastingMode = ShadowCastingMode.On;
                hs.segs[i] = s.transform;
            }
            hs.ResetChain();
            Util.SetLayerRecursive(go, Layers.Actors);
            return hs;
        }

        public void ResetChain()
        {
            var root = anchor.TransformPoint(rootLocal);
            var dir = anchor.TransformDirection(restDirLocal);
            float scale = anchor.lossyScale.y;
            for (int i = 0; i < pos.Length; i++) { pos[i] = root + dir * segLen * scale * i; prev[i] = pos[i]; }
            Pose();
        }

        void LateUpdate()
        {
            if (anchor == null) return;
            float dt = Mathf.Min(Time.deltaTime, 1f / 30f);
            if (dt <= 0f) return;
            float scale = anchor.lossyScale.y;
            float len = segLen * scale;
            var root = anchor.TransformPoint(rootLocal);
            var restDir = anchor.TransformDirection(restDirLocal);
            if (!physics || rig != null && rig.FarFromCamera)
            {
                for (int i = 0; i < pos.Length; i++) { pos[i] = root + restDir * len * i; prev[i] = pos[i]; }
                Pose();
                return;
            }
            pos[0] = root; prev[0] = root;
            var g = Physics.gravity * dt * dt;
            for (int i = 1; i < pos.Length; i++)
            {
                var v = (pos[i] - prev[i]) * (1f - drag);
                prev[i] = pos[i];
                var rest = root + restDir * len * i;
                pos[i] += v + g + (rest - pos[i]) * stiffness * 0.2f;
            }
            for (int it = 0; it < 3; it++)
                for (int i = 1; i < pos.Length; i++)
                {
                    var d = pos[i] - pos[i - 1];
                    float l = d.magnitude;
                    if (l < 1e-5f) continue;
                    pos[i] = pos[i - 1] + d / l * len;
                }
            // keep strands from sinking into the head/neck
            if (rig != null && rig.head != null)
            {
                var hc = rig.head.TransformPoint(new Vector3(0, 0.15f, 0));
                float hr = 0.115f * scale;
                for (int i = 1; i < pos.Length; i++)
                {
                    var d = pos[i] - hc;
                    if (d.sqrMagnitude < hr * hr) pos[i] = hc + d.normalized * hr;
                }
            }
            Pose();
        }

        void Pose()
        {
            var up = anchor.TransformDirection(Vector3.forward);
            for (int i = 0; i < segs.Length; i++)
            {
                var d = pos[i + 1] - pos[i];
                if (d.sqrMagnitude < 1e-10f) d = anchor.TransformDirection(restDirLocal);
                segs[i].position = pos[i];
                segs[i].rotation = Quaternion.LookRotation(Vector3.ProjectOnPlane(up, d).normalized.sqrMagnitude > 0.01f ? Vector3.ProjectOnPlane(up, d).normalized : Vector3.forward, -d.normalized);
                segs[i].localScale = Vector3.one * (anchor.lossyScale.y / Mathf.Max(0.001f, transform.lossyScale.y));
            }
        }
    }
}
