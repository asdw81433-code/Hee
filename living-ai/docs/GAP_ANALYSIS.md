# Kivo vs. MASTER SPECIFICATION — audit and gap analysis (v3.1.0)

Audit of the real project: ~13,000 lines of Kotlin/C++ in `:core` (pure JVM, unit tested) and
`:app` (Android), 110+ unit tests, 11 emulator tests on Android 16. Status words mean:
**Done** = implemented and covered by a test that ran; **Partial** = works but narrower than the
spec; **Not done** = absent. Nothing here is claimed without code behind it.

| Part | Area | Status | What exists / what is missing |
|---|---|---|---|
| 1 | Identity, personality | Done / Partial | Persistent personality (traits, speech style, interests, bond), custom name + free-text persona. Spec's 8 traits are covered by 4 sliders + prompt; no separate humor/empathy dials |
| 2 | Brain architecture | Partial | Perception, context (anchored chat window + memories), decision (rules → model), tools, memory, personality are separate modules behind interfaces. No standalone "reasoning" or "self-evaluation" engine: reasoning is whatever the model does |
| 3 | Multi-AI | **Done (new)** | `ProviderStore`, `RemoteGenerator` (any OpenAI-compatible API, streaming), `ModelRouter` (primary → fallbacks → phone model, says who answered and why), API screen with test button, keys in Android Keystore. Router picks by availability and order, not by task type / price |
| 4 | Memory | Partial | SQLite, kinds: fact, episode, knowledge, note, to-do, routines (procedural); relevance search for Thai; manager UI; auto-memory switch; backup/restore. Missing metadata: confidence, source, expiration, privacy level; no consolidation / merge |
| 5 | Learning | Partial | Learns facts from talk, app-usage habits, autopilot routines that worked. No learning from explicit feedback on answers (length, style) |
| 6 | Research | Partial | Wikipedia lookup with source link (new). No multi-source comparison, date / reliability grading, or background "curiosity" |
| 7 | Agent | Partial | Autopilot loop observe → decide → act → verify with learned routines, safety gate, stop. No task objects with IDs / priorities / deadlines, no recovery of an interrupted task |
| 8 | Screen awareness | Done | Accessibility tree, MediaProjection capture, Thai + English OCR, sensitive-screen blocking |
| 9 | Device control | Done / Partial | Apps, settings pages, tap / type / scroll / back, alarm, timer, reminders, calendar, share, verified actions. No file manager, clipboard, notification listener |
| 10 | Voice | Partial | System STT with own listening card, system TTS (best offline voice, rate, pitch, pauses). **New in 3.1:** continuous voice conversation (listen → answer out loud → listen again until "End", tolerates short silences). No barge-in (talking over Kivo), no pronunciation dictionary. The voice is the phone's, not a unique Kivo voice |
| 11 | Avatar | Partial | Animated robot with state machine (idle, listening, thinking, talking, moods, working, sleeping, gestures), emotion → animation mapping. **New in 3.1:** selectable style — 3D-shaded hovering robot (default) or pixel; on Home it is big, can be dragged to turn, looks toward the finger and reacts to taps. The "3D" is shaded vector drawing in code, not a real-time mesh engine (Unity/Filament) |
| 12 | Emotion | Done | Event-driven mood engine, sentiment from text, never claims real feelings |
| 13 | Proactive | Done | Initiative with gap, daily cap, back-off, quiet mode, DND hours, user-adjustable |
| 14 | Tools | Partial | **New in 3.1:** AI Tools page (translate, summarise text, help me write, plan, look up, picture → OCR + AI explanation, .txt file → AI summary, screen summary, to-do, reminders, calculator, autopilot, app stats, games, system check) — each runs the real command and the answer appears in Chat. No formal tool registry with schemas. Pictures: the AI reads the *text* in them; it cannot see photos (the phone model is text-only) |
| 15 | Automation | Partial | One-off reminders (AlarmManager), habit nudges. No recurring user-defined jobs, no workflow builder, no dashboard |
| 16 | Knowledge base | Partial | Built-in fact table, user-taught knowledge in memory. No vector search |
| 17 | Security & privacy | Done / Partial | Keystore-encrypted keys, redaction, permission-by-need, delete-all, emergency stop, switch for sending screen text online. No single privacy dashboard page |
| 18 | Architecture | Partial | Kotlin, clean module split with interfaces, SQLite, coroutines. Deliberately **not** Compose / Hilt / Retrofit / Room / Unity: plain views and HttpURLConnection keep the app small (~18 MB without the bundled model) and light on a 4 GB phone |
| 19 | UI | Done / Partial | **New in 3.1:** Companion Home (big interactive robot, greeting, status, last reply, talk / chat, float / stop, shortcuts), separate Chat (streaming, stop, long-press copy, search old chats, new conversation, attach picture or text file), Tools, Memory, Settings tabs. No task cards / citations UI beyond text |
| 20 | Performance | Partial | Resource manager, load on demand, low-RAM mode, frame pacing. **Never measured on a real Galaxy A07** |
| 21 | Diagnostics | **Done (new)** | "ตรวจระบบ": network, each provider (live call), phone model, database, RAM, storage, permissions |
| 22 | Extensibility | Partial | New providers need no code; in-app update check. No plugin system |
| 23 | Testing | Done / Partial | Unit + emulator tests in CI on every push. No stress / soak tests |

## Honest limits that no update removes
* A phone with 4 GB RAM runs only a ~1B-parameter model locally: weak. Real intelligence needs an
  online provider (user's own API key; cost and privacy follow that provider).
* Android does not allow any app to act in other apps without the accessibility permission, to read
  protected screens, or to flip system switches. Kivo does not try to get around that.
* Playing action games (RoV, Roblox) to completion is not possible for this design and using bots
  in online games breaks their rules.
