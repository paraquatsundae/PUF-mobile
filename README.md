# PUF-mobile

Lightweight, field-ready GPS / guidance display for Android tablets, built for the
PUFworks spot-spraying program. Runs on old, low-power cab tablets (target: Android
6.0.1 / API 23, 32-bit `armeabi-v7a`, OpenGL ES 2.0) using **Qt 5.15 LTS**.

It parses NMEA-0183 (`GGA`/`RMC`/`VTG`/`HDT`) and the AgOpenGPS `$PANDA`/`$PAOGI`
sentences and renders a heading-up map with the tractor/implement, coverage
("recording the work"), field boundaries, run (AB) lines, and a configurable
multi-page UI.

---

## Features

- **Heading-up navigation map** — centred tractor (rear GPS antenna at map centre),
  chase / top-down / whole-paddock perspectives, textured ground, sky + horizon,
  on-map zoom/centre controls.
- **Coverage mapping** — real, non-overlapping worked-area accumulation tied to the
  implement width, with a flat per-frame render cost (frozen + active chunk split).
- **Farm setup** — Client / Farm / Field hierarchy, local persistence (ISOXML
  `TASKDATA.XML`), KML import (one paddock per polygon, auto-named), boundaries and
  width-spaced run lines.
- **Configurable layout** — selectable left/right info columns, per-page column
  visibility, active-page cycle, persistent top banner + bottom soft keys.
- **Multiple GPS sources** (see below).

---

## GPS sources (`GpsSource` interface)

| Backend | File | Platform | Use |
|---|---|---|---|
| Internal serial (POSIX/termios) | `posixserialgpssource.cpp` | Android/Linux | Tablet's built-in GNSS (e.g. BT-770 antenna feed) on `/dev/ttyS0` @ 115200 |
| UDP listener | `udpgpssource.cpp` | All | **John Deere StarFire / 616R via the CAN bridge** (recommended), or any PC relay. Default port **9999** |
| USB-CAN (slcan, JD) | `cangpssource.cpp` + `android/src/org/qtproject/example/JdUsbCan.java` | Android | On-tablet CANable → JD `$PANDA`. Works only if the tablet's USB-host can drive the adapter (see DEV_NOTES) |
| Bluetooth GPS (SPP/RFCOMM) | `btgpssource.cpp` + `android/src/org/qtproject/example/BtGps.java` | Android | NMEA from a paired CAN→BT host (laptop/Pi running `bt_gps_host.py`) or any off-the-shelf Bluetooth GPS |
| QtSerialPort | `serialgpssource.cpp` | Desktop only | PC COM-port testing |

### Recommended JD path: the CAN → UDP bridge

The most reliable way to get John Deere GPS/TCM into the app is the companion
bridge, which reuses the field-validated PUFworks decoder
(`PUFworks-isobus/scripts/gps_bridge.py`):

```
CANable (slcan) → laptop/Pi running gps_bridge.py → UDP (NMEA) → tablet :9999
```

Run on a machine with the CANable plugged in, on the same Wi-Fi as the tablet:

```powershell
.\bridge_to_tablet.ps1 -TabletIp 192.168.1.50 -Com COM2
```

Then on the tablet: **Setup → GPS → UDP port `9999` → Listen UDP**. (Defaults:
CAN 250 kbps, USB-serial 2,000,000 baud; pass `-CanBitrate 500000` if "no data".)

### Alternative JD path: the CAN → Bluetooth bridge

When no shared Wi-Fi is available — or for a future stand-alone appliance (Pi /
Arduino) — the same decoder can serve NMEA over a direct Bluetooth serial link:

```
CANable (slcan) → laptop/Pi running bt_gps_host.py → Bluetooth (SPP) → tablet
```

Pair the host and tablet in Android Bluetooth settings first, then on a **Windows**
laptop (note the *Incoming* Bluetooth COM port under "More Bluetooth options"):

```powershell
.\bt_bridge.ps1 -Com COM3 -BtSerial COM5         # live CAN
.\bt_bridge.ps1 -BtSerial COM5 -Demo             # synthetic motion (no CANable)
```

On a **Raspberry Pi** (BlueZ RFCOMM server, channel 1):

```bash
sudo python3 bt_gps_host.py --interface /dev/ttyACM0 --bitrate 250000 --channel 1
```

Then on the tablet: **Setup → GPS → Bluetooth GPS → pick the host → Connect BT**.
(Needs `pip install python-can pyserial` on the host.) Also works with any SPP
Bluetooth GPS receiver.

---

## Build (desktop tooling on Windows)

Prereqs: JDK 11, Android SDK (platform-tools, `platforms;android-23`,
`build-tools;34.0.0`), NDK `21.4.7075529`, Qt `5.15.2` (android).

```powershell
$env:JAVA_HOME='C:\Program Files\Microsoft\jdk-11.0.31.11-hotspot'
$env:ANDROID_SDK_ROOT='C:\Android\Sdk'
$env:ANDROID_NDK_ROOT='C:\Android\Sdk\ndk\21.4.7075529'
$env:ANDROID_NDK_HOME=$env:ANDROID_NDK_ROOT
$ndkMake='C:\Android\Sdk\ndk\21.4.7075529\prebuilt\windows-x86_64\bin\make.exe'

cd C:\Projects\PUF-mobile
C:\Qt\5.15.2\android\bin\qmake.exe pufmobile.pro -spec android-clang CONFIG+=qtquickcompiler ANDROID_ABIS=armeabi-v7a
& $ndkMake -j4
& $ndkMake apk
```

Output APK: `android-build\build\outputs\apk\debug\android-build-debug.apk`
(minSdk 23, `armeabi-v7a`, v1+v2 signed). It is staged at the project root as
`PUF-Mobile_v1.0.0.apk`.

Close the running app on the tablet before reinstalling. The app installs as
`com.pufworks.pufmobile` (distinct from the old `gps-display` build).

---

## Project layout

- `*.cpp` / `*.h` — C++ model, controllers, GPS sources, coverage, farm/ISOXML store.
- `*.qml` / `*.js` — QML UI (pages, banners, map view, info columns).
- `android/` — `AndroidManifest.xml`, `res/drawable/icon.png` (app icon), and the
  `JdUsbCan.java` (USB-host) + `BtGps.java` (Bluetooth SPP) helpers.
- `bridge_to_tablet.ps1` — launcher for the CAN→UDP (Wi-Fi) bridge.
- `bt_gps_host.py` / `bt_bridge.ps1` — CAN→Bluetooth (SPP) host bridge (Windows + Pi).
- `scripts/` — dev helpers (e.g. `probe_tablet_gnss.ps1`).
- `DEV_NOTES.md` — architecture, decisions, and hardware findings.
