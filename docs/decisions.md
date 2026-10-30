# Decision log

Running record of project decisions. Newest last. Superseded entries stay
for history (marked as such).

## 2026-10-26 — Day 1

### D1: Monorepo layout
Single repo, one directory per component: `server/`, `ios/`, `scale/`,
`docs/`, spec at root. Scale firmware lives in `scale/`, not `firmware/`
(renamed: the old name described a file type, the new one the subsystem).

### D2: One Python venv at root, manifests per component
Only `server/` uses Python, so a single `.venv` at the root (editor
auto-detect) is enough. Dependency and secret manifests live with the
component: `server/requirements.txt`, `server/requirements-dev.txt`,
`server/.env` (gitignored). `scale/` (PlatformIO) and `ios/` (Xcode)
already isolate their own toolchains.

### D3: Proxy owns the Meta key; strict JSON + fallback everywhere
The iOS app never holds an API key. Every proxy endpoint returns strict
JSON and degrades to deterministic local data on any model failure, with
a `source: model | fallback` field so clients know what they got.

### D4: Meta Model API via Responses API
Base `https://api.meta.ai/v1`, `POST /responses`, `Authorization: Bearer`,
temperature 0. Model IDs pinned to versions (`muse-spark-1.3`,
`muse-wonder-1.0`) after bare IDs (`muse-spark`) returned 404.
Both `META_API_KEY` and the docs' `MODEL_API_KEY` env names are accepted
(`META_` wins). Superseded: placeholder IDs in the first `.env.example`.

### D5: Recipe validation + regenerate-on-violation
`POST /recipe` validates ratio 1:15–1:17, last `target_total_g == water_g`,
3–5 steps; one regeneration on violation, then fallback (SPEC §9.1).

### D6: Vision is single-attempt + fallback
`POST /vision` sends one JPEG (base64 data-URL `input_image` block) with
step context to Wonder. One attempt, schema-validated, then canned
coaching. Guards: frames > 5 MB → 413, bad context JSON → 422.

### D7: iOS project via xcodegen
`ios/project.yml` is the source of truth (committed); the generated
`.xcodeproj` is gitignored. Bundle ID `com.felipemunoz.brewpilot`
(`com.brewpilot.app` was already taken globally), free provisioning with
`DEVELOPMENT_TEAM` pinned in `project.yml`, deployment target iOS 17.

### D8: Two buttons on the scale, not three
Hardware has TARE + TIMER only (GPIO 5/6, active-low). TIMER long-press
cycles MANUAL → AUTO POUR → SET; TARE+TIMER together sleeps; a short
press while the timer is stopped resets it. Superseded: 3-button layout.

### D9: Scale wakes on TARE only
ESP32-S3 deep-sleep wake (ext0) supports a single pin, so only the TARE
button wakes the scale. Auto-off never fires while the timer runs or a
phone is connected. Superseded SPEC line: "any press wakes".

### D10: Bring-up folded into the main firmware
No separate `bringup/` project: `brewpilot_scale` prints weight at 10 Hz
over serial (`t` = tare), covering the Day-2 bring-up need.

### D11: Arduino core 3.x / NimBLE BLE APIs
No manual 2902 descriptor (auto-added), `getValue()` returns Arduino
`String`. Pinned implicitly via current `espressif32` platform.

### D12: Standalone scale, additive app
Display, buttons, timer, and modes never depend on BLE; the phone adds
coaching only. Same principle as the server: AI/plumbing failures must
never block a brew.

### D13: Single universal app icon + custom Info.plist
`Assets.xcassets/AppIcon` uses one 1024×1024 PNG (universal idiom). The
project uses a hand-written `Info.plist` (UILaunchScreen for full-screen,
usage strings, portrait-only, standard CFBundle keys) instead of a
generated one, after the generated plist letterboxed the app.

### D14: SAM via Responses stream, RLE masks with bounds
`POST /segment` calls sam-3.1 with `stream: true` +
`metadata.mask_encoding: one_bit`, parses with `meta-sam-parser`, and
returns boxes plus per-mask `{x, y, w, h, counts}` where counts is
row-major RLE over an h×w bitmap placed at the bounds rect (verified
against live data + a rendered overlay). RLE `size` is (h, w). Empty
result → fallback, never an error to the app. Recorded streams live in
`server/tests/fixtures/` as regression goldens.

### D15: Proxy deployed to Modal
`modal deploy server/modal_app.py` → the `brewpilot-proxy` app (stable
`*.modal.run` URL). Meta key lives in the `brewpilot-meta` secret, never
in the image. iOS points at the Modal URL by default; local uvicorn
remains the dev path.

### D16: Dark espresso design system, shared Theme.swift
iOS uses a dark theme (espresso black/cards, cream text, caramel accent,
green in-zone): one `Theme.swift` with colors, cards, buttons, chips, and
timer formatting shared by all four tabs. `BrewPilotApp` accepts an
`-initialTab N` launch argument for screenshots.

### D17: Headless scale, UI moved to the iOS Scale tab
Dropped the ST7735S display, both buttons, on-device modes, and deep
sleep: firmware is ESP32 + HX711 only (weigh, filter, stream 10 Hz over
BLE, persist tare/calibration). Live weight, tare, g/oz units, timer
with auto-start, and the calibration wizard all live in the iOS Scale
tab (ex-Connect). Superseded: D8, D9, D12.

## 2026-10-29 — Day 4

### D18: Pulses rest; pours end on the settled flag
A pour step is done when the scale reports settled within 3 g of target,
not when the weight first crosses it. Each pulse is followed by a REST
phase (until `duration_s` from pulse start, at least 5 s); an early pour
starts the next pulse (nudge, never block). The coffee tare also waits
for settled. The app tares itself when prep is confirmed (wet filter +
mug). The brew clock starts on the first +3 g pour and excludes pauses.

### D19: Drawdown end comes from the camera, not the scale
Scale under mug + dripper means total mass is flat while the bed
drains, so the old "flow < 0.5 ml/s for 10 s" rule fired ~10 s after the
last pour with the dripper still full. `/vision` gains `bed_drained`;
during DRAWDOWN the app polls it every 5 s from +15 s. Also ends the
brew: "Drained" button, dripper lifted off (> 8 g drop), 180 s cap.
Proxies deployed before the field return no `bed_drained` (decoded as
nil), so only the manual paths apply until redeploy.

### D20: Vision checks after the pour, one in flight, model-only bubbles
Frames are taken 1.5 s after a pour settles (kettle out of frame, bed
visible), cropped to the on-screen framing box, ≤ 320 px JPEG q0.6 (Wonder: ~7 s at 320 vs ~9 s at 640).
One request in flight, 20 s client timeout (Wonder takes 6–13 s), drawdown polls dropped when
busy. `source: fallback` replies are not shown: a canned line is not
something the camera saw. Vision bubbles carry an eye icon and the step
label.

### D21: Voice coach + one-shot local warnings
AVSpeechSynthesizer (playback category, mixes with other audio) speaks
the stop cue, the next-pour cue, warnings, and vision coaching; toggle
in the Brew header. Overshoot, flow-zone, and slow-drawdown warnings fire
once per step (the old overshoot check appended a bubble on every 10 Hz
sample).

### D22: Proxy runs on the Mac for the demo
The app reads `proxyURL` (launch argument `-proxyURL http://<mac-ip>:8000`
or a stored default) and falls back to Modal. Info.plist allows local
networking. Latency is the model, not the host: Wonder measured 6–11 s
locally vs 9–13 s on Modal. Supersedes the "iOS points at Modal" part of D15.
