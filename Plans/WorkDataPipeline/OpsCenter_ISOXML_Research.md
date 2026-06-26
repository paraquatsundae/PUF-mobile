# Operations Center ISOXML / Rx Research — Findings

**Scope:** Move agricultural work data in/out of John Deere Operations Center (JDOC) **without API access** (manual file upload only), and ingest prescription (Rx) maps for the PUF-mobile parallel implement (spreader / spot-sprayer). PUF-mobile must (a) export its own **as-applied** to JDOC via manual upload and (b) ingest **Rx maps** as files.

**Date:** 2026-06-23. Sources are current JD Operations Center / Gen4 display help docs, ISO 11783‑10 references (isobus.net, isoxml.tools, dev4Agriculture, agrirouter), and reputable precision-ag sources (2024–2026). Local PUFworks/AGGPS reference material cited where relevant.

> Research/findings document only. No application code. A sibling `PLAN.md` in this folder was authored by another agent — this file does not modify it; it supplies the format-sensitive inputs `PLAN.md` defers to (its §4, §5, §7).

---

## Executive summary

- **The supported no‑API on‑ramp is the JDOC web `Files` tool** (`Tools → Files → Upload`), which accepts a **zipped ISOXML `TASKDATA` set** and **zipped ESRI shapefile** sets. Web upload cap is **100 MB per compressed file**; larger goes through the **John Deere Data Manager** desktop app. JDOC ingests ISOXML from mixed fleets including **as‑applied/documentation**, not just setup — but the documentation path is **more fragile** than setup. ([Files upload + 100 MB + Data Manager](https://talk.newagtalk.com/forums/thread-view.asp?mid=7415850&tid=844957); [How to upload (JD video)](https://www.youtube.com/watch?v=9k9Nm7K3_4Q); [mixed-fleet ISOXML](https://www.futurefarming.com/smart-farming/tools-data/john-deere-offers-data-transfer-for-mixed-fleets/))
- **ISOXML version matters.** Current ISO 11783‑10 is **V4 (4.x)**, but many terminals/importers only fully digest **V3.3**, and there are documented field cases of imports rejected solely because `VersionMajor="4"` (fix = edit to `"3"`). A **V3.3** set is the safest lowest‑common‑denominator to emit. ([dev4Agriculture: "terminal says no"](https://dev4agriculture.de/terminal-says-no-first-aid-for-isoxml-imports/); [PIX4D community: rejected unless V3](https://community.pix4d.com/t/isoxml-3-support/30008))
- **Most common import failures:** wrong **folder/filename casing** (`TASKDATA.XML`, uppercase, inside a `TASKDATA` folder at the zip root); **missing binary payload** (`.BIN`/`GRD*.BIN`/`TLG*.BIN`) so XML loads but the map is empty; **schema‑invalid attributes / out‑of‑range values / unknown or proprietary elements**; and a **broken device model** (the `DLV → DET → DOR → DPD → DVP` chain) so as‑applied can't be resolved to a layer. ([dev4Agriculture](https://dev4agriculture.de/terminal-says-no-first-aid-for-isoxml-imports/); [farming forum: missing .BIN](https://thefarmingforum.co.uk/index.php?threads/iso-xml.216466/); [isoxml.tools heatmaps](https://isoxml.tools/docs/heatmaps/common-ddi/))
- **Rx comes in two shapes we must read:** (1) **ESRI shapefile** (`.shp/.shx/.dbf/.prj`, **WGS84 geographic, EPSG:4326, unprojected**) where the rate lives in a **DBF attribute column** whose name is *not standardized* (`rate`, `rateInt`, `Tgt_Rate`, `Target_Rate`, etc.) and **units are out‑of‑band** (operator picks them at load time); and (2) **ISOXML prescription** where rate is carried in **`TZN` treatment zones** (or a **grid**) via **`PDV`** values, identified by **DDI** (setpoint volume/area = **DDI 1**, setpoint mass/area = **DDI 6**) and scaled by a **`VPN`** value presentation. ([PIX4D shapefile columns + EPSG:4326](https://support.pix4d.com/hc/en-us/articles/360038644731); [Gen4 rate-column mapping](https://progressivecrops.com/wp-content/uploads/2024/01/Loading-Prescriptions-into-John-Deere-Gen-4-Displays.pdf); [VPN vs DVP](https://isoxml.tools/docs/convert-raw-isoxml-values-vpn-vs-dvp/); [DDI dictionary](https://www.isobus.net/isobus/exports/completeTXT))
- **The most reliable manual route into JDOC is via a JD display (USB → Gen4 4640 / G5, then JDLink / Auto‑Sync).** Gen4/G5 send work data to JDOC **every ~30 s** over JDLink, and the display's importer is the same engine the cab uses. **But this only moves the display's own documentation** — it will **not** carry a third‑party tablet's as‑applied unless that data was recorded *through* the JD display. ([Data Sync ~30 s](https://www.deere.com/en/technology-products/precision-ag-technology/data-management/data-sync/); [Gen4 File Manager import](https://displaysimulator.deere.com/onscreen_help/4640/current/en/file_manager/file_manager_import_data.htm))
- **Highest‑risk items to test early with a real upload:** does JDOC accept our **documentation/as‑applied ISOXML** and surface it in Field Analyzer (not just store the zip in Files); whether our **DDIs + device/DDOP description** are honored end‑to‑end; whether the **TLG binary + paired XML header** parse cleanly. Treat these as must‑verify; the rest is well‑grounded.

---

## A. Getting data INTO Ops Center via manual upload (no API)

### A1. What the web import accepts (documentation + setup)

- **Two upload mechanisms, no API needed:**
  - **`Files` web tool** (`Tools → Files`, "Upload a file") — drag‑and‑drop **`.zip`** archives. This is the primary no‑API on‑ramp. ([newagtalk: Files upload steps](https://talk.newagtalk.com/forums/thread-view.asp?mid=7415850&tid=844957))
  - **John Deere Data Manager** (free Windows desktop app) — used for **larger datasets / >100 MB** and for bulk USB→cloud transfer. ([JD how-to video transcript](https://www.youtube.com/watch?v=9k9Nm7K3_4Q))
- **Accepted formats for our purposes:**
  - **ISO 11783‑10 ISOXML `TASKDATA`** (zipped). Entry point inside the zip is `TASKDATA.XML`, which references every other resource. JDOC supports ISOXML from mixed fleets — **work orders, application maps, as‑applied, and yield maps** are all in scope of the format. ([agrirouter TaskData spec](https://agrirouter.com/en/docs/message-types/taskdata); [mixed-fleet ISOXML](https://www.futurefarming.com/smart-farming/tools-data/john-deere-offers-data-transfer-for-mixed-fleets/))
  - **ESRI shapefile** (zipped) — used for **boundaries** and **prescriptions**. A boundary shapefile zip must contain `*.shp`, `*.shx`, `*.dbf`, `*.prj` (some known sources accepted without `.prj`). ([newagtalk: shapefile components](https://talk.newagtalk.com/forums/thread-view.asp?mid=7415850&tid=844957))
- **Setup vs documentation:** JDOC's mixed-fleet ISOXML support explicitly covers **field documentation** coming back from displays, and partners (GeoPard, SatAgro, PIX4D) push **prescriptions/setup** in as Files. So both setup import **and** as‑applied/documentation import are officially supported routes — with the documentation route being the pickier of the two (see A3). ([GeoPard export to JDOC](https://docs.geopard.tech/geopard-tutorials/product-tour-web-app/export-download); [SatAgro JDOC integration](https://satagro.net/help/data-import-export/))

### A2. Required ISOXML bundle structure, zipping, filenames, size

Canonical `TASKDATA.zip` layout (ISO 11783‑10), from isoxml.tools and the standard ([isoxml.tools TASKDATA structure](https://isoxml.tools/docs/fundamentals/taskdata-xml/); [isoxml.tools get-started](https://isoxml.tools/docs/get-started/)):

```
TASKDATA.zip
└── TASKDATA/                 ← folder at zip root (terminals expect this)
    ├── TASKDATA.XML          ← main descriptor (UPPERCASE name)
    ├── LINKLIST.XML          ← optional, V4 only (maps internal IDs ↔ external keys)
    ├── TLG00001.XML          ← time-log header (one per time log; defines DDIs/columns)
    ├── TLG00001.BIN          ← time-log binary (the actual recorded rows)
    ├── GRD00001.BIN          ← grid binary (variable-rate grid cell values), if grid Rx
    └── [other referenced XML/BIN]
```

- **Root element** of `TASKDATA.XML` is `<ISO11783_TaskData>` carrying `VersionMajor` / `VersionMinor`, `ManagementSoftwareManufacturer/Version`, and **`DataTransferOrigin`**: `1` = FMIS→machine (planned / application map), **`2` = machine→FMIS (recorded / as‑applied)**. For our as‑applied export, **`DataTransferOrigin="2"`**. ([isoxml.tools TASKDATA structure](https://isoxml.tools/docs/fundamentals/taskdata-xml/))
- **Time logs (as‑applied):** each `TLG#####` is a **pair** — a `.XML` **header** that declares which DDIs are logged and how to parse each binary row, plus a `.BIN` with the compact rows (GPS + sensor values, changed-column deltas). A `TASKDATA.XML` `TSK` references its `TLG` by filename. Missing/empty `.BIN` = XML loads but no data. ([isoxml.tools structure](https://isoxml.tools/docs/fundamentals/taskdata-xml/); [farming forum: missing .BIN](https://thefarmingforum.co.uk/index.php?threads/iso-xml.216466/))
- **Grids (Rx):** a `GRD#####.BIN` holds grid cell values; **there is no separate grid header** — the `GRD` element inside `TASKDATA.XML` defines grid origin, cell size, rows/cols and the per-cell layout. ([isoxml.tools structure](https://isoxml.tools/docs/fundamentals/taskdata-xml/))
- **`LINKLIST.XML`** (V4 only, uppercase) relates XML element object IDs to external key values; referenced from `TASKDATA.XML` via an `AFE` (AttachedFile) element; at most one per dataset. Not required for a basic as‑applied export. ([ISO 11783-10 Annex E](http://www.igreen-projekt.de/download/dvd/pdf/ISO11783-10_AFE_And_Annex_E.pdf))
- **Zipping conventions:** zip so that the **`TASKDATA` folder (or `TASKDATA.XML`) is at/near the zip root**, not buried under extra parent folders. **Filenames are case‑sensitive to strict importers** — `TASKDATA.XML`, `TLG#####`, `GRD#####`, `LINKLIST.XML` should all be uppercase. ([dev4Agriculture](https://dev4agriculture.de/terminal-says-no-first-aid-for-isoxml-imports/))
- **Size limit:** **100 MB per compressed file** via `Files`; over that, use **Data Manager**. ([newagtalk](https://talk.newagtalk.com/forums/thread-view.asp?mid=7415850&tid=844957); [JD video](https://www.youtube.com/watch?v=9k9Nm7K3_4Q))

### A3. Known caveats / why imports fail or partially import

Ranked by how often they bite (synthesized from dev4Agriculture, farming forum, PIX4D community):

1. **Wrong folder / filename casing.** File dropped loose on USB, or named `TaskData.xml`. Fix: `TASKDATA/TASKDATA.XML` exactly. ([dev4Agriculture](https://dev4agriculture.de/terminal-says-no-first-aid-for-isoxml-imports/))
2. **Version rejection.** Importer wants V3.3; a `VersionMajor="4"` file is refused (documented fault e.g. `TD.505 "Task data version not version 3"`). Workaround in the field is literally editing `VersionMajor` 4→3. **Emit V3.3 to avoid this.** ([PIX4D community](https://community.pix4d.com/t/isoxml-3-support/30008))
3. **Missing binary payload.** XML present, `.BIN`/`GRD*.BIN`/`TLG*.BIN` missing → task appears but map/rate is empty. ([farming forum](https://thefarmingforum.co.uk/index.php?threads/iso-xml.216466/))
4. **Schema‑invalid / out‑of‑range attributes or unknown elements.** A TaskController/importer chokes on an attribute out of range or an element it doesn't recognize. Run **XSD schema validation** (e.g. against `ISO11783_TaskFile_V3-3.xsd`) before shipping. ([dev4Agriculture](https://dev4agriculture.de/terminal-says-no-first-aid-for-isoxml-imports/); [V3.3 XSD](https://www.isobus.net/isobus/attachments/files/ISO11783_TaskFile_V3-3.xsd))
5. **Proprietary `P###_` / vendor extension elements.** Strict importers can reject vendor-specific extensions. Keep the emitted set to standard elements.
6. **Broken device model for as‑applied.** A recorded `DLV` (data-log value) only becomes a readable layer when the chain resolves: `DLV.C → DET` (device element) `→ DOR → DPD` (`DPD.B` matches the `DLV` DDI) `→ DVP` (scaling/unit). If the `DVC/DET/DPD/DVP` model is incomplete, the as‑applied won't map even though the file "imports." ([isoxml.tools heatmaps](https://isoxml.tools/docs/heatmaps/common-ddi/))
7. **JDOC-specific quirk:** setup files that contain **only run pages** show as *invalid* in JDOC; and field names >20 chars get shortened on re-import to a display (matched back by ID). Not blockers for as‑applied, but illustrate JDOC normalizes/validates aggressively. ([Gen4 File Manager import help](https://displaysimulator.deere.com/onscreen_help/4640/current/en/file_manager/file_manager_import_data.htm))

**Is as‑applied (documentation) more fragile than setup?** Yes. Setup (fields/boundaries/guidance) is mostly geometry + names and imports reliably; **as‑applied requires the full device-model + time-log chain to be valid AND the DDIs to be ones JDOC recognizes**, which is where partial/empty imports happen. Plan to verify the documentation path explicitly.

### A4. The alternate route: USB → Gen4 (4640 / G5) → JDLink sync

- **How:** put the `TASKDATA` set on a USB stick (`TASKDATA/` at root; prescriptions in an `Rx/` folder at root), import via the display **File Manager → Import from USB Drive**, then the display **auto-syncs work data to JDOC every ~30 s** over JDLink (MTG cellular, 4640 built-in Wi‑Fi, or wireless USB adapter). ([Gen4 import help](https://displaysimulator.deere.com/onscreen_help/4640/current/en/file_manager/file_manager_import_data.htm); [Data Sync ~30 s](https://www.deere.com/en/technology-products/precision-ag-technology/data-management/data-sync/))
- **Is it more reliable?** For data that the **display itself recorded**, yes — it's the native engine and the round-trip is well-trodden. For **importing our externally-authored ISOXML *through* the display**, it is **not obviously more forgiving than the web import** — the display importer is, if anything, *stricter* about version/structure (it's the source of the V3-only rejections above). Its advantage is mainly the **automatic, low-friction cloud sync** once data is on the display.
- **Constraints:** 25.3+ software cannot import the **Legacy System** format (old 4600 V1 / GS3 2630 / Apex) — those must go to JDOC first and be re-created as Current-System setup files. Interior boundaries require an exterior boundary present. AutoTrac engaged blocks setup import. Requires JDLink + an established JDOC org for the auto-sync. ([Gen4 import help](https://displaysimulator.deere.com/onscreen_help/4640/current/en/file_manager/file_manager_import_data.htm))

---

## B. Rx prescription export formats we must ingest

### B1. How JDOC / tools export prescriptions (shapefile vs ISOXML)

- **Shapefile** is the most broadly compatible export and the one to support first. Component files: **`.shp` (geometry), `.shx` (index), `.dbf` (attributes/rates), `.prj` (CRS)** — zipped together. ([newagtalk components](https://talk.newagtalk.com/forums/thread-view.asp?mid=7415850&tid=844957))
- **CRS / projection:** prescription shapefiles are **geographic lat/lon, WGS84 datum, EPSG:4326 (unprojected)**. Don't assume a projected CRS; read `.prj` and reproject if present, but expect 4326. ([PIX4D: EPSG:4326](https://support.pix4d.com/hc/en-us/articles/360038644731))
- **Rate attribute / column naming (NOT standardized):** PIX4D's exporter, for example, writes four columns: **`rate`** (decimal), **`rateInt`** (integer), **`unit`** (units string), **`zone`** (zone id). Other tools use `Tgt_Rate`, `Target_Rate`, `Rx`, `VRA`, etc. On the **Gen4 display the operator must manually pick the "Rate Column" and "Rate Column Units"** at load time — proof that names/units are not fixed and not always carried in-band. ([PIX4D columns](https://support.pix4d.com/hc/en-us/articles/360038644731); [Gen4 rate-column mapping](https://progressivecrops.com/wp-content/uploads/2024/01/Loading-Prescriptions-into-John-Deere-Gen-4-Displays.pdf); [Koenig Gen4 setup](https://support.koenigequipment.com/how-to-set-up-field-variety-and-prescription-on-the-john-deere-gen-4-display))
- **Zone vs grid:** shapefile prescriptions are typically **polygon zones** (one row per management zone; PIX4D notes 1–7 zones common, terminals may cap polygon count). ISOXML can carry either **treatment zones (`TZN`)** or a **raster grid (`GRD`)**. ([PIX4D zones](https://support.pix4d.com/hc/en-us/articles/360038644731))
- **For loading onto a JD display via USB,** shapefiles must be in a folder named **`Rx`** at the USB root. ([Gen4 import help](https://displaysimulator.deere.com/onscreen_help/4640/current/en/file_manager/file_manager_import_data.htm))

### B2. ISOXML prescription structure (as exported by JDOC + FMIS/agronomy tools)

- A prescription is a **`TSK`** (task) with `DataTransferOrigin="1"` containing either:
  - **Treatment zones:** one or more **`TZN`** elements (each a polygon + a `TreatmentZoneCode`), each carrying a **`PDV`** (ProcessDataVariable) with the rate; plus `DefaultTreatmentZoneCode` / `OutOfFieldTreatmentZoneCode` / `PositionLostTreatmentZoneCode` fallbacks; **or**
  - **Grid:** a **`GRD`** element (origin, cell size, rows/cols) whose `GRD#####.BIN` stores per-cell zone codes / values. ([V3.3 XSD elements](https://www.isobus.net/isobus/attachments/files/ISO11783_TaskFile_V3-3.xsd); [isoxml.tools prescription maps](https://isoxml.tools/docs/))
- **Rate DDIs (the key bit):**
  | DDI | Hex | Meaning | Unit (raw) | Resolution |
  |-----|-----|---------|------------|-----------|
  | **1** | `0x0001` | **Setpoint Volume per Area** application rate | mm³/m² | 0.01 |
  | **6** | `0x0006` | **Setpoint Mass per Area** application rate | mg/m² | 1 |
  | 2 | `0x0002` | Actual Volume per Area (recorded) | mm³/m² | 0.01 |
  | 7 | `0x0007` | Actual Mass per Area (recorded) | mg/m² | 0.01 |
  | 21 | `0x0015` | Setpoint Volume per Volume | mm³/m³ | 1 |

  Setpoint DDIs (1/6) are the **prescription** side; actual DDIs (2/7) are what we **record** for as‑applied. ([ISOBUS DD dictionary](https://www.isobus.net/isobus/exports/completeTXT))
- **Value scaling — `VPN` (task side) vs `DVP` (device side):** prescription/`PDV` values are raw integers presented via a **`VPN`** (`ValuePresentation`: offset, scale, decimals, unit). Example: `PDV B="2500" E="VPN1"` with `VPN1` scale `0.01`, unit `l/ha` → **25.00 l/ha**. **Recorded** device values (`DLV`) instead use the device's **`DVP`**. Don't cross them. ([VPN vs DVP](https://isoxml.tools/docs/convert-raw-isoxml-values-vpn-vs-dvp/))
- **Product linkage:** a `PDV` can reference a `Product` (`PDT`) / `ProductGroup` (`PGP`) and a `DeviceElement`; multi-product prescriptions carry multiple `PDV`s per zone. ([V3.3 XSD](https://www.isobus.net/isobus/attachments/files/ISO11783_TaskFile_V3-3.xsd))
- **Tool reality:** GeoPard exports an ISOXML `.zip` containing **all three ISOXML variants** and tells the user to pick the one matching their monitor — concrete evidence that version compatibility is a real consumer concern. SatAgro/PIX4D offer shapefile + ISOXML side by side. ([GeoPard export](https://docs.geopard.tech/geopard-tutorials/product-tour-web-app/export-download); [SatAgro](https://satagro.net/help/data-import-export/); [PIX4D](https://support.pix4d.com/hc/en-us/articles/360038644731))

### B3. Practical gotchas for a consumer app reading these

1. **CRS:** expect **EPSG:4326** for shapefiles, but read `.prj` defensively and reproject; handle a **missing `.prj`** (assume WGS84 lat/lon). ([PIX4D](https://support.pix4d.com/hc/en-us/articles/360038644731))
2. **Attribute name variability:** never hard-code the rate column. Detect among `rate`/`rateInt`/`Tgt_Rate`/`Target_Rate`/`Rx`/`VRA`/… and **let the operator confirm/override** the rate column and **units** at load (mirrors the Gen4 workflow). ([Gen4 rate-column](https://progressivecrops.com/wp-content/uploads/2024/01/Loading-Prescriptions-into-John-Deere-Gen-4-Displays.pdf))
3. **Units are often out-of-band** in shapefiles — provide an explicit unit picker and define **No-GPS-rate** and **Out-of-zone-rate** fallbacks (JD does exactly this). ([Koenig](https://support.koenigequipment.com/how-to-set-up-field-variety-and-prescription-on-the-john-deere-gen-4-display))
4. **Multi-product Rx:** a zone may carry several rates/products; pick by product, don't assume single-rate.
5. **ISOXML scaling:** always apply `VPN` offset/scale/decimals — `PDV.B` is **not** the final value.
6. **Zone count / polygon caps:** some terminals cap polygons; large grids vs few zones differ a lot in size/behavior.
7. **Geometry hygiene:** zones can have holes/overlaps; need a robust point-in-zone lookup (and a deterministic tie-break for overlaps) for the live GPS→rate lookup.

---

## C. JD Gen4 wireless transfer (lighter touch)

- **Two distinct wireless flows, both via JDLink/MTG (or 4640 Wi‑Fi / wireless USB adapter):**
  - **Machine → wireless (work data up):** Gen4/G5 **send work data to JDOC every ~30 s** automatically ("Enable Sync to Operations Center"); buffered on the display when offline and flushed on reconnect. This is **as‑applied/documentation going up**. ([Data Sync ~30 s](https://www.deere.com/en/technology-products/precision-ag-technology/data-management/data-sync/); [Gen4 Data Sync help](https://displaysimulator.deere.com/onscreen_help/4640/current/en/file_manager/file_manager_data_sync.htm))
  - **Wireless → machine (setup down):** **Data Sync Setup** keeps fields, boundaries, flags, guidance lines in near-real-time sync JDOC↔displays; **Setup File Creator** (JDOC web) builds setup/work files to send wirelessly to specific equipment **or** download for USB. ([Data Sync](https://www.deere.com/en/technology-products/precision-ag-technology/data-management/data-sync/); [Setup File Creator / Data Sync](https://support.koenigequipment.com/data-sync-setup-in-operations-center))
- **What Data Sync does NOT cover:** **prescriptions** and **AutoPath** files are **excluded** from Data Sync and still need file transfer (USB or Setup File Creator). Also, work-data auto-send carries only Client/Farm/Field attached to the work — products, boundaries, guidance need Data Sync Setup or a push. ([Koenig: Rx/AutoPath excluded](https://support.koenigequipment.com/data-sync-setup-in-operations-center); [newagtalk practitioner note](https://talk.newagtalk.com/forums/thread-view.asp?mid=10597774&tid=1146486))
- **Crucial scope limit for PUF-mobile:** wireless transfer moves **the JD display's own data only**. It will **not** pick up a third-party tablet's recordings. PUF-mobile cannot "wirelessly" inject its as‑applied this way unless that data was first recorded *through* a JD display (e.g. a certified ISOBUS TC‑BAS client, or a sanctioned serial path the display documents). For our parallel implement, the realistic no‑API paths remain **(1) web `Files` upload of our own `TASKDATA.zip`** and **(2) USB → Gen4 import → auto-sync.**

---

## Implications for PUF-mobile (concrete recommendations)

**As‑applied export — what to emit:**
1. **Emit ISOXML `TASKDATA` at `VersionMajor="3" VersionMinor="3"`** (V3.3) as the default; treat V4 as opt-in later. This dodges the single most common hard rejection. ([PIX4D community](https://community.pix4d.com/t/isoxml-3-support/30008))
2. **Set `DataTransferOrigin="2"`** on the dataset (machine→FMIS / recorded). ([isoxml.tools](https://isoxml.tools/docs/fundamentals/taskdata-xml/))
3. **Bundle structure:** `TASKDATA.zip` containing a top-level `TASKDATA/` folder with **`TASKDATA.XML`** + **paired `TLG#####.XML` header and `TLG#####.BIN`** time logs. All filenames **UPPERCASE**. Keep each zip **< 100 MB** (split by job/field if needed). ([isoxml.tools structure](https://isoxml.tools/docs/fundamentals/taskdata-xml/); [size limit](https://talk.newagtalk.com/forums/thread-view.asp?mid=7415850&tid=844957))
4. **Record the right DDIs:** as a parallel spreader/spot-sprayer, log **actual application rate** — **DDI 7 (mass/area, e.g. kg/ha) for granular spreading**, **DDI 2 (volume/area, e.g. L/ha) for liquid**; include working width, work state (on/off), and position. Provide a complete **device model** (`DVC` + `DET` + `DPD` with `DPD.B` = the logged DDI + `DVP` scale/unit) so JDOC can resolve the layer. ([DD dictionary](https://www.isobus.net/isobus/exports/completeTXT); [device-model chain](https://isoxml.tools/docs/heatmaps/common-ddi/))
5. **Carry Client/Farm/Field + Product + Worker** so JDOC files the operation against the right field automatically (and so a later USB→Gen4 round-trip matches by ID).
6. **Validate against the V3.3 XSD** in CI before any upload (`ISO11783_TaskFile_V3-3.xsd`). ([XSD](https://www.isobus.net/isobus/attachments/files/ISO11783_TaskFile_V3-3.xsd))

**Zip/bundle conventions:** one job (or one field-day) per `TASKDATA.zip`; `TASKDATA/` at the archive root (not nested under extra folders); uppercase names; UTF‑8 XML; no proprietary `P###_` elements.

**Rx ingestion — order of support:**
1. **Shapefile first** (`.shp/.shx/.dbf/.prj`, EPSG:4326). It's the most universal JDOC/agronomy export and matches the JD display workflow. Build: read `.prj` (default WGS84), **operator-selectable rate column + units**, polygon-zone point lookup, No-GPS / out-of-zone fallback rates.
2. **ISOXML prescription second** (`TZN`/`GRD` + `PDV`/DDI 1 or 6 + `VPN` scaling, product linkage). Reuse the same internal "zoned rate surface" the shapefile path produces.
3. Keep PUF-mobile a **consumer only** (per `PLAN.md` §5) — parse, map to field, look up rate by GPS, command, log target-vs-actual.

**Reuse an existing ISOXML library rather than hand-rolling:** the AGGPS bundle already vendors **`Dev4Agriculture.ISO11783.ISOXML.dll`** (`C:\Projects\General_files\AGGPS\Dev4Agriculture.ISO11783.ISOXML.dll`) — the dev4Agriculture .NET ISOXML reader/writer/validator. PUF-mobile is Qt/C++ (per `PLAN.md`), so it can't link this directly, but it's a known-good **reference implementation and validation oracle** for round-tripping our emitted `TASKDATA.zip` on the desktop/home-server before upload. (dev4Agriculture also authors the "terminal says no" guidance cited above.)

**Highest-risk validation items to test early (real upload):**
1. **Does our as‑applied actually surface in Field Analyzer / map layers in JDOC** — not merely sit as a stored zip in `Files`? (The documentation path is the fragile one.)
2. **Are our DDIs + device model honored** so rate/coverage render with correct units?
3. **Do TLG `.BIN` + header parse** (column order, scaling) when JDOC ingests them?
4. **V3.3 acceptance** by both JDOC web import **and** a Gen4/G5 import (the stricter consumer).
5. **Shapefile rate-column/units round-trip** for the Rx we ingest (and a multi-zone case).

---

## Confidence / unknowns

**High confidence (well-sourced, consistent across independent sources):**
- Web `Files` upload accepts zipped ISOXML `TASKDATA` and zipped shapefiles; **100 MB** cap; Data Manager for larger.
- ISOXML bundle structure (`TASKDATA.XML` + `TLG` pair + `GRD` + optional V4 `LINKLIST`), casing requirements, and the V3‑vs‑V4 rejection pattern.
- Shapefile components, EPSG:4326, non-standardized rate column, out-of-band units, operator-mapped rate column on Gen4.
- DDIs 1/6 (setpoint) and 2/7 (actual) and the `VPN`/`DVP` scaling model.
- Gen4/G5 ~30 s wireless work-data sync; Data Sync excludes Rx/AutoPath; wireless moves the display's own data only.

**Needs a real test upload to confirm (treat as assumptions until verified):**
- **Whether JDOC fully ingests third-party as‑applied ISOXML into agronomic layers** (vs storing the zip) — JD docs confirm the *format* is supported but don't guarantee every DDI/device-model shape renders. **This is the #1 thing to prove.**
- **Exact JDOC-accepted ISOXML version ceiling** (does current JDOC happily take V4, or is V3.3 still safest end-to-end including a Gen4 round-trip?). Default to V3.3 until tested.
- **Precise JDOC error/normalization behavior** for our specific device model and DDI choices (units, resolution, work-state encoding).
- **Whether any `.prj`-less or non-4326 Rx** from a given partner needs special handling in practice.
- **TLG binary edge cases** (changed-column delta encoding, time/position record specifics) — verify against the dev4Agriculture library output and a real JDOC import.

---

## Local references checked

- `C:\Projects\General_files\AGGPS\Dev4Agriculture.ISO11783.ISOXML.dll` — vendored dev4Agriculture **.NET ISOXML** reader/writer/validator (AgOpenGPS dependency). Best local round-trip/validation oracle.
- `C:\Projects\PUFworks-isobus\JD_ISOBUS_MAP.md` — confirms **TC‑BAS = "Task totals, as‑applied documentation, ISO‑XML export to FMIS / Operations Center"**, and flags JDOC import shape as an **open item** ("Research JDOC import spec before building converter", §14.7). Also documents DDI usage on the live bus (DDI 141 sections, 157/158 rate) — bus-side, not file-side, but consistent on DDI semantics.
- `C:\Projects\PUFworks-isobus\library\JD_THIRD_PARTY_SOFTWARE.md` — display stack inventory (GDAL/Fiona/Shapely/shapelib/proj/pyproj, libxml2/lxml/xerces, sqlite, protobuf) confirming JD's GIS/XML import lives in a standard GIS+XML stack (shapefile + ISOXML are first-class on the display).
- `C:\Projects\General_files\Information\` — present but **empty / no readable files** at scan time (no JD screenshots found there in this run).
- A vendored Gen4 manual was **not** found under `AgValoniaGPS-develop/.../External/`; that folder mirrors the PUFworks-isobus docs only.
