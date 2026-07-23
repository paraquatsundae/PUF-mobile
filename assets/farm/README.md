# Farm data (ISOXML)

## Tester / external builds

Shipped APKs seed from **`TASKDATA.EMPTY.xml`** — no paddocks on first launch.
Testers import their own farm via **SETUP → Paddock → Scan** (phone) or
**Setup → Paddock Setup → Farm Setup → Scan** (tablet).

### Where to put import files on the phone

Copy into either folder (the app scans both):

1. **`Download/Farm_data/`** (preferred — created automatically on Scan)
2. **`Download/`** (root — JD USB exports, emailed zips unzipped here)

Supported:

| Type | What to copy | Import behaviour |
|------|----------------|------------------|
| **ISOXML** | `TASKDATA.XML`, or a folder containing it (e.g. `TASKDATA/TASKDATA.XML`, or a JD export folder) | Adds clients/farms/fields from the file |
| **KML** | `.kml` polygon file | Adds paddocks into the **selected** farm |

ISOXML does **not** need Clare Downs or any bundled data. Each tester can use their own JD export or FMIS `TASKDATA` set.

### Workshop / Clare Downs dev seed (local only)

**Do not commit** real `TASKDATA.XML` to git.

For a local dev build with Clare Downs pre-loaded, place your copy at
`assets/farm/TASKDATA.XML`, add it to `qml.qrc`, and change
`seedBundledFarmIfEmpty()` to prefer `:/assets/farm/TASKDATA.XML` over
`TASKDATA.EMPTY.xml`. Tester builds should leave only `TASKDATA.EMPTY.xml` in the resource bundle.

### Resetting a test device

```powershell
# Jobs only (keeps imported paddocks):
.\scripts\clear_phone_appdata.ps1

# Full reset (paddocks + settings):
.\scripts\clear_phone_appdata.ps1 -All
```
