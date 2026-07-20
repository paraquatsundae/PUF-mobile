# PUF-mobile — Developer Notes

Working notes for the PUF-mobile tablet app: architecture, key decisions, and the
hardware findings behind them. Keep this current as the app evolves.

---

## Origin

Started as an Android "spike" off `QtAgOpenGPS` to prove a Qt GPS app on an old
Allwinner T3 tablet (Android 6.0.1 / API 23). Extracted and rebuilt into this
standalone project (`PUF-mobile`) under `C:\Projects\PUF-mobile`.

## JD GPS / coverage (2026-07-19)

Symptoms with IsobusWifiHub / gps_bridge NMEA: jittery implement, paddock “wrong place”.

**Not a lat/lon swap.** FEF3 is SAE J1939 Vehicle Position: **uint32** × 1e-7° with
−210° offset on **both** lat and lon. Reading lon as signed int32 makes WA (~121°E)
show as ~−98° (the “−90” bug). Hub `gps_bridge_lib.decode_fef3` and on-tablet
`JdCanDecoder` must both use uint32 − 210. Confirm Setup → GPS shows south lat and
east lon (~120°) for Clare Downs.

Fixes in `19Jul-jd-gps`:
1. `$PANDA` TCM heading sets `m_haveTrueHeading` (was track-derived COG only).
2. ENU filter runs once per NMEA burst (not once per GGA/RMC/VTG/PANDA).
3. Refuse seeding origin from (0,0); re-pin to paddock if GPS is >5 km from ring.
4. Tractor rotation Behavior removed (200 ms lerp looked like boom sway).
5. On-tablet Can path: FEE6 roll parked; FFFF byte7 → GGA quality (RTK tier).

## Stack & target

- **Qt 5.15.2** (not 6.x). Qt 6.8's `androiddeployqt` enforces `minSdk >= 28`, which
  cannot target API 23; Qt 6 APKs also failed to install on Android 6 (no v1
  signing). Qt 5.15 supports `minSdk 23` and v1+v2 signing out of the box.
- **NDK r21e (`21.4.7075529`)**, **JDK 11**, build-tools 34, platform android-23.
- **ABI:** universal dual-ABI `armeabi-v7a` + `arm64-v8a` (32- and 64-bit), GL ES 2.0.
  Old workshop tablet is API 23 (v7a); new Samsung SM-T545 is Android 11 (arm64).
- App id: `com.pufworks.pufmobile`. Native libs: `libpufmobile_<abi>.so`.
- **targetSdk 29 + `android:requestLegacyExternalStorage="true"`** (manifest). Android
  10/11 scoped storage otherwise blocks reading non-media files (e.g. `TASKDATA.XML`
  in `Download/Farm_data`) even with `READ_EXTERNAL_STORAGE` granted — `MediaProvider`
  denies the read because that perm only grants MediaStore access. Legacy storage is
  only honored when targetSdk ≤ 29, so targetSdk is pinned at 29 (minSdk stays 23). Do
  not raise it; the alternative would be a SAF document-tree picker or
  `MANAGE_EXTERNAL_STORAGE`.

## Architecture

- C++ exposes context objects to QML: `gps` (`GpsModel`, NMEA parse), `app`
  (`AppController`, source selection + status), `layout` (`LayoutManager`),
  `coverage` (`Coverage`), `farm` (`FarmStore`).
- **GPS sources** implement the `GpsSource` interface and emit `sentence(QString)` /
  `status(text, connected)`. The model parses `GGA`/`RMC`/`VTG` (by 3-char tail, so
  `$GP*`/`$GN*` both work) and `$PANDA`/`$PAOGI`.
- **Coverage** is split into frozen chunks (rendered once) + a capped active chunk so
  per-frame cost stays flat as worked area grows (fixes GPS-runtime lag).
- **Map** is heading-up; the rear GPS antenna sits at screen centre; default zoom
  frames ~80 m behind the implement. Tractor drawn as a true 3 m × 6 m footprint.
- **Persistence:** ISOXML `TASKDATA.XML` (read/write) for farms/fields/boundaries/
  run lines; KML import creates one paddock per polygon, auto-named from placemarks.

## GPS source decisions

- **Internal GNSS:** BT-770 is a passive antenna feeding the tablet's built-in
  receiver, which streams NMEA on `/dev/ttyS0 @ 115200` (OEM app says 9600 — wrong;
  sweep bauds if garbled). Read via raw POSIX/termios (`posixserialgpssource`).
- **John Deere:** decode map ported from `PUFworks-isobus/scripts/gps_bridge_lib.py`
  (the field-validated PGN set):
  - PGN `0xFEF3` lat/lon (int32 LE * 1e-7; lat offset −210°), SA `0x1C`
  - PGN `0xFEE8` heading/speed/pitch/altitude, SA `0x1C`
  - PGN `0xFEE6` roll, SA `0x1C`
  - PGN `0xFFFF` GNSS satellite count (sub-msg `0x51`, byte3), SA `0x1C`
  - PGN `0xFEF1` wheel-speed fallback (any SA)
  → rendered as AgOpenGPS `$PANDA`.

## Satellites = available · HDOP / PDOP / VDOP = NOT on the 616R implement bus

The JD CommandCenter shows sats + HDOP from the StarFire's own GNSS solution. A
deep scan of the 616R recordings (`recordings/20260615_095343_616r_spray_live`,
`..._observe_3_long`, `..._transport`, the single-section captures, 25+ sessions)
shows **the satellite count IS on the X119 tap**, but the DOP values are not:

- **Satellites (decoded):** StarFire/ATX `0x1C` emits a JD-proprietary multiplexed
  PGN **`0xFFFF`** (`can_id 0x18FFFF1C`, ~5 Hz). byte0 selects a sub-message;
  sub-msg **`0x51`** (signature `b1=0x03 b2=0x02`) is the GNSS solution summary:
  - **byte3 = satellites used** (uint8). Field range across sessions ≈ **25–39**,
    slowly varying, and it *drops during headland turns* — exactly sat-count
    behaviour. This is now decoded by `gps_bridge_lib.decode_gnss_sats_ffff()` and
    populated into `GpsFix.satellites` → GGA field 7 / `$PANDA` field 7.
  - bytes4–6 are **per-constellation sat counts** (GPS / GLONASS / Galileo): they
    *fall together with* byte3 when signal degrades, i.e. they track sat count, not
    DOP (DOP would *rise* as sats fall). So they are **not** usable as HDOP/VDOP.
  - Gate strictly to SA `0x1C`: DISP `0xF0` also emits `0xFFFF` with unrelated
    content.
- **HDOP / PDOP / VDOP (not present):** no NMEA-2000 GNSS DOP / sats-in-view fast
  packet (`129539` / `129540`) appears on this classic 250 kbps bus. The other ATX
  proprietary PGNs are accounted for: `0xFAB3` (~5 Hz) is fine position/velocity,
  `0xF010` is a rolling counter, and `0xFFFF` sub-msgs `0x52`/`0x53` carry
  high-entropy tails (checksums / fine data), none of which decode to a plausible
  sub-1 DOP. Decoding any of them to an HDOP would be **speculation** — not done.

**Decision (do not fake numbers):** satellites are now **real**; HDOP is emitted as
an **empty** NMEA field (`$GPGGA,...,1,33,,alt,...` and the `$PANDA` equivalent).
`GpsModel` tracks `satellitesValid` / `hdopValid`; the banner (`GpsHealth`) and the
GPS Information page render the live sat count and `—` for HDOP. If a VB1 GNSS DOP
PGN is ever captured, set it in `GpsFix` + the GGA/PANDA HDOP field — no UI change
needed. (Note: the `parseGGA`/`parsePANDA` comments in `gpsmodel.cpp` still say
sats are blank — stale, harmless; update opportunistically.)

## TCM terrain compensation (roll/pitch) + antenna height

**Status (2026-07-19): PARKED for coverage.** TCM **yaw/heading** from FEE8 via
`$PANDA` is live and should be near pass-through in `gpsfilter` (no boom-width EMA).

| Signal | Source | Coverage use |
| :--- | :--- | :--- |
| Heading | FEE8 → PANDA field 12 | Live (true heading) |
| Roll | FEE6 | **Parked** — field RTK showed constant bogus vs cab TCM |
| Pitch | FEE8 | **Parked for TCM** — ~−9° constant bias on flat → ~0.5 m along-track shift at 3 m height |

Crossed wire that caused weird coverage: `hasAttitude` became true from pitch (and
from roll `0.00`), so `RecordPoint.recordLocal` applied **pitch-only** compensation
while roll stayed 0. Flag `TERRAIN_COMP_LIVE` in `RecordPoint.js` gates re-enable.

Intended formula (when re-enabled after field check of both axes):

```
lateral  ≈ antennaHeight · sin(roll)
longitudinal ≈ antennaHeight · sin(pitch)
ground = antenna − lateral·right(heading) − longitudinal·forward(heading)
record = ground − implementOffset·forward(heading)
```

**Antenna height** remains on the GPS Information page (display / future TCM).

## GPS Information page

`GpsInfoPage.qml`, reachable from **Setup → GPS Information** (registered in
`main.qml` `pageInfo` as `gpsinfo`, stack index 8). Shows fix quality, sats
(used / in view), HDOP/PDOP/VDOP, a **Position** card (lat/lon, UTC, local E/N,
sentence count — see "Position card" below), speed, heading, altitude, TCM
roll/pitch/yaw, and the antenna-height adjuster. All values bind live to the
`gps` / `app` context objects; unavailable values render `—`.

## No coverage recording — `recordOffsetM()` TypeError

**Symptom (SM-T545):** Record on, GPS live, area stays 0 / no green swath.
**Logcat:** `qrc:/RecordPoint.js:29: TypeError: Property 'recordOffsetM' of object
AppController is not a function` on every fix.

**Cause:** `RecordPoint.js` called `app.recordOffsetM()`; in QML that Q_PROPERTY is
a property, not a callable. The throw aborted `_recordPoint()` so coverage never
marked. **Fix:** use `app.recordOffsetM` (no parentheses). Build stamp
`17Jul-record-fix`.

## Record Coverage freeze (~3 min) — frozen Shape PathPolyline on Samsung tablets

**Repro:** Record Coverage on, drive for ~2–4 minutes on the Samsung cab tablets
(older unit failed first; both eventually freeze then the process is killed).

**Root cause:** live coverage already painted as rotated rects, but **frozen** chunks
were still `Shape { PathPolyline }` with boom-width `strokeWidth`. Each freeze added
another triangulated Shape; viewport model rebuilds recreated them. Tessellation cost
grew with worked distance until the UI wedged (Adreno on SM-T545 / similar).

**Fix (`FieldView.qml`):** frozen coverage uses the same `_appendWorldStrokeSegs`
rect painter as the active stroke (`_frozenPaintSegs`, capped, fed from `_visChunks`).
No coverage PathPolyline on the tablet map. Phone path: coalesce `coverage.onChanged`
paint rebuilds to 250 ms so cell-span scans are not per-mark.

**Verify on-device:** dual-ABI APK on both Samsungs — Record Coverage for ≥15 min with
GPS moving; UI should stay responsive and coverage should still paint behind the boom.

## Coverage crash fix — overlap + section control (empty PathPolyline)

**Repro:** driving back over already-worked ground with *section control* **and**
*record coverage* both on → hard crash (SIGSEGV) on the tablet (Mali-400, GL ES 2).

**Root cause (no logcat was captured; diagnosed from the coverage render path).**
Coverage swaths are drawn by two `Repeater`s of `Shape { ShapePath { PathPolyline } }`
in `FieldView.qml` — frozen chunks + one *active* chunk per section. On a first
pass every section stays on, so each active chunk always holds ≥ 2 points. **The
only thing that empties an active chunk is section control turning a section off
over worked ground** (`activeStrokes[i] = null`). The delegate then bound
`path: []` (and, on the very next point, a 1-point path) straight into
`PathPolyline`. A degenerate/empty polyline handed to the GL ES 2 Shapes
triangulator on this GPU crashes — and that state is reachable *only* in the
overlap + section-control case, which is exactly the repro. The frozen `Repeater`
also dereferenced `doneStrokes[index].w` with no null guard.

**Fix (focused, feature kept):**
- `FieldView.qml`: both coverage `Repeater`s now gate on a real line — each `Shape`
  is `visible` only when its chunk exists and `pts.length >= 2`, and `strokeWidth`/
  `path` fall back to `0`/`[]` otherwise, so the renderer is never handed an
  empty/1-point geometry.
- Defense in depth against NaN feeding the grid / a stroke array: `_recordPoint()`
  returns `null` on a non-finite result (caller skips the fix), the per-section
  sampling loop skips any section whose `(se,sn)` is non-finite, and
  `Coverage::mark()` / `isCovered()` (C++) reject non-finite `x/y/heading/width`,
  clamp the cell index to the `key()`-safe band, and bound the swath width so the
  inner loop can't run away.

### Follow-up: same crash via the boundary + AB-line Shapes (KML field activate)

**Repro:** import a farm/field from KML, set it active with GPS running (origin
set) → hard crash. **Root cause:** the original coverage fix guarded *only* the
two coverage `Repeater`s. The **field-boundary `Shape`** and the **AB run-line
`Repeater` `Shape`s** were left unguarded. When a KML field goes active, the
boundary `Shape` becomes `visible` (`boundaryCount >= 3`) and the AB `Shape`s
become `visible` (`abLineName` non-empty) — but their `PathPolyline` could still
be empty: `_abPts()` returns `[]` for a degenerate line (A ≈ B, `len < 0.001`),
and `_selAb` can be `null` while the AB `Shape`s are `visible`. An empty
`PathPolyline` reaching the GL ES2 triangulator on the Mali-400 segfaults — the
exact KML repro.

**Fix (`FieldView.qml`, same pattern as coverage):**
- Boundary `Shape`: compute the ring once into a `ring` property; `visible` only
  when `ring.length >= 2`; `path`/`strokeWidth` fall back to `[]`/`0` otherwise.
- AB `Repeater`: each delegate computes its polyline once into a `pts` property
  (and `_abPts(null, …)` now returns `[]`); `visible` is gated on
  `pts.length >= 2`, so the `visible`-while-empty window is closed.
- Hardened the geometry helpers: `_mapRing()` drops non-finite points, and
  `_abPts()` bails to `[]` on a null line or any non-finite A/B/endpoint. No
  `PathPolyline` is ever handed an empty/1-point/NaN path, even transiently.

### Follow-up 2: KML activate STILL crashed — huge-but-finite coords + bad origin

**Repro (unchanged):** set a KML-imported paddock active (especially in
**whole-paddock** fit mode) with a recorded job on disk → hard crash, even after
the `visible`/`isFinite` guards above.

**Root cause (static analysis; no logcat — no device was attached).** The earlier
guards only rejected *non-finite* (`NaN`/`Inf`) geometry. They did **not** catch
**huge-but-finite** coordinates, which is the real KML-activate failure:

- `restoreActiveJob()` (`FieldView.qml`) trusted `metadata.json`'s
  `originLat/originLon` after only an `=== undefined` check, then called
  `gps.setOrigin(...)`. A stale/aborted/corrupt job whose origin is `0,0` (or any
  wrong value) pins the local frame to the wrong place, so every boundary/coverage
  vertex resolves to **millions of metres** (`toLocal` of a real paddock vs a
  `0,0` origin ≈ 1.6e7 m). Those values are *finite*, so they sailed past
  `isFinite()` and were fed to the **filled** boundary `PathPolyline` → the
  Mali-400 GL ES2 triangulator overflows/segfaults. Whole-paddock fit makes the
  boundary always visible + central, which is why that mode crashes hardest.
- A **scanned/traced KML** ring can also carry a stray wild vertex (→ huge local
  coord) and/or **thousands of vertices** (a large filled concave polygon the
  Mali-400 chokes on).

**Fix (`FieldView.qml` + `gpsmodel.cpp`, self-healing):**
- **Origin validation + self-heal.** `_validLatLon()` requires finite, in-range,
  non-`(0,0)` lat/lon. `restoreActiveJob()` applies the job origin only if valid;
  otherwise it **derives the origin from the boundary centroid** (`_boundaryCentroid()`)
  so stored coverage still lines up and the frame stays small — or, with no
  boundary, leaves the origin to the first live fix. `GpsModel::setOrigin()` now
  **rejects** non-finite / out-of-range origins outright (keeps any live origin).
- **Magnitude clamp.** A shared `_maxLocalM` (200 km) bound is enforced in
  `_mapRing()`, `_fieldBounds()`, `_spanMeters`, `_abPts()` and
  `_loadCoverageGeoJson()`: any vertex beyond it is dropped, so a corrupt origin or
  stray KML point can never reach a `PathPolyline` or skew the fit-to-screen scale.
- **Vertex decimation.** `_mapRing()` stride-decimates rings to `_maxRingVerts`
  (1000) before the filled boundary `Shape`, capping triangulator load.
- **Quarantine / never throw.** `restoreActiveJob()` wraps `jobs.hasJob/jobMeta/
  loadCoverage` in `try/catch`; unreadable or malformed job data → empty coverage,
  never a crash. `_loadCoverageGeoJson()` already `try/catch`es the JSON parse and
  skips bad features; it now also skips empty/short coordinate tuples.
- **Fit-to-screen is divide-safe.** `viewScale` already clamps the extent with
  `Math.max(1, …)`; `_fieldBounds()` now returns `null` (→ falls back to the base
  scale) when fewer than 3 valid vertices survive filtering.

Net: regardless of what is on disk, a KML paddock activates with either a valid
origin or a centroid-derived one, sane-magnitude decimated geometry, and empty
(not crashing) coverage if the job is unreadable. **Not yet verified on the tablet
— retest on-device (optionally after running `scripts/clear_tablet_jobdata.ps1`).**

### Tablet job-data wipe script (`scripts/clear_tablet_jobdata.ps1` + `.bat`)

Clears recorded coverage jobs from the tablet via `adb run-as` (debug build, no
root). Default removes **only** `files/jobs` (keeps imported paddocks in
`files/TASKDATA` and all QSettings); `-All` also clears `files/TASKDATA`,
`files/.config` and `shared_prefs` (full reset). Auto-reads the package id from
`android/AndroidManifest.xml` (`com.pufworks.pufmobile`), checks `adb devices`
first and offers `adb connect 192.168.1.83:5555` over Wi-Fi if none, lists the job
folders, and prompts before deleting (`-Force` to skip). Launcher
`clear_tablet_jobdata.bat` mirrors `run_bridge.bat`.

## Record point / boom alignment — boom drawn in world space

**Symptom:** recorded coverage appeared at the GPS "hat" (antenna), not at the
implement, even though `_recordPoint()` already sets the record point back by
`implementOffset` (default 3 m) with TCM terrain compensation.

**Causes:** (a) the boom arm + section bar were drawn in flat **screen** space
while the coverage swaths live inside the tilted `world` `Item` (chase tilt ≈ 74°),
so coverage was perspective-compressed near the tractor and never lined up with the
boom bar; (b) the antenna sits at the FRONT-top of the 6 m machine sprite (drawn
last, on top) with only a 3 m set-back, so the record point landed mid-sprite and
was hidden under the machine image.

**Fix (`FieldView.qml`):** the boom arm + per-section bar are now drawn inside the
**same tilt + world transform** as the coverage swaths (a second world-transform
layer, identical `Rotation`(tilt) + `Scale`/`Rotation`/`Translate` as `world`), in
**metres**, anchored at `_recordPoint()` (returns world `east,-north`; the layer is
hidden when it is `null`). An inner `Item` is positioned at the record point and
`rotation: gps.headingDeg`, so local **+x** runs along the bar (perpendicular to
travel) and local **−y** points forward to the antenna — the boom arm is a
`0.4 m × implementOffset` rect from `(0,−offset)` to `(0,0)` and the bar is a `Row`
of section rects centred on the record point. Section on/off colouring is kept
(`field.sectionOn[index]`). The layer is placed **after** the `Tractor` so the bar
(mid-sprite at the 3 m default) is **not occluded** by the machine image. The
antenna stays at screen centre (map convention); only this world-space boom moves.
Result: in chase/top-down/whole-paddock the boom + orange bar scale/tilt with the
ground and the green coverage emerges from the bar behind the machine.

**`implementOffset` fallback (`appcontroller.cpp`):** an older build could persist
a `0 m` offset, which would record at the antenna. `loadSettings()` now treats a
stored `< 0.05 m` offset as unset and falls back to the **3 m** default.

## GPS Information page — Position card

`GpsInfoPage.qml` gained a **Position** card (between Fix/DOP and Motion) binding
the existing `gps` properties: `latitude`/`longitude` (7 dp), `utcTime`, local
`E / N` metres from origin (`localX`/`localY`), and `sentenceCount` (+ a "(stale)"
marker). Lat/lon/E-N are gated on `gps.hasOrigin` (render `—` with a "waiting for
first fix" note until then). The **satellites** row now shows a live count (decoded
from StarFire PGN `0xFFFF`/`0x51`, see the Satellites section above); the
HDOP/PDOP/VDOP rows stay honest `—` (those DOP values are not on the X119 implement
tap — they live on the StarFire's own GNSS bus).

## Settings & job persistence

Two stores, both under the app data dir (`QStandardPaths::AppDataLocation`,
on Android `/data/data/com.pufworks.pufmobile/files/`):

### 1. Machine / app settings — `QSettings` (org `PUFworks`, app `PUF-mobile`)
- **Saved by** the **Save Settings** button (top-right of the **Setup** hub) →
  `AppController::saveSettings()`. **Loaded once at startup** in `main()`
  (`controller.loadSettings()`), before QML binds, so the last setup auto-restores.
- Keys: `machine/` = implement width, implement offset, antenna height, section
  control, track name; `source/` = last source kind + UDP port, internal device/
  baud, CAN device/bitrate/tty baud, serial port/baud, BT MAC. The `start*()`
  methods record the params actually used so the connection screen can repopulate
  (exposed as `lastSource`, `canBitrate`, … read-only properties).
- **Layout** persists separately and automatically: `LayoutManager::save()` is
  called on every mutation (column visibility, active pages, element lists) and
  `LayoutManager::load()` runs at startup. Stored under the `layout/` group.

### 2. Coverage jobs — re-enterable per field (`JobStore`, exposed as `jobs`)
Self-describing, upload-ready layout (one folder per job):

```
<AppData>/jobs/<fieldId>/<jobId>/
    metadata.json     schema "puf-mobile.job" v1: client/farm/field ids+names,
                      created/modifiedUtc, areaHa, implement width/offset, antenna
                      height, GPS source, and the local-frame origin (lat/lon).
    coverage.geojson  FeatureCollection of LineString swaths in WGS84, each with a
                      width_m property.
<AppData>/jobs/<fieldId>/current.txt   names the active (resumable) jobId.
```

- **Why GeoJSON in WGS84:** the live coverage geometry lives in QML as local-metre
  polylines tied to the session origin, so it cannot be replayed verbatim next
  session. Saving in lat/lon (via `GpsModel::toGeo()`) makes it world-referenced
  and ready for a future upload/sync system. `metadata.json` is deliberately
  generic so a sync tool needs no app-internal knowledge.
- **Save flow** (`FieldView._coverageGeoJson()` → `jobs.saveJob(meta, geojson)`):
  freeze the open active chunks, convert every frozen stroke point to lat/lon,
  write `metadata.json` + `coverage.geojson`, and point `current.txt` at the job.
  Triggered automatically when **recording stops**, on **field switch** (the
  outgoing field is saved first), and by the **Save job** button (Work page).
- **Re-entry flow** (`FieldView.restoreActiveJob()`): on field activation (and at
  startup) `_syncActiveField()` checks `jobs.hasJob(fieldId)`; if present it pins
  the GPS origin to the saved `originLat/Lon` (`GpsModel::setOrigin()` — so stored
  coverage lines up with this session's fixes *and* renders even before the first
  live fix), clears the layer, rebuilds the swaths from the GeoJSON, and **replays
  each swath through `Coverage::mark()`** so the worked-area total and section-
  control `isCovered()` match what was recorded. **Start new job** (Work page)
  drops `current.txt` (the old folder is kept) and clears coverage.

**Wiring:** new `jobstore.{h,cpp}` added to `pufmobile.pro` and registered as the
`jobs` context property in `main.cpp`; `FarmStore` now exposes
`activeClientId/activeFarmId/activeFieldId`; `GpsModel` gains `setOrigin()`,
`toGeo()`, `originLat()/originLon()`.

**Limitations / user notes:**
- Re-entry sets the local origin to the job's saved origin. You're expected to be
  physically at that field; opening a field you're not at will draw stored coverage
  + the tractor relative to that origin (cosmetic mismatch only — area/section data
  is correct).
- Replay rebuilds cells from swath centrelines + width (heading inferred from
  consecutive points), so a resumed area can differ by well under a cell (0.5 m)
  from the original; live recording from then on is exact.
- The upload/sync *mechanism* is intentionally not built — only the local,
  documented store. Old jobs are never deleted automatically.

### 3. Job lifecycle, day-start Resume, New-Job flow, Rx (Work Data Pipeline, slice 1)

Implements `Plans/WorkDataPipeline/PLAN.md` §1 (day workflow), §2 (lifecycle), §5
(Rx ingestion — shapefile). **Local persistence only** — no home-server sync / no
ISOXML export in this pass.

**Job state machine + active job (`JobStore`, schema v2).** `metadata.json` now
carries `state` (`open` | `paused` | `complete`) and a `displayName` (application/
mix name + created date-time, matching the naming convention). A global
`<AppData>/jobs/active.txt` ("realFieldId⇥jobId") records the **last open job**
across all fields so it survives an app restart / unclean exit. New `JobStore` API:
- `activeJob()` → the last-open job meta (with fieldId/jobId injected), `{}` if none.
- `listAllJobs(limit)` → every job across all fields, newest first (the Resume list).
- `openJob(fieldId, jobId)` → point the field's `current.txt` at it, mark `open`,
  set the global active pointer (UI then activates the field to restore coverage).
- `setJobState(fieldId, jobId, state)`; `jobMetaById` / `loadCoverageById`.
- `saveJob()` defaults `state="open"` and updates the active pointer; a `complete`
  save releases it.

**Save-on-exit (closes the unclean-exit gap, §2).** `main.cpp` connects
`QGuiApplication::applicationStateChanged` (Inactive/Suspended) **and** `aboutToQuit`
to `jobs.requestSave()`, which drives `FieldView` (owner of the live coverage) to
write `metadata.json` + `coverage.geojson`. So backgrounding the app on Android or
quitting persists the active job + coverage.

**Day-start Resume popup (`ResumeJobPopup.qml`, §1/§A).** Shown ~0.5 s after launch
(and re-openable from the Work page → *Jobs / Resume…*). Top: the last open job with
a prominent **Resume**; below: a chronological list (most recent first); plus **Start
New Job**. Resume/tap → `jobs.openJob()` + `farm.setActiveField()`, which makes
`FieldView._syncActiveField()` restore that job's coverage/origin/application via the
already-hardened path.

**New-Job flow (`NewJobPopup.qml`, §1/§B).** Farm → Field → Product/Tank-mix, with a
**flat rate OR an Rx map**. On *Create job*: `setActiveField` → `requestNew` (fresh,
empty coverage) → `setApplication` (incl. rx descriptor) → `requestSave` (writes the
open job). Reuses `ListPicker`/`NumberPad`/`RxImportPopup`; builds the same
`application` map the Work page uses.

**Rx prescription rate (`rxmap.{h,cpp}`, exposed as `rx`; `RxImportPopup.qml`; §5).**
- **Shapefile ingest (priority):** a compact, dependency-free reader parses `.shp`
  polygons (types 5/15/25) + `.dbf` attributes (dBASE III), with an optional `.prj`
  read only to annotate CRS. **Assumes EPSG:4326 / lon-lat**; reprojecting a
  projected CRS is a TODO (flagged in `crsNote`).
- **Operator mapping:** the rate column name is not standardised and units are
  out-of-band, so the import UI lets the operator **pick the rate column** (from the
  `.dbf` fields, with sample values shown) and **pick the units**, plus
  **out-of-zone** and **no-GPS** fallback rates (mirrors the Gen4 workflow).
- **Live:** `rx.rateAt(lat,lon)` does point-in-polygon (even-odd ray cast, holes
  subtract; first matching zone wins, deterministic by record order). `FieldView`
  shows a live **target-rate pill** (Rx/flat; flags *out of zone* / *no GPS*) and
  **logs the target rate per worked chunk** into `coverage.geojson`
  (`target_rate` + `rate_unit` feature properties).
- **Stored with the job:** the chosen Rx descriptor (`file`, `column`, `unit`,
  `zoneCount`, `outOfZoneRate`, `noGpsRate`, `crs`) lives in `application.rx`;
  resuming reloads it via `rx.loadFromDescriptor()` (the source shapefile must remain
  on disk at its original path).
- **ISOXML Rx (TZN/GRD + PDV, DDI 1/6, VPN scaling): stubbed** — `RxMap::loadIsoxml()`
  returns false with a clear TODO; shapefile is the priority per the plan.
- **Actual-rate feedback:** there is **no rate-controller feedback** wired, so only
  the **target** rate is logged; `actual_rate` is intentionally omitted from the
  GeoJSON and is the documented future hardware hook.

**Wiring:** `rxmap.{h,cpp}` added to `pufmobile.pro`; `rx` registered in `main.cpp`;
new QML files registered in `qml.qrc`
(`ResumeJobPopup`, `NewJobPopup`, `RxImportPopup`). Work page (`WorkSetupPage.qml`)
gains a flat/Rx toggle, an Rx chooser, a *Complete job* button, and a *Jobs / Resume…*
launcher.

## CAN bitrate reference (from `PUFworks-isobus/JD_ISOBUS_MAP.md`)

- **250 kbps** = ISO 11783 implement bus / X119 connector — where StarFire (`SA 0x1C`)
  frames were captured. **Try this first.**
- **500 kbps / CAN-FD 2 Mbps** = JD proprietary buses (616R internal). slcan can't do
  CAN-FD. If 250k shows zero frames, try 500k classic before assuming FD.
- The **USB-serial baud (tty) is NOT the CAN bitrate.** Known-good CANable config
  here: CAN 250k, tty 2,000,000.

## On-tablet USB-CAN: status = blocked by hardware (Samsung tablet)

Implemented a full Android USB-host slcan path (`JdUsbCan.java` → localhost UDP →
`CanGpsSource` → `JdCanDecoder`), with an on-screen diagnostic report on the
Connection page (no adb needed). Findings on the Samsung test tablet with a
**CANable 2.0 isolated** (VID:PID `16D0:117E`, the same unit that works via python-can
`slcan` on a PC):

1. Device enumerates fine (CDC-ACM, `dc2 i0c2 i1c10`).
2. Android `claimInterface(force=true)` returns `true` but does NOT detach the kernel
   `cdc_acm` driver → every `UsbDeviceConnection` transfer returns `-1`.
3. Worked around it natively: `USBDEVFS_DISCONNECT` + `CLAIMINTERFACE` ioctls on the
   raw fd succeed (`det=0,0`), and all transfers moved onto raw `USBDEVFS_CONTROL` /
   `USBDEVFS_BULK` ioctls (Android's wrappers are unusable on this device).
4. Transfers then returned **EPROTO (`-71`)** on every endpoint incl. control ep0,
   and the device then dropped off the bus entirely (**ENODEV `-19`**) under load.
   That escalation = a **brownout**: the isolated CANable's DC-DC draws more than the
   tablet's OTG port supplies.

**Conclusion:** the software path is correct; the wall is electrical/power. Options:
a powered OTG hub / Y-cable (may fix the brownout), or — recommended — a **host
bridge** that keeps the CANable on mains-powered hardware and sends only NMEA to the
tablet: standalone `dist\gps_bridge.exe` / `dist\run_gps_bridge.bat` (Wi-Fi/UDP;
prefer this — no Python), or `bridge_to_tablet.ps1` / `bt_bridge.ps1` (Bluetooth, below).
Rebuild exe: `PUFworks-isobus\scripts\build_gps_bridge_exe.ps1`.

## Bluetooth (SPP/RFCOMM) GPS path

Same idea as the UDP bridge but over a direct Bluetooth serial link — no shared
Wi-Fi needed, and it's the basis for a future stand-alone appliance (Pi/Arduino).
The CANable runs on the host; only NMEA crosses Bluetooth.

- **Host** (`bt_gps_host.py`, launcher `bt_bridge.ps1`): reuses the field-validated
  `gps_bridge_lib` decoder (live CAN → `$GPGGA`/`$GPRMC`) and serves NMEA over either
  transport:
  - *Windows laptop:* pair the tablet + PC, then write NMEA to the paired **incoming
    Bluetooth COM port** via pyserial (`--bt-serial COM5`). Windows advertises SPP, so
    the tablet's UUID connect works. No PyBluez.
  - *Linux / Raspberry Pi:* a built-in BlueZ **RFCOMM server socket** on a fixed
    channel (`--channel 1`). No SDP record published, so the tablet uses its
    reflection channel-connect fallback. Make the adapter pairable first
    (`bluetoothctl discoverable on`) and pair once.
  - `--demo` emits synthetic motion so the BT link can be proven without the CANable.
- **Tablet** (`BtGps.java` → localhost UDP → `BtGpsSource` → model): a Bluetooth SPP
  client. `start()` tries `createRfcommSocketToServiceRecord(SPP)` first, then falls
  back to the hidden `createRfcommSocket(channel)` (for the Pi's no-SDP server). Read
  bytes are forwarded to `127.0.0.1:17627`; `BtGpsSource` splits them into `$`
  sentences and emits them (same Java→UDP pattern as USB-CAN, port 17626).
  - Also works with any **off-the-shelf SPP Bluetooth GPS** receiver.
  - Connection page: *Bluetooth GPS* row lists bonded devices
    (`AppController::refreshBtDevices()` → `BtGps.pairedDevices()`); pick + *Connect BT*.
  - Manifest: legacy `BLUETOOTH` + `BLUETOOTH_ADMIN` (install-time perms on API 23;
    no runtime prompt — `BLUETOOTH_CONNECT` is only needed at targetSdk ≥ 31).

### Tablet GPS (device's own GNSS via Android location services)

- **Tablet** (`TabletGps.java` → localhost UDP → `TabletGpsSource` → model): registers
  a `LocationManager` listener (`GPS_PROVIDER`, plus `NETWORK_PROVIDER` as a coarse
  cold-start fallback) on a `HandlerThread` looper. Each fix is sent to
  `127.0.0.1:17628` as `TGPS,lat,lon,alt,speedKmh,bearing,sats,hdop`. `TabletGpsSource`
  synthesises a `$PANDA` sentence (fix quality 1) from it and emits it — same Java→UDP
  pattern as USB-CAN (17626) and Bluetooth (17627).
  - **Heading** comes from the course-over-ground `bearing` (only valid while moving).
    There is **no TCM** (roll/pitch) from the tablet, so those `$PANDA` fields are left
    empty. **Sats** is read from `Location.getExtras()` `"satellites"` when the device
    populates it (best-effort); **HDOP** is not exposed by `android.location.Location`
    so it stays an honest blank.
  - **Permission:** targetSdk = 29 (≥ 23), so `ACCESS_FINE_LOCATION` is requested at
    runtime via `QtAndroid::requestPermissions` (in `TabletGpsSource::start`) before the
    Java listener is started; the prompt appears on first selection. Manifest carries
    `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION`.
  - Connection page: *Tablet GPS* row → *Use Tablet GPS*. It is an explicit menu choice
    and never auto-overrides a live UDP/StarFire feed; selecting another source (or
    *Stop*) tears it down (`removeUpdates` + looper quit).

### On-screen USB-CAN report fields (Connection page status line)

`VID:PID  dc# i#c# … data# in## out##  fd=N  det=a,b  claim=n/m  lc dtr C S5 O rd`
- `det=0,0` = kernel driver evicted + claimed natively.
- `lc/dtr` = CDC line-coding / DTR control transfers; `C/S5/O` = slcan write bytes;
  `rd` = test read. Negative values are `-errno` (`-71` EPROTO, `-19` ENODEV, …).
- `claim=2/2` = both interfaces claimed at the Java level.

## UI assets (icons + machine sprite)

**Icon font.** UI iconography uses Material Design Icons (Pictogrammers, Apache-2.0).
- `fonts/materialdesignicons-webfont.ttf` (v7.4.47) is embedded via `qml.qrc`.
- `main.qml` loads it once: `FontLoader { source: "qrc:/fonts/materialdesignicons-webfont.ttf" }`.
  The family name is the fixed string `"Material Design Icons"`, so any `Text` can
  render an icon by setting `font.family` to it — no need to pass the loader around.
- `Icons.js` (`.pragma library`) maps friendly names → glyphs. Codepoints are in the
  Supplementary PUA (> U+FFFF) so they are built with `String.fromCodePoint(0xF0XXX)`,
  not `\uXXXX`. To add an icon: find its name on pictogrammers.com, grab the
  `content: "\F0XXX"` value from `fonts/mdi.css`, add `var foo = _c(0xF0XXX);`.
- `MdiIcon.qml` is a thin `Text` that sets the family for you: `MdiIcon { icon: Icons.foo }`.
  For `Controls` `Button`s, set `text: Icons.foo; font.family: Icons.family` directly.

**Machine sprite.** The map machine (`Tractor.qml`) is a top-down HD render
`assets/sprayer_topdown.png` (transparent PNG), drawn with the cab/front at the item
TOP = GPS receiver = rotation pivot. It is sized off `width = 3 m * scale` and keeps
its native 623:1014 aspect. `sourceSize.width` caps the decode (the machine is small
on screen); `mipmap` keeps it crisp when scaled down.
- The working boom/sections are still drawn separately behind the machine, so the
  sprite intentionally has **no booms** (transport-folded booms would contradict the
  extended working boom).
- Future vehicle/implement customisation: swap the `Image.source` per a machine
  profile (e.g. tractor, SP sprayer, tractor+trailed) — keep the front-at-top,
  receiver-as-pivot convention so map maths is unchanged.

## Direct USB-CAN parity with the Wi-Fi bridge (field fix)

The on-tablet direct CANable path (`CanGpsSource` / `JdCanDecoder` in
`cangpssource.cpp`) is now a 1:1 port of `PUFworks-isobus/scripts/gps_bridge_lib.py`
so direct-plug output to `GpsModel` equals the Wi-Fi bridge's output (readouts AND
coverage).

- **Root cause of the divergence:** the direct decoder was missing the StarFire GNSS
  quality PGN — `0xFFFF` sub-message `0x51` (signature `51 03 02`, byte 3 =
  satellites-used, SA-gated to ATX `0x1C`) — that the bridge decodes
  (`decode_gnss_sats_ffff`). It also emitted **only `$PANDA`** while the bridge sends
  the full `GGA + RMC + VTG + PANDA` bundle. Position/heading/speed/pitch/roll/alt
  scaling and the slcan 250k config (`JdUsbCan.java`, `S5`) were already aligned.
- **Fix:** added the `0xFFFF/0x51` sats decode; `JdCanDecoder::bundle()` now renders
  the same four sentences the bridge sends (PANDA last so its attitude wins), with the
  satellite field populated; `handleToken()` emits the bundle paced on the `0xFEF3`
  position frame (decoder already holds the latest heading/speed/attitude/sats from
  the other PGNs by then). PANDA roll/pitch/yaw precision bumped to `.2f` to match.

## Delete jobs / tank-mix name / catalog manager (on-device fixes)

- `JobStore::deleteJob(fieldId, jobId)` removes the job folder
  (`metadata.json` + `coverage.geojson`), and first releases the global `active.txt`
  pointer + the field `current.txt` pointer if they referenced it (safe to delete the
  open/active job). Delete affordance (with confirm) added to `ResumeJobPopup`.
- `NewJobPopup` gained a full tank-mix builder (products + carrier + **Name**) so a
  mix can be created/named in the New Job flow and saved to `WorkCatalog`
  (`addTankMix`). WorkSetupPage already had a name field.
- `CatalogManagerPage.qml` (Setup hub → "Products & Mixes", `stack: 11`) views/edits/
  deletes tank mixes, products, crops and product types, backed by new `WorkCatalog`
  methods: `deleteProduct`, `updateProduct`, `deleteProductType`, `deleteTankMix`,
  `tankMixByName`, `deleteCrop`, `renameCrop`.

## Build gotchas

- Close the running app before rebuild (Windows/Android DLL/so locks; here it's the
  device — uninstall/replace).
- After moving the project, re-run `qmake` (the generated `Makefile` and
  `android-*-deployment-settings.json` carry absolute paths).
- **After adding/removing files in `qml.qrc`, re-run `qmake`** before `make`. The
  qmlcache loader expects a compiled unit per listed QML/JS file; a stale `Makefile`
  links without them → `undefined reference to ...::qmlData`.
- The icon lives at `android/res/drawable/icon.png` and is referenced by
  `android:icon="@drawable/icon"`; `androiddeployqt` merges `android/res` into the
  build.

## Open items

- Field-test the CAN→UDP bridge end to end on the 616R (expect `[gps]` log lines).
- Field-test the Bluetooth bridge (`bt_bridge.ps1` / `bt_gps_host.py`) on the 616R;
  prove the link first with `--demo`, then live CAN.
- Stand-alone appliance: package `bt_gps_host.py` on a Pi (BlueZ RFCOMM server) so the
  CANable + bridge run without a laptop.
- Powered-OTG-hub retest of the on-tablet USB-CAN path.
- Optional: gs_usb code path if a candleLight-firmware CANable is ever used.
- Optional one-tap auto-baud on the internal serial port.
- Build the upload/sync consumer for `<AppData>/jobs/` (metadata.json + GeoJSON
  are already laid down per job for this).
