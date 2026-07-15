# AudioVision (eye-assist)

Live camera object detection that **speaks what it sees** — built eyes-free-first for
blind and low-vision users. A YOLO11n Core ML model runs on-device over the camera
feed; detections are narrated with position ("on your left"), distance, and optional
stereo panning that matches where the object actually is.

Built from the claude.ai/design mockups ("iOS audio object detection app") via
spec-driven development — see [specs/requirements.md](specs/requirements.md),
[specs/design.md](specs/design.md), [specs/tasks.md](specs/tasks.md).

## Features

- **Live HUD** — bounding boxes + confidence labels, model/FPS telemetry, crosshair,
  spatial-pan indicator, narration bar with waveform.
- **Three narration modes** (Settings): **Continuous** scene summaries ·
  **New only** (announce objects as they appear) · **On demand** ("Describe scene"
  button + hold-to-ask voice questions like *"Where is my cup?"*).
- **Focus mode** — tap any bounding box to lock one object: distance / position /
  tone tiles, a stereo tracking tone that follows the object, "Guide me to it"
  spoken guidance.
- **History** — session timeline of announced detections with per-row replay and
  full-session audio replay.
- **Settings** — voice, speech speed, narration mode, verbosity (brief/detailed/full),
  detection filter groups, spatial audio toggle.
- **Distance on every object** — LiDAR depth on Pro iPhones (median depth inside the
  box), size-prior heuristic covering all 80 detectable classes elsewhere; each
  bounding box shows its distance (`PERSON 0.94 1.2M`). Estimates, not measurements.
- **Safe-path navigation** — the frame is split into left/center/right lanes; nearby
  obstacles produce one stabilized suggestion (CLEAR · MOVE LEFT · MOVE RIGHT ·
  STRAIGHT WITH CAUTION · STOP) shown as a banner and spoken when it changes.
  STOP interrupts speech immediately; announcements of near obstacles carry the
  avoidance hint ("Chair ahead, one meter — move left to avoid").
- **Street-ready** — a "Street & signals" filter group (traffic light, stop sign,
  fire hydrant, parking meter, bench) is on by default, and safety-critical street
  objects (signals, vehicles, people) take announcement priority.
- **Always-reachable settings** — a persistent gear icon sits top-right of the Live
  screen in every mode.
- **GPS walking navigation** — search a destination (navigate icon, top-right),
  get a walking-only route with spoken turn-by-turn directions: "In 50 meters,
  turn left onto Elm Street", then "Turn left onto Elm Street" at the corner.
  Off-route recovery reroutes automatically; arrival is announced within 15 m.
  A guidance bar on the Live screen shows the current instruction, distance to
  the turn, and distance remaining — object detection and obstacle cautions keep
  running the whole time.
- **Accessibility** — VoiceOver labels everywhere, large targets, double-tap anywhere
  to repeat the last utterance, audio keeps working with the ringer silenced.

## Run it on your iPhone

1. Open `eye-assist.xcodeproj` in Xcode.
2. Plug in your iPhone (or have it on the same Wi-Fi with Xcode's wireless debugging
   already paired). Select it as the run destination.
3. Press **Run**. Signing is already configured (automatic, team `V9RLAJRWS8`).
   First install may require trusting the developer profile on the phone:
   Settings → General → VPN & Device Management.
4. On first launch, grant Camera and Speech & audio permissions on the onboarding
   screen, then Continue.

Detection only works on a real device — the simulator has no camera.

## Project layout

```
specs/                       requirements / design / tasks (spec-driven dev docs)
scripts/export_model.sh      re-export the YOLO Core ML model (uv + ultralytics)
eye-assist/
  AppModel.swift             central state + service wiring, focus tracking
  Theme.swift                design tokens from the mockups
  Domain/                    Detection, history entries, category filters
  Services/                  camera, detection, distance, speech, spatial tone,
                             narration engine, voice questions, history, settings
  Views/                     Onboarding · Live (HUD/narration bar) · Focus ·
                             History · Settings · camera preview
  Models/                    YOLODetector.mlpackage (YOLO11n, embedded NMS)
```

## Regenerating the model

```sh
./scripts/export_model.sh
```

Exports `yolo26n`→`yolo11n` (first that succeeds) to a Vision-compatible
`.mlpackage` with embedded NMS, falling back to Apple's YOLOv3-Tiny download.
The telemetry badge in the app reads `Models/model_name.txt`.

## Notes

- COCO-80 classes only; "keys"/"wallet" aren't detectable classes (the voice
  assistant says so rather than guessing). Street objects outside COCO —
  crosswalks, curbs, potholes, bollards, generic traffic signs — need a
  custom-trained model; the detection pipeline is model-agnostic, so that's a
  drop-in `.mlpackage` swap later.
- Navigation suggestions are advisory only and derived from camera-visible
  obstacles; they are not a substitute for a cane, guide dog, or traffic
  judgment.
- Heuristic distances assume typical object sizes; treat them as rough guidance.
- DEBUG builds accept `-screen onboarding|settings|history` launch arguments for
  UI verification.
