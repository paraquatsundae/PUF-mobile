# Automatic GPS Smoothing — PUF-mobile shared C++ core

**Status:** Implemented (Jun 2026) in the shared PUF-mobile C++ core. **Fully automatic** — no user-facing tuning knobs. Behaviour is driven by GPS accuracy tier (fix quality / HDOP) + ground speed + implement width.

**Why:** Consumer phone GNSS (and even SBAS) produces wobbly recorded coverage and erratic position/heading, especially at low speed / standstill. This stage smooths position and heading before coverage and the UI consume them, so worked swaths are cleaner and heading is steady — more so for wide booms, where a small heading error throws the boom tips a long way sideways.

> **Porting note (AgValoniaGPS .NET):** The cab app is a separate .NET codebase and is **not** touched here. This document is the spec to port the same algorithm + constants into AgValoniaGPS later. The algorithm is plain math (a 1€ filter + a unit-vector heading EMA); no Qt is involved, so it translates directly to C#.

---

## 1. Where it sits in the pipeline

```
raw NMEA / $PANDA / $PAOGI
        │  (parse → raw lat/lon, course-over-ground, speed, fixQuality, hdop)
        ▼
   GpsModel::feed()
        │  raw values stored in m_lat / m_lon / m_heading  (UNCHANGED — raw)
        │  raw-track logger appends the raw fix (if recording)  ── recordings/*.csv
        ▼
   GpsModel::updateLocal()
        │  raw lat/lon → raw ENU metres (equirectangular, vs first-fix origin)
        │              ┌──────────────────────────────────────────┐
        │   rawX,rawY  │  gpsfilter::GpsFilter (1€ position + EMA   │
        │  speed,dt ──►│  heading), tier-aware, width-aware        │──► filtered ENU + heading
        │   tier,width └──────────────────────────────────────────┘
        ▼
   canonical (filtered) values:
     latitude() / longitude()  → filtered (mirrored back from filtered ENU)
     headingDeg()              → filtered, track-derived
     localX() / localY()       → filtered ENU  (what coverage.mark consumes)
     rawLatitude()/rawLongitude()/rawHeadingDeg() → still available (logger)
```

**Files:**
- `gpsfilter.h` / `gpsfilter.cpp` — the filter itself. **Qt-free** (only `<cmath>`) so the offline harness compiles the exact same code.
- `gpsmodel.h` / `gpsmodel.cpp` — runs the filter inside `updateLocal()`, exposes filtered values as canonical, keeps raw values for the logger, owns the raw-track CSV logger.
- `appcontroller.cpp` — feeds implement width into the filter (`GpsModel::setImplementWidth`) and toggles the logger with coverage recording.

The filter runs on **local ENU metres**, not lat/lon, to avoid longitude-scaling issues and keep the tuning constants in metres/seconds.

---

## 2. Algorithm

### 2.1 Position — One Euro filter (1€)

The 1€ filter (Casiez, Roussel & Vogel, CHI 2012) is a low-pass whose cutoff rises with the signal's speed of change:

```
α(dt, fc) = 1 / (1 + τ/dt),   τ = 1 / (2π·fc)
dx̂        = lowpass(dx, α(dt, dcutoff))           // smoothed derivative
fc        = mincutoff + beta·|dx̂|                 // speed-adaptive cutoff
x̂         = lowpass(x,  α(dt, fc))                 // filtered output
```

Applied **independently to ENU x and y**. It is inherently speed-adaptive:
- **Slow / stationary:** `|dx̂|` ≈ 0 → cutoff ≈ `mincutoff` (low) → heavy smoothing → kills standstill drift.
- **Fast:** cutoff opens up via `beta` → light smoothing → low lag → boom/coverage alignment preserved.

### 2.2 Heading — derived from the smoothed track

Heading is the **bearing between consecutive filtered positions**, not raw course-over-ground:

- **Low-speed hold:** below `kHoldSpeedKmh` (0.8 km/h), freeze the last good heading (don't let it spin from position noise). Also requires a minimum filtered step `kMinStepM` (0.05 m) before a new bearing is taken.
- **Wraparound-safe EMA:** the bearing is smoothed as a **unit vector** (EMA on `sin`/`cos`, then `atan2`) so it crosses 360°/0° cleanly.
- **Width-scaled time constant:** `τ = τ_base(tier) + kWidth·width_m`, capped at `τ_max`. Rationale: lateral error at the boom tip ≈ `(width/2)·sin(heading_error)`, so **wider booms need steadier heading**.
- **Authoritative heading:** if a true heading (dual-antenna `$..HDT`) is present, it is trusted and only lightly EMA'd (phone GNSS never has this, so the track path is used).

Compass convention (matches `coverage.mark` / `recordingPoint`): `0° = north, 90° = east`, clockwise; bearing = `atan2(dEast, dNorth)`.

### 2.3 Tier mapping (`gpsfilter::tierFor`)

| Fix quality | HDOP | Tier | Filtering |
|-------------|------|------|-----------|
| 4 (RTK fixed), 5 (RTK float) | — | **RTK** | minimal (data already clean / 10 Hz) |
| 2 (DGPS), 3 (PPS) | — | **SBAS** | moderate |
| 1 (GPS/GNSS), 0/unknown | < 1.0 (valid) | **SBAS** | moderate |
| 1 (GPS/GNSS), 0/unknown | else | **GNSS** | aggressive (phone GNSS) |

> HDOP is usually blank on the StarFire tap (`hdopValid == false`), so a single-point fix defaults to the **GNSS** (aggressive) tier — correct for phone GNSS.

---

## 3. Constants (initial — tune offline, then update here)

All defined in `gpsfilter.cpp`. These are **starting points**; capture a real pass and tune with `tools/gps_replay` (see §5).

### One Euro position filter
| Tier | `mincutoff` (Hz) | `beta` |
|------|------------------|--------|
| RTK  | 5.00 | 0.50 |
| SBAS | 1.00 | 0.20 |
| GNSS | 0.30 | 0.05 |

`dcutoff = 1.0 Hz` (all tiers). Lower `mincutoff` = smoother when slow; higher `beta` = snappier (less lag) when moving.

### Heading EMA
| Tier | `τ_base` (s) |
|------|--------------|
| RTK  | 0.20 |
| SBAS | 0.40 |
| GNSS | 0.70 |

- `kWidth = 0.05 s per metre` → `τ = τ_base + 0.05·width_m`
- `τ_max = 3.0 s` (cap so steering never feels dead)
- `kHoldSpeedKmh = 0.8` (freeze heading below this)
- `kMinStepM = 0.05 m` (minimum filtered displacement to take a new bearing)

**Width examples (GNSS tier):** 6 m → τ ≈ 1.0 s · 12 m → τ ≈ 1.3 s · 24 m → τ ≈ 1.9 s · 36 m → τ ≈ 2.5 s (capped at 3.0 s by ~46 m).

### dt guards
- `dt` is computed from the wall-clock gap between fixes.
- Non-positive or > 1.0 s gaps (first fix, stream stall) are replaced by a nominal `0.1 s` so the filter stays stable.

---

## 4. Boom / coverage alignment (not regressed)

A recent fix records coverage at the boom **behind** the machine (`FieldView._recordPoint()` → `gps.localX/localY` offset back by `implementOffset` along `gps.headingDeg`). The smoothing must not add excessive **position lag** that would re-break that alignment.

- The 1€ filter is **light at working speed** (cutoff opens via `beta`), so position lag while driving is small (sub-decimetre at typical rates) — the recorded boom point still sits where the boom is.
- Heavy smoothing only kicks in at **low/zero speed**, where lag is irrelevant (the machine isn't laying a swath).
- Heading now comes from the **smoothed track**, which is *steadier* than raw COG, so the boom orientation (and thus the lateral position of each section centre) is **more** consistent, not less.
- `_recordPoint()` and `recordingPoint()` are unchanged in structure; they just consume the filtered `localX/localY` + `headingDeg` instead of raw. The offset-behind geometry is identical.

Net: alignment is preserved; the win is steadier heading + less position jitter feeding the same record geometry.

---

## 5. Capture + replay (offline tuning)

### 5.1 Capture a track (on device)

The raw-track logger turns on **automatically whenever coverage recording is on** (`AppController::setRecording` → `GpsModel::setRawLogging`).

1. Connect the GPS source (phone GNSS / `TabletGpsSource`) as usual.
2. Press **Record** and drive **one representative pass** (include a slow/stationary bit and some turns).
3. Press **Stop**. The raw fixes are written to:
   - **Android:** `Download/PUF-mobile/recordings/rawtrack_<yyyyMMdd_HHmmss>.csv`
   - **Desktop:** `<Downloads>/PUF-mobile/recordings/rawtrack_*.csv`
4. Pull it to the dev host, e.g.:
   ```powershell
   adb pull /sdcard/Download/PUF-mobile/recordings C:\Projects\PUF-mobile\recordings
   ```

CSV columns: `timestamp,raw_lat,raw_lon,raw_heading,raw_speed,fix_quality,hdop` (timestamp = epoch ms; header row written automatically). `recordings/` is gitignored.

### 5.2 Run the replay harness (on the host, Windows)

```powershell
cd C:\Projects\PUF-mobile\tools\gps_replay
qmake
"C:\Android\Sdk\ndk\21.4.7075529\prebuilt\windows-x86_64\bin\make.exe"   # or nmake / jom / mingw32-make
gps_replay ..\..\recordings\rawtrack_YYYYMMDD_HHMMSS.csv 24
```

(or, with any host compiler, no qmake:
`g++ -std=c++17 -O2 -I..\.. replay.cpp ..\..\gpsfilter.cpp -o gps_replay`)

Arguments: `gps_replay <input.csv> [width_m] [output.csv]` (width defaults to 24 m; output defaults to `<input>_filtered.csv`).

It writes a filtered CSV (`raw_*` vs `filt_*` lat/lon/heading + ENU + tier per row) and prints wobble metrics:

```
position jitter (mean 2nd-diff, m):  raw 0.0421 -> filt 0.0093  (77.9% smoother)
heading wobble  (RMS step, deg):      raw 6.812 -> filt 1.244   (81.7% smoother)
```

### 5.3 Tuning loop

The harness compiles **the same `gpsfilter.cpp`** the phone runs. To A/B constants: edit the tier constants in `gpsfilter.cpp`, rebuild `gps_replay`, re-run on the same capture, and compare the wobble metrics + plot the `filt_lat/filt_lon` track. When happy, the phone build picks up the identical constants automatically (shared file). Update §3 of this doc with the chosen numbers.

---

## 6. Quick reference for the .NET port

- One Euro filter: standard, ~30 lines; port `gpsfilter::OneEuro` verbatim.
- Run it on local ENU metres (you already keep a local frame in AgValoniaGPS); seed origin from the first fix.
- Heading = EMA (sin/cos) of `atan2(dEast, dNorth)` between filtered points, with the low-speed hold + width-scaled τ.
- Tier from fix quality / HDOP exactly as `tierFor`.
- Use the constants in §3 as the starting point; re-tune against a cab capture with the same metric definitions (§5.2).
