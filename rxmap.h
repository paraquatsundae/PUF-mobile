#pragma once

#include <QObject>
#include <QPointF>
#include <QPolygonF>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

// Prescription-map (Rx) rate surface. Reads an ESRI shapefile zone set
// (.shp polygons + .dbf attributes, optional .prj) with a compact, dependency-free
// reader that is safe on Android/arm, then answers the target rate at a GPS
// position by point-in-polygon lookup over the management zones.
//
// The rate column name is NOT standardised and units are out-of-band, so the
// operator picks the rate column (from the .dbf fields) and the units on import
// (mirrors the Gen4 "Rate Column / Rate Column Units" workflow). Out-of-zone and
// no-GPS fallback rates are explicit.
//
// CRS: shapefiles for Rx are essentially always geographic WGS84 (EPSG:4326), i.e.
// X=longitude, Y=latitude, which we compare directly to the GPS lat/lon. If a .prj
// is present it is read only to confirm/annotate; reprojecting a projected CRS is a
// TODO (we assume lon/lat and flag it). ISOXML Rx (TZN/GRD + PDV / DDI 1|6 + VPN
// scaling) is a separate, secondary path (stubbed — see loadIsoxml()).
//
// Exposed to QML as `rx`.
class RxMap : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool loaded READ loaded NOTIFY changed)
    Q_PROPERTY(int zoneCount READ zoneCount NOTIFY changed)
    Q_PROPERTY(QStringList fieldNames READ fieldNames NOTIFY changed)
    Q_PROPERTY(QString rateColumn READ rateColumn WRITE setRateColumn NOTIFY changed)
    Q_PROPERTY(QString unit READ unit WRITE setUnit NOTIFY changed)
    Q_PROPERTY(QString sourceFile READ sourceFile NOTIFY changed)
    Q_PROPERTY(QString crsNote READ crsNote NOTIFY changed)
    Q_PROPERTY(double outOfZoneRate READ outOfZoneRate WRITE setOutOfZoneRate NOTIFY changed)
    Q_PROPERTY(double noGpsRate READ noGpsRate WRITE setNoGpsRate NOTIFY changed)

public:
    explicit RxMap(QObject *parent = nullptr);

    bool loaded() const { return m_loaded; }
    int zoneCount() const { return m_zones.size(); }
    QStringList fieldNames() const { return m_fields; }
    QString rateColumn() const { return m_rateColumn; }
    QString unit() const { return m_unit; }
    QString sourceFile() const { return m_sourceFile; }
    QString crsNote() const { return m_crsNote; }
    double outOfZoneRate() const { return m_outOfZoneRate; }
    double noGpsRate() const { return m_noGpsRate; }

    void setRateColumn(const QString &c);
    void setUnit(const QString &u);
    void setOutOfZoneRate(double r);
    void setNoGpsRate(double r);

    // Parse a shapefile from its .shp path (sibling .dbf/.prj read automatically).
    // Resets any previous map. Returns true on success.
    Q_INVOKABLE bool loadShapefile(const QString &shpPath);
    // Secondary path: ISOXML prescription (TZN/GRD). Stubbed for this slice.
    Q_INVOKABLE bool loadIsoxml(const QString &path);
    // Clear the loaded map.
    Q_INVOKABLE void clear();

    // List *.shp files in a folder (for the import picker).
    Q_INVOKABLE QStringList listShapefiles(const QString &folder) const;
    // Default Rx import folder (same shared-storage location as KML/ISOXML import).
    Q_INVOKABLE QString defaultFolder() const;

    // Distinct values of a .dbf column (string form), capped, to help the operator
    // confirm they picked the rate column.
    Q_INVOKABLE QVariantList previewValues(const QString &column, int maxN = 8) const;

    // Target rate at a WGS84 position: the chosen column's value for the first zone
    // whose polygon contains (lat,lon); out-of-zone fallback if none match.
    Q_INVOKABLE double rateAt(double lat, double lon) const;
    // True if the position is inside any zone.
    Q_INVOKABLE bool inAnyZone(double lat, double lon) const;

    // Persist/restore the operator's choice with a job (zones are re-read from
    // sourceFile, which must remain on disk).
    Q_INVOKABLE QVariantMap descriptor() const;
    Q_INVOKABLE bool loadFromDescriptor(const QVariantMap &d);

signals:
    void changed();

private:
    struct Zone {
        QVector<QPolygonF> parts;        // rings, points are (lon, lat)
        QVariantMap attrs;               // .dbf column -> value (string)
        double minLon, minLat, maxLon, maxLat;
    };

    bool parseShp(const QString &path, QVector<QVector<QPolygonF>> &geoms);
    bool parseDbf(const QString &path, QStringList &fields,
                  QVector<QVariantMap> &records);
    static bool pointInParts(const QVector<QPolygonF> &parts, double lon, double lat);

    bool m_loaded = false;
    QString m_sourceFile;
    QString m_crsNote;
    QString m_rateColumn;
    QString m_unit = QStringLiteral("L/ha");
    double m_outOfZoneRate = 0.0;
    double m_noGpsRate = 0.0;
    QStringList m_fields;
    QVector<Zone> m_zones;
};
