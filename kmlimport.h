#pragma once

#include "farmdata.h"
#include <QString>
#include <QVector>

// Minimal KML importer: every Polygon outer ring -> a named paddock, each
// LineString (>= 2 pts) -> an AB line. KML coordinates are "lon,lat,alt".
namespace KmlImport {
struct Poly {
    QString name;
    QVector<GeoPt> ring;
};
struct Result {
    QVector<Poly> polygons;
    QVector<AbLine> lines;
};
bool parse(const QString &path, Result &out);
}
