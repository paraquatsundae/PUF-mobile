.pragma library

// Catalog of selectable info elements for the side columns.
var order = ["area", "speed", "heading", "location", "satellites",
             "hdop", "fix", "altitude", "implwidth", "track"];

var labels = {
    area:       "Area covered",
    speed:      "Speed",
    heading:    "Heading",
    location:   "Location",
    satellites: "Satellites",
    hdop:       "HDOP",
    fix:        "Fix type",
    altitude:   "Altitude",
    implwidth:  "Impl. width",
    track:      "Run line"
};

function label(id) { return labels[id] !== undefined ? labels[id] : id; }
