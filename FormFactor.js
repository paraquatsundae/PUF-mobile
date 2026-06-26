.pragma library

// Phone vs tablet routing. Tablets target 1024×600 landscape (short side = 600).
// Pass Screen.width/height (device short side is stable across rotation); do not
// use ApplicationWindow width/height — those bootstrap from isPhone and mis-classify
// tablets locked in portrait as phones.
function isPhone(width, height) {
    return Math.min(width, height) < 600
}

function shortSide(width, height) {
    return Math.min(width, height)
}
