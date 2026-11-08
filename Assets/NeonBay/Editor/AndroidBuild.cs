using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace NeonBay.EditorTools
{
    /// <summary>
    /// One-click Android APK: "Neon Bay > Build Android APK". Also the entry point for CI
    /// (-executeMethod NeonBay.EditorTools.AndroidBuild.BuildCI, used by .github/workflows/android-apk.yml).
    /// Needs the Android Build Support module (with SDK/NDK and OpenJDK) installed in Unity Hub.
    /// </summary>
    public static class AndroidBuild
    {
        const string PackageId = "com.neonbay.staticsaints";
        const string Version = "2.0.0";
        const int VersionCode = 20;
        const string DefaultOutput = "Builds/Android/NeonBay.apk";

        [MenuItem("Neon Bay/Build Android APK", priority = 20)]
        public static void BuildMenu() => Build(DefaultOutput, false, VersionCode, Version);

        [MenuItem("Neon Bay/Build Android APK (Development)", priority = 21)]
        public static void BuildDevMenu() => Build("Builds/Android/NeonBay-dev.apk", true, VersionCode, Version);

        /// <summary>Command-line / CI build. Understands game-ci's arguments (-customBuildPath, -androidVersionCode, keystore args).</summary>
        public static void BuildCI()
        {
            string output = Arg("-customBuildPath") ?? Arg("-buildPath") ?? DefaultOutput;
            if (Directory.Exists(output) || !output.EndsWith(".apk", StringComparison.OrdinalIgnoreCase)) output = Path.Combine(output, "NeonBay.apk");
            int code = int.TryParse(Arg("-androidVersionCode"), out var c) && c > 0 ? c : VersionCode;
            string version = Arg("-buildVersion");
            if (string.IsNullOrEmpty(version) || version == "none") version = Version;

            string ks = Arg("-androidKeystoreName");
            if (!string.IsNullOrEmpty(ks) && File.Exists(ks) && new FileInfo(ks).Length > 0)
            {
                PlayerSettings.Android.useCustomKeystore = true;
                PlayerSettings.Android.keystoreName = Path.GetFullPath(ks);
                PlayerSettings.Android.keystorePass = Arg("-androidKeystorePass") ?? "";
                PlayerSettings.Android.keyaliasName = Arg("-androidKeyaliasName") ?? "";
                PlayerSettings.Android.keyaliasPass = Arg("-androidKeyaliasPass") ?? "";
            }
            else PlayerSettings.Android.useCustomKeystore = false; // debug-signed APK, installs fine by sideloading

            bool ok = Build(output, Arg("-development") != null, code, version);
            EditorApplication.Exit(ok ? 0 : 1);
        }

        static bool Build(string output, bool development, int versionCode, string version)
        {
            bool batch = Application.isBatchMode;
            try
            {
                NeonBaySetup.Setup(false); // URP asset, linear colour, always-included shaders, game scene
                if (!File.Exists(NeonBaySetup.ScenePath))
                {
                    Fail("The game scene could not be created (" + NeonBaySetup.ScenePath + "). Open 'Neon Bay > Setup Project' once and try again.", batch);
                    return false;
                }
                Configure(versionCode, version);

                var dir = Path.GetDirectoryName(output);
                if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
                var options = new BuildPlayerOptions
                {
                    scenes = new[] { NeonBaySetup.ScenePath },
                    locationPathName = output,
                    target = BuildTarget.Android,
                    targetGroup = BuildTargetGroup.Android,
                    options = development ? BuildOptions.Development : BuildOptions.None,
                };
                var report = BuildPipeline.BuildPlayer(options);
                var s = report.summary;
                if (s.result != BuildResult.Succeeded)
                {
                    Fail("Android build " + s.result + " with " + s.totalErrors + " error(s). See the Console for details.", batch);
                    return false;
                }
                Debug.Log("[Neon Bay] APK ready: " + Path.GetFullPath(output) + " (" + (s.totalSize / (1024f * 1024f)).ToString("0.0") + " MB, " + s.totalTime.TotalMinutes.ToString("0.0") + " min)");
                if (!batch) EditorUtility.RevealInFinder(output);
                return true;
            }
            catch (Exception e)
            {
                Fail("Android build failed: " + e.Message, batch);
                Debug.LogException(e);
                return false;
            }
        }

        static void Configure(int versionCode, string version)
        {
            var android = NamedBuildTarget.Android;
            PlayerSettings.companyName = "Neon Bay";
            PlayerSettings.productName = "Neon Bay";
            PlayerSettings.bundleVersion = version;
            PlayerSettings.SetApplicationIdentifier(android, PackageId);
            PlayerSettings.Android.bundleVersionCode = versionCode;
            EditorUserBuildSettings.buildAppBundle = false;

            // 64-bit IL2CPP is required by Google Play and runs far faster than Mono on phones
            PlayerSettings.SetScriptingBackend(android, ScriptingImplementation.IL2CPP);
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            // the game reaches URP through reflection; link.xml keeps it, minimal stripping keeps the rest safe
            PlayerSettings.SetManagedStrippingLevel(android, ManagedStrippingLevel.Minimal);
            PlayerSettings.Android.targetSdkVersion = AndroidSdkVersions.AndroidApiLevelAuto;

            // landscape only
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.AutoRotation;
            PlayerSettings.allowedAutorotateToLandscapeLeft = true;
            PlayerSettings.allowedAutorotateToLandscapeRight = true;
            PlayerSettings.allowedAutorotateToPortrait = false;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;

            PlayerSettings.SetUseDefaultGraphicsAPIs(BuildTarget.Android, true); // Vulkan with OpenGL ES 3 fallback
            PlayerSettings.colorSpace = ColorSpace.Linear;
            PlayerSettings.Android.renderOutsideSafeArea = true; // the touch overlay lays itself out inside Screen.safeArea

            // touch -> IMGUI menus and the touch overlay work with both input back-ends; "Both" is the safest on Android
            SetActiveInputHandling(2);
            AssetDatabase.SaveAssets();
        }

        /// <summary>0 = Input Manager (old), 1 = Input System (new), 2 = both.</summary>
        static void SetActiveInputHandling(int mode)
        {
            try
            {
                var assets = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/ProjectSettings.asset");
                if (assets == null || assets.Length == 0) return;
                var so = new SerializedObject(assets[0]);
                var prop = so.FindProperty("activeInputHandler");
                if (prop == null || prop.intValue == mode) return;
                prop.intValue = mode;
                so.ApplyModifiedPropertiesWithoutUndo();
                Debug.Log("[Neon Bay] Active Input Handling set to 'Both' for the Android build.");
            }
            catch (Exception e) { Debug.LogWarning("[Neon Bay] Couldn't set Active Input Handling: " + e.Message); }
        }

        static string Arg(string name)
        {
            var args = Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length; i++)
            {
                if (!string.Equals(args[i], name, StringComparison.OrdinalIgnoreCase)) continue;
                if (i + 1 < args.Length && !args[i + 1].StartsWith("-")) return args[i + 1];
                return "";
            }
            return null;
        }

        static void Fail(string message, bool batch)
        {
            Debug.LogError("[Neon Bay] " + message);
            if (!batch) EditorUtility.DisplayDialog("Neon Bay - Android build", message, "OK");
        }
    }
}
