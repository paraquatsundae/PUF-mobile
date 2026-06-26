# PUF-mobile — Work Data Pipeline

**Status: DRAFT for user review.** This is a planning/architecture document only — it
records the decisions and open questions from the work-data design workshop. **No
application code is described as built here**; treat it as a durable reference for
future implementation.

Scope: how PUF-mobile captures work (spraying/spreading) data for its **own parallel
implement**, makes that capture power-cut resilient, syncs it to a home server,
ingests prescription (Rx) maps, and exports as-applied data to John Deere Operations
Center.

> **Operating context.** PUF-mobile is an Android tablet app (Qt 5.15 / QML + C++) for
> guidance + section/rate control + work recording, built for a workshop/local-first
> operation (no public distribution). It frequently runs **in parallel** with a John
> Deere system — e.g. a spreader on the back of a sprayer, or a separate lightweight
> spot-spray line. PUF-mobile controls and documents **its own** parallel implement
> while the JD system handles the sprayer.

> **Companion research (complete).** The Ops Center ISOXML import rules and Rx export
> format specifics have been researched and are captured in the companion file
> **`OpsCenter_ISOXML_Research.md`** (same folder), which is the **detailed
> source-of-record**. Its concrete, validated findings are folded into the
> format-sensitive sections below (§4, §5, §7) so this plan is self-contained; consult
> the research file for full citations, the failure-cause ranking, and confidence/
> unknowns. Where this plan still says "validate with a real upload", that is the
> research's explicit recommendation, not an unresolved gap.

---

## 1. Day workflow / UX

**Status: decided** (layout/flow), with in-cab control specifics to be refined during
implementation.

- **Launch → Resume popup.** On app launch, show a resume dialog:
  - **Top:** the last open job, with a prominent **"Resume"** action.
  - **Below:** a chronological, clearly-named list of recent jobs.
  - Plus a **"Start New Job"** action.
- **New Job flow:** **Farm → Field → Product / Tank-mix selection.**
- **Product step:** choose **Single Product** *or* **Tank Mix**. Rate is either a
  **flat rate** *or* an **Rx** (prescription map, see §5).
- **Auto-generated job names** (product + date/time) so the chronological list stays
  clean without typing. The **full timestamp** is kept in metadata regardless of the
  display name.
- **In-cab ergonomics:**
  - Glove-friendly touch targets; sunlight-readable contrast.
  - **Persistent bottom banner** for record / section control / run line / pause.
  - **Any action taken while moving must be a single tap on a permanent control** — no
    multi-step dialogs while the machine is in motion.

---

## 2. Job lifecycle & persistence

**Status: decided.**

- **Explicit job state machine**, persisted:

```
create → record → pause/resume → complete → export
```

- **"Active job" + save-on-exit.** The last open job is always recoverable (this
  closes previously identified gaps where an unclean exit could lose the active job).
  Builds on the existing `JobStore` + `current.txt` active-job pointer (see
  `DEV_NOTES.md` → "Settings & job persistence").
- **Jobs recorded per paddock**, giving a comprehensive **paddock history** over time.

---

## 3. Data capture & power-cut resilience

**Status: decided (key requirement).**

This is the integrity backbone. The goal is that a power cut (cab power loss, tablet
yank, battery pull) **never** yields a corrupt or partially-written as-applied record,
and loses at most a few seconds of work.

- **Full-resolution, continuous recording.** Record at full as-applied detail. The
  cadence rules below are about *when bytes hit disk and get sealed* — **not** about
  downsampling. We keep full resolution.
- **Append-only journal with atomic writes.** Each write is: **write temp file →
  `fsync` → atomic rename**. The **atomic rename is the real defense** — it guarantees
  that any file ever observed (and therefore ever persisted or uploaded) is whole,
  never torn/half-written. A power cut mid-write leaves the temp file, not a corrupt
  record.
- **Flush ≤ 30 s.** Force data to durable storage at least every 30 seconds, so a
  power cut loses **at most ~30 s** of capture.
- **Seal a chunk every 3 min.** Every 3 minutes, seal an atomic chunk and **queue it
  for upload** (see §4).
- **5-min overlapping local checkpoint.** Keep a rolling 5-minute **overlapping**
  checkpoint snapshot **locally** as an integrity/repair backstop. It is **not
  uploaded**; its purpose is to **detect and heal a corrupt 3-min chunk from its
  neighbor** (the overlap is what makes a torn chunk recoverable).

> Relationship to today's store: the current per-job `coverage.geojson` is written on
> stop / field-switch / explicit save. The journal/chunk model above is the continuous,
> crash-safe layer that feeds those job artifacts; exact on-disk layout (journal +
> sealed chunks + checkpoint) is an implementation detail to design when this phase
> starts.

---

## 4. Sync architecture

**Status: decided** for the tablet↔server roles and the Ops Center workaround;
**open** for the server stack / transport (see §8).

- **Tablet = offline-first capture client.** It must fully function with no
  connectivity and never block on the network.
- **Home server = farm "system of record" / hub.** It holds jobs + Rx maps, serves all
  connected units, and stages Ops Center upload bundles.
  - Multi-unit / multi-user shared access is a **future workshop** — **out of scope
    here** (noted in §8).
- **Tablet → home server:** **near-live when connected** (Starlink / cellular is often
  available in the paddock), with an **offline queue** that flushes on reconnect. The
  sealed 3-min chunks (§3) are the natural unit to ship.
- **Home server → JD Operations Center (JDOC):** **no direct API.** JD API access is
  not attainable for this app. The validated no-API on-ramp:
  - **JDOC web `Files` tool** (`Tools → Files → Upload`): **drag-drop** a **zipped
    ISOXML `TASKDATA`** set or a **zipped shapefile** set. **~100 MB cap per zip**;
    anything larger goes through the free **John Deere Data Manager** desktop app
    (Windows). Split bundles per job / field-day to stay under the cap.
  - ⚠️ **IMPORTANT correction — the USB → Gen4/G5 → JDLink path does NOT carry our
    data.** That display auto-sync (work data to JDOC every ~30 s) only moves the
    **display's *own* recorded documentation**, **not** a third-party tablet's
    as-applied unless it was recorded *through* the JD display. **So the JDOC web
    `Files` upload is THE path for PUF-mobile's as-applied** — don't mis-read USB→Gen4
    as a working route for our recordings. (USB→Gen4 is still useful for *setup*
    geometry, and the display importer is, if anything, *stricter* than the web import.)
  - Also note: **JD Data Sync excludes prescriptions / AutoPath** — those always move
    as files, never via wireless Data Sync.
  - ⚠️ **JDOC ISOXML import is format/version-picky, and as-applied/documentation
    import is more fragile than setup import.** A **real test upload must confirm the
    data actually *renders* in JDOC (Field Analyzer / agronomic layers)** — not merely
    that the zip stores in `Files` (see §9 and the Validation-first tasks note). Exact
    format spec is in §7; full detail in `OpsCenter_ISOXML_Research.md`.

```
Tablet (offline-first capture)
   │  near-live + offline queue (sealed chunks)
   ▼
Home server (system of record / hub) ── stages bundles ──► TASKDATA.zip (<100 MB)
                                                              │ manual drag-drop
                                                              ▼
                                  JD Operations Center → Tools → Files → Upload
                                  (Data Manager desktop app if >100 MB)

   NOTE: USB → Gen4/G5 → JDLink auto-sync moves the DISPLAY'S OWN data only —
         NOT our tablet's as-applied. Web Files upload is our path.
```

---

## 5. Rx (prescription) ingestion

**Status: decided** for the role and formats; **open** for the live control-loop
specifics (see §8).

- **Consumer only, never a creator.** PUF-mobile ingests Rx maps; it does **not** author
  them. **JD's own Rx workflow is unchanged.**
- **Ingestion path:** Rx maps are exported from Ops Center (or other Rx software),
  landed on the laptop / PC / home server, then **synced to the tablet** (same channel
  as §4, server → tablet direction).
- **Support order — shapefile FIRST, then ISOXML** (shapefile is the most universal
  JDOC / agronomy export and matches the JD display workflow):
  1. **Shapefile** (`.shp` / `.shx` / `.dbf` / `.prj`, zipped):
     - **CRS** is **typically EPSG:4326** (geographic WGS84, unprojected). Read `.prj`
       defensively and reproject if present; **assume WGS84 if `.prj` is missing**.
     - **Rate attribute / column name is NOT standardized** — e.g. `rate`, `rateInt`,
       `Tgt_Rate`, `Target_Rate`, `Rx`, `VRA`, etc. — and **units are out-of-band**.
       So the **operator must map the rate column + its units on import** (mirrors the
       Gen4 "Rate Column / Rate Column Units" workflow). Never hard-code the column.
     - Typically **polygon management zones** (one row per zone). Provide explicit
       **No-GPS-rate** and **out-of-zone-rate** fallbacks.
  2. **ISOXML prescription** (reuse the same internal "zoned rate surface"):
     - Rate carried in **`TZN` (treatment zones)** *or* **`GRD` (grid)** + **`PDV`**
       (ProcessDataVariable) values.
     - **Setpoint DDIs:** **DDI 1 = setpoint volume/area** (liquid), **DDI 6 = setpoint
       mass/area** (granular). Apply **`VPN`** (ValuePresentation) **offset/scale/
       decimals** scaling — `PDV.B` is a raw integer, **not** the final rate.
- **Ingestion gotchas to handle** (full detail in the research file):
  - **CRS** — expect 4326 but handle `.prj`-less / reprojected sources.
  - **Attribute-name variability** — operator-confirmed column mapping.
  - **Rate units** — out-of-band; explicit unit picker.
  - **Multi-product prescriptions** — a zone may carry several rates/products; pick by
    product, don't assume single-rate.
- **Live behavior:**
  1. Map the Rx to the field.
  2. Look up the rate by **GPS position** for the parallel implement (robust
     point-in-zone lookup with a deterministic tie-break for overlaps).
  3. **Command the rate** to the implement's rate controller.
  4. **Log target vs actual** rate (this is what gets exported in §7).

---

## 6. System-of-record separation

**Status: decided.**

- PUF-mobile documents **its parallel implement's** as-applied data.
- The **JD / Goldacres GRC** system documents the **sprayer**.
- Because the two systems cover **different products / implements on the same pass**,
  there is **no double-recording conflict**. PUF-mobile is cleanly the **system of
  record for its own implement**, and the JD system remains the system of record for
  the sprayer.

---

## 7. Export to JD Operations Center

**Status: decided** on content + route; **export format = decided (pending real-upload
validation)** — the spec below is research-validated but must be confirmed to *render*
in JDOC, not just store (see §9 / Validation-first tasks).

- **Export content** — ISOXML `TASKDATA` with **TLG time logs**, carrying:
  - As-applied **target vs actual rate**
  - **Coverage**, **area**, **timestamps**
  - **Product**, **operator**, **field**

### Export format spec to emit

- **ISOXML V3.3** — `VersionMajor="3"` (V3.3). This is the safe lowest-common-
  denominator; **V4 (`VersionMajor="4"`) is a documented hard-rejection cause** on many
  importers. Treat V4 as opt-in later.
- **`DataTransferOrigin="2"`** (machine → FMIS / recorded as-applied).
- **Bundle layout:** a **`TASKDATA/` folder at the zip root**, containing **UPPERCASE
  `TASKDATA.XML`** plus **paired `TLG#####.XML` (header) + `TLG#####.BIN` (binary
  rows)** time logs. Keep each zip **< 100 MB** (split per job / field-day).

```
TASKDATA.zip
└── TASKDATA/              ← folder at zip root
    ├── TASKDATA.XML       ← UPPERCASE main descriptor (V3.3, DataTransferOrigin=2)
    ├── TLG00001.XML       ← time-log header (declares logged DDIs + row layout)
    └── TLG00001.BIN       ← time-log binary (the recorded rows) — REQUIRED, not empty
```

- **DDIs to log:** actual application rate — **DDI 2 (volume/area)** for liquid,
  **DDI 7 (mass/area)** for granular spreading — plus working width, work state, and
  position. Provide a complete **device model** so JDOC can resolve the layer.
- **Top failure causes to avoid** (ranked in the research file):
  1. **Wrong filename casing** (must be `TASKDATA/TASKDATA.XML`, all uppercase).
  2. **V4 rejection** (emit V3.3).
  3. **Missing `.BIN` payload** (XML loads but the map/rate is empty).
  4. **Schema-invalid / out-of-range / proprietary (`P###_`) elements** (validate
     against the V3.3 XSD; keep to standard elements).
  5. **Broken device-model chain** — `DLV → DET → DPD → DVP` must resolve, or the
     as-applied won't map even though the file "imports".

### Upload route + validation

- **Manual upload** as in §4: **JDOC web `Files` upload** of our `TASKDATA.zip` is THE
  path (Data Manager desktop app for >100 MB). **USB → Gen4 does NOT carry our
  as-applied** (see §4 correction).
- **As-applied / documentation import is more fragile than setup import.** A **real
  test upload must confirm the data actually renders in JDOC Field Analyzer /
  agronomic layers — not just that the zip stores in `Files`.**
- **Local validation oracle:** `General_files\AGGPS\Dev4Agriculture.ISO11783.ISOXML.dll`
  (the vendored dev4Agriculture .NET ISOXML reader/writer/validator) can serve as a
  **desktop / home-server round-trip + validation oracle** for our `TASKDATA.zip`
  before any upload. PUF-mobile is Qt/C++ so it can't link the DLL directly, but it is
  a known-good reference implementation to check our output against.

> **Implementation gap:** today's `taskdata.{h,cpp}` reads/writes ISOXML for farms /
> fields / boundaries / run lines but **has no TLG writer yet**. Adding the paired
> TLG header + `.BIN` writer, the device model, and the `TASKDATA.zip` packager is the
> new work for this phase.

---

## 8. Open questions / future workshops

*(Listed, not solved.)*

- **Multi-unit / multi-user shared jobs** via the home server.
- **JD Gen4 "wireless to machine / machine to wireless"** transfer — now characterized
  in the research (Data Sync moves the **display's own** data only, every ~30 s, and
  **excludes Rx / AutoPath**; it will **not** carry our tablet's recordings). Remaining
  open: whether any sanctioned path could ever let our data ride the display sync.
- **Home server software stack + transport protocol** — HTTP POST vs network share vs
  a sync queue. To be decided.
- **Security / auth** for tablet ↔ server (and any cloud touchpoints).
- **Rx control-loop specifics** — the rate-controller interface for the parallel
  implement.
- **GPS diagnostics over USB-CAN** — porting StarFire PGN decode from the Wi-Fi bridge
  (a separate active thread; see `DEV_NOTES.md`).

---

## 8a. Validation-first tasks (must be proven with a REAL upload)

The research is well-grounded on format, but several end-to-end behaviors **cannot be
assumed** — they must be confirmed with an actual JDOC upload (and a Gen4 round-trip)
before we trust the export pipeline. These are the highest-risk items; prove them
early (they gate §9 phase 4).

1. **As-applied actually renders** — our documentation/as-applied ISOXML surfaces in
   **JDOC Field Analyzer / agronomic layers**, not merely sits as a stored zip in
   `Files`. *(This is the #1 thing to prove — the documentation path is the fragile
   one.)*
2. **V3.3 acceptance both ways** — accepted by **JDOC web import** *and* by a **Gen4/G5
   import round-trip** (the stricter consumer).
3. **DDIs + device model honored** — rate/coverage render with **correct units** end to
   end (the `DLV → DET → DPD → DVP` chain resolves).
4. **TLG `.BIN` + header parse cleanly** — column order / scaling / changed-column
   delta encoding ingest correctly (cross-check against the dev4Agriculture DLL
   output).
5. **Shapefile rate-column / units round-trip** — including a multi-zone (and
   multi-product) case for Rx ingestion (§5).

---

## 9. Implementation phasing (proposed)

High-level suggested order — each phase is independently useful and de-risks the next.

1. **Job lifecycle + persistence + Resume UX.** State machine, active-job /
   save-on-exit, the launch Resume popup, and the Farm → Field → Product new-job flow.
2. **Journaling / atomic capture.** Append-only journal, atomic temp+fsync+rename,
   ≤ 30 s flush, 3-min sealed chunks, 5-min local checkpoint backstop.
3. **Tablet → server sync.** Offline-first queue + near-live upload of sealed chunks to
   the home server.
4. **ISOXML export + Ops Center validation.** TLG as-applied writer (V3.3,
   `DataTransferOrigin=2`, device model), `TASKDATA.zip` packaging, **round-trip via the
   dev4Agriculture DLL oracle**, then an **early real `Files` upload** to JDOC to prove
   the data *renders* (the §8a Validation-first tasks).
5. **Rx ingestion + live rate.** **Shapefile first, then ISOXML** Rx parsing (operator
   column/units mapping; `VPN` scaling), server → tablet sync, GPS-position rate
   lookup, command + target-vs-actual logging.

---

## References

- `DEV_NOTES.md` — current persistence (`JobStore`, `metadata.json` +
  `coverage.geojson`, `current.txt` active-job pointer), ISOXML `TASKDATA.XML`
  read/write, KML import, GPS sources.
- `README.md` — app overview, GPS source matrix, build.
- `OpsCenter_ISOXML_Research.md` *(companion, same folder — **detailed
  source-of-record**)* — full JDOC import rules, ISOXML bundle structure, failure-cause
  ranking, Rx shapefile/ISOXML specifics, citations, and confidence/unknowns. Informs
  §4, §5, §7, §8a.
- `General_files\AGGPS\Dev4Agriculture.ISO11783.ISOXML.dll` — vendored dev4Agriculture
  .NET ISOXML reader/writer/validator; **local round-trip / validation oracle** for our
  `TASKDATA.zip` before upload.
- Workspace `AGENTS.md` / `PUFworks-isobus/JD_ISOBUS_MAP.md` — broader PUFworks
  platform context.
