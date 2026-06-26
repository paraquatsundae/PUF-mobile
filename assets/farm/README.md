# Bundled farm data (ISOXML)

**Do not commit real `TASKDATA.XML` or KML paddock files to git.**

For first-run seeding, a local-only copy may be placed here as
`assets/farm/TASKDATA.XML` and listed in `qml.qrc`. The app copies it into
`<AppData>/TASKDATA/TASKDATA.XML` when storage is empty (`seedBundledFarmIfEmpty`).

Normal operator workflow: import unzipped ISOXML or KML from
`/storage/emulated/0/Download/QtAgGPS/` via **Setup → Paddock Setup → Scan**.
