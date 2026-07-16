# AudioVision — Technical Design

Implements `requirements.md`. Target: iOS 18.0+, SwiftUI, portrait iPhone. Existing project `eye-assist.xcodeproj` (synchronized file groups — files under `eye-assist/` auto-join the target; Info.plist generated from `INFOPLIST_KEY_*` build settings).

## 1. Architecture

MVVM-lite: SwiftUI views observe one `AppModel` (@MainActor ObservableObject) that owns the service layer. Services are plain classes; heavy work stays off the main thread and publishes summarized state back.

```
eye-assist/
  eye_assistApp.swift          app entry, routes Onboarding vs Live
  AppModel.swift               central observable state + service wiring
  Theme.swift                  design tokens (colors, fonts, radius)
  Models/
    YOLODetector.mlmodel|.mlpackage   exported YOLO (Vision-compatible, embedded NMS)
    model_name.txt                    actual model name for telemetry badge
  Domain/
    Detection.swift            Detection, PositionBucket, FilterCategory, enums
    HistoryEntry.swift         Codable history record + session
  Services/
    CameraService.swift        AVCaptureSession + optional LiDAR depth
    DetectionService.swift     Vision/CoreML inference + FPS + distance merge
    DistanceEstimator.swift    LiDAR median depth | size-prior heuristic
    SpeechService.swift        AVSpeechSynthesizer queue, pan-able output
    SpatialToneService.swift   AVAudioEngine tracking tone (focus mode)
    NavigationAdvisor.swift    lane analysis → safe-path suggestion (R11)
    RouteNavigator.swift       MapKit walking routes + turn-by-turn guidance (R13)
    TextReaderService.swift    Vision OCR at low cadence + speak-once gate (R15)
    NarrationEngine.swift      mode logic: continuous / new-only / on-demand
    VoiceQueryService.swift    SFSpeechRecognizer hold-to-ask
    HistoryStore.swift         session log, JSON persistence
    SettingsStore.swift        @AppStorage-backed settings
  Views/
    OnboardingView.swift       mockup 1d
    LiveView.swift             mockups 1a/1b/1c (mode-dependent)
    HUDOverlay.swift           boxes, labels, telemetry pills, crosshair, pan bar
    NarrationBar.swift         waveform + current sentence
    FocusView.swift            mockup 1g
    HistoryView.swift          mockup 1f
    SettingsView.swift         mockup 1e
```

## 2. Data flow

```
CameraService (frames, depth)
   └─ DetectionService (VNCoreMLRequest, throttled ~10 inferences/s)
        └─ [Detection] ── AppModel.detections (main thread, drives HUD)
             ├─ NarrationEngine ── SpeechService (pan from position) ── HistoryStore
             ├─ FocusTracker (locked object) ── SpatialToneService
             └─ VoiceQueryService (matches question → answer)
```

`Detection`: `label: String`, `confidence: Float`, `bbox: CGRect` (normalized, Vision coords), `position: PositionBucket` (LEFT/AHEAD/RIGHT from bbox midX thirds), `distanceMeters: Double?`, `category: FilterCategory`.

## 3. Key design decisions

- **Model-agnostic detection.** Model exported with embedded NMS → `VNCoreMLRequest` yields `VNRecognizedObjectObservation` (label+box+confidence) for YOLOv3-Tiny, YOLO11, or YOLO26 alike (R1.1). Telemetry badge text comes from `model_name.txt`.
- **Instance segmentation (R14).** Ships `yolo11n-seg` — its Core ML export has **no** embedded-NMS pipeline (Vision can't decode it), so `SegmentationDecoder` handles the raw tensors from `VNCoreMLFeatureValueObservation`s: output0 `[1, 116, 8400]` (4 xywh + 80 class scores + 32 mask coefficients per anchor) and protos `[1, 32, 160, 160]`. Decode: score filter ≥0.5 → greedy NMS (IoU 0.45, cap 12) → per-instance mask = coeffs · protos via `cblas_sgemv` (sigmoid skipped — threshold logits at 0), cropped to the box in proto space, stored as a `SegMask` (binary sub-grid + per-column occupancy fractions). Boxes are model-space xywh/640 → converted to Vision's bottom-left-origin normalized rect so all downstream math (viewRect, lanes) is unchanged. `DetectionService` picks the path at runtime from the compiled model's output names (`coordinates`/`confidence` → box pipeline; else seg decoder) — R14.5 fallback for free. HUD tints a `CGImage` built from the mask under each hairline box; `NavigationAdvisor` uses `Detection.footprintXInterval` (mask columns >10% occupied) instead of the raw bbox interval (R14.3).
- **Throttling.** Camera runs at native 30fps; inference dispatched only when the previous one finished (serial queue, drop-late). Measured inference FPS shown in the pill (R1.3).
- **Distance (R1.5, R1.7).** If `AVCaptureDevice` supports LiDAR depth (`builtInLiDARDepthCamera`), attach `AVCaptureDepthDataOutput` synchronized with video; distance = median depth in the central 50% of the bbox. Fallback heuristic: pinhole model `distance = f_y * realHeight / pixelHeight` with height priors for **all 80 COCO classes**, plus a generic 0.5 m prior for anything unmapped — every detection carries a distance. Clamped 0.3–12 m; displayed on every box label. (A neural monocular-depth model was considered and deferred: on the target device LiDAR already provides measured depth, and a second network would roughly halve detection FPS.)
- **Route navigator (R13).** `RouteNavigator` wraps `CLLocationManager` (when-in-use, `.fitness` activity, 3 m filter) + `MKLocalSearch` + `MKDirections(.walking)`. Guidance is our own loop (Apple exposes no turn-by-turn engine): each location update measures map-point distance to the next step's maneuver point (start of that step's polyline) — <50 m fires the advance cue once, <12 m fires the immediate cue (interrupting) and advances the step. Off-route = nearest distance to the route polyline > 30 m → announce + recompute (20 s rate limit). Arrival = within 15 m of route end (R13.5). Speech goes through the shared SpeechService closure so narration, cautions, and turn cues serialize on one queue. UI: `NavigateView` sheet (search field, result rows, end-navigation) + `GuidanceBar` pinned under the navigation banner on Live while guidance is active. Static, unit-testable helpers for the geometry (`nearestDistance`, step-advancement thresholds).
- **Text reader (R15).** `TextReaderService.process(pixelBuffer:)` throttles to one `VNRecognizeTextRequest` (`.accurate`, language correction, orientation `.right`) every 1.5 s on a dedicated queue. Results ≥0.5 confidence publish as `TextDetection` (string, bbox) for the HUD. Speaking goes through `TextSpeakGate` — a pure, unit-tested struct: key = lowercased alphanumerics; skip keys spoken <30 s ago; confidence ≥0.8 admits immediately, lower needs two consecutive scans (pending set); cap 3 strings per scan, ordered top-to-bottom. AppModel enables the service only in CONTINUOUS/NEW-ONLY with the setting on and audio unpaused (R15.5); `describeScene` appends visible text for ON-DEMAND. Spoken as "Text: …" with pan from the first region's midX.
- **Settings affordance (R6.8).** Persistent gear icon button (44 pt, `gearshape.fill`) pinned to the top-right of the Live chrome in every mode, opening the Settings sheet; bottom HIST/SET squares remain for mockup parity.
- **Navigation advisor (R11).** `NavigationAdvisor` splits the frame into three x-lanes (0–0.38 / 0.38–0.62 / 0.62–1). An obstacle is a detection with `category ∉ {smallItems}`, distance < 2.5 m, bbox height > 0.12; a lane is blocked when an obstacle's x-interval overlaps ≥ 20% of it. Decision table → CLEAR / MOVE LEFT / MOVE RIGHT / STRAIGHT-CAUTION / STOP, carrying the nearest blocking obstacle (label + distance) for speech. Hysteresis: a new suggestion must persist 0.6 s before replacing the current one. AppModel publishes it (HUD banner); NarrationEngine speaks changes rate-limited (≥4 s apart, STOP interrupts immediately, CLEAR only after a blocked state) and appends avoidance hints to near-obstacle announcements (R11.5).
- **Narration modes (R2.1)** in `NarrationEngine`:
  - *Continuous*: every ≥3.5s (and only when synthesizer idle), compose scene sentence from top-3 confident detections.
  - *New-only*: keep decaying set of announced labels (expire after 10s absence); announce a label's (re)appearance once, publish "ignoring N known" count.
  - *On-demand*: no automatic speech; `describeScene(verbosity:)` invoked by button/question.
  - Verbosity (R2.2): BRIEF `"Person, ahead-left"` · DETAILED `+ "one meter"` · FULL `+ confidence % and object count`.
  - Distances/positions spoken in natural words; numbers rounded to halves.
- **Spatial audio (R3).** `SpeechService` routes `AVSpeechSynthesizer.write(_:)` buffers through an `AVAudioEngine` player with `pan` set from object position (−1…+1 = bbox midX*2−1) when the setting is on; falls back to plain `speak()` if buffer routing fails. `SpatialToneService` renders a sine tone via `AVAudioSourceNode`, pan follows the locked object, frequency 440→1320 Hz as |offset from center| → 0 (R3.3).
- **Focus mode (R4).** `AppModel.focusedObject` — matched each frame to nearest same-label detection (IoU + label). Lost >2s → spoken notice (R4.5). Guidance = tone + spoken updates every 2.5s.
- **History (R5).** Announced (not merely seen) detections appended as `HistoryEntry`; saved as JSON to Documents (`history.json`, cap 200 entries). Replay re-speaks entries via SpeechService.
- **Voice ask (R7).** Hold gesture → AVAudioSession record mode → `SFSpeechRecognizer` partial results; on release, extract object noun (match against COCO-80 synonym table) → answer from live detections, then recent history.
- **Audio session (R9.3).** `.playback` category, `.duckOthers` + `.interruptSpokenAudioAndMixWithOthers`; switches to `.playAndRecord` only while holding-to-ask.

## 4. Design tokens (`Theme.swift`) — R10

| Token | Value |
|---|---|
| `bg` | `#0E0F10` |
| `bgDeep` / `cardBg` | `#0A0A0A` / `#141618` |
| `accent` | `#40CC6D` (oklch 0.75 0.18 150) |
| `stroke` | white 10–25% |
| `radius` | 2pt everywhere |
| `telemetry type` | `.system(.caption, design: .monospaced)` weight 600, tracking wide, UPPERCASE |
| `prose type` | system sans; hero names 34–44pt bold, tight tracking |
| animations | `av-pulse` (opacity 1↔0.35, 1.4s), waveform bars (scaleY, staggered) |

Screen ↔ mockup mapping: LiveView(1a continuous / 1b new-only / 1c on-demand states) · OnboardingView(1d, rendered on dark) · SettingsView(1e) · HistoryView(1f) · FocusView(1g).

## 5. Threading

- Camera + Vision: dedicated serial `DispatchQueue`s.
- `AppModel` is `@MainActor`; services hand results over via `Task { @MainActor in … }`.
- Speech/tone engines are thread-confined to their own instances; state exposed via published snapshots.

## 6. Project configuration

- `IPHONEOS_DEPLOYMENT_TARGET` → 18.0 (both configurations).
- Add `INFOPLIST_KEY_NSCameraUsageDescription`, `INFOPLIST_KEY_NSMicrophoneUsageDescription`, `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription`.
- `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait`.

## 7. Verification strategy

1. `xcodebuild -scheme eye-assist -destination 'iPhone 17 Pro sim'` compile gate per phase.
2. Simulator run + screenshots: Onboarding, Live scaffold (no camera in sim → permission/placeholder path must look right), Settings, History (seeded sample entries in DEBUG).
3. On-device (user): detection, narration, LiDAR distance, spatial pan.
