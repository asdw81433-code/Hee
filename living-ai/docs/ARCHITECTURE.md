# Kivo — architecture and migration plan

Kivo is a local-first Android companion: a robot that lives on the screen, talks, remembers,
has simulated moods, starts activities on its own and operates the phone — with all AI
inference on the device. No OpenAI / Claude / Gemini / other cloud AI is used anywhere.

Target device: Samsung Galaxy A07 4G (Android 16, 4 GB RAM, Helio G99). `minSdk 26`, `targetSdk 36`.
Package ID (unchanged): `com.livingai.companion`.

## 1. What the project was before this work (inspection)

| Item | Finding |
|---|---|
| Framework | Native Android, Kotlin, plain framework Views (no Compose, no Unity). The Unity project at the repository root (`Assets/`, `Packages/`) is an unrelated game and is not part of the app. |
| Modules | `:core` (pure Kotlin/JVM logic + unit tests), `:app` (Android), `:typecheck` (compiles app sources against Android 16 classes on a plain JVM) |
| Working, tested features | reading other apps' UI through the accessibility service; tap / type / scroll / back / home with verification; safety policy and secret redaction; screen capture service (MediaProjection); Latin OCR (ML Kit); floating robot overlay (accessibility overlay or "display over other apps"); on-device rule-based conversation ("LocalMind"); memory in Room; Thai / English UI |
| Removed in this migration | Claude SDK client and Gemini REST client (cloud AI, never verified against the real services), API-key storage, "send screenshots to the AI" |
| Memory bottlenecks found | Anthropic SDK + Jackson + OkHttp in the dex (largest dependency by far); ML Kit; full-size capture frames; no control over what is loaded at the same time |

## 2. Modules

All logic lives in `:core` as packages with interfaces between them; `:app` only implements
the Android-facing ports. Nothing in `:core` depends on Android, so every module is unit-tested
on a plain JVM.

| Module (spec name) | Package | Responsibility | Main interfaces |
|---|---|---|---|
| Core | `core` | `KivoCore`: receives a message or a phone event, decides, drives the other modules | `AgentListener`, `KeyValueStore`, `Clock` |
| AI Engine | `core.ai` | local text generation (llama.cpp + GGUF), chat prompt with cached prefix, model catalog / download / import | `TextGenerator`, `LlamaEngine`, `ChatBrain`, `ModelFiles`, `ModelDownloader` |
| Memory | `core.memory` | short-term, long-term, episodic, knowledge; relevance search; export | `MemoryStore` |
| Personality | `core.personality` | persistent traits, speech style, interests, bond level | `Personality` |
| Emotion | `core.emotion` | simulated mood state machine driven by events | `EmotionEngine`, `Mood` |
| Perception | `core.perception` | what is on screen (UI tree, capture, OCR), sanitised | `ScreenSource`, `VisionAgent` |
| Tools | `core.tools` | acting on the screen and on the phone; command parsing; safety | `ActionPort`, `DevicePort`, `ConfirmationPort`, `SafetyPolicy` |
| Robot | `core.robot` | 3D rig, animation state machine, renderer | `Painter` |
| Resource Manager | `core.resource` | what may be in memory at once; idle unload; memory pressure | `ResourceManager`, `ManagedResource`, `MemoryProbe` |
| Privacy | `core.privacy` | redaction of secrets before anything is stored or shown | `Redactor` (the action gate is `tools.SafetyPolicy`; data wipe is `AgentController.deleteAllData`) |
| Companion | `core.companion` | built-in conversation, initiative, activities and games | `LocalMind`, `Initiative`, `ActivityHub`, `Activity` |

Android implementations (`:app`, package `com.livingai.companion`):

| Port | Implementation |
|---|---|
| `ScreenSource` | `vision.AndroidScreenSource` (accessibility tree → capture → OCR) |
| `ActionPort` | `control.A11yActionPort` (AccessibilityService) |
| `DevicePort` | `tools.AndroidDevicePort` (intents, package manager) |
| `MemoryStore` | `memory.SqliteMemoryStore` (SQLiteOpenHelper, n-gram index) |
| reminders | `tools.ReminderScheduler` + `ReminderReceiver` (AlarmManager) |
| OCR | `vision.OcrEngine` (Tesseract, Thai + English) |
| voice | `agent.Speaker` (system TTS), `ui.VoiceActivity` (system recogniser, on-device first) |
| `MemoryProbe` | `resource.AndroidMemoryProbe` (ActivityManager) |
| `TextGenerator` | llama.cpp through JNI (`core.ai.LlamaEngine` + `app/src/main/cpp`) |

## 3. Resource manager

A 4 GB phone cannot hold the AI model, OCR, voice and capture at the same time next to the
app the user is actually using. `ResourceManager` therefore:

* loads nothing heavy until it is asked for (`acquire`);
* before a load, unloads idle resources (least recently used first) until the new one fits
  while leaving a safety margin (300 MB) for Android and the foreground app;
* refuses a load with a clear reason when it still does not fit, instead of risking a crash;
* releases resources nobody used for a while (`onIdleTick`, default 5 minutes);
* releases everything not in use on memory pressure (`onMemoryPressure`) and reports
  `LOW_RAM` mode so animation can slow down.

No RAM number is guaranteed in advance; the manager works from what `MemoryProbe` reports
on the actual device at that moment.

## 4. How a message is handled

```
user text ─► KivoCore
              1. a game in progress / a request to play     → ActivityHub        (no model)
              2. arithmetic                                  → Calculator         (no model)
              3. small talk, time, battery, name             → LocalMind          (no model, instant)
              4. commands, possibly chained with "แล้ว"       → LocalBrain → ActionAgent (SafetyPolicy, confirmation) / DevicePort / memory
              5. anything else                               → ChatBrain → LlamaEngine (streamed), if a model is installed and RAM allows
           emotion events, memory extraction and the speech style are applied around all of them
```

The language model never produces actions. Only the rule parser does, and every screen action
passes the safety policy. This keeps behaviour predictable and makes prompt injection through
on-screen text harmless.

Prompt layout for step 5: English system prompt (few tokens), two Thai example turns, the
anchored conversation window, then the new message with a bracketed context note (time, mood,
user name, relevant memories). Everything before the new message is identical from turn to
turn, so llama.cpp's KV cache is reused (measured: 90 %+ of prompt tokens cached in a running
conversation). A GBNF grammar keeps the output in Thai / Latin script.

## 5. Work order (all eight phases are done)

1. Architecture, module split, resource manager, cloud AI removed
2. Robot (3D rig, animation state machine) and overlay service
3. Memory (SQLite, relevance search), personality, emotion
4. Local AI engine (llama.cpp, GGUF) and Thai conversation
5. Voice (system TTS / STT, offline first) and vision (Thai OCR)
6. Android tools (apps, settings, alarms, reminders, notes)
7. Active companion (initiative, activities, quiet mode)
8. UI pages, performance read-outs, documentation, release APK

Existing user data is kept: the old memory database is imported into the new store on first
start, and settings keys are unchanged. Test evidence: `docs/TEST_RESULTS.md`.
