#include "rxmap.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QtEndian>

#include <cmath>
#include <cstring>

RxMap::RxMap(QObject *parent) : QObject(parent) {}

void RxMap::setRateColumn(const QString &c)
{
    if (c == m_rateColumn)
        return;
    m_rateColumn = c;
    emit changed();
}

void RxMap::setUnit(const QString &u)
{
    if (u == m_unit)
        return;
    m_unit = u;
    emit changed();
}

void RxMap::setOutOfZoneRate(double r)
{
    if (qFuzzyCompare(r, m_outOfZoneRate))
        return;
    m_outOfZoneRate = r;
    emit changed();
}

void RxMap::setNoGpsRate(double r)
{
    if (qFuzzyCompare(r, m_noGpsRate))
        return;
    m_noGpsRate = r;
    emit changed();
}

void RxMap::clear()
{
    m_loaded = false;
    m_sourceFile.clear();
    m_crsNote.clear();
    m_rateColumn.clear();
    m_fields.clear();
    m_zones.clear();
    emit changed();
}

QString RxMap::defaultFolder() const
{
    // Mirror FarmStore::defaultImportFolder() — shared Download/Farm_data on Android.
#ifdef Q_OS_ANDROID
    return QStringLiteral("/storage/emulated/0/Download/Farm_data");
#else
    return QDir::homePath() + QStringLiteral("/Farm_data");
#endif
}

QStringList RxMap::listShapefiles(const QString &folder) const
{
    QStringList out;
    const QString base = folder.isEmpty() ? defaultFolder() : folder;
    QDir d(base);
    if (!d.exists())
        return out;
    // *.shp directly in the folder, plus one level of sub-folders (Rx exports are
    // commonly delivered as a per-prescription sub-folder).
    const QFileInfoList shps = d.entryInfoList(QStringList() << QStringLiteral("*.shp"),
                                               QDir::Files, QDir::Name);
    for (const QFileInfo &fi : shps)
        out << fi.absoluteFilePath();
    const QFileInfoList subs = d.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QFileInfo &sub : subs) {
        QDir sd(sub.absoluteFilePath());
        const QFileInfoList ss = sd.entryInfoList(QStringList() << QStringLiteral("*.shp"),
                                                  QDir::Files, QDir::Name);
        for (const QFileInfo &fi : ss)
            out << fi.absoluteFilePath();
    }
    return out;
}

// ---- Shapefile .shp polygon reader (ESRI, little/big-endian mixed) -----------
static double rdDoubleLE(const QByteArray &b, int off)
{
    if (off + 8 > b.size())
        return 0.0;
    // Shapefile coordinates are little-endian IEEE-754 doubles; every target
    // (armv7/arm64/x86) is little-endian, so an unaligned-safe byte copy is correct.
    double v = 0.0;
    std::memcpy(&v, b.constData() + off, sizeof(double));
    return v;
}
static qint32 rdInt32LE(const QByteArray &b, int off)
{
    if (off + 4 > b.size())
        return 0;
    return qFromLittleEndian<qint32>(reinterpret_cast<const uchar *>(b.constData() + off));
}
static qint32 rdInt32BE(const QByteArray &b, int off)
{
    if (off + 4 > b.size())
        return 0;
    return qFromBigEndian<qint32>(reinterpret_cast<const uchar *>(b.constData() + off));
}

bool RxMap::parseShp(const QString &path, QVector<QVector<QPolygonF>> &geoms)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return false;
    const QByteArray data = f.readAll();
    f.close();
    if (data.size() < 100)
        return false;

    int pos = 100; // past the 100-byte main header
    while (pos + 8 <= data.size()) {
        // Record header: record number + content length (16-bit words), big-endian.
        const qint32 contentWords = rdInt32BE(data, pos + 4);
        pos += 8;
        const int contentBytes = contentWords * 2;
        if (contentBytes <= 0 || pos + contentBytes > data.size())
            break;
        const int recStart = pos;
        const qint32 shapeType = rdInt32LE(data, recStart);
        // 5 = Polygon, 15 = PolygonZ, 25 = PolygonM (all share the X/Y layout).
        if (shapeType == 5 || shapeType == 15 || shapeType == 25) {
            int o = recStart + 4 + 32;             // skip shape type + bounding box
            const qint32 numParts = rdInt32LE(data, o); o += 4;
            const qint32 numPoints = rdInt32LE(data, o); o += 4;
            if (numParts > 0 && numPoints > 0
                && o + numParts * 4 + numPoints * 16 <= data.size()) {
                QVector<int> parts(numParts);
                for (int i = 0; i < numParts; ++i)
                    parts[i] = rdInt32LE(data, o + i * 4);
                const int ptBase = o + numParts * 4;
                QVector<QPolygonF> rings;
                for (int p = 0; p < numParts; ++p) {
                    const int start = parts[p];
                    const int end = (p + 1 < numParts) ? parts[p + 1] : numPoints;
                    QPolygonF ring;
                    ring.reserve(end - start);
                    for (int i = start; i < end; ++i) {
                        const double x = rdDoubleLE(data, ptBase + i * 16);
                        const double y = rdDoubleLE(data, ptBase + i * 16 + 8);
                        ring << QPointF(x, y); // (lon, lat)
                    }
                    if (ring.size() >= 3)
                        rings << ring;
                }
                geoms << rings;
            } else {
                geoms << QVector<QPolygonF>(); // keep index aligned with .dbf
            }
        } else {
            geoms << QVector<QPolygonF>();      // non-polygon / null shape
        }
        pos += contentBytes;
    }
    return !geoms.isEmpty();
}

// ---- dBASE III (.dbf) attribute reader ---------------------------------------
bool RxMap::parseDbf(const QString &path, QStringList &fields,
                     QVector<QVariantMap> &records)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return false;
    const QByteArray data = f.readAll();
    f.close();
    if (data.size() < 32)
        return false;

    const quint32 numRecords =
        qFromLittleEndian<quint32>(reinterpret_cast<const uchar *>(data.constData() + 4));
    const quint16 headerSize =
        qFromLittleEndian<quint16>(reinterpret_cast<const uchar *>(data.constData() + 8));
    const quint16 recordSize =
        qFromLittleEndian<quint16>(reinterpret_cast<const uchar *>(data.constData() + 10));
    if (headerSize < 33 || recordSize == 0)
        return false;

    struct Fld { QString name; int len; int offset; };
    QVector<Fld> flds;
    int fieldOffset = 1; // record byte 0 is the deletion flag
    int o = 32;
    while (o + 32 <= headerSize && o + 1 <= data.size()) {
        if (static_cast<uchar>(data.at(o)) == 0x0D) // field terminator
            break;
        QByteArray nameRaw = data.mid(o, 11);
        const int nul = nameRaw.indexOf('\0');
        if (nul >= 0)
            nameRaw = nameRaw.left(nul);
        const QString name = QString::fromLatin1(nameRaw).trimmed();
        const int len = static_cast<uchar>(data.at(o + 16));
        flds.append({ name, len, fieldOffset });
        fields << name;
        fieldOffset += len;
        o += 32;
    }
    if (flds.isEmpty())
        return false;

    for (quint32 r = 0; r < numRecords; ++r) {
        const int base = headerSize + int(r) * recordSize;
        if (base + recordSize > data.size())
            break;
        if (static_cast<uchar>(data.at(base)) == 0x2A) // deleted record
            continue;
        QVariantMap rec;
        for (const Fld &fl : flds) {
            const QByteArray raw = data.mid(base + fl.offset, fl.len);
            rec.insert(fl.name, QString::fromLatin1(raw).trimmed());
        }
        records.append(rec);
    }
    return true;
}

bool RxMap::loadShapefile(const QString &shpPath)
{
    clear();
    QFileInfo fi(shpPath);
    if (!fi.exists())
        return false;
    const QString stem = fi.absolutePath() + QLatin1Char('/') + fi.completeBaseName();

    QVector<QVector<QPolygonF>> geoms;
    if (!parseShp(shpPath, geoms))
        return false;

    QStringList fields;
    QVector<QVariantMap> records;
    parseDbf(stem + QStringLiteral(".dbf"), fields, records); // attributes optional

    // .prj: read only to annotate the CRS; full reprojection of a projected CRS is
    // a TODO — Rx shapefiles are geographic WGS84 in practice (we assume lon/lat).
    QFile prj(stem + QStringLiteral(".prj"));
    if (prj.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString p = QString::fromUtf8(prj.readAll());
        prj.close();
        if (p.contains(QStringLiteral("4326")) || p.contains(QStringLiteral("WGS_1984"), Qt::CaseInsensitive)
            || p.contains(QStringLiteral("WGS84"), Qt::CaseInsensitive))
            m_crsNote = QStringLiteral("WGS84 (EPSG:4326)");
        else if (p.contains(QStringLiteral("PROJCS"), Qt::CaseInsensitive))
            m_crsNote = QStringLiteral("projected CRS \u2014 assuming lon/lat (reprojection TODO)");
        else
            m_crsNote = QStringLiteral("CRS from .prj \u2014 assuming lon/lat");
    } else {
        m_crsNote = QStringLiteral("no .prj \u2014 assuming WGS84 (EPSG:4326)");
    }

    const int n = geoms.size();
    m_zones.clear();
    m_zones.reserve(n);
    for (int i = 0; i < n; ++i) {
        if (geoms[i].isEmpty())
            continue;
        Zone z;
        z.parts = geoms[i];
        z.attrs = (i < records.size()) ? records[i] : QVariantMap();
        z.minLon = z.minLat = 1e18;
        z.maxLon = z.maxLat = -1e18;
        for (const QPolygonF &ring : z.parts)
            for (const QPointF &pt : ring) {
                z.minLon = qMin(z.minLon, pt.x()); z.maxLon = qMax(z.maxLon, pt.x());
                z.minLat = qMin(z.minLat, pt.y()); z.maxLat = qMax(z.maxLat, pt.y());
            }
        m_zones.append(z);
    }
    m_fields = fields;
    m_sourceFile = fi.absoluteFilePath();
    m_loaded = !m_zones.isEmpty();

    // Best-effort default rate column: pick the first field whose name looks like a
    // rate. The operator still confirms/overrides on import.
    if (!m_fields.isEmpty()) {
        const QStringList hints = { QStringLiteral("rate"), QStringLiteral("tgt_rate"),
                                    QStringLiteral("target_rate"), QStringLiteral("rateint"),
                                    QStringLiteral("rx"), QStringLiteral("vra") };
        for (const QString &f : m_fields)
            if (hints.contains(f.toLower())) { m_rateColumn = f; break; }
        if (m_rateColumn.isEmpty())
            m_rateColumn = m_fields.first();
    }
    emit changed();
    return m_loaded;
}

bool RxMap::loadIsoxml(const QString & /*path*/)
{
    // TODO: ISOXML prescription (TSK with DataTransferOrigin=1): parse TZN treatment
    // zones (polygon + PDV) or a GRD grid, identified by DDI 1 (setpoint vol/area)
    // or DDI 6 (setpoint mass/area), applying VPN offset/scale/decimals (PDV.B is a
    // raw integer, not the final rate). Reuse the same zoned rate surface as the
    // shapefile path. Secondary to shapefile; intentionally not implemented yet.
    m_crsNote = QStringLiteral("ISOXML Rx not yet supported (shapefile only)");
    emit changed();
    return false;
}

QVariantList RxMap::previewValues(const QString &column, int maxN) const
{
    QVariantList out;
    if (column.isEmpty())
        return out;
    for (const Zone &z : m_zones) {
        const QString v = z.attrs.value(column).toString();
        if (!out.contains(v))
            out.append(v);
        if (out.size() >= maxN)
            break;
    }
    return out;
}

bool RxMap::pointInParts(const QVector<QPolygonF> &parts, double lon, double lat)
{
    // Even-odd ray casting across all rings (so interior holes subtract).
    bool inside = false;
    for (const QPolygonF &ring : parts) {
        const int n = ring.size();
        for (int i = 0, j = n - 1; i < n; j = i++) {
            const double xi = ring[i].x(), yi = ring[i].y();
            const double xj = ring[j].x(), yj = ring[j].y();
            const bool cross = ((yi > lat) != (yj > lat))
                && (lon < (xj - xi) * (lat - yi) / ((yj - yi) != 0.0 ? (yj - yi) : 1e-18) + xi);
            if (cross)
                inside = !inside;
        }
    }
    return inside;
}

bool RxMap::inAnyZone(double lat, double lon) const
{
    for (const Zone &z : m_zones) {
        if (lon < z.minLon || lon > z.maxLon || lat < z.minLat || lat > z.maxLat)
            continue;
        if (pointInParts(z.parts, lon, lat))
            return true;
    }
    return false;
}

double RxMap::rateAt(double lat, double lon) const
{
    if (!m_loaded || m_rateColumn.isEmpty())
        return m_outOfZoneRate;
    for (const Zone &z : m_zones) {
        if (lon < z.minLon || lon > z.maxLon || lat < z.minLat || lat > z.maxLat)
            continue;
        if (pointInParts(z.parts, lon, lat)) {
            bool ok = false;
            const double v = z.attrs.value(m_rateColumn).toString().toDouble(&ok);
            return ok ? v : m_outOfZoneRate;
        }
    }
    return m_outOfZoneRate; // first zone wins; deterministic by record order
}

QVariantMap RxMap::descriptor() const
{
    QVariantMap d;
    if (!m_loaded)
        return d;
    d[QStringLiteral("type")] = QStringLiteral("shapefile");
    d[QStringLiteral("file")] = m_sourceFile;
    d[QStringLiteral("column")] = m_rateColumn;
    d[QStringLiteral("unit")] = m_unit;
    d[QStringLiteral("zoneCount")] = m_zones.size();
    d[QStringLiteral("outOfZoneRate")] = m_outOfZoneRate;
    d[QStringLiteral("noGpsRate")] = m_noGpsRate;
    d[QStringLiteral("crs")] = m_crsNote;
    return d;
}

bool RxMap::loadFromDescriptor(const QVariantMap &d)
{
    const QString file = d.value(QStringLiteral("file")).toString();
    if (file.isEmpty() || !loadShapefile(file))
        return false;
    const QString col = d.value(QStringLiteral("column")).toString();
    if (!col.isEmpty())
        m_rateColumn = col;
    m_unit = d.value(QStringLiteral("unit"), m_unit).toString();
    m_outOfZoneRate = d.value(QStringLiteral("outOfZoneRate"), 0.0).toDouble();
    m_noGpsRate = d.value(QStringLiteral("noGpsRate"), 0.0).toDouble();
    emit changed();
    return true;
}
