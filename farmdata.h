#pragma once

#include <QString>
#include <QVector>

// Plain data structs shared by FarmStore (in-memory model) and TaskData
// (ISOXML on-disk format). Geometry is WGS84 decimal degrees.
struct GeoPt {
    double lat = 0.0;
    double lon = 0.0;
};

struct AbLine {
    QString id;
    QString name;
    GeoPt a;
    GeoPt b;
};

struct Field {
    QString id;
    QString name;
    QVector<GeoPt> boundary;   // exterior ring
    QVector<AbLine> abLines;
    double areaHa = 0.0;
    int selectedAb = -1;
};

struct Farm {
    QString id;
    QString name;
    QVector<Field> fields;
};

struct Client {
    QString id;
    QString name;
    QVector<Farm> farms;
};
