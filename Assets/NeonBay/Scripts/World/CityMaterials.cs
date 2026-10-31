using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    /// <summary>Shared materials for the city. Built once after the render pipeline is known.</summary>
    public class CityMaterials
    {
        public Material road, isect, sidewalk, lotConcrete, lotDirt, roof, curb, megaWall, water, metalDark, metal, ribbed,
            rust, glassDark, lampWarm, lampCool, lampSodium, signs, signsVertical, ads, holo, lightCone, cable, white, black, rubber,
            wood, plaster, screen, blinkRed, craneOrange, hazard, chrome, fabric;
        public Material[] awnings, containers, shopfronts, carPaints;
        public readonly Dictionary<FacadeStyle, Material[]> facades = new Dictionary<FacadeStyle, Material[]>();
        public readonly List<Material> emissiveFacades = new List<Material>();
        public readonly Dictionary<Material, float> facadeEmission = new Dictionary<Material, float>();
        public readonly List<Material> neonMats = new List<Material>();
        readonly Dictionary<Color, Material> neonByColor = new Dictionary<Color, Material>();
        public readonly List<Material> wetMaterials = new List<Material>();

        public CityMaterials()
        {
            var rs = Tex.Road; var ri = Tex.Intersection; var sw = Tex.Sidewalk; var cc = Tex.Concrete; var dirt = Tex.Dirt; var met = Tex.Metal; var rib = Tex.Ribbed;

            road = Mats.Lit(Color.white, rs.albedo, 0.35f, 0f, rs.normal, 0.6f); Mats.SetSmoothnessMap(road, rs.gloss);
            isect = Mats.Lit(Color.white, ri.albedo, 0.35f, 0f, ri.normal, 0.6f); Mats.SetSmoothnessMap(isect, ri.gloss);
            sidewalk = Mats.Lit(Color.white, sw.albedo, 0.3f, 0f, sw.normal, 0.8f); Mats.SetSmoothnessMap(sidewalk, sw.gloss);
            wetMaterials.Add(road); wetMaterials.Add(isect); wetMaterials.Add(sidewalk);

            lotConcrete = Mats.Lit(new Color(0.75f, 0.75f, 0.75f), cc.albedo, 0.25f, 0f, cc.normal);
            lotDirt = Mats.Lit(Color.white, dirt.albedo, 0.1f, 0f, dirt.normal);
            roof = Mats.Lit(new Color(0.55f, 0.55f, 0.57f), cc.albedo, 0.2f, 0f, cc.normal);
            curb = Mats.Lit(new Color(0.6f, 0.6f, 0.6f), cc.albedo, 0.2f);
            megaWall = Mats.Lit(new Color(0.35f, 0.37f, 0.42f), met.albedo, 0.4f, 0.4f, met.normal);
            water = Mats.Lit(new Color(0.02f, 0.05f, 0.07f), null, 0.96f, 0.3f);
            metalDark = Mats.Lit(new Color(0.12f, 0.12f, 0.14f), met.albedo, 0.5f, 0.7f, met.normal);
            metal = Mats.Lit(new Color(0.55f, 0.56f, 0.6f), met.albedo, 0.55f, 0.8f, met.normal);
            ribbed = Mats.Lit(new Color(0.7f, 0.7f, 0.7f), rib.albedo, 0.35f, 0.4f, rib.normal);
            rust = Mats.Lit(new Color(0.45f, 0.25f, 0.15f), rib.albedo, 0.15f, 0.3f, rib.normal);
            glassDark = Mats.Lit(new Color(0.03f, 0.04f, 0.06f), null, 0.95f, 0.6f);
            chrome = Mats.Lit(new Color(0.8f, 0.82f, 0.86f), null, 0.92f, 1f);
            white = Mats.Lit(new Color(0.85f, 0.86f, 0.88f), null, 0.45f);
            black = Mats.Lit(new Color(0.03f, 0.03f, 0.035f), null, 0.4f);
            rubber = Mats.Lit(new Color(0.04f, 0.04f, 0.04f), null, 0.15f);
            wood = Mats.Lit(new Color(0.35f, 0.24f, 0.15f), null, 0.2f);
            plaster = Mats.Lit(new Color(0.8f, 0.78f, 0.72f), cc.albedo, 0.15f);
            fabric = Mats.Lit(new Color(0.3f, 0.3f, 0.32f), null, 0.05f);
            craneOrange = Mats.Lit(new Color(0.9f, 0.4f, 0.05f), met.albedo, 0.4f, 0.5f);
            hazard = Mats.Emissive(new Color(0.9f, 0.75f, 0.1f), new Color(0.6f, 0.45f, 0f));
            cable = Mats.Lit(new Color(0.02f, 0.02f, 0.02f), null, 0.3f);

            lampWarm = Mats.Unlit(new Color(1f, 0.8f, 0.55f) * 4f);
            lampCool = Mats.Unlit(new Color(0.8f, 0.92f, 1f) * 4f);
            lampSodium = Mats.Unlit(Palette.Sodium * 3.5f);
            blinkRed = Mats.Unlit(Palette.Red * 5f);
            screen = Mats.Unlit(new Color(0.2f, 0.9f, 1f) * 1.6f, Tex.Scanlines);

            signs = Mats.Unlit(Color.white * 2.6f, Tex.SignAtlas);
            signsVertical = Mats.Unlit(Color.white * 2.8f, Tex.VerticalAtlas);
            ads = Mats.Unlit(Color.white * 1.8f, Tex.AdAtlas);
            holo = Mats.Additive(new Color(0.2f, 0.9f, 1f, 0.55f) * 1.5f, Tex.Scanlines);
            lightCone = Mats.Additive(new Color(1f, 0.85f, 0.6f, 0.06f), Tex.Glow);

            awnings = new[]
            {
                Mats.Lit(new Color(0.7f, 0.1f, 0.15f), null, 0.2f), Mats.Lit(new Color(0.1f, 0.4f, 0.6f), null, 0.2f),
                Mats.Lit(new Color(0.15f, 0.5f, 0.25f), null, 0.2f), Mats.Lit(new Color(0.8f, 0.6f, 0.1f), null, 0.2f),
                Mats.Lit(new Color(0.4f, 0.15f, 0.5f), null, 0.2f)
            };
            containers = new[]
            {
                Mats.Lit(new Color(0.65f, 0.12f, 0.1f), rib.albedo, 0.3f, 0.4f, rib.normal), Mats.Lit(new Color(0.1f, 0.3f, 0.6f), rib.albedo, 0.3f, 0.4f, rib.normal),
                Mats.Lit(new Color(0.15f, 0.45f, 0.2f), rib.albedo, 0.3f, 0.4f, rib.normal), Mats.Lit(new Color(0.75f, 0.5f, 0.1f), rib.albedo, 0.3f, 0.4f, rib.normal),
                Mats.Lit(new Color(0.5f, 0.5f, 0.52f), rib.albedo, 0.3f, 0.4f, rib.normal), Mats.Lit(new Color(0.85f, 0.85f, 0.85f), rib.albedo, 0.3f, 0.4f, rib.normal)
            };
            carPaints = new[]
            {
                Mats.Lit(new Color(0.6f, 0.05f, 0.08f), null, 0.85f, 0.6f), Mats.Lit(new Color(0.05f, 0.05f, 0.06f), null, 0.9f, 0.7f),
                Mats.Lit(new Color(0.8f, 0.8f, 0.82f), null, 0.85f, 0.7f), Mats.Lit(new Color(0.1f, 0.25f, 0.6f), null, 0.85f, 0.6f),
                Mats.Lit(new Color(0.9f, 0.7f, 0.05f), null, 0.85f, 0.5f), Mats.Lit(new Color(0.2f, 0.5f, 0.45f), null, 0.85f, 0.6f),
                Mats.Lit(new Color(0.45f, 0.1f, 0.55f), null, 0.85f, 0.6f)
            };

            AddFacade(FacadeStyle.Glass, 0.92f, 0.55f, 2.2f, new Color(0.75f, 0.85f, 1f), new Color(0.6f, 0.95f, 0.9f), new Color(0.85f, 0.75f, 1f), new Color(0.9f, 0.9f, 0.9f));
            AddFacade(FacadeStyle.Office, 0.25f, 0f, 1.8f, new Color(0.8f, 0.8f, 0.82f), new Color(0.75f, 0.7f, 0.62f), new Color(0.55f, 0.58f, 0.62f));
            AddFacade(FacadeStyle.Residential, 0.15f, 0f, 1.6f, new Color(0.95f, 0.72f, 0.75f), new Color(0.7f, 0.9f, 0.8f), new Color(0.95f, 0.9f, 0.7f), new Color(0.7f, 0.8f, 0.95f), new Color(0.85f, 0.85f, 0.82f));
            AddFacade(FacadeStyle.Slum, 0.3f, 0.3f, 1.4f, Color.white, new Color(0.85f, 0.8f, 0.75f));
            AddFacade(FacadeStyle.Industrial, 0.35f, 0.4f, 1f, new Color(0.7f, 0.7f, 0.72f), new Color(0.55f, 0.6f, 0.65f), new Color(0.75f, 0.68f, 0.55f));
            AddFacade(FacadeStyle.Ruin, 0.08f, 0f, 1.5f, new Color(0.7f, 0.68f, 0.62f), new Color(0.55f, 0.52f, 0.5f));

            var sf = new List<Material>();
            for (int v = 0; v < 3; v++)
            {
                var f = Tex.Facade(FacadeStyle.Shopfront, v);
                var m = Mats.Emissive(Color.white, Color.white * 1.6f, f.albedo, f.emission, 0.6f, 0.1f);
                sf.Add(m); emissiveFacades.Add(m); facadeEmission[m] = 1.6f;
            }
            shopfronts = sf.ToArray();
        }

        void AddFacade(FacadeStyle style, float smooth, float metal, float emissionIntensity, params Color[] tints)
        {
            var list = new List<Material>();
            for (int v = 0; v < 2; v++)
                foreach (var t in tints)
                {
                    var f = Tex.Facade(style, v);
                    var m = Mats.Emissive(t, Color.white * emissionIntensity, f.albedo, f.emission, smooth, metal);
                    facadeEmission[m] = emissionIntensity;
                    list.Add(m);
                    emissiveFacades.Add(m);
                }
            facades[style] = list.ToArray();
        }

        public Material Facade(FacadeStyle s, Rng rng) => rng.Pick(facades[s]);
        public Vector2 FacadeTile(FacadeStyle s) => Tex.Facade(s, 0).tileMeters;

        public Material Neon(Color c, float intensity = 4f)
        {
            if (!neonByColor.TryGetValue(c, out var m))
            {
                m = Mats.Unlit(c * intensity);
                neonByColor[c] = m;
                neonMats.Add(m);
            }
            return m;
        }
    }
}
