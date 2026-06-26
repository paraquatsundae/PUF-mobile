# PUF-mobile — Phone Port PLAN (design doc)

**Status:** Sign-off received (Jun 2026) · §6 open decisions resolved (Jun 2026) · **Scope:** new direction · **No code changes proposed yet.**
**Goal:** A deliberately minimal *phone* build of PUF-mobile — **Android-only for Phase 1+2** (iOS deferred to a later phase) — with a simplified, one-hand, sunlight-readable UI and a dedicated **map + coverage** screen.

Phone feature set (intentionally minimal):
1. Set implement width
2. Record coverage (start/stop)
3. Overlap control on/off
4. Area covered (live readout)
5. **Map view** — paddock boundary + live coverage overlay while recording

Everything else from the tablet app (multi-source GPS config, AB lines, Rx maps, layout manager, farm/job catalogs, ISOXML editing) is **out of scope** for the phone UI.

---

## 1. Current-state assessment

### Stack (verified)
- **Qt 5.15.2 LTS, Qt Quick (QML) + C++17, built with qmake** (`pufmobile.pro`). Not CMake.
- Android target is mature: `ANDROID_MIN_SDK_VERSION = 23`, `TARGET_SDK = 29`, ABIs `armeabi-v7a` + `arm64-v8a`, `QT += quick network` (+ `androidextras` on Android), already producing signed APKs (`README.md`, `pufmobile.pro`).
- Android packaging present: `android/AndroidManifest.xml`, `android/src/org/qtproject/example/*.java` helpers, `android-build/` gradle output.
- `androidextras` is a **Qt 5 module with no Qt 6 equivalent** — relevant to any future Qt 6 / iOS move (see §2).

### Reusable core logic (platform-agnostic C++/JS — keep as-is on phone)
- **Coverage + area + overlap** — `coverage.h`/`coverage.cpp`: a 0.5 m raster-cell `QSet`; `areaHa()` = `cells * cell² / 10000`; `mark(x,y,heading,width)`; `isCovered(x,y)`. Exact, non-overlapping area. This is the entire "area covered" + "overlap" engine and is pure C++/Qt — **fully reusable**.
- **Implement width + sections + record state** — `appcontroller.h`: `implementWidth` (`setImplementWidth`), `sectionCount`/`sectionWidths`, `recordingCoverage` + `toggleRecording`/`setRecording`, `sectionControl` + `toggleSectionControl`, `saveSettings`/`loadSettings`. **Reusable.**
- **Record + overlap loop** — `FieldView.qml` (~628–678, `Connections{ target: gps; onFixChanged }`): per-section it computes a lateral centre, then `var on = !(app.sectionControl && coverage.isCovered(se,sn))`; if on → `coverage.mark(...)`. This is the canonical overlap rule — extract into a shared recorder used by MAIN (headless) and MAP (live overlay). **Logic reusable; tablet FieldView chrome is not.**
- **GPS model + local frame** — `gpsmodel.h`: NMEA/`$PANDA` parse → `latitude/longitude/headingDeg/speedKmh/fixQuality/hdop`, plus a local ENU frame (`localX`/`localY` metres, `setOrigin`/`hasOrigin`, WGS84→metres). **Reusable** and is what coverage consumes.
- **GPS source abstraction** — `gpssource.h`: clean `GpsSource` interface (emits one NMEA sentence + status). All transports are pluggable behind it.
- **Phone GNSS already exists** — `tabletgpssource.h` + `android/src/org/qtproject/example/TabletGps.java`: Android `LocationManager` fix → localhost UDP `TGPS,...` → synthesized `$PANDA`. Runtime `ACCESS_FINE_LOCATION` already wired (`AndroidManifest.xml` lines 19–22). **This is the phone's GPS path, already built.**
- **Paddock/boundary model + import** — `farmdata.h` (`Client→Farm→Field`, `boundary` = WGS84 ring + `abLines`), `kmlimport.h` (KML polygon→paddock), `taskdata.*`/`farmstore.*` (ISOXML `TASKDATA.XML` persistence). **Reusable as the data layer / hard-code source (see §4).** Section labelling helper `Sections.js` is trivial and reusable but barely needed for whole-boom phone use.

### Tablet-specific UI to DROP on phone
- `FieldView.qml` heavy heading-up SkiaSharp-style map (textured ground, sky/horizon, chase/top-down/whole-paddock perspectives, viewport-culled chunk rendering), `Tractor.qml`.
- `LayoutManagerPage.qml`/`layoutmanager.*` configurable multi-column layout, `TopBanner.qml`, info columns (`InfoElement.qml`).
- `AbLinesPage.qml`/`RunLinePopup.qml`, `RxImportPopup.qml`/`rxmap.*`, `CatalogManagerPage.qml`/`workcatalog.*`, job catalog popups (`NewJobPopup`/`ResumeJobPopup`), full `ConnectionPage.qml` multi-source picker, `FarmSetupPage`/`PaddockSetupPage`/`WorkSetupPage`/`GpsInfoPage`.
- Net: phone keeps the **C++/JS core**, replaces tablet `.qml` pages with a **4-destination phone shell** (MAIN · MAP · WIDTH · SETUP/paddock) — see §3.

---

## 2. Tech approach + cross-platform recommendation

### The central decision
The reusable core (coverage/overlap/area/width/GPS) is already pure Qt C++/QML. Throwing it away to rebuild in another framework would mean re-porting the validated coverage/overlap math. So the real question is *only* how to add a phone form factor and whether iOS is reachable.

### Option A — Extend the existing Qt app with a responsive/phone QML layout (Android + iOS via Qt)
- **Approach:** Add a phone QML front-end (MAIN · MAP · SETUP) selected at runtime by screen size/form factor; reuse 100% of the C++ core. Android ships immediately from the existing toolchain.
- **iOS reality check:**
  - iOS builds **require macOS + Xcode** and an **Apple Developer account** (even a free account can side-load to a personally-owned device for 7-day-renewing provisioning; a paid $99/yr account gives 1-year provisioning). There is **no way to build/sign an iOS app from Windows.**
  - Current app is **Qt 5.15** and uses **`androidextras`** (Android-only) + a **Java** GNSS helper (`TabletGps.java`) — none of that compiles for iOS. iOS GNSS would need either **Qt Positioning** (`QGeoPositionInfoSource`, cross-platform) feeding synthesized NMEA into `GpsModel`, or a small Objective-C/Swift Core Location shim behind `GpsSource`.
  - Qt 5.15 iOS support exists but **commercial-LTS / aging**; a clean iOS path realistically wants **Qt 6.x** (current iOS support, CMake). Moving to Qt 6 means replacing `androidextras` usage and re-validating the Android build.
  - **Licensing:** Qt under LGPLv3 can ship on iOS, but App Store distribution of LGPL dynamic-link Qt is legally fiddly; **personal side-load install avoids the store entirely** and is the intended use here. (Confirm with user; commercial Qt license sidesteps all of it.)
- **Effort:** Android phone UI = low (days). iOS = medium-high (Qt 6 migration + Positioning/Core Location shim + Mac/Xcode setup).
- **Code reuse:** Maximal (one codebase, one core).

### Option B — Separate lightweight phone app (Flutter / React Native / native) reusing the *algorithms*
- **Approach:** New thin app; re-implement coverage/overlap/area from `coverage.cpp` (small, ~1 file of math) + width/record state; use platform GPS + map plugin.
- **Pros:** Best-in-class phone UX/tooling; Flutter gives Android+iOS from one Dart codebase; iOS still needs a Mac to build/sign but the framework story is smoother than Qt-on-iOS.
- **Cons:** **Re-port and re-validate** the safety-relevant coverage/overlap math (divergence risk vs the tablet app); two languages/toolchains to maintain; loses the existing GPS-source/NMEA stack.
- **Effort:** Medium-high; **lower iOS risk than Qt**, higher duplication risk.

### Option C — Android-only now, iOS later ✅ **RESOLVED (sign-off)**
- **Approach:** Ship Option A's Android phone UI now; treat iOS as a separate later milestone (either Qt 6 iOS, or a Flutter rewrite if Qt-on-iOS proves painful).
- **Pros:** Fastest to a working phone in the paddock; zero Mac dependency to start; defers the only hard/unknown part.
- **Cons:** iOS users wait; iOS decision still pending at the *later* gate.
- **Decision:** **Android-only is the approved path for Phase 1+2.** iOS feasibility notes below remain for future planning; no iOS work until a separate phase is opened.

### RECOMMENDATION ✅ **Approved**
**Option C is signed off — build on Option A's architecture, Android-only for now.**
1. **Now (Android, Phase 1+2):** Add a phone QML front-end to the *existing* Qt app, reusing the C++ core unchanged; GPS via the already-built `TabletGpsSource`. Lowest effort, highest reuse, no new toolchain. Ship MAIN + MAP + coverage recording before any iOS spike.
2. **Design for iOS from day one (Option A-ready, deferred):** Behind `GpsSource`, plan a **Qt Positioning** backend (cross-platform, no Java) so the phone GPS path is not Android-locked; keep all new code free of `androidextras`. *No iOS build work until a later phase.*
3. **iOS decision gate (deferred phase):** Only pursue iOS once (a) the user confirms access to a **Mac + Apple Developer account**, and (b) we accept a **Qt 5→6 migration** (current iOS support). If Qt-on-iOS proves too costly at that gate, fall back to **Option B (Flutter)** for iOS only, reusing the documented coverage math.

**iOS verdict (deferred):** *Feasible but not free.* It is gated on a Mac + Apple account and a Qt 6 migration; it is **not** achievable from the current Windows/Qt5/Java setup as-is. **Do not block Android delivery on iOS.**

---

## 3. Simplified phone UI/UX design

### Principles
- One-hand, portrait, big touch targets (≥ 56 dp), high-contrast for sunlight (dark map / bright text, no thin lines), minimal chrome, glanceable numbers.
- The **giant primary control is Record start/stop**; area is the headline number; width + overlap are quick toggles.
- **Map + coverage is a first-class destination** — not a tablet-style heavy FieldView, but a dedicated MAP tab the operator can switch to while recording to see boundary + worked area update live.

### Information architecture (bottom nav: MAIN · MAP · SETUP)

**Navigation pattern:** persistent **3-tab bottom bar** (Material-style, thumb-reachable). WIDTH and PADDOCK live inside SETUP as sub-screens — keeps in-field nav to three taps max.

| Tab | Role | In-field time |
|-----|------|---------------|
| **MAIN** | Glanceable drive screen: area, Record/Stop, Overlap, GPS, width shortcut, active paddock name | ~70% |
| **MAP** | Boundary outline + live coverage overlay; updates while recording | ~25% |
| **SETUP** | Width number-pad + paddock picker (one-time / occasional) | ~5% |

- **MAIN (Drive)** — area readout (big), Record button, Overlap toggle (default **ON**), GPS status banner (see below), current width + `[ EDIT ]` shortcut → SETUP/Width, active paddock name (tap → SETUP/Paddock).
- **MAP (Coverage)** — paddock boundary polygon + live worked-area raster/swaths as the user drives. Same three orientation modes as tablet `FieldView.qml`: **chase** (default), **top-down**, **whole paddock**. Minimal chrome: GPS status banner, mode toggle, area chip, Record state indicator, GPS fix dot. Big touch targets for pan/zoom. Coverage updates on every GPS fix while recording (same `coverage.mark` loop as tablet).
- **SETUP** — hub with two rows: **Width** (number-pad) and **Paddock** (installed paddock list). One-time install / doorway for future imports (§4).
- **WIDTH** — sub-screen under SETUP (unchanged intent: `NumberPad.qml` pattern → `app.setImplementWidth`).
- **PADDOCK** — sub-screen under SETUP: pick bundled paddock; skippable when a default is seeded.

**MAP orientation:** Same three modes as tablet `FieldView.qml`: **chase** (mode 0), **top-down** (mode 1), **whole paddock** (mode 2). **Default = chase** — matches in-cab driving UX and reuses existing framing/rotation logic from `FieldView.qml`. Top-down and whole-paddock remain available for boundary review and corner checks. **Phone UX:** a **3-way segmented control** in the MAP top strip (`Chase | Top | Paddock`) — orientation is map-specific, thumb-reachable, and avoids cluttering MAIN. No separate heading-up toggle needed (chase covers heading-up drive view).

**Overlap (v1):** Accept phone overlap as a **coarse aid** (not section-precise); **default ON** (see §5).

### GPS status banner (MAIN + MAP)

Shared top-banner widget on MAIN and MAP:

| Element | Behaviour |
|---------|-----------|
| **Satellite icon** | Colour = fix quality: **green** (good fix), **yellow** (marginal / degraded), **red** (no fix / unusable). |
| **Correction tier text** | Show applicable John Deere StarFire tier when known: **RTK**, **GS1**, **GS2**, **GS3** (from `GpsModel` fix quality / NMEA where available). When phone GNSS only, show **GPS** or **GNSS** instead. |
| **Cellular assist** | When using **mobile phone GPS source** (`TabletGpsSource`), show **4G** or **5G** indicator alongside satellite icon (cellular-assisted GNSS). Hidden when an external RTK/puck source is active. |

Layout: compact horizontal strip — `[sat icon + colour] [tier text] [4G/5G if phone GPS]` — left-aligned in the top banner; on MAIN, app title **PUF** may share the row (right-aligned or centred per theme pass).

### Wireframe — MAIN (portrait)
```
+-----------------------------+
| PUF  [sat] RTK  4G          |   <- GPS banner: sat icon (G/Y/R), tier, 4G/5G
+-----------------------------+
|                             |
|        AREA COVERED         |
|         12.84 ha            |   <- huge, primary number
|                             |
|     Paddock: North 40       |   <- tap -> SETUP/Paddock
+-----------------------------+
|   Width: 6.0 m   [ EDIT ]   |   <- tap EDIT -> SETUP/Width
+-----------------------------+
|   OVERLAP   [ ON  |  off ]  |   <- big segmented toggle (default ON)
+-----------------------------+
|                             |
|     +---------------------+ |
|     |      ●  RECORD      | |   <- full-width primary; turns red "■ STOP"
|     +---------------------+ |
|                             |
+-----------------------------+
|  MAIN  |   MAP   |  SETUP  |   <- bottom nav (MAIN selected)
+-----------------------------+
```
Recording state: button shows `■ STOP` (red), a pulsing dot, and area ticks up live (`coverage.areaHa`, already a notifying property). Switch to **MAP** anytime to see boundary + coverage build.

### Wireframe — MAP (portrait, chase default)
```
+-----------------------------+
| [sat] GS2  4G  12.84 ha  ●  |   <- GPS banner + area + record dot
|  Chase | Top | Paddock     |   <- 3-way orientation toggle (Chase selected)
+-----------------------------+
|  +-----------------------+  |
|  |     ~ ~ ~ ~ ~ ~       |  |   <- paddock boundary (outline)
|  |   ~  [coverage]  ~    |  |   <- worked swaths / raster cells (live)
|  |  ~    ▲ you      ~    |  |   <- GPS position (chase: heading-up)
|  |   ~  (chase view) ~   |  |
|  |     ~ ~ ~ ~ ~ ~       |  |
|  +-----------------------+  |
|                             |
|   [ − ]          [ + ]      |   <- big zoom out / zoom in
|   ( drag to pan )           |
+-----------------------------+
|  MAIN  |   MAP   |  SETUP  |   <- bottom nav (MAP selected)
+-----------------------------+
```
Coverage renders from the same `coverage` object as MAIN; boundary from active `Field.boundary` (WGS84 ring → local frame). No tractor sprite, sky, AB lines, or Rx overlay.

### Wireframe — SETUP (hub)
```
+-----------------------------+
|           SETUP             |
+-----------------------------+
|   Width          6.0 m   >  |   -> WIDTH sub-screen
+-----------------------------+
|   Paddock     North 40   >  |   -> PADDOCK sub-screen
+-----------------------------+
|  MAIN  |   MAP   |  SETUP  |   <- bottom nav (SETUP selected)
+-----------------------------+
```

### Wireframe — WIDTH (SETUP sub-screen)
```
+-----------------------------+
|  < SETUP       WIDTH        |
+-----------------------------+
|        6.0  m               |   <- live value
+-----------------------------+
|     7    8    9             |
|     4    5    6             |
|     1    2    3             |
|     .    0    <x            |
+-----------------------------+
|        [   SET   ]          |  -> app.setImplementWidth(v)
+-----------------------------+
```

### Wireframe — PADDOCK (SETUP sub-screen)
```
+-----------------------------+
|  < SETUP      PADDOCK       |
+-----------------------------+
|  ( ) North 40      24.1 ha  |
|  (•) River Block   18.6 ha  |   <- installed paddocks (config-driven)
|  ( ) Home East      9.2 ha  |
+-----------------------------+
|        [  SELECT  ]         |
+-----------------------------+
```

### Reuse notes — what backs the MAP page

| Layer | Reuse from existing PUF-mobile | Phone-specific work |
|-------|-------------------------------|---------------------|
| **Coverage math + area** | `coverage.h`/`coverage.cpp` — `mark()`, `isCovered()`, `areaHa()`, 0.5 m raster `QSet` | None — bind directly |
| **Record + overlap loop** | Logic from `FieldView.qml` (~628–678, `onFixChanged`) | Extract to shared `CoverageRecorder.qml` or C++ helper; callable from MAIN headless *and* MAP live |
| **Boundary geometry** | `farmdata.h` `Field.boundary` (WGS84 ring), loaded via `farmstore.*`/`taskdata.*` | Draw outline only — no fill triangulation for huge polygons unless needed |
| **Local frame / GPS** | `gpsmodel.h` (`localX`/`localY`, `setOrigin`, WGS84→metres) | None |
| **Map framing / bounds** | `FieldView.qml` helpers: `_boundaryCentroid()`, `_fieldBounds()`, perspective modes 0/1/2 (chase, top-down, whole-paddock) | Port into `PhoneMapView.qml` — reuse mode logic; drop sky, tractor, chunk persistence UI only |
| **Coverage rendering** | `FieldView.qml` chunk stroke model (`doneStrokes`/`activeStrokes`, `_chunkBbox`, `coverage.addChunkBox`) *or* direct raster viz from `coverage` cell set | **New simplified renderer:** either (a) lightweight Canvas/QML polylines per swath chunk, or (b) periodic raster tile from `coverage` cells — avoid viewport-culled chunk complexity of full FieldView |
| **Pan / zoom** | `FieldView.qml` world↔screen helpers (`_worldToScreen` / `_screenToWorld`) | Big `+`/`−` buttons + drag pan; no pinch required for v1 but nice-to-have |
| **Tablet-only (DROP)** | Textured ground, `Tractor.qml`, horizon/sky, AB lines, Rx maps, job save/resume UI on map | — |

**Summary:** C++ core and coverage data path are 100% reusable. MAP is a **new thin QML component** that borrows framing/coordinate math from `FieldView.qml` but renders boundary + coverage with phone-minimal chrome — not a responsive resize of the tablet map.

### GPS / permissions / background implications (phone)
- **Permission:** `ACCESS_FINE_LOCATION` (already declared) requested at first record. For Android 12+, also handle the **approximate/precise** prompt and request **precise**.
- **Background recording (v1 required):** Phone must keep recording with **screen off / app backgrounded**. Implement via Android **foreground service** (persistent notification while recording) + **wake lock** (or equivalent) + continuous location updates. May require `ACCESS_BACKGROUND_LOCATION` on Android 10+ — document rationale in Play/console notes if distributing beyond sideload. **`KeepScreenOn` remains useful when screen is on**, but is not sufficient alone.
- **Cross-cutting follow-up (tablet):** User also wants background/screen-off recording on the **tablet** app — out of phone-port scope but track as a separate tablet enhancement.
- **iOS (deferred):** Core Location `WhenInUse` authorization + a "location indicator" while recording; background needs the location background mode — not in scope until a later iOS phase.
- **Sensors:** Phone has **no TCM (roll/pitch)** and heading from course-over-ground only — same assumption `TabletGpsSource` already documents; chase mode may wobble at very low speed (same as tablet behaviour).

---

## 4. Boundary / paddock model (hard-code now, clean doorway later)

The data model already exists and is the right shape: `farmdata.h` (`Field.boundary` = WGS84 ring, `Field.abLines`, `areaHa`) loaded by `farmstore.*` and importable via `kmlimport.h` (KML) and `taskdata.*` (ISOXML `TASKDATA.XML`). **Do not invent a new format.**

### Recommended approach: one bundled config file, not literals in code
1. **Author once on the desktop/tablet** the farm's paddocks (boundaries imported from KML/ISOXML as today).
2. **Bundle the result as a single read-only asset** in the phone build — preferred format **ISOXML `TASKDATA.XML`** (already the persistence format, so `farmstore`/`taskdata` load it unchanged) bundled via the Qt resource (`qml.qrc`/a new `farm.qrc`) or copied to app storage on first run. KML is an acceptable alternative since `kmlimport` already parses it.
3. **On first launch**, if no user paddock store exists, **seed from the bundled asset** (copy into the app's writable store). This keeps the hard-coded farm working out-of-the-box.

This satisfies "hard-coded for the user's own farm" (ships working, no setup) while keeping geometry in **data, not scattered literals**.

### The clean doorway (future paddocks / edited boundaries)
- The import path **already exists** — `kmlimport.h` + `taskdata.*` + `farmstore.*`. Keep it compiled into the phone build even if the phone UI hides it.
- Expose a single hidden/secondary action ("Import paddock") or simply allow dropping a new `TASKDATA.XML`/`.kml` into a known folder that the app re-seeds from. No rewrite needed to add/modify paddocks.
- **Format to support later:** stay aligned with the workspace — **ISOXML TASKDATA.XML** is primary (matches PUF-mobile and the broader PUFworks ISO-XML direction), **KML** secondary. Shapefile is *not* currently supported and is not recommended unless required.

### Where paddock data lives ✅ **RESOLVED**
- **Format:** bundled **ISOXML `TASKDATA.XML`** (confirmed).
- **Asset path:** `assets/farm/TASKDATA.XML` — create this folder/path as the bundled load location; seed to app writable store on first run (see §6).

---

## 5. Coverage / area on a phone (accuracy expectations)

The math is unchanged: `Coverage` rasterizes worked area into 0.5 m cells and reports exact, non-overlapping `areaHa` (`coverage.h`). What changes on a phone is **input accuracy**, not the algorithm.

- **Machine (tablet today):** JD StarFire / 616R via CAN bridge → often RTK / SF (centimetre-to-decimetre). Overlap control and area are trustworthy at sub-pass precision.
- **Phone GNSS:** typical **3–10 m horizontal** (single-frequency), **2–5 m** for modern dual-frequency phones in open sky; heading is course-over-ground (jittery at low speed, which `GpsModel` already guards). No RTK, no TCM.

### Implications / honest limitations
- **Area-covered:** good for an *operational estimate* (paddock-level totals, "did I get it all"). Expect a few % error vs the true sprayed area; not an invoice-grade as-applied record.
- **Overlap control:** with a 0.5 m cell and ±3–10 m position noise, automatic overlap shutoff on the phone is **coarse** — it will prevent gross re-spraying but should **not** be relied on for tight skip/overlap at boom-section precision. **User sign-off:** accept as a coarse aid; **default ON** in the UI (`app.sectionControl` / Overlap toggle).
- **Mitigations (optional, later):** raise the cell size to ~1 m to match phone noise; require a minimum speed before recording (already a 0.5 m step gate in `FieldView.qml`); optionally accept an external Bluetooth RTK puck via the existing `btgpssource` path for users who want machine-grade accuracy on the phone.
- **Set expectation with the user up front:** phone = convenience/estimate tier; the cab tablet remains the precision tier.

---

## 6. Phased plan + open decisions

### Phases
- **P0 — Sign-off ✅ Done.** Option C (Android-only now) approved; MAP + coverage screen required; §6 open decisions resolved (Jun 2026).
- **P1 — Android phone shell + MAIN tab.**
  - Form-factor detection + phone QML shell with bottom nav (MAIN · MAP · SETUP stubs).
  - MAIN tab bound to existing `app`/`coverage`/`gps`: area, Record/Stop, Overlap (default ON), width shortcut, paddock name, **GPS status banner**.
  - Wire the 4 features to existing API: `app.setImplementWidth`, `app.toggleRecording`, `app.toggleSectionControl`, `coverage.areaHa`.
  - GPS via existing `TabletGpsSource`; **`KeepScreenOn` while recording (screen on)**.
  - **Background recording:** Android foreground service + wake lock + continuous location while recording (screen off / background) — **v1 requirement**, not polish.
  - SETUP/Width sub-screen (`NumberPad.qml` pattern).
- **P2 — MAP tab + coverage recording on map.**
  - Extract record+overlap loop from `FieldView.qml` into shared recorder (headless from MAIN, visual from MAP).
  - `PhoneMapView.qml`: boundary outline + live coverage overlay; **chase / top-down / whole-paddock** modes (default chase); MAP top-strip mode toggle; pan/zoom; updates on GPS fix while recording.
  - Port framing/coordinate helpers + perspective modes 0/1/2 from `FieldView.qml`; simplified coverage renderer (see reuse table §3).
  - **GPS status banner** on MAP (shared widget with MAIN).
- **P3 — Paddock bundle + SETUP/Paddock.**
  - Seed paddocks from bundled `assets/farm/TASKDATA.XML`.
  - SETUP/Paddock picker; boundary drives MAP framing (whole-paddock mode + default chase bounds).
- **P4 — Polish (Android).** Sunlight theme pass, optional external RTK puck, optional 1 m cell for phone, tablet background-recording follow-up.
- **P5 — iOS (deferred phase, gated).** Qt Positioning `GpsSource` backend; Qt 6 migration spike; Mac + Xcode + Apple account; Core Location/permissions; personal side-load or store. *Not started until Android P1–P3 are field-validated.*

### Open decisions (remaining)
1. **GPS accuracy tier labeling:** How prominently to label phone GNSS as "estimate tier" vs cab tablet (first-run disclaimer vs status-banner wording only)?

**Resolved (Jun 2026 sign-off):**
- ~~MAP orientation~~ → **Three modes as tablet:** chase (default), top-down, whole paddock; **3-way toggle on MAP tab** ✅
- ~~Paddock data location/format~~ → **ISOXML `TASKDATA.XML`** at **`assets/farm/TASKDATA.XML`**, seeded on first run ✅
- ~~Overlap expectation~~ → **Coarse aid accepted; default ON** ✅
- ~~Background recording~~ → **Required for phone v1** (foreground service + wake/location); tablet background recording noted as cross-cutting follow-up ✅
- ~~GPS status banner~~ → **Satellite icon (G/Y/R) + RTK/GS1/GS2/GS3 tier text + 4G/5G when phone GPS** in MAIN/MAP top banner ✅

**Resolved / deferred (no longer blocking):**
- ~~Android-first vs both now~~ → **Android-only for Phase 1+2** ✅
- ~~iOS stack (Qt 6 vs Flutter)~~ → deferred to P5 gate
- ~~Mac + Apple Developer account~~ → deferred to P5 gate
- ~~Qt 6 migration appetite~~ → deferred to P5 gate
- ~~MAP heading-up toggle (post field-test)~~ → **N/A** — chase mode covers heading-up; top-down and whole-paddock in scope ✅

---

## Appendix — key files cited
`pufmobile.pro`, `README.md`, `coverage.h`/`coverage.cpp`, `appcontroller.h`/`appcontroller.cpp`, `FieldView.qml` (record/overlap loop ~628–678; perspective modes 0/1/2 chase/top-down/whole-paddock; boundary/coverage bounds helpers), `PhoneMapView.qml` *(planned)*, `Sections.js`, `gpsmodel.h`, `gpssource.h`, `tabletgpssource.h` + `android/src/org/qtproject/example/TabletGps.java`, `farmdata.h`, `kmlimport.h`, `taskdata.*`, `farmstore.*`, `assets/farm/TASKDATA.XML` *(bundled paddock seed)*, `android/AndroidManifest.xml`, `NumberPad.qml`.
