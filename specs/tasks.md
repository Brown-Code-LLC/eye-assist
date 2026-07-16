# AudioVision — Implementation Tasks

Checklist executes `design.md`; requirement IDs from `requirements.md`. Check items off as they complete.

## Phase 1 — Model pipeline
- [x] 1.1 `scripts/export_model.sh` — uv venv, ultralytics export, fallback chain (R1.1)
- [x] 1.2 Export succeeded: **yolo11n** `.mlpackage` (5.2 MB, pipeline with embedded NMS → `VNRecognizedObjectObservation`), placed at `eye-assist/Models/YOLODetector.mlpackage`; `model_name.txt` drives the telemetry badge (R1.3)

## Phase 2 — Domain & services
- [x] 2.1 `Domain/Detection.swift` — Detection struct, PositionBucket, FilterCategory + COCO-80 category map (R1.4, R1.6, R6.4)
- [x] 2.2 `Domain/HistoryEntry.swift` — Codable entry + session container (R5.1)
- [x] 2.3 `Services/SettingsStore.swift` — mode, verbosity, voice, speed, filters, spatial toggle (R6.*)
- [x] 2.4 `Services/CameraService.swift` — capture session, preview layer, frames + LiDAR depth when available (R1.1, R1.5)
- [x] 2.5 `Services/DistanceEstimator.swift` — LiDAR median / pinhole prior fallback (R1.5)
- [x] 2.6 `Services/DetectionService.swift` — VNCoreMLRequest, throttle, FPS, filter, position bucket, distance merge (R1.*)
- [x] 2.7 `Services/SpeechService.swift` — synthesizer queue, rate/voice, stereo pan path (R2.5, R3.1)
- [x] 2.8 `Services/SpatialToneService.swift` — pan/pitch tracking tone (R3.3)
- [x] 2.9 `Services/NarrationEngine.swift` — continuous / new-only / on-demand + verbosity composition (R2.*)
- [x] 2.10 `Services/VoiceQueryService.swift` — hold-to-ask, object matching, answers (R7.*)
- [x] 2.11 `Services/HistoryStore.swift` — JSON persistence + replay (R5.*)
- [x] 2.12 `AppModel.swift` — wiring, focus tracking (R4.*), permission flow (R8.*)

## Phase 3 — UI
- [x] 3.1 `Theme.swift` — tokens per design.md §4 (R10.1)
- [x] 3.2 `Views/OnboardingView.swift` — mockup 1d (R8.*)
- [x] 3.3 `Views/LiveView.swift` + `HUDOverlay.swift` + `NarrationBar.swift` — mockups 1a/1b/1c (R1–R3)
- [x] 3.4 `Views/FocusView.swift` — mockup 1g (R4.*)
- [x] 3.5 `Views/HistoryView.swift` — mockup 1f (R5.*)
- [x] 3.6 `Views/SettingsView.swift` — mockup 1e (R6.*)
- [x] 3.7 Accessibility pass — VoiceOver labels/hints, double-tap repeat, target sizes (R9.*)

## Phase 4 — Project config
- [x] 4.1 Deployment target → 18.0; permission `INFOPLIST_KEY`s; portrait-only (design.md §6)

## Phase 5 — Verification
- [x] 5.1 Clean `xcodebuild` for iPhone 17 Pro simulator
- [x] 5.2 Simulator screenshots: Onboarding / Live / Settings / History vs mockups
- [x] 5.3 README with on-device run instructions (iPhone 16 Pro Max "Trigger")

## Phase 6 — Navigation & depth-for-all (2026-07-14 follow-up)
- [x] 6.1 `DistanceEstimator` — height priors for all 80 COCO classes + generic fallback; every detection carries a distance (R1.5)
- [x] 6.2 `HUDOverlay` — distance shown on every bounding-box label (R1.7)
- [x] 6.3 `Services/NavigationAdvisor.swift` — 3-lane occupancy → CLEAR/MOVE LEFT/MOVE RIGHT/STRAIGHT-CAUTION/STOP with 0.6s hysteresis, STOP immediate (R11.1–R11.4)
- [x] 6.4 `NarrationEngine` — speaks suggestion changes (rate-limited, STOP interrupts, CLEAR only after blocked), avoidance hints on near-obstacle announcements, suggestion appended to describeScene (R11.3, R11.5, R11.6)
- [x] 6.5 `NavigationBanner` on Live screen (R11.3)
- [x] 6.6 Street & signals filter category (traffic light, stop sign, fire hydrant, parking meter, bench), announcement priority for safety-critical labels, street voice synonyms (R6.4, R6.7)
- [x] 6.7 Verified: 12/12 standalone logic tests pass (lane decisions, small-item exclusion, prior + generic distances); simulator screenshots of banner + settings row

## Phase 7 — Settings icon + motion & approach detection (2026-07-14 follow-up)
- [x] 7.1 Persistent gear icon (44pt, VoiceOver-labeled) in Live top chrome, all modes (R6.8)
- [x] 7.2 `MotionInfo` on Detection + `Services/MotionTracker.swift`: frame-to-frame track matching, least-squares closing speed (box-growth backup), lateral drift, 1s track expiry (R12.1, R12.2, R12.6)
- [x] 7.3 Approach cautions: priority/fast objects <4m, 4s per-track cooldown, urgency escalation bypasses cooldown once, urgent interrupts speech (R12.4)
- [x] 7.4 Pulsing APPROACHING chip on bounding boxes; motion folded into narration phrases + VoiceOver labels (R12.3, R12.5)
- [x] 7.5 Verified: 15/15 motion-tracker logic tests pass (incl. escalation gap found by testing); simulator screenshot of gear icon

## Phase 8 — GPS walking navigation (2026-07-14 follow-up)
- [x] 8.1 `Services/RouteNavigator.swift` — CLLocationManager (when-in-use, fitness), MKLocalSearch biased to current location, MKDirections walking-only routes (R13.1, R13.2)
- [x] 8.2 Turn-by-turn guidance loop: advance cue <50m (once), immediate cue <12m (interrupts) + step advancement, off-route >30m → announce + reroute (20s cooldown), arrival <15m (R13.3–R13.5)
- [x] 8.3 `Views/NavigateView.swift` (search field, result rows, end navigation, denied-permission card) + `GuidanceBar` on Live; nav icon in top chrome, all modes (R13.1, R13.6)
- [x] 8.4 Turn cues share the SpeechService queue with narration/cautions (R13.6); `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` added (R13.7)
- [x] 8.5 Verified: geometry helpers tested against known GPS coordinates (on-path ≈0m, 33m offset, endpoint clamp, threshold ordering); simulator screenshots of Navigate sheet + Live nav icon; full route flow is an on-device test (simulator/mac CLI can't exercise live guidance)

## Phase 9 — Remove motion & approach detection (2026-07-14, user request)
- [x] 9.1 Deleted `Services/MotionTracker.swift`; removed `MotionInfo`/`Detection.motion`, AppModel annotate wiring, NarrationEngine cautions + phrase motion words, HUD APPROACHING tag (R12 withdrawn; Phase 7 items 7.2–7.5 superseded — settings icon 7.1 retained)

## Phase 10 — Instance segmentation: shape-true detection (2026-07-16)
- [x] 10.1 Exported yolo11n-seg (.mlpackage, 5.7 MB, raw tensors) replacing the box model; export script tries seg first, box models as fallback (R14.1, R14.5)
- [x] 10.2 `Services/SegmentationDecoder.swift` — score filter, greedy NMS (cap 12), mask = coeffs·protos via cblas_sgemv (logit-thresholded), cropped SegMask with per-column occupancy (R14.4)
- [x] 10.3 `DetectionService` picks pipeline at runtime from model output names (coordinates/confidence → Vision box path; raw tensors → seg decoder) (R14.5)
- [x] 10.4 `Detection.footprintXInterval` (mask columns >10% occupied) — `NavigationAdvisor` lane overlap now uses true footprints instead of bbox intervals (R14.3)
- [x] 10.5 HUD renders tinted mask fills (accent for primary, white otherwise) under hairline boxes (R14.2)
- [x] 10.6 Verified: Python decode of exported model on bus.jpg established ground truth; the Swift decoder run on the same model + image reproduced it (4 instances, matching confidences, person footprints 13–29% tighter than bboxes)

## Phase 11 — OCR text detection & reading (2026-07-16)
- [x] 11.1 `Services/TextReaderService.swift` — Vision VNRecognizeTextRequest (.accurate, language correction) every 1.5s on its own queue; publishes TextDetection regions (R15.1)
- [x] 11.2 `TextSpeakGate` — normalized-key dedupe (30s expiry), two-sighting rule for confidence <0.8, 3 strings/scan cap (R15.3)
- [x] 11.3 Auto-speak "Text: …" with spatial pan, only in continuous/new-only + toggle + unpaused; on-demand gets text via Describe scene (R15.2, R15.5)
- [x] 11.4 HUD dashed text-region outlines + snippet chips; "Read text aloud" settings toggle, default ON (R15.4, R15.6)
- [x] 11.5 Verified: 9/9 tests — gate dedupe/expiry/anti-flicker/cap + real Vision OCR on a generated sign ("EXIT", "Main Street 24" both recognized)
