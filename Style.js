.pragma library

// Central palette + helpers. Imported as:  import "Style.js" as Style
var bg        = "#0e1714";  // app background
var banner    = "#0b1310";  // top/bottom banners
var bannerHi  = "#13201b";  // banner button hover/active
var panel     = "#16241f";  // cards / panels
var panelEdge = "#23362f";
var accent    = "#3ddc84";  // brand green
var textDim   = "#9fb4ac";
var white      = "#ffffff";

// Navigation field (higher contrast sky vs ground)
var skyTop    = "#3f93d6";  // deeper blue up high
var sky       = "#bfe2f6";  // pale blue at horizon
var ground    = "#bcc3bd";  // light grey ground
var groundEdge= "#cdd3ce";
var gridMinor = "#a6ada7";  // fine grid
var gridMajor = "#838d85";  // N/S/E/W cardinal axes (different shade)
var cardinal  = "#525d55";  // N/S/E/W labels
var horizon   = "#3c4850";  // crisp horizon line

function fixColor(q, stale) {
    if (stale || q === 0) return "#c0392b";   // red: no/stale fix
    if (q === 4) return "#2ecc71";            // RTK fixed: bright green
    if (q === 5) return "#f1c40f";            // RTK float: amber
    if (q === 2) return "#27ae60";            // DGPS
    return "#2f9e57";                          // plain GPS
}

// Signal-quality bar count (1..5) derived from HDOP.
function bars(hdop, hasFix) {
    if (!hasFix) return 0;
    if (hdop <= 0.8) return 5;
    if (hdop <= 1.2) return 4;
    if (hdop <= 2.0) return 3;
    if (hdop <= 5.0) return 2;
    return 1;
}

// Area readout — avoid rounding small worked areas to "0.00 ha".
function formatAreaHa(ha) {
    if (!isFinite(ha) || ha <= 0)
        return "0.00 ha"
    if (ha < 0.01)
        return ha.toFixed(3) + " ha"
    return ha.toFixed(2) + " ha"
}
