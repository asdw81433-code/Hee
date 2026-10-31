using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace NeonBay
{
    public enum Weather { Clear, Cloudy, Smog, Rain, Storm, AcidHaze }

    /// <summary>Day/night cycle, weather (rain, storms, smog, acid haze), reflections, ambience and sky traffic.</summary>
    public class WorldEnvironment : MonoBehaviour
    {
        public float timeOfDay = 21.5f;
        public int day = 1;
        public float dayLengthMinutes = 48f;
        public Weather weather = Weather.Rain;
        public float wetness = 0.8f;
        public float rainAmount;
        public bool timeFrozen;

        Weather target;
        float weatherHoursLeft = 6f;
        float blend = 1f;
        Light sun;
        Material sky;
        ReflectionProbe probe;
        ParticleSystem rain, splash;
        CityMaterials M;
        CityGenerator gen;
        float probeTimer, emissionTimer, blinkTimer, lightningTimer = 12f, flash;
        bool blinkOn;
        readonly List<ParticleSystem> steamPool = new List<ParticleSystem>();
        readonly List<ParticleSystem> firePool = new List<ParticleSystem>();
        float fxAssignTimer;
        readonly List<Transform> flyers = new List<Transform>();
        readonly List<Vector4> flyerPaths = new List<Vector4>(); // x,z centre, radius, height
        readonly List<float> flyerPhase = new List<float>();
        readonly List<float> flyerSpeed = new List<float>();
        AudioSource ambCity, ambRain, ambWind;

        public float NightFactor
        {
            get
            {
                float t = timeOfDay;
                if (t >= 7f && t <= 17.5f) return 0f;
                if (t >= 19.5f || t <= 5f) return 1f;
                if (t < 7f) return Mathf.InverseLerp(7f, 5f, t);
                return Mathf.InverseLerp(17.5f, 19.5f, t);
            }
        }

        public string WeatherName => weather switch
        {
            Weather.Clear => "Clear",
            Weather.Cloudy => "Overcast",
            Weather.Smog => "Smog Alert",
            Weather.Rain => "Rain",
            Weather.Storm => "Thunderstorm",
            _ => "Acid Haze"
        };

        public void Init(CityGenerator generator)
        {
            gen = generator;
            M = generator.M;
            Game.Env = this;

            // Sun / moon
            foreach (var l in Util.FindAll<Light>())
                if (l.type == LightType.Directional && l.gameObject.name != "NK_Sun") l.gameObject.SetActive(false);
            var sg = new GameObject("NK_Sun");
            sg.transform.SetParent(transform, false);
            sun = sg.AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.shadows = LightShadows.Soft;
            sun.shadowStrength = 0.9f;
            sun.shadowBias = 0.04f;
            RenderSettings.sun = sun;

            sky = Mats.Skybox();
            if (sky != null) RenderSettings.skybox = sky;
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Exponential;

            var pg = new GameObject("NK_ReflectionProbe");
            pg.transform.SetParent(transform, false);
            probe = pg.AddComponent<ReflectionProbe>();
            probe.mode = ReflectionProbeMode.Realtime;
            probe.refreshMode = ReflectionProbeRefreshMode.ViaScripting;
            probe.timeSlicingMode = ReflectionProbeTimeSlicingMode.IndividualFaces;
            probe.resolution = 128;
            probe.size = new Vector3(600f, 300f, 600f);
            probe.farClipPlane = 400f;
            probe.hdr = true;
            probe.importance = 1;
            probe.boxProjection = false;

            BuildRain();
            BuildFxPools();
            BuildAirTraffic();

            if (Game.Audio != null)
            {
                ambCity = Game.Audio.Loop2D("amb_city", 0.5f);
                ambRain = Game.Audio.Loop2D("amb_rain", 0f);
                ambWind = Game.Audio.Loop2D("amb_wind", 0f);
            }
            target = weather;
            Apply(true);
        }

        void BuildRain()
        {
            var rg = new GameObject("Rain");
            rg.transform.SetParent(transform, false);
            rain = rg.AddComponent<ParticleSystem>();
            rain.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = rain.main;
            main.loop = true;
            main.startLifetime = 1.1f;
            main.startSpeed = 26f;
            main.startSize = 0.025f;
            main.maxParticles = 9000;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.startColor = new Color(0.7f, 0.8f, 0.95f, 0.35f);
            var shape = rain.shape;
            shape.shapeType = ParticleSystemShapeType.Box;
            shape.scale = new Vector3(60f, 60f, 1f);
            shape.rotation = new Vector3(90f, 0f, 0f);
            shape.position = Vector3.zero;
            var em = rain.emission;
            em.rateOverTime = 0f;
            var r = rain.GetComponent<ParticleSystemRenderer>();
            r.renderMode = ParticleSystemRenderMode.Stretch;
            r.velocityScale = 0.035f;
            r.lengthScale = 1f;
            r.sharedMaterial = Mats.Particle(new Color(0.75f, 0.85f, 1f, 0.45f), Tex.Streak, true);
            r.shadowCastingMode = ShadowCastingMode.Off;
            rain.Play();

            var sg = new GameObject("Splashes");
            sg.transform.SetParent(transform, false);
            splash = sg.AddComponent<ParticleSystem>();
            splash.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var sm = splash.main;
            sm.loop = true;
            sm.startLifetime = 0.3f;
            sm.startSpeed = 0f;
            sm.startSize = new ParticleSystem.MinMaxCurve(0.1f, 0.35f);
            sm.maxParticles = 1500;
            sm.simulationSpace = ParticleSystemSimulationSpace.World;
            sm.startColor = new Color(0.8f, 0.9f, 1f, 0.3f);
            var ss = splash.shape;
            ss.shapeType = ParticleSystemShapeType.Box;
            ss.scale = new Vector3(28f, 0.01f, 28f);
            var se = splash.emission;
            se.rateOverTime = 0f;
            var sol = splash.sizeOverLifetime;
            sol.enabled = true;
            sol.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0, 0.3f, 1, 1f));
            var sr = splash.GetComponent<ParticleSystemRenderer>();
            sr.renderMode = ParticleSystemRenderMode.HorizontalBillboard;
            sr.sharedMaterial = Mats.Particle(new Color(0.8f, 0.9f, 1f, 0.5f), Tex.Ring, true);
            sr.shadowCastingMode = ShadowCastingMode.Off;
            splash.Play();
        }

        ParticleSystem MakeFx(string name, bool fire)
        {
            var go = new GameObject(name);
            go.transform.SetParent(transform, false);
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = ps.main;
            main.loop = true;
            main.startLifetime = fire ? new ParticleSystem.MinMaxCurve(0.4f, 0.9f) : new ParticleSystem.MinMaxCurve(2f, 4f);
            main.startSpeed = fire ? new ParticleSystem.MinMaxCurve(0.8f, 2f) : new ParticleSystem.MinMaxCurve(0.6f, 1.4f);
            main.startSize = fire ? new ParticleSystem.MinMaxCurve(0.3f, 0.7f) : new ParticleSystem.MinMaxCurve(1f, 2.5f);
            main.startColor = fire ? new Color(1f, 0.55f, 0.15f, 0.9f) : new Color(0.75f, 0.78f, 0.85f, 0.18f);
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.maxParticles = 120;
            var shape = ps.shape;
            shape.shapeType = ParticleSystemShapeType.Cone;
            shape.angle = fire ? 12f : 18f;
            shape.radius = fire ? 0.25f : 0.4f;
            shape.rotation = new Vector3(-90f, 0, 0);
            var em = ps.emission;
            em.rateOverTime = fire ? 30f : 8f;
            var col = ps.colorOverLifetime;
            col.enabled = true;
            var grad = new Gradient();
            grad.SetKeys(new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(fire ? new Color(1f, 0.2f, 0.05f) : Color.white, 1f) },
                new[] { new GradientAlphaKey(0f, 0f), new GradientAlphaKey(1f, 0.15f), new GradientAlphaKey(0f, 1f) });
            col.color = grad;
            var size = ps.sizeOverLifetime;
            size.enabled = true;
            size.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0, fire ? 1f : 0.5f, 1, fire ? 0.2f : 1.6f));
            var r = ps.GetComponent<ParticleSystemRenderer>();
            r.sharedMaterial = fire ? Mats.Particle(Color.white, Tex.Glow, true) : Mats.Particle(Color.white, Tex.Smoke, false);
            r.shadowCastingMode = ShadowCastingMode.Off;
            go.SetActive(false);
            return ps;
        }

        void BuildFxPools()
        {
            for (int i = 0; i < 10; i++) steamPool.Add(MakeFx("Steam" + i, false));
            for (int i = 0; i < 10; i++) firePool.Add(MakeFx("Fire" + i, true));
        }

        void AssignFx(List<ParticleSystem> pool, List<Vector3> spots, Vector3 cam)
        {
            if (spots.Count == 0) return;
            var near = new List<(float, Vector3)>();
            foreach (var s in spots)
            {
                float d = (s - cam).sqrMagnitude;
                if (d < 120f * 120f) near.Add((d, s));
            }
            near.Sort((a, b) => a.Item1.CompareTo(b.Item1));
            for (int i = 0; i < pool.Count; i++)
            {
                var ps = pool[i];
                if (i < near.Count)
                {
                    if ((ps.transform.position - near[i].Item2).sqrMagnitude > 0.5f || !ps.gameObject.activeSelf)
                    {
                        ps.transform.position = near[i].Item2;
                        ps.gameObject.SetActive(true);
                        ps.Play();
                    }
                }
                else if (ps.gameObject.activeSelf) ps.gameObject.SetActive(false);
            }
        }

        void BuildAirTraffic()
        {
            var r = new Rng(77);
            var city = Game.City;
            var spire = city.Loc("helix_tower");
            var center = spire != null ? spire.pos : city.Center;
            var body = M.metalDark;
            for (int i = 0; i < 26; i++)
            {
                var go = new GameObject("AV_" + i);
                go.transform.SetParent(transform, false);
                var mb = new MeshBuilder();
                mb.SimpleBox(new Vector3(0, 0, 0), new Vector3(2.4f, 1.1f, 5.5f), body);
                mb.SimpleBox(new Vector3(0, 0.4f, 0.6f), new Vector3(2f, 0.6f, 2.4f), M.glassDark);
                mb.SimpleBox(new Vector3(0, -0.1f, -2.8f), new Vector3(2.2f, 0.25f, 0.1f), M.Neon(Palette.Red, 5f));
                mb.SimpleBox(new Vector3(0, -0.1f, 2.8f), new Vector3(1.8f, 0.2f, 0.1f), M.lampCool);
                mb.SimpleBox(new Vector3(0, -0.6f, 0), new Vector3(2.2f, 0.06f, 4.5f), M.Neon(r.Pick(Palette.Neon), 3f));
                mb.BuildObject("Body", go.transform, false);
                flyers.Add(go.transform);
                float radius = r.Range(150f, 650f);
                var c = center + new Vector3(r.Range(-200f, 200f), 0, r.Range(-200f, 200f));
                flyerPaths.Add(new Vector4(c.x, c.z, radius, r.Range(70f, 220f)));
                flyerPhase.Add(r.Range(0f, Mathf.PI * 2));
                flyerSpeed.Add(r.Range(25f, 55f) * (r.Chance(0.5f) ? 1 : -1));
            }
        }

        public void SetWeather(Weather w, bool instant)
        {
            target = w;
            if (instant) { weather = w; blend = 1f; }
            else blend = 0f;
            weatherHoursLeft = Random.Range(4f, 10f);
        }

        public void SkipHours(float h)
        {
            timeOfDay += h;
            while (timeOfDay >= 24f) { timeOfDay -= 24f; day++; }
            weatherHoursLeft -= h;
            Apply(true);
        }

        void Update()
        {
            float dt = Time.deltaTime;
            if (!timeFrozen && Game.IsPlaying)
            {
                float hoursPerSecond = 24f / (dayLengthMinutes * 60f);
                timeOfDay += dt * hoursPerSecond;
                if (timeOfDay >= 24f) { timeOfDay -= 24f; day++; }
                weatherHoursLeft -= dt * hoursPerSecond;
                if (weatherHoursLeft <= 0f) PickNextWeather();
            }
            if (blend < 1f)
            {
                blend += dt / 40f;
                if (blend >= 1f) { blend = 1f; weather = target; }
            }
            Apply(false);
        }

        void PickNextWeather()
        {
            var weights = new[] { 3f, 2f, 1.5f, 2.5f, 1f, 0.6f };
            int i = new Rng((int)(Time.time * 1000) + day).WeightedIndex(weights);
            SetWeather((Weather)i, false);
        }

        float RainOf(Weather w) => w == Weather.Rain ? 0.7f : w == Weather.Storm ? 1f : 0f;
        float FogOf(Weather w) => w switch { Weather.Clear => 0.0012f, Weather.Cloudy => 0.0018f, Weather.Smog => 0.0042f, Weather.Rain => 0.0026f, Weather.Storm => 0.0034f, _ => 0.005f };
        Color FogTint(Weather w) => w switch { Weather.Smog => new Color(0.75f, 0.62f, 0.42f), Weather.AcidHaze => new Color(0.45f, 0.75f, 0.3f), Weather.Storm => new Color(0.5f, 0.55f, 0.7f), _ => Color.white };

        void Apply(bool force)
        {
            float night = NightFactor;
            float dt = Time.deltaTime;
            Weather from = weather, to = target;
            float k = blend;
            rainAmount = Mathf.Lerp(RainOf(from), RainOf(to), k);
            float fogD = Mathf.Lerp(FogOf(from), FogOf(to), k);
            var tint = Color.Lerp(FogTint(from), FogTint(to), k);
            wetness = force ? Mathf.Max(wetness, rainAmount) : Mathf.MoveTowards(wetness, rainAmount > 0.05f ? 1f : 0f, dt * (rainAmount > 0.05f ? 0.05f : 0.008f));

            // --- sun & moon
            float sunAngle = (timeOfDay - 6f) / 12f * 180f;
            bool sunUp = sunAngle > -6f && sunAngle < 186f;
            Color sunCol; float sunInt;
            if (sunUp)
            {
                float elev = Mathf.Clamp(sunAngle, 2f, 178f);
                sun.transform.rotation = Quaternion.Euler(elev, 35f, 0f);
                float noon = Mathf.Sin(Mathf.Deg2Rad * Mathf.Clamp(sunAngle, 0, 180));
                sunCol = Color.Lerp(new Color(1f, 0.5f, 0.3f), new Color(1f, 0.95f, 0.88f), Mathf.Pow(noon, 0.5f));
                sunInt = Mathf.Lerp(0.15f, 1.35f, Mathf.Pow(noon, 0.6f)) * (1f - night * 0.8f);
            }
            else
            {
                sun.transform.rotation = Quaternion.Euler(38f, 210f, 0f);
                sunCol = new Color(0.55f, 0.62f, 0.95f);
                sunInt = 0.14f;
            }
            float overcast = Mathf.Lerp(Overcast(from), Overcast(to), k);
            sun.color = Color.Lerp(sunCol, new Color(0.6f, 0.65f, 0.75f), overcast * 0.5f);
            sun.intensity = sunInt * (1f - overcast * 0.6f) + flash * 3f;
            sun.shadowStrength = Mathf.Lerp(0.95f, 0.5f, overcast);

            // --- ambient & fog
            var skyDay = new Color(0.48f, 0.55f, 0.68f); var skyNight = new Color(0.07f, 0.05f, 0.14f);
            var eqDay = new Color(0.38f, 0.38f, 0.42f); var eqNight = new Color(0.08f, 0.05f, 0.1f);
            var grDay = new Color(0.2f, 0.19f, 0.18f); var grNight = new Color(0.035f, 0.025f, 0.04f);
            RenderSettings.ambientSkyColor = Color.Lerp(skyDay, skyNight, night) * (1f - overcast * 0.25f) + Color.white * flash;
            RenderSettings.ambientEquatorColor = Color.Lerp(eqDay, eqNight, night);
            RenderSettings.ambientGroundColor = Color.Lerp(grDay, grNight, night);
            var fogDay = new Color(0.55f, 0.58f, 0.63f); var fogNight = new Color(0.09f, 0.06f, 0.15f);
            var fc = Color.Lerp(fogDay, fogNight, night);
            fc = new Color(fc.r * tint.r, fc.g * tint.g, fc.b * tint.b);
            RenderSettings.fogColor = fc + Color.white * flash * 0.5f;
            RenderSettings.fogDensity = fogD * (1f + night * 0.25f);

            if (sky != null)
            {
                sky.SetFloat("_SunSize", 0.035f);
                sky.SetFloat("_AtmosphereThickness", Mathf.Lerp(1.1f, 0.55f, night) + overcast * 0.6f);
                sky.SetColor("_SkyTint", Color.Lerp(new Color(0.5f, 0.55f, 0.65f), new Color(0.35f, 0.2f, 0.5f), night));
                sky.SetColor("_GroundColor", Color.Lerp(new Color(0.4f, 0.38f, 0.36f), new Color(0.15f, 0.06f, 0.2f), night));
                sky.SetFloat("_Exposure", Mathf.Lerp(1.25f, 0.18f, night) * (1f - overcast * 0.35f) + flash * 2f);
            }

            // --- post processing grade
            if (PostFX.Available)
            {
                PostFX.SetBloom(Mathf.Lerp(0.55f, 1.45f, night) + flash, Mathf.Lerp(1.05f, 0.85f, night));
                var filter = Color.Lerp(Color.white, new Color(0.92f, 0.95f, 1.05f), night);
                if (to == Weather.AcidHaze) filter = Color.Lerp(filter, new Color(0.9f, 1.05f, 0.85f), k);
                if (to == Weather.Smog) filter = Color.Lerp(filter, new Color(1.05f, 0.98f, 0.85f), k);
                PostFX.SetGrade(Mathf.Lerp(0.05f, 0.4f, night), Mathf.Lerp(12f, 22f, night) + rainAmount * 6f, Mathf.Lerp(-2f, 14f, night), filter);
                PostFX.SetWhiteBalance(Mathf.Lerp(4f, -10f, night), Mathf.Lerp(0f, 8f, night));
            }

            // --- emissive windows, blinking beacons
            emissionTimer -= dt;
            if (emissionTimer <= 0f || force)
            {
                emissionTimer = 2f;
                float wk = Mathf.Lerp(0.25f, 1f, night);
                foreach (var kv in M.facadeEmission)
                    if (kv.Key != null) kv.Key.SetColor("_EmissionColor", Color.white * kv.Value * wk);
                float wetGloss = Mathf.Lerp(0.38f, 0.95f, wetness);
                foreach (var m in M.wetMaterials) Mats.SetSmoothness(m, wetGloss);
            }
            blinkTimer -= dt;
            if (blinkTimer <= 0f)
            {
                blinkTimer = 0.9f;
                blinkOn = !blinkOn;
                M.blinkRed.color = blinkOn ? Palette.Red * 6f : Palette.Red * 0.1f;
                if (Mats.URP) M.blinkRed.SetColor("_BaseColor", M.blinkRed.color);
            }

            // --- camera-following effects
            var cam = Game.Cam;
            if (cam != null)
            {
                var cp = cam.transform.position;
                var lead = Game.Player != null ? Game.Player.Velocity * 0.6f : Vector3.zero;
                rain.transform.position = cp + Vector3.up * 16f + lead;
                var em = rain.emission;
                em.rateOverTime = cp.y < -20f ? 0f : rainAmount * 5200f;
                splash.transform.position = new Vector3(cp.x, 0.2f, cp.z);
                var se = splash.emission;
                se.rateOverTime = cp.y < 30f ? rainAmount * 900f : 0f;

                probeTimer -= dt;
                if (probeTimer <= 0f)
                {
                    probeTimer = 0.8f;
                    probe.transform.position = cp + Vector3.up * 2f;
                    probe.RenderProbe();
                }

                fxAssignTimer -= dt;
                if (fxAssignTimer <= 0f && gen != null)
                {
                    fxAssignTimer = 1f;
                    AssignFx(steamPool, gen.steamVents, cp);
                    AssignFx(firePool, gen.fireBarrels, cp);
                }

                if (ambRain != null) ambRain.volume = rainAmount * 0.75f * (cp.y < -20f ? 0.1f : 1f);
                if (ambCity != null) ambCity.volume = (cp.y < -20f ? 0.12f : 0.5f) * (Game.Audio != null ? Game.Audio.SfxVolume : 1f);
                if (ambWind != null) ambWind.volume = Mathf.Clamp01((cp.y - 40f) / 150f) * 0.8f + (to == Weather.Storm ? 0.25f : 0f);
            }

            // --- storms
            if (Mathf.Max(from == Weather.Storm ? 1 : 0, to == Weather.Storm ? k : 0) > 0.5f)
            {
                lightningTimer -= dt;
                if (lightningTimer <= 0f)
                {
                    lightningTimer = Random.Range(7f, 22f);
                    StartCoroutine(Lightning());
                }
            }
            flash = Mathf.MoveTowards(flash, 0f, dt * 6f);

            // --- sky traffic
            for (int i = 0; i < flyers.Count; i++)
            {
                var path = flyerPaths[i];
                flyerPhase[i] += flyerSpeed[i] / path.z * dt;
                float a = flyerPhase[i];
                var p = new Vector3(path.x + Mathf.Cos(a) * path.z, path.w + Mathf.Sin(a * 3f) * 4f, path.y + Mathf.Sin(a) * path.z);
                var tangent = new Vector3(-Mathf.Sin(a), 0, Mathf.Cos(a)) * Mathf.Sign(flyerSpeed[i]);
                flyers[i].SetPositionAndRotation(p, Quaternion.LookRotation(tangent));
            }

            if (Game.Chunks != null) Game.Chunks.nightFactor = Mathf.Max(0.35f, night);
        }

        float Overcast(Weather w) => w switch { Weather.Clear => 0f, Weather.Cloudy => 0.6f, Weather.Smog => 0.5f, Weather.Rain => 0.8f, Weather.Storm => 1f, _ => 0.7f };

        System.Collections.IEnumerator Lightning()
        {
            flash = 1f;
            yield return new WaitForSeconds(0.08f);
            flash = 0.2f;
            yield return new WaitForSeconds(0.06f);
            flash = 0.9f;
            float delay = Random.Range(0.4f, 2.2f);
            yield return new WaitForSeconds(delay);
            Game.Audio?.Play2D("thunder", Mathf.Lerp(1f, 0.5f, delay / 2.2f), Random.Range(0.85f, 1.1f));
        }
    }
}
