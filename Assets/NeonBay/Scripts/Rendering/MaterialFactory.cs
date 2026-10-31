using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace NeonBay
{
    /// <summary>
    /// Creates runtime materials for whichever pipeline is active (URP recommended, Built-in as fallback).
    /// </summary>
    public static class Mats
    {
        public static bool URP { get; private set; }
        static Shader lit, unlit, particle, particleAdd, standardFallback, skybox;
        static bool initialized;
        static readonly Dictionary<string, Material> cache = new Dictionary<string, Material>();

        public static void Init()
        {
            if (initialized) return;
            initialized = true;
            var rp = GraphicsSettings.currentRenderPipeline;
            URP = rp != null && rp.GetType().Name.Contains("Universal");
            if (rp != null && !URP)
                Debug.LogWarning("[NeonBay] Unknown render pipeline " + rp.GetType().Name + " - materials may render incorrectly. URP is recommended.");

            if (URP)
            {
                lit = Shader.Find("Universal Render Pipeline/Lit");
                unlit = Shader.Find("Universal Render Pipeline/Unlit");
                particle = Shader.Find("Universal Render Pipeline/Particles/Unlit");
                particleAdd = particle;
            }
            else
            {
                lit = Shader.Find("Standard");
                unlit = Shader.Find("Unlit/Texture");
                particle = Shader.Find("Legacy Shaders/Particles/Alpha Blended");
                particleAdd = Shader.Find("Legacy Shaders/Particles/Additive");
            }
            standardFallback = Shader.Find("Sprites/Default");
            skybox = Shader.Find("Skybox/Procedural");
            if (lit == null) lit = standardFallback;
            if (unlit == null) unlit = standardFallback;
            if (particle == null) particle = standardFallback;
            if (particleAdd == null) particleAdd = particle;
        }

        public static Material Cached(string key, System.Func<Material> make)
        {
            if (!cache.TryGetValue(key, out var m) || m == null)
            {
                m = make();
                m.name = key;
                cache[key] = m;
            }
            return m;
        }

        public static Material Lit(Color color, Texture tex = null, float smoothness = 0.3f, float metallic = 0f, Texture normal = null, float normalScale = 1f)
        {
            Init();
            var m = new Material(lit) { enableInstancing = true };
            m.color = color;
            if (tex != null) m.mainTexture = tex;
            if (URP)
            {
                m.SetColor("_BaseColor", color);
                if (tex != null) m.SetTexture("_BaseMap", tex);
                m.SetFloat("_Smoothness", smoothness);
                m.SetFloat("_Metallic", metallic);
                if (normal != null)
                {
                    m.SetTexture("_BumpMap", normal);
                    m.SetFloat("_BumpScale", normalScale);
                    m.EnableKeyword("_NORMALMAP");
                }
            }
            else
            {
                m.SetFloat("_Glossiness", smoothness);
                m.SetFloat("_Metallic", metallic);
                if (normal != null)
                {
                    m.SetTexture("_BumpMap", normal);
                    m.SetFloat("_BumpScale", normalScale);
                    m.EnableKeyword("_NORMALMAP");
                }
            }
            return m;
        }

        /// <summary>Uses the alpha channel of a texture as a per-pixel smoothness mask (puddles, wet patches).</summary>
        public static void SetSmoothnessMap(Material m, Texture2D map)
        {
            if (URP)
            {
                m.SetTexture("_MetallicGlossMap", map);
                m.EnableKeyword("_METALLICSPECGLOSSMAP");
            }
            else
            {
                m.SetTexture("_MetallicGlossMap", map);
                m.EnableKeyword("_METALLICGLOSSMAP");
                m.SetFloat("_GlossMapScale", 1f);
            }
        }

        public static void SetSmoothness(Material m, float s)
        {
            if (m == null) return;
            if (URP) m.SetFloat("_Smoothness", s);
            else { m.SetFloat("_Glossiness", s); m.SetFloat("_GlossMapScale", s); }
        }

        public static Material Emissive(Color baseColor, Color emission, Texture tex = null, Texture emissionMap = null, float smoothness = 0.4f, float metallic = 0f)
        {
            var m = Lit(baseColor, tex, smoothness, metallic);
            SetEmission(m, emission, emissionMap);
            return m;
        }

        public static void SetEmission(Material m, Color emission, Texture emissionMap = null)
        {
            if (m == null) return;
            m.EnableKeyword("_EMISSION");
            m.SetColor("_EmissionColor", emission);
            if (emissionMap != null) m.SetTexture("_EmissionMap", emissionMap);
            m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None;
        }

        /// <summary>Unlit material. Colours above 1 are fine (HDR) and will bloom in URP.</summary>
        public static Material Unlit(Color color, Texture tex = null)
        {
            Init();
            var m = new Material(unlit) { enableInstancing = true };
            if (!URP && tex == null && Shader.Find("Unlit/Color") != null)
            {
                m.shader = Shader.Find("Unlit/Color");
            }
            m.color = color;
            if (tex != null) m.mainTexture = tex;
            if (URP)
            {
                m.SetColor("_BaseColor", color);
                if (tex != null) m.SetTexture("_BaseMap", tex);
            }
            return m;
        }

        public static Material Additive(Color color, Texture tex = null)
        {
            Init();
            Material m;
            if (URP)
            {
                m = new Material(unlit);
                m.SetColor("_BaseColor", color);
                if (tex != null) m.SetTexture("_BaseMap", tex);
                MakeTransparent(m, true);
            }
            else
            {
                m = new Material(particleAdd);
                m.SetColor("_TintColor", color * 0.5f);
                m.mainTexture = tex != null ? tex : Texture2D.whiteTexture;
            }
            m.color = color;
            if (tex != null) m.mainTexture = tex;
            return m;
        }

        public static Material Transparent(Color color, Texture tex = null, float smoothness = 0.9f, float metallic = 0f)
        {
            var m = Lit(color, tex, smoothness, metallic);
            if (URP) MakeTransparent(m, false);
            else
            {
                m.SetFloat("_Mode", 3f);
                m.SetInt("_SrcBlend", (int)BlendMode.One);
                m.SetInt("_DstBlend", (int)BlendMode.OneMinusSrcAlpha);
                m.SetInt("_ZWrite", 0);
                m.DisableKeyword("_ALPHATEST_ON");
                m.DisableKeyword("_ALPHABLEND_ON");
                m.EnableKeyword("_ALPHAPREMULTIPLY_ON");
                m.renderQueue = 3000;
            }
            return m;
        }

        public static Material Particle(Color color, Texture tex, bool additive)
        {
            Init();
            Material m;
            if (URP)
            {
                m = new Material(particle);
                m.SetColor("_BaseColor", color);
                if (tex != null) m.SetTexture("_BaseMap", tex);
                MakeTransparent(m, additive);
            }
            else
            {
                m = new Material(additive ? particleAdd : particle);
                m.SetColor("_TintColor", color * 0.5f);
                m.mainTexture = tex != null ? tex : Texture2D.whiteTexture;
            }
            m.color = color;
            if (tex != null) m.mainTexture = tex;
            return m;
        }

        static void MakeTransparent(Material m, bool additive)
        {
            m.SetFloat("_Surface", 1f);
            m.SetFloat("_Blend", additive ? 2f : 0f);
            m.SetOverrideTag("RenderType", "Transparent");
            m.SetFloat("_SrcBlend", (float)(additive ? BlendMode.SrcAlpha : BlendMode.SrcAlpha));
            m.SetFloat("_DstBlend", (float)(additive ? BlendMode.One : BlendMode.OneMinusSrcAlpha));
            m.SetFloat("_SrcBlendAlpha", (float)BlendMode.One);
            m.SetFloat("_DstBlendAlpha", (float)(additive ? BlendMode.One : BlendMode.OneMinusSrcAlpha));
            m.SetFloat("_ZWrite", 0f);
            m.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
            m.renderQueue = (int)RenderQueue.Transparent;
            m.SetShaderPassEnabled("DepthOnly", false);
            m.SetShaderPassEnabled("ShadowCaster", false);
        }

        public static Material Skybox()
        {
            Init();
            if (skybox == null) return null;
            var m = new Material(skybox);
            return m;
        }

        public static Material TextMaterial(Font font)
        {
            var sh = Shader.Find("GUI/Text Shader");
            var m = new Material(sh != null ? sh : unlit);
            if (font != null) m.mainTexture = font.material.mainTexture;
            return m;
        }
    }
}
