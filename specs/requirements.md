# AudioVision — Requirements

App: **AudioVision** — live camera object detection that speaks what it sees. Built eyes-free first for blind and low-vision users. Source of truth for UI: claude.ai/design project "iOS audio object detection app", file *AudioVision Mockups.dc.html* (screens 1a–1g).

Requirement IDs are referenced from `design.md` and `tasks.md`.

## R1 — Live object detection

- **R1.1** WHEN the Live screen is visible and camera permission is granted, the system SHALL run YOLO object detection on the live camera feed continuously.
- **R1.2** The system SHALL render a bounding box and label (`NAME confidence`) over each detection with confidence ≥ 0.5. The highest-confidence detection uses the accent-green box; others use white boxes at opacity graded by confidence (mockup 1a).
- **R1.3** The system SHALL display live telemetry: model name + measured FPS pill (top-left) and current object count pill (top-right).
- **R1.4** For each detection the system SHALL compute a horizontal position bucket — LEFT / AHEAD (center) / RIGHT — from the bounding-box center.
- **R1.5** For **every** detection the system SHALL estimate distance in meters: via LiDAR depth when the device has it, else a size-prior heuristic covering all 80 COCO classes, else a generic size fallback — a detection never lacks a distance. Distances are presented as estimates (one decimal, e.g. `1.2 M`).
- **R1.7** Every bounding-box label SHALL show the object's estimated distance alongside name and confidence, so depth is visible per object at a glance.
- **R1.6** WHEN detection filters (R6.4) exclude a class category, matching detections SHALL be neither displayed nor narrated.

## R2 — Audio narration (three modes)

- **R2.1** The system SHALL support three narration modes, switchable in Settings and defaulting to CONTINUOUS:
  - **CONTINUOUS** (mockup 1a): periodic spoken scene summaries ("Person ahead-left, one meter. Chair to your right."), rate-limited so speech never backlogs.
  - **NEW ONLY** (mockup 1b): speak only when an object class newly enters the scene; known objects are silently tracked ("Ignoring N known objects in view").
  - **ON DEMAND** (mockup 1c): silent by default; speaks the scene when the user taps "Describe scene" or asks a voice question.
- **R2.2** Narration SHALL respect the verbosity setting: BRIEF (name + position), DETAILED (+ distance), FULL (+ confidence and counts).
- **R2.3** WHILE narration is unmuted, the narration bar SHALL show the current/last spoken sentence with an animated waveform while speaking.
- **R2.4** The user SHALL be able to pause/mute all audio with one large button, and repeat the last utterance via a Repeat control and via double-tap anywhere on the live screen.
- **R2.5** Speech SHALL use the configured voice and speed (R6.1–R6.2).

## R3 — Spatial audio

- **R3.1** WHEN spatial audio is enabled, spoken/announced object audio SHALL be stereo-panned to match the object's horizontal position.
- **R3.2** The Live screen SHALL show a SPATIAL PAN indicator bar (L…R) reflecting the pan of the most recently announced object.
- **R3.3** In Focus mode (R4), a tracking tone SHALL play whose stereo pan follows the locked object's position; its pitch is displayed (e.g. `880 HZ`) and rises as the object nears the center of frame.

## R4 — Focus mode (lock & track one object)

- **R4.1** WHEN the user taps a bounding box (or a History row's object while it is in view), the system SHALL enter Focus mode locked to that object; all other objects' audio is silenced.
- **R4.2** Focus mode SHALL display: live feed with the locked object's box, object name in large type, and stat tiles DISTANCE / POSITION / TONE, plus the pan bar (mockup 1g).
- **R4.3** "Guide me to it" SHALL start guidance: the tracking tone plus periodic spoken direction/distance updates ("Backpack, right, 1.8 meters").
- **R4.4** "Unlock" SHALL exit Focus mode and resume the active narration mode.
- **R4.5** IF the locked object is lost for more than ~2 seconds, the system SHALL say so ("Backpack lost") and keep listening for it to reappear.

## R5 — Detection history

- **R5.1** The system SHALL log announced detections per session: name, confidence, position, distance, timestamp.
- **R5.2** The History screen SHALL show the session as a timeline (mockup 1f) with a header `SESSION · TODAY HH:MM–HH:MM` and total detection count.
- **R5.3** Each row SHALL have a replay button that re-speaks that detection; a "Replay full session audio" button re-speaks the session chronologically.
- **R5.4** History SHALL persist across launches (most recent session shown; log capped to a reasonable size).

## R6 — Settings

- **R6.1** Voice: choose among available system voices (default enhanced English).
- **R6.2** Speed: slider mapped to speech rate.
- **R6.3** Narration mode selector: NEW ONLY / CONTINUOUS / ON DEMAND (R2.1).
- **R6.4** Detection filters — toggle groups of COCO classes: People (person); Vehicles (car, bicycle, bus, truck, motorcycle…); **Street & signals** (traffic light, stop sign, fire hydrant, parking meter, bench); Furniture & obstacles (chair, table/dining table, couch, bed…); Small items (cup, phone, bag, bottle, book…). Defaults: all ON except Small items (mockup 1e, extended for street use).
- **R6.7** Safety-critical street objects (traffic light, stop sign, oncoming vehicle classes, person) SHALL take announcement priority over other detections at equal confidence.
- **R6.5** Spatial audio: "Pan by object position" toggle, default ON.
- **R6.6** All settings persist across launches.
- **R6.8** A recognizable settings icon (gear) SHALL be persistently visible on the Live screen in **all** narration modes, with a ≥44pt target and VoiceOver label, so settings are always one tap away.

## R7 — Voice questions (on-demand ask)

- **R7.1** WHEN the user holds the ask control (mockup 1c "hold anywhere and ask"), the system SHALL capture speech and answer questions of the form "Where is/are (my) X?" by matching X against current and recent detections.
- **R7.2** Found: answer with position and distance ("Cup — center, about half a meter"). Not found: say it hasn't been seen ("I haven't seen keys in this session").

## R8 — Onboarding & permissions

- **R8.1** On first launch the system SHALL show the onboarding screen (mockup 1d): headline "Your camera becomes your narrator.", explanation that detection runs on-device, and permission rows for Camera and Speech & audio with GRANTED/ALLOW state chips.
- **R8.2** Tapping a permission row (or Continue) SHALL trigger the corresponding system permission prompts; Continue proceeds to Live once camera permission is granted.
- **R8.3** IF camera permission is denied, the Live screen SHALL show a clear message and a button that opens the app's Settings page.

## R9 — Accessibility (non-negotiable)

- **R9.1** Every interactive element SHALL have a VoiceOver label and hint; touch targets ≥ 44pt (primary actions much larger, per mockups).
- **R9.2** The app SHALL function fully without looking at the screen: all state changes that matter are spoken.
- **R9.3** Audio SHALL use a playback session that ducks but does not stop other audio, and keeps speaking with the ringer silent.

## R10 — Visual design

- **R10.1** The app SHALL follow the mockup design system: OLED black `#0E0F10` / `#0A0A0A` surfaces, clinical white text, single green accent `#40CC6D` (oklch 0.75 0.18 150), 2pt corner radius, system sans for prose + monospaced type for telemetry/labels, pulse and waveform animations.
- **R10.2** Screens map 1:1 to mockups: Live (1a/1b/1c unified by mode), Onboarding (1d), Settings (1e), History (1f), Focus (1g). Portrait only.

## R11 — Safe navigation suggestions

- **R11.1** The system SHALL divide the camera view into three lanes (LEFT / CENTER / RIGHT) and mark a lane blocked WHEN a physical obstacle (person, vehicle, furniture, animal — not small handheld items) overlaps it within ~2.5 m.
- **R11.2** From lane occupancy the system SHALL derive one path suggestion: **CLEAR** · **MOVE LEFT** · **MOVE RIGHT** · **STRAIGHT WITH CAUTION** (center free, side blocked) · **STOP** (all lanes blocked).
- **R11.3** The active suggestion SHALL be displayed as a persistent banner on the Live screen and SHALL be spoken whenever it changes (rate-limited; "clear" only announced when recovering from a blocked state; STOP interrupts current speech).
- **R11.4** Suggestions SHALL be stabilized with hysteresis (~0.6 s persistence) so a flickering detection cannot flip the advice.
- **R11.5** WHEN an announced object is itself a near obstacle, its announcement SHALL append the avoidance hint (e.g. "Chair ahead, one meter — move left to avoid").
- **R11.6** Spoken suggestions SHALL name the nearest blocking obstacle and its distance ("Chair ahead, one meter. Move left.").

## R12 — (withdrawn)

Motion & approach detection was implemented and then removed at the user's request on 2026-07-14 (see specs/tasks.md Phase 9). R13 keeps its numbering.

## R13 — GPS walking navigation (turn-by-turn)

- **R13.1** The user SHALL be able to search for a destination by name/address (MapKit local search biased to the current location) from a Navigate screen reachable via a persistent icon on the Live screen.
- **R13.2** Routes SHALL be computed **walking-only** (`MKDirections` with `.walking` transport); driving routes are never offered.
- **R13.3** During guidance the system SHALL give spoken turn-by-turn directions: an advance cue ~50 m before each maneuver ("In 50 meters, turn left onto Elm Street"), an immediate cue ~12 m before ("Turn left onto Elm Street"), and automatic step advancement as maneuvers are passed.
- **R13.4** IF the user strays more than ~30 m from the route, the system SHALL announce it and recompute the route from the current position (rate-limited).
- **R13.5** WHEN the user is within ~15 m of the destination, the system SHALL announce arrival and end guidance.
- **R13.6** Guidance SHALL run alongside object detection: a persistent guidance bar on the Live screen shows the current instruction, distance to the next maneuver, and remaining distance; spoken turn cues share the speech queue with narration (immediate turn cues interrupt).
- **R13.7** Location permission (when-in-use) SHALL be requested with a purpose string; if denied, the Navigate screen explains and links to system Settings. Location is used only while navigating.

## R14 — Instance segmentation (shape-true detection)

- **R14.1** Detection SHALL use an instance-segmentation model (YOLO11n-seg) producing a per-pixel mask for each object, not just a rectangle.
- **R14.2** The HUD SHALL render each object's mask as a tinted fill matching the object's shape (label chip and hairline box retained as the anchor/tap target).
- **R14.3** Each detection SHALL expose its **true horizontal footprint** — the x-interval its mask actually occupies — and the safe-path advisor (R11) SHALL use that footprint instead of the bounding-box interval when marking lanes blocked, so free space between/beside irregular objects is not overstated.
- **R14.4** Segmentation decode (score filtering, NMS, mask composition from prototype tensors) SHALL run off the main thread and cap per-frame instances (~12) to protect detection FPS.
- **R14.5** IF the segmentation model is missing from the bundle, the pipeline SHALL fall back to the box-only detection model transparently (masks absent, footprint = bbox).

## R15 — OCR text detection & reading

- **R15.1** The system SHALL detect and recognize text in the camera view on-device (Vision `VNRecognizeTextRequest`, accurate level), scanning at a low cadence (~1.5 s) on its own queue so detection FPS is unaffected.
- **R15.2** Newly appearing text SHALL be read aloud automatically, prefixed "Text:", panned to the text's position when spatial audio is on.
- **R15.3** Recognized text SHALL be spoken **once**: a normalized form of each string is remembered for ~30 s; low-confidence strings (< 0.8) must be seen in two consecutive scans before being read (anti-flicker), high-confidence strings read immediately. At most 3 new strings are read per scan, top-to-bottom.
- **R15.4** Text regions SHALL be outlined on the HUD with a monospace snippet chip, styled per the design system.
- **R15.5** Automatic reading SHALL respect the narration contract: active in CONTINUOUS and NEW ONLY modes (when the "Read text aloud" setting is on and audio isn't paused); in ON DEMAND mode text is silent until "Describe scene", which appends currently visible text.
- **R15.6** A "Read text aloud" toggle SHALL live in Settings (default ON) and persist (R6.6).

## Out of scope (v1)

- Motion/approach detection (withdrawn R12 — removed per user request).

- Cloud/LLM scene description; only YOLO class narration.
- Multi-session history browsing (only latest session is browsable).
- Custom model training; COCO-80 classes only. (Street objects outside COCO — crosswalks, curbs, potholes, bollards, generic traffic signs — need a custom-trained model; planned as a future model swap, the pipeline is already model-agnostic.)
- Localization beyond English.
