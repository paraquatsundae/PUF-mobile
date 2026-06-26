# Phone coverage paint — realign with FieldView

**Status:** In progress (Jun 2026)  
**Build tag:** `26Jun15:38-area-guard`

## Problem

Phone MAP diverged from tablet `FieldView.qml` during the phone port:

1. Original plan called for a "simplified renderer" instead of FieldView's chunk model.
2. Mali workarounds stacked: screen-space rectangles, global segment caps, cell fallback, double paint (screen + world).
3. Chase mode painted coverage **outside** the 74° tilt transform while the boom/ground are inside it — the same class of misalignment fixed on tablet in `DEV_NOTES.md` (boom in world space).

Symptoms: blocky green clusters, swaths offset from implement, width changes (3 m / 36 m) don't fix appearance. Area/cells correct; **paint architecture wrong**.

## Tablet model (authoritative)

| Layer | Paint | Space |
|-------|-------|-------|
| Frozen chunks (`doneStrokes`) | `Shape` + `PathPolyline`, `strokeWidth: section width` | World, inside tilt |
| Active chunks (`activeStrokes`) | Rectangle tessellation (`_activePaintSegs`) | World, inside tilt |
| Culling | `coverage.visibleChunks()` → max 300 in-view indices | Per chunk |

Recording: `coverage.mark()` + stroke `pts` in one GPS handler (`FieldView` inline; phone via `CoverageRecorder.qml`).

## Phone constraints (Samsung S911B)

| Approach | Result |
|----------|--------|
| Thick `Shape` stroke (boom width in world m) | Invisible on S911B (thin boundary `Shape` OK) |
| Screen-space coverage | Misaligned in chase tilt |
| Global rect cap across all chunks | Blob / gaps |
| Thousands of 0.5 m cell rects | HWUI crash |

## Target architecture

```
CoverageRecorder (shared record path — unchanged)
        ↓
PhoneMapView world layer (inside tiltContainer):
  ├─ done chunks  → Repeater model: _visChunks (viewport culled, max 300)
  │                 preferRectSwaths=true (S911B): per-chunk rect tessellation
  │                 preferRectSwaths=false: Shape/PathPolyline (tablet path, retest)
  ├─ active chunks → _activePaintSegs (world rects, coalesced 250 ms)
  └─ legacy cells  → only if doneCount==0 && cells>0 (0.5 m world rects, capped)

DELETE: screen-space coverage Repeater, _covScreenSegs, global _strokesForPaint cap
```

## Files

| File | Role |
|------|------|
| `PhoneMapView.qml` | Paint rewrite |
| `CoverageRecorder.qml` | Record path (already aligned) |
| `PhoneWorkSync.qml` | GeoJSON restore (already aligned) |
| `FieldView.qml` | Reference — do not fork paint logic again |

## Verification

1. SETUP → build ID `26Jun15:45-world-paint`
2. RECORD, drive 20 m at 3 m and 36 m width
3. Chase / Top / Paddock: solid green swath emerges from boom bar, same tilt as ground
4. Debug strip: `chunks:N` (visible frozen), `active:M` (live segs), no `scr:` screen count
5. `done>0` after freeze; `pts>0` while moving

## Future

If `preferRectSwaths=false` works on a future device/GPU driver, flip default. Otherwise add C++ `QQuickItem` stripe mesh for frozen chunks (one triangulation per freeze, like `Shape` internally).
