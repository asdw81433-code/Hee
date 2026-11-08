using System;
using System.Linq;
using System.Reflection;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;

namespace NeonBay.EditorTools
{
    /// <summary>
    /// One-time project setup: creates the game scene, adds it to Build Settings, switches to Linear color space,
    /// creates a URP asset when URP is installed but not assigned, and keeps runtime shaders in builds.
    /// </summary>
    [InitializeOnLoad]
    public static class NeonBaySetup
    {
        internal const string ScenePath = "Assets/NeonBay/Scenes/NeonBay.unity";
        const string SettingsDir = "Assets/NeonBay/Settings";
        const string DoneKey = "NeonBay.SetupDone.v1";

        static NeonBaySetup()
        {
            EditorApplication.delayCall += () =>
            {
                if (EditorApplication.isPlayingOrWillChangePlaymode) return;
                if (!SessionState.GetBool(DoneKey, false))
                {
                    SessionState.SetBool(DoneKey, true);
                    Setup(false);
                }
            };
        }

        [MenuItem("Neon Bay/Setup Project", priority = 0)]
        public static void SetupMenu() => Setup(true);

        [MenuItem("Neon Bay/Open Game Scene", priority = 1)]
        public static void OpenScene()
        {
            EnsureScene();
            if (EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) EditorSceneManager.OpenScene(ScenePath);
        }

        [MenuItem("Neon Bay/Play", priority = 2)]
        public static void Play()
        {
            OpenScene();
            EditorApplication.isPlaying = true;
        }

        internal static void Setup(bool verbose)
        {
            try
            {
                if (PlayerSettings.colorSpace != ColorSpace.Linear)
                {
                    PlayerSettings.colorSpace = ColorSpace.Linear;
                    Debug.Log("[Neon Bay] Switched the project to Linear color space.");
                }
                PlayerSettings.productName = "Neon Bay";
                EnsureUrpAsset();
                EnsureAlwaysIncludedShaders();
                EnsureScene();
                if (verbose) EditorUtility.DisplayDialog("Neon Bay", "Setup complete.\n\nOpen 'Neon Bay > Open Game Scene' and press Play.", "OK");
            }
            catch (Exception e)
            {
                Debug.LogWarning("[Neon Bay] Setup step failed: " + e.Message);
            }
        }

        static void EnsureScene()
        {
            if (!AssetDatabase.IsValidFolder("Assets/NeonBay/Scenes")) AssetDatabase.CreateFolder("Assets/NeonBay", "Scenes");
            if (!System.IO.File.Exists(ScenePath))
            {
                var current = EditorSceneManager.GetActiveScene();
                // Additive scene creation isn't allowed while an untitled scene is open, so replace it in that case.
                bool single = string.IsNullOrEmpty(current.path) && !current.isDirty;
                if (!single && string.IsNullOrEmpty(current.path)) return;
                var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, single ? NewSceneMode.Single : NewSceneMode.Additive);
                var boot = new GameObject("NeonBay Boot");
                boot.AddComponent<NeonBayBoot>();
                EditorSceneManager.MoveGameObjectToScene(boot, scene);
                EditorSceneManager.SaveScene(scene, ScenePath);
                if (!single) EditorSceneManager.CloseScene(scene, true);
                Debug.Log("[Neon Bay] Created " + ScenePath);
            }
            var scenes = EditorBuildSettings.scenes.ToList();
            if (!scenes.Any(s => s.path == ScenePath))
            {
                scenes.Insert(0, new EditorBuildSettingsScene(ScenePath, true));
                EditorBuildSettings.scenes = scenes.ToArray();
            }
        }

        static Type FindType(string fullName)
        {
            foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
            {
                var t = asm.GetType(fullName, false);
                if (t != null) return t;
            }
            return null;
        }

        /// <summary>Creates and assigns a URP asset through reflection, so this compiles without URP installed.</summary>
        static void EnsureUrpAsset()
        {
            if (GraphicsSettings.defaultRenderPipeline != null) return;
            var assetType = FindType("UnityEngine.Rendering.Universal.UniversalRenderPipelineAsset");
            var dataType = FindType("UnityEngine.Rendering.Universal.UniversalRendererData");
            if (assetType == null || dataType == null) { Debug.Log("[Neon Bay] URP not installed - running on the Built-in pipeline (no post-processing). Install 'Universal RP' for the full look."); return; }
            if (!AssetDatabase.IsValidFolder(SettingsDir)) AssetDatabase.CreateFolder("Assets/NeonBay", "Settings");

            var data = ScriptableObject.CreateInstance(dataType);
            var ppType = FindType("UnityEngine.Rendering.Universal.PostProcessData");
            var getDefault = ppType?.GetMethod("GetDefaultPostProcessData", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic);
            var ppField = dataType.GetField("postProcessData", BindingFlags.Public | BindingFlags.Instance);
            if (getDefault != null && ppField != null) ppField.SetValue(data, getDefault.Invoke(null, null));
            var modeProp = dataType.GetProperty("renderingMode", BindingFlags.Public | BindingFlags.Instance);
            if (modeProp != null && modeProp.CanWrite)
            {
                try { modeProp.SetValue(data, Enum.Parse(modeProp.PropertyType, "ForwardPlus")); } catch (Exception) { }
            }
            AssetDatabase.CreateAsset(data, SettingsDir + "/NeonBay_Renderer.asset");

            var create = assetType.GetMethod("Create", BindingFlags.Static | BindingFlags.Public, null, new[] { FindType("UnityEngine.Rendering.Universal.ScriptableRendererData") }, null);
            if (create == null) { Debug.LogWarning("[Neon Bay] Couldn't find UniversalRenderPipelineAsset.Create - assign a URP asset manually in Project Settings > Graphics."); return; }
            var asset = (RenderPipelineAsset)create.Invoke(null, new object[] { data });
            void Set(string prop, object value)
            {
                var p = assetType.GetProperty(prop, BindingFlags.Public | BindingFlags.Instance);
                if (p != null && p.CanWrite) { try { p.SetValue(asset, value); } catch (Exception) { } }
            }
            Set("supportsHDR", true);
            Set("msaaSampleCount", 4);
            Set("shadowDistance", 160f);
            Set("supportsCameraDepthTexture", true);
            Set("supportsCameraOpaqueTexture", true);
            Set("supportsSoftShadows", true);
            Set("mainLightShadowmapResolution", 2048);
            Set("maxAdditionalLightsCount", 8);
            AssetDatabase.CreateAsset(asset, SettingsDir + "/NeonBay_URP.asset");
            AssetDatabase.SaveAssets();
            GraphicsSettings.defaultRenderPipeline = asset;
            QualitySettings.renderPipeline = asset;
            Debug.Log("[Neon Bay] Created and assigned a URP asset with HDR, soft shadows and post-processing.");
        }

        static void EnsureAlwaysIncludedShaders()
        {
            var names = new[]
            {
                "Universal Render Pipeline/Lit", "Universal Render Pipeline/Unlit", "Universal Render Pipeline/Particles/Unlit",
                "Standard", "Unlit/Texture", "Unlit/Color", "Legacy Shaders/Particles/Additive", "Legacy Shaders/Particles/Alpha Blended",
                "Skybox/Procedural", "Sprites/Default", "GUI/Text Shader"
            };
            var gs = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/GraphicsSettings.asset").FirstOrDefault();
            if (gs == null) return;
            var so = new SerializedObject(gs);
            var arr = so.FindProperty("m_AlwaysIncludedShaders");
            if (arr == null) return;
            bool changed = false;
            foreach (var n in names)
            {
                var sh = Shader.Find(n);
                if (sh == null) continue;
                bool found = false;
                for (int i = 0; i < arr.arraySize; i++) if (arr.GetArrayElementAtIndex(i).objectReferenceValue == sh) { found = true; break; }
                if (found) continue;
                arr.InsertArrayElementAtIndex(arr.arraySize);
                arr.GetArrayElementAtIndex(arr.arraySize - 1).objectReferenceValue = sh;
                changed = true;
            }
            if (changed) so.ApplyModifiedProperties();
        }
    }
}
