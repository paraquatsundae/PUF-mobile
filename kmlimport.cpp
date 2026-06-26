#include "kmlimport.h"

#include <QFile>
#include <QXmlStreamReader>

namespace {

QVector<GeoPt> parseCoords(const QString &text)
{
    QVector<GeoPt> pts;
    const QStringList tuples = text.simplified().split(' ', Qt::SkipEmptyParts);
    for (const QString &t : tuples) {
        const QStringList xy = t.split(',');
        if (xy.size() < 2)
            continue;
        GeoPt p;
        p.lon = xy.at(0).toDouble();
        p.lat = xy.at(1).toDouble();
        pts.append(p);
    }
    return pts;
}

void dropClosingPoint(QVector<GeoPt> &ring)
{
    if (ring.size() > 1) {
        const GeoPt &f = ring.first();
        const GeoPt &l = ring.last();
        if (qFuzzyCompare(f.lat + 1.0, l.lat + 1.0)
            && qFuzzyCompare(f.lon + 1.0, l.lon + 1.0))
            ring.removeLast();
    }
}

} // namespace

bool KmlImport::parse(const QString &path, Result &out)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;

    enum Ctx { None, Ring, Hole, Line };
    Ctx ctx = None;
    bool inPlacemark = false;
    bool inOuter = false;
    QString placemarkName;
    int seq = 0;

    QXmlStreamReader xml(&file);
    while (!xml.atEnd()) {
        const auto tok = xml.readNext();
        if (tok == QXmlStreamReader::StartElement) {
            const QStringRef name = xml.name();
            if (name == QLatin1String("Placemark")) {
                inPlacemark = true;
                placemarkName.clear();
            } else if (name == QLatin1String("name") && inPlacemark && placemarkName.isEmpty()) {
                placemarkName = xml.readElementText().trimmed();
            } else if (name == QLatin1String("outerBoundaryIs")) {
                inOuter = true;
            } else if (name == QLatin1String("LinearRing")) {
                ctx = inOuter ? Ring : Hole;
            } else if (name == QLatin1String("LineString")) {
                ctx = Line;
            } else if (name == QLatin1String("coordinates")) {
                const QVector<GeoPt> pts = parseCoords(xml.readElementText());
                if (ctx == Ring && pts.size() >= 3) {
                    Poly poly;
                    poly.name = placemarkName.isEmpty()
                            ? QStringLiteral("Field %1").arg(out.polygons.size() + 1)
                            : placemarkName;
                    poly.ring = pts;
                    dropClosingPoint(poly.ring);
                    out.polygons.append(poly);
                } else if (ctx == Line && pts.size() >= 2) {
                    AbLine ab;
                    ab.name = placemarkName.isEmpty()
                            ? QStringLiteral("AB %1").arg(++seq)
                            : placemarkName;
                    ab.a = pts.first();
                    ab.b = pts.last();
                    out.lines.append(ab);
                }
            }
        } else if (tok == QXmlStreamReader::EndElement) {
            const QStringRef name = xml.name();
            if (name == QLatin1String("Placemark"))
                inPlacemark = false;
            else if (name == QLatin1String("outerBoundaryIs"))
                inOuter = false;
            else if (name == QLatin1String("LinearRing") || name == QLatin1String("LineString"))
                ctx = None;
        }
    }
    file.close();
    return !xml.hasError() && (!out.polygons.isEmpty() || !out.lines.isEmpty());
}
