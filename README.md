# PUF-mobile

Field-ready GPS guidance for Android tablets and phones, built for the **PUFworks**
spot-spraying program. Qt 5.15 LTS, heading-up map, coverage recording, farm/paddock
setup, and John Deere StarFire / 616R position via a UDP NMEA bridge.

Target hardware is a small **cab tablet fleet**:

| Device | Android | ABI | Role |
|---|---|---|---|
| Allwinner T3 workshop tablet | 6.0.1 (API 23) | `armeabi-v7a` | Legacy cab unit, GL ES 2.0 |
| Samsung SM-T545 | 11 (API 30) | `arm64-v8a` | Primary test / deploy tablet |

Both builds ship in one dual-ABI APK (`minSdk 23`, `targetSdk 29`). App id:
`com.pufworks.pufmobile`.

---

## What PUF-mobile is

PUF-mobile is the **cab-side guidance display** in the PUFworks stack. It:

- Parses NMEA-0183 (`GGA`/`RMC`/`VTG`/`HDT`) and AgOpenGPS `$PANDA`/`$PAOGI`
- Renders a **heading-up map** with tractor/implement, field boundaries, AB run lines,
  and worked-area coverage
- Persists **Client → Farm → Field** hierarchy locally (ISOXML `TASKDATA.XML`)
- Records coverage as GeoJSON per job under app-private storage
- Supports multiple GPS backends (internal serial, UDP, Bluetooth, tablet GNSS, USB-CAN)

It does **not** run vision inference or ISOBUS section actuation — those live in
`PUFworks-vision` and `PUFworks-isobus`. The tablet consumes position from the CAN
bridge and shows guidance; sprayer control stays on the bus engine path.

---

## Who PUFworks is

**PUFworks** is a workshop/field precision-ag program centred on Clare Downs equipment
and split across dedicated repos:

| Repo | Role |
|---|---|
| `PUFworks-vision` | Camera → Green-on-Brown → `SectionBitmapV1` |
| `PUFworks-isobus` | CAN/ISOBUS bus engine, GreenSeeker, safety ladder |
| `PUFworks-contracts` | IPC schemas (`SectionBitmapV1`, telemetry, etc.) |
| `PUFworks-shell` | Cab integrator (vision + isobus sidecars) |
| `PUF-mobile` | Android tablet/phone GPS guidance (this repo) |
| `AgValoniaGPS` | Desktop Gen4 shell + GPS bridge integration |

Live sprayer work is **Green-on-Brown only**; agronomy/GoG labelling is offline.
616R = GreenSeeker serial + whole-boom blanking (no CAN section injection).
Goldacres GRC = DDI 141 sections. Boot ISOBUS in `OBSERVE`; never bypass the
Control Authority ladder.

This repo is Windows-first, local workshop builds — no auto-updater, no public
distribution pipeline.

---

## How to use it

### Install

1. Build or obtain the debug APK (see **Build** below), or install from a GitHub
   Release if one is published.
2. Close any running copy of the app on the tablet, then install/replace the APK.
3. Open **Setup** and confirm the **Build** stamp (top-right) matches the build you
   deployed — e.g. `26Jun-tablet-setup-polish` on tablet layout, or the phone build
   id on phone layout. Mismatch means an old APK is still installed.

### GPS source

**Setup → GPS / Source** (tablet) or **GPS** tab (phone):

| Source | When to use |
|---|---|
| **UDP port 9999** | **Recommended for John Deere.** Run standalone
  `dist\run_gps_bridge.bat` (or `bridge_to_tablet.ps1`) on a laptop with the
  CANable; tablet listens on UDP 9999. |
| **Internal serial** | Tablet built-in GNSS on `/dev/ttyS0` @ 115200 (e.g. BT-770 antenna). |
| **Bluetooth GPS** | CAN→BT host (`bt_bridge.ps1` / `bt_gps_host.py`) or any SPP GPS. |
| **Tablet GPS** | Android location services (no TCM attitude). |
| **USB-CAN** | On-tablet CANable — blocked on some tablets by OTG power limits; prefer UDP. |

John Deere path (recommended):

```
CANable (slcan) → gps_bridge.exe on laptop → UDP NMEA → tablet :9999
```

**Standalone exe (no Python):** double-click `dist\run_gps_bridge.bat`, or:

```powershell
# rebuild after decoder changes
powershell -ExecutionPolicy Bypass -File C:\Projects\PUFworks-isobus\scripts\build_gps_bridge_exe.ps1

# run (edit COM / tablet IP in the bat, or pass args)
C:\Projects\PUF-mobile\dist\run_gps_bridge.bat COM2 192.168.1.59
```

Or via PowerShell (prefers the exe when present):

```powershell
cd C:\Projects\PUF-mobile
.\bridge_to_tablet.ps1 -TabletIp 192.168.1.59 -Com COM2
```

On tablet: **Setup → GPS → UDP port `9999` → Listen UDP**.

After changing bridge or implement settings, use **Setup → Save Settings** (top-right)
so width, offset, antenna height, and source params restore on next launch.

### Implement width and coverage

1. **Setup → Implement** — set **implement width** (m), **offset** (m behind GPS antenna),
   and section count if using section control.
2. **Setup → GPS Information** — set **antenna height** (m) for TCM terrain compensation
   when using `$PANDA` from the JD bridge.
3. On the map page, turn **Record coverage** on. Worked area accumulates as non-overlapping
   swaths tied to implement width.
4. **Work** page — create/resume jobs, flat or Rx rate, **Save job** / **Complete job**.
   Jobs persist under app-private `files/jobs/` (see **On-tablet storage** below).

### Setup hub

**Setup** tiles:

| Tile | Purpose |
|---|---|
| Paddock Setup | Client / farm / field hierarchy, boundaries, AB lines, import |
| Implement | Width, sections, offset |
| Layout | Pages, info columns, element visibility |
| GPS / Source | Connection and NMEA source selection |
| GPS Information | Fix, sats, HDOP, TCM roll/pitch, antenna height |
| Products & Mixes | Tank mixes, products, crops catalog |

Use **Save Settings** on the Setup hub after changing machine or GPS params.

---

## ISOXML / farm data import

**Do not commit farm or field data to this git repo.** Real paddock boundaries, client
names, and coordinates belong on the tablet or in Ops Center exports — not in source
control. See `.gitignore`.

### What the app reads

The app reads **unzipped ISOXML** — plain `TASKDATA.XML` and sibling files — **not**
a `.zip` archive directly. If John Deere / Ops Center gives you a zip, **extract it
first** on the tablet (or on a PC, then copy the folder).

`FarmStore::importIsoxml()` accepts either:

- A path to `TASKDATA.XML` itself, or
- A **folder** that contains `TASKDATA.XML` (or `TASKDATA/TASKDATA.XML`, or any
  immediate subfolder that nests the XML — typical JD export layout).

KML import (`.kml` file) creates **one paddock per polygon** into the **currently
selected farm**, named from the KML placemark. Select a farm before importing KML.

### Typical unzipped ISOXML layout

John Deere / AgGateway exports often look like:

```
MyExport/                    ← copy this whole folder to the tablet
  TASKDATA.XML               ← root-level (app finds this)
  …                          ← optional BIN/IMG/TIM sidecar files
```

Or nested:

```
MyExport/
  TASKDATA/
    TASKDATA.XML
    …
```

The app scans the import folder for `*.kml`, `*.xml`, and **subfolders** that contain
a `TASKDATA.XML`.

### Where to put files on the tablet

**Import scan folder** (Setup → Paddock Setup → **Scan**):

```
/storage/emulated/0/Download/Farm_data/
```

Copy `.kml` files or unzipped ISOXML **folders** here. Tap **Scan**, then **Import**
on the row you want.

**Persistent app storage** (after import or manual edits — not for git):

```
/data/data/com.pufworks.pufmobile/files/TASKDATA/TASKDATA.XML
```

This is where `FarmStore` loads/saves the active farm hierarchy. You normally reach it
via in-app import, not by hand; `adb run-as` is for debug builds only.

**Coverage jobs** (recorded work — also never commit):

```
/data/data/com.pufworks.pufmobile/files/jobs/<fieldId>/<jobId>/
  metadata.json
  coverage.geojson
```

### Copying from Ops Center / John Deere

1. Export Task Data / fields from **Operations Center** or Gen4 (ISOXML / TaskData zip).
2. **Unzip** on a PC or on the tablet (Files app → long-press zip → Extract).
3. Copy the extracted folder (or standalone `.kml`) to the tablet:
   - **Samsung (Android 11):** USB → `Internal storage/Download/Farm_data/`, or Wi-Fi
     FTP via `scripts/upload_tablet_ftp.ps1`.
   - **Allwinner (Android 6):** same `Download/Farm_data/` path; legacy external storage
     is enabled (`requestLegacyExternalStorage`) so the app can read non-media files
     in Download without a document picker.
4. In PUF-mobile: **Setup → Paddock Setup → Scan → Import** on the folder or KML row.
5. For KML: select **Client** and **Farm** first, then import.

The app uses `READ_EXTERNAL_STORAGE` for Download access on API 23–29. Grant storage
permission when prompted on first import.

### First run / empty install

With no farm data yet, create clients/farms/fields in **Paddock Setup**, or import
ISOXML/KML as above. A bundled seed copy is **not** shipped in this repo — operators
import their own TaskData export.

---

## GPS sources (reference)

| Backend | File | Platform | Use |
|---|---|---|---|
| Internal serial | `posixserialgpssource.cpp` | Android/Linux | Tablet GNSS on `/dev/ttyS0` @ 115200 |
| UDP listener | `udpgpssource.cpp` | All | **JD StarFire / 616R via CAN bridge**, port **9999** |
| USB-CAN (slcan) | `cangpssource.cpp` + `JdUsbCan.java` | Android | On-tablet CANable (power-limited on some tablets) |
| Bluetooth SPP | `btgpssource.cpp` + `BtGps.java` | Android | CAN→BT host or off-the-shelf BT GPS |
| Tablet GNSS | `tabletgpssource.cpp` + `TabletGps.java` | Android | Android `LocationManager` |
| QtSerialPort | `serialgpssource.cpp` | Desktop | PC COM-port testing |

Bridge scripts live beside this repo and call `PUFworks-isobus/scripts/gps_bridge.py`.

---

## Build (desktop tooling on Windows)

Prereqs: JDK 11, Android SDK (`platforms;android-23`, `build-tools;34.0.0`),
NDK `21.4.7075529`, Qt `5.15.2` (android).

```powershell
$env:JAVA_HOME='C:\Program Files\Microsoft\jdk-11.0.31.11-hotspot'
$env:ANDROID_SDK_ROOT='C:\Android\Sdk'
$env:ANDROID_NDK_ROOT='C:\Android\Sdk\ndk\21.4.7075529'
$env:ANDROID_NDK_HOME=$env:ANDROID_NDK_ROOT
$ndkMake='C:\Android\Sdk\ndk\21.4.7075529\prebuilt\windows-x86_64\bin\make.exe'

cd C:\Projects\PUF-mobile
C:\Qt\5.15.2\android\bin\qmake.exe pufmobile.pro -spec android-clang CONFIG+=qtquickcompiler
& $ndkMake -j4
& $ndkMake apk
```

Output: `android-build/build/outputs/apk/debug/android-build-debug.apk` (dual ABI,
v1+v2 signed). Staged copy may appear as `PUF-Mobile_v1.0.0.apk` at project root.

Close the running app on the tablet before reinstalling. After adding/removing QML in
`qml.qrc`, re-run `qmake` before `make`.

---

## Project layout

| Path | Contents |
|---|---|
| `*.cpp` / `*.h` | Model, GPS sources, coverage, `FarmStore`, `JobStore`, Rx map |
| `*.qml` / `*.js` | UI — map, Setup hub, phone shell, job popups |
| `android/` | Manifest, icon, `JdUsbCan.java`, `BtGps.java`, `TabletGps.java` |
| `bridge_to_tablet.ps1` | CAN→UDP bridge launcher |
| `bt_gps_host.py` / `bt_bridge.ps1` | CAN→Bluetooth host bridge |
| `scripts/` | Deploy, FTP upload, tablet job-data clear, GNSS probe |
| `DEV_NOTES.md` | Architecture, hardware findings, persistence detail |

---

## Related docs

- PUFworks workspace overview: `C:\Projects\AGENTS.md`
- ISOBUS / JD decisions: `PUFworks-isobus/JD_ISOBUS_MAP.md`
- Mobile dev notes: `DEV_NOTES.md`
