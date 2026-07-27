# Quota Watch agent guide

## Mission

Use Quota Watch as a learning project that helps the user define, inspect, verify, and ship software while continuing to use AI. Work implementation-first: complete a small verified feature, and discuss concepts when the user asks or when an error, risk, or product choice appears.

The primary learning unit is an end-to-end product slice, not a Dart, Flutter, Python, or framework chapter. Teach language and framework details just in time, only to the depth needed to understand and verify the current slice. Keep connecting work to the full-stack chain: requirement and acceptance criteria → UI and state → data contract → backend/API → tests and debugging → Git/diff → build, documentation, and release evidence.

The detailed route is `docs/VIBE_CODING_LEARNING_PLAN.md`; evidence belongs in `docs/LEARNING_LOG.md`; third-party API claims belong in `docs/API_RESEARCH.md`.

## Current stage and scope

- Current stage: stage 5 is verified; Codex, Kimi, and the default-off GLM adapter have completed sanitized local structural checks. A live GLM contract drift (percent-only token windows and TIME_LIMIT unit 5) was fixed with current/legacy parser branches. All three current GLM `percentage` fields now map directly to used percentage; `all_real` and the stage 8 one-click launcher are verified. User comparison against ZCode is still pending.
- Flutter 3.44.2 and Dart 3.12.2 are installed at `E:\Move\flutter`; Chrome/Web is available. Android SDK and the Visual Studio C++ workload are not installed yet. The workspace has a Git baseline and has completed an initial commit and push.
- Flutter uses Riverpod to switch between offline Fixture data and `BackendQuotaRepository`; the settings page selects mode, scenario, and local backend URL. `codex_real`, `kimi_real`, `glm_real`, and `all_real` are backend-only. Mock remains available for deterministic Widget tests.
- `backend/` contains fake scenarios, default-off Codex/Kimi adapters, a default-off experimental GLM adapter fixed to the official plugin quota endpoint, and an `all_real` route that calls only individually enabled providers. Python 3.12 and `backend/.venv` are available locally.
- Stages 0-5 used only offline data. Provider slices are recorded in `docs/STAGE6_CODEX_REAL_TASK.md`, `docs/STAGE6_KIMI_REAL_TASK.md`, and `docs/STAGE7_GLM_REAL_AND_ALL_REAL_TASK.md`; the launcher is recorded in `docs/STAGE8_ONE_CLICK_LAUNCHER_TASK.md`. Provider UI content still needs the user's acceptance/short reverse explanation.
- A later informed user decision authorized one local, sanitized GLM structural experiment; it succeeded without retaining values or raw data. This does not authorize public/commercial use or broader adapter changes. Do not read ZCode private storage, worker config files, cookies, or traffic; use ZCode only for manual comparison unless it publishes a supported machine-readable interface.
- `scripts/start_quota_watch.ps1` may map existing `KIMI_CODING_API_KEY`/`GLM_API_KEY` values only into its new backend child process. It must never print, persist, or place them in Flutter, tests, logs, fixtures, screenshots, or Git.
- Develop and verify on a Windows host first. Add other platforms only in their later task cards.

## People and model roles

- User: product decisions and final acceptance; may ask about any implementation detail when it becomes relevant.
- Codex: lead agent and implementation partner. Inspect the repo, create a small task card, edit files, run checks, integrate advice, review the final diff, and explain errors, risks, choices, or requested concepts concisely.
- GLM worker: read-only backend and general-programming consultant. Use for bounded architecture, error-path, parsing, and test reviews. It may return advice or a proposed diff; Codex must inspect, apply, and test any accepted change.
- Kimi worker: read-only Flutter UI, interaction, responsive-layout, accessibility, and visual-consistency consultant. Codex must turn accepted advice into testable code.

Use at most one worker by default. Parallel read-only reviews are acceptable when independent; never allow multiple models to write the same area. If a worker is unavailable or slow, continue with Codex rather than blocking the task. Never send credentials or sensitive responses to a worker.

## Task workflow

1. Inspect current files, behavior, errors, and stage evidence.
2. Write one 30-120 minute task card with goal, context, allowed scope, non-goals, done conditions, and learning points.
3. Implement the smallest coherent feature without requiring a teaching pause first; keep new code simple and comment unfamiliar syntax at first use.
4. Ask a relevant worker for a bounded read-only review only when it adds clear value.
5. Run the smallest relevant experiment and then full formatting, static analysis, tests, and a behavior check proportional to risk. Do not say "should work" without evidence.
6. If an error, risk, or product decision appears, report it in plain language and discuss only what is needed to proceed.
7. Review the complete diff for scope, regressions, secrets, and unexplained code.
8. Give a concise outcome-first handoff; ask for a personal check only when it provides evidence Codex cannot obtain directly.
9. Record evidence and the next smallest card in the learning log.

## Learning rules

- Prefer workflow breadth over technology depth: each task card must say where it sits in the full-stack delivery chain and what downstream layer it prepares.
- Prefer verified working increments over mandatory pre-teaching. Do not turn routine handoff into a quiz.
- When the user asks for an explanation, keep it concrete: one concept, one current-code example, and one observable consequence.
- Do not schedule detached language courses. Explain a syntax or framework concept at first use, then immediately connect it to observable behavior or a test; the source comments serve as reference rather than memorization homework.
- Use thin vertical slices whenever prerequisites allow: define an input and expected output, cross the smallest necessary layers, test at least one failure or boundary path, inspect the diff, and record delivery evidence.
- Do not begin with long, detached theory. Explain concepts where they first appear, then run a small experiment.
- When asking the user to run a command, edit a file, make a choice, or complete a learning step, add one brief sentence explaining why that action matters in the current engineering workflow.
- Do not treat successful startup as proof of correctness; test at least one failure or boundary path.
- Preserve one approximately 20-minute no-AI exercise each week. Codex may define and later review it but must not complete it for the user.
- If the user cannot explain a critical change, shrink the explanation and experiment; do not advance merely because code exists.
- Change stage status only when the documented Definition of Done has evidence.

## Safety and open-source rules

- Never print, store, commit, screenshot, or send API keys, tokens, cookies, `auth.json` content, private account data, or unredacted provider responses.
- Keep tests deterministic and offline unless a task card explicitly marks a manual, local real-service experiment.
- Treat provider endpoints and response shapes as unstable research until reverified at implementation time.
- Public clients must not embed provider credentials. A public multi-user backend requires a separate security design and is not an early milestone.
- Preserve unrelated user changes and keep diffs small enough for a beginner to review.

## Expected verification commands

Use only after the corresponding toolchain exists:

```powershell
flutter doctor -v
flutter pub get
flutter analyze
flutter test
```

Backend verification:

```powershell
backend\.venv\Scripts\python.exe -m pytest -c backend\pytest.ini backend\tests
python scripts\run_e2e.py
```
