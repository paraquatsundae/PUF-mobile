.pragma library

// Material Design Icons (Pictogrammers, Apache-2.0) glyph map.
// The webfont is loaded once in main.qml via FontLoader; its family name is a
// fixed string, so any Text can render an icon by setting font.family = family.
// Codepoints live in the Supplementary Private Use Area (> U+FFFF), so they are
// built with String.fromCodePoint rather than \u escapes.
var family = "Material Design Icons";

function _c(cp) { return String.fromCodePoint(cp); }

// --- Pages ---
var nav         = _c(0xF0390); // navigation
var data        = _c(0xF0279); // format-list-bulleted
var work        = _c(0xF08A8); // clipboard-check-outline
var setup       = _c(0xF0493); // cog
var farm        = _c(0xF0B5E); // barn
var implement   = _c(0xF084E); // arrow-expand-horizontal
var layout      = _c(0xF0570); // view-grid
var gps         = _c(0xF01A4); // crosshairs-gps

// --- Actions / bottom bar ---
var home        = _c(0xF02DC); // home
var record      = _c(0xF0EC2); // record-circle
var stop         = _c(0xF0666); // stop-circle
var section     = _c(0xF0665); // spray
var perspective = _c(0xF0464); // rotate-3d-variant

// --- Map controls / status ---
var plus        = _c(0xF0415); // plus
var minus       = _c(0xF0374); // minus
var center      = _c(0xF01A3); // crosshairs
var satellite   = _c(0xF0471); // satellite-variant
var track       = _c(0xF0D20); // map-marker-path
var tractor     = _c(0xF0892); // tractor
var ruler       = _c(0xF0CC2); // ruler-square

// --- Chevrons / misc ---
var chevronLeft  = _c(0xF0141);
var chevronRight = _c(0xF0142);
var chevronUp    = _c(0xF0143);
var chevronDown  = _c(0xF0140);
var check        = _c(0xF012C);
var pencil       = _c(0xF03EB);
var del          = _c(0xF01B4); // delete
var close         = _c(0xF0156); // close
